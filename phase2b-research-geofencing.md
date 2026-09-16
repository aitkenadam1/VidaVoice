# Phase 2B — Safe Zones (Geofencing): Platform-Landscape Briefing

Date: 2026-09-16 · Status: **research only — no code changed**
Context: OneVoz (Flutter: iOS, Android, web). Child device evaluates enter/exit on-device; caregiver defines zones; alerts fan out via the Cloudflare worker; zone definitions stay E2E-encrypted like dashboard sync.

---

## 0. Recommendation (one approach)

**Use native platform geofencing via the `native_geofence` Flutter plugin**
(`pub.dev/packages/native_geofence` — wraps `CLLocationManager` region monitoring on iOS and `GeofencingClient` on Android).

Why this one:

- **Background reliability:** the OS owns the regions. iOS's locationd and Google Play services wake the app on boundary crossing *even when terminated*. No persistent GPS, no isolate the OS can starve.
- **Battery:** no continuous location polling. Region monitoring is the battery-cheap primitive both OS vendors built exactly for this.
- **Limits are fine at family scale:** iOS allows 20 monitored regions per app; Android allows 100 geofences per app per user. A family will define single-digit zones (Home, School, Grandma's). No 20-region workaround needed; if it ever matters, register the nearest 20 dynamically (future work, not Phase 2B).
- **Cost:** free, no SDK license. (The main commercial alternative, Transistor Software's `flutter_background_geolocation`, is excellent but its strength is continuous tracking — overkill and paid for proximity-only use.)
- **Maintenance:** `native_geofence` (ChunkyTofuStudios fork lineage) is actively maintained as of mid-2026, works foreground/background/terminated, re-registers geofences after reboot on Android, and supports current toolchains (Flutter 3.44 / AGP 9). Its README is honest about rough edges (the optional foreground-service promotion is "not well tested") — we avoid that path anyway (see §2).

Rejected alternatives:

| Option | Verdict |
|---|---|
| `geofence_service` (older community plugin) | Legacy / effectively unmaintained — has not kept pace with Android 14 foreground-service types or current Flutter releases. Verify last publish date on pub.dev, but do not build on it. |
| `flutter_background_geolocation` (Transistor) | Great tech, commercial license, built for continuous tracking. Wrong cost/complexity fit for enter/exit only. |
| `polyfence` / `geofence_sdk` (new 0.x SDKs) | Interesting (polyfence does its own on-device math, dodging the iOS 20-region limit), but immature and they run their own background tracking — reintroducing the battery/reliability problem native APIs solve. |
| Custom background-location + manual radius checks | Drains battery, gets killed by Doze/OEM task killers, no terminated-state relaunch guarantee. This is the defect class we're avoiding. |

Design note: register geofences **only on the child's device**. The caregiver defines/edits zones; definitions sync E2E; the child decrypts and registers native regions with **opaque random IDs** (UUID v4) — never names or coordinates in the OS-registered identifier, since the OS persists them.

---

## 1. Native configuration required

### iOS

**Info.plist keys:**

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>OneVoz uses your location to check safe zones in the background…</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>OneVoz checks safe zones even when the app is closed so caregivers get enter/exit alerts…</string>
```

(`NSLocationAlwaysUsageDescription` is legacy pre-iOS-11 — not needed.)

**Background modes:** region monitoring does *not* strictly require `UIBackgroundModes = location` — locationd tracks regions and relaunches a terminated app via the `UIApplicationLaunchOptions.location` key. **Enable `remote-notification`** background mode for push handling. If the geofence callback does network work (posting the alert), wrap it in a `beginBackgroundTask` — you get roughly 30 seconds, which is plenty for one HTTPS POST.

**Runtime permission flow (order matters):**

1. Call `requestWhenInUseAuthorization()` first. Since iOS 13 you *cannot* jump straight to Always.
2. After `.authorizedWhenInUse`, call `requestAlwaysAuthorization()`. iOS shows "Change to Allow Always" (often deferred — iOS may prompt again later on its own schedule).
3. If the user stays on When-In-Use: region monitoring only fires while the app is in use — **no terminated-state alerts**. The caregiver panel must show a degraded state ("Background location is limited — open Settings to allow Always") with a deep link to Settings.
4. iOS 14+: check `accuracyAuthorization`. Geofencing needs **Precise** location; if the user picked Approximate, prompt them to flip it (Settings deep link). Detect via `CLLocationManager.accuracyAuthorization == .reducedAccuracy`.

**iOS-specific limits/gotchas:**

- 20 `CLCircularRegion`s max per app. Exceeding it fails silently-ish (monitoredRegions just won't add) — enforce the cap client-side.
- `CLLocationManager.maximumRegionMonitoringDistance` caps radius; keep zone radii well under it (typical: 100–500 m; never below ~100 m — small radii flap and miss exits due to GPS/Wi-Fi jitter).
- **Exit events lag.** iOS deliberately delays exit detection (often minutes) to avoid flapping. Set caregiver expectations: exits are not real-time; enters are faster.
- App Store review: "Always" location needs a justification narrative. Write it early (child-safety / safe-zone alerts).

### Android

**AndroidManifest.xml:**

```xml
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/> <!-- Android 13+, runtime -->
<!-- Only if using a foreground service for geofence callbacks (avoid if possible): -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION"/>
```

Plus `android:foregroundServiceType="location"` on any location foreground service (Android 14 throws `MissingForegroundServiceTypeException` without it).

**Runtime permission flow (order matters, Android 10+/11+):**

1. Request `ACCESS_FINE_LOCATION` first, alone.
2. Only after granted, request `ACCESS_BACKGROUND_LOCATION` in a **separate** request — Android 11+ ignores/silently fails bundled requests.
3. On Android 11+, the system dialog does *not* offer "Allow all the time" directly. Show an in-app rationale screen, then deep-link to the app's Settings page (`ACTION_APPLICATION_DETAILS_SETTINGS`) so the user can pick "Allow all the time" manually.
4. Without background location, `GeofencingClient.addGeofences` throws `ApiException 1004 (GEOFENCE_NOT_AVAILABLE)`. Handle it: degraded-mode UI on the caregiver panel.
5. Android 13+: request `POST_NOTIFICATIONS` at runtime or alert notifications are silently dropped.

**Android-specific limits/gotchas:**

- 100 geofences per app per user (Play services limit) — plenty.
- Transitions arrive via `PendingIntent` → `BroadcastReceiver`. On Android 8+ the receiver gets ~10 s of execution. **Keep the callback short:** decrypt zone ID, build the alert, one HTTPS POST to the worker, done. Do *not* depend on the plugin's foreground-service promotion (its own README flags it as untested); if longer work is ever needed, use WorkManager (expedited) instead — and note Android 12+ background-start restrictions on `startForeground()`.
- **Play Store policy risk (see §5, risk #1):** `ACCESS_BACKGROUND_LOCATION` triggers a location declaration + prominent in-app disclosure requirement. Prepare disclosure copy and a demo video before submission.
- **OEM battery killers** (Samsung, Xiaomi, Oppo, etc.) and Doze can defer the app's callback work. Geofence *detection* itself runs in Play services (robust), but our alert-upload runs in our process. Mitigate with a battery-optimization exemption prompt in the caregiver panel (`ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` — use the Settings-intent route carefully; Play policy frowns on direct requests without justification).
- `RECEIVE_BOOT_COMPLETED` + re-register geofences on boot (`native_geofence` handles this).

---

## 2. FCM/APNs push design (no coordinates, ever)

### Recommended pattern: generic visible notification + resolve-on-open

Do **not** rely on silent/data-only pushes to wake the caregiver app. Two hard facts:

- **iOS never wakes a force-quit app** for background (`content-available`) pushes, and APNs throttles silent pushes by an opaque per-app budget — bursts get dropped.
- **Android** delivers data messages to `FirebaseMessaging.onBackgroundMessage` even when the app is killed, but *not* after force-stop; Android 13+ also needs the `POST_NOTIFICATIONS` grant or nothing renders.

So the reliable cross-platform design:

**Server → FCM HTTP v1 → caregiver device payload:**

```json
{
  "message": {
    "token": "<caregiver device FCM token>",
    "notification": { "title": "OneVoz", "body": "Safe zone update — tap to view" },
    "data": {
      "kind": "geofence_exit",
      "zone_id": "9f3c… (opaque UUID)",
      "profile_id": "… (opaque)",
      "alert_id": "… (uuid, for dedup)",
      "ts": "2026-09-16T21:04:11Z"
    },
    "android": { "priority": "high" },
    "apns": { "headers": { "apns-priority": "10" } }
  }
}
```

- The `notification` block text is **generic** — no name, no place, no coordinates. Apple/Google push infra only ever sees opaque IDs.
- **Name resolution happens on-device:** `zone_id → "Home"` comes from the E2E-encrypted zone blob already synced to the caregiver device (same sync engine as dashboards); `profile_id → "Brianna"` from the local profile store.
- **Tap routing:** `getInitialMessage()` (terminated launch) and `onMessageOpenedApp` (background tap) → app opens, decrypts zone/profile names, fires a local notification via `flutter_local_notifications` with the real text ("Brianna left Home · 3:42 PM") and updates the alerts feed. Foreground: `onMessage` → local notification directly.
- **Privacy upgrade (recommended, cheap):** encrypt the `data` block's `zone_id`/`profile_id` with the family sync key (AES-GCM envelope) before the worker fans out. Then even FCM/APNs metadata can't map *which* zone fired — the worker routes on `family_id` only. Both devices already hold the sync key.

**Gotchas checklist:**

- iOS: Push Notifications capability + Background Modes → Remote notifications. Data-only (no `notification` block) messages must go out with `content_available: true` → FCM sets `apns-push-type: background`, priority 5. Don't mix: if you include `notification`, iOS shows it and `onBackgroundMessage` won't fire while terminated — that's fine, tap routing covers it.
- `firebase_messaging` background handler must be a top-level `@pragma('vm:entry-point')` function registered before `runApp` — without the pragma it works in debug and **vanishes in release**.
- Known-good pair from current practice: `firebase_messaging ^15.2.0` + `flutter_local_notifications ^18.0.1`. Create the Android notification channel once (high importance for safety alerts); posts to an undefined channel are silently dropped on Android 8+.
- FCM tokens rotate — listen to `onTokenRefresh` and re-register with the worker every time.
- Use FCM `high` priority sparingly (quotas); safe-zone exits qualify, routine sync does not.

---

## 3. What the Cloudflare worker needs

**Reuse the existing alert pipeline; extend it. No new zone-content endpoints.**

1. **New alert kinds** in the existing alert ingest: `geofence_enter`, `geofence_exit` (reserve `geofence_dwell` for later). The child's device POSTs these exactly like today's `share_started`/`sos` alerts — including `ts` (the recent `invalid_ts` fix applies here too).
2. **FCM token registry:** `POST /v1/devices/push-token { device_id, fcm_token, platform }` + delete on logout/token-refresh supersede. Tokens stored per caregiver device, keyed by `family_id`.
3. **Fanout on alert ingest:** when a `geofence_*` alert arrives, the worker looks up the family's caregiver device tokens and sends the FCM message (generic notification + opaque/encrypted data block). The worker **never sees coordinates or names** — only `family_id`, the kind enum, `ts`, and ciphertext.
4. **Zone sync = existing E2E blob sync, new doc type.** Add doc_type `safe_zones`: the blob is `AES-GCM(plaintext JSON {zones: [{id, name, lat, lng, radius_m}]}, nonce)` under the **existing per-family sync key** (PBKDF2 from the caregiver password + server-held `sync_salt`). Server stores `{family_id, doc_type, version, updated_at, ciphertext, nonce}` — opaque, same as dashboard blobs today. No new crypto design; no new key.
   - Child device pulls the blob on sync, decrypts with its cached sync key, registers native geofences.
   - Caregiver device uses the same blob for name resolution in notifications (§2).
5. **Key rotation:** when the caregiver changes the account password, re-derive the sync key and re-encrypt *all* doc types including `safe_zones`; bump a `key_version` in sync metadata. The child must re-pull and re-register geofences on any zone-blob version change. Include `key_version` in alerts so the caregiver side can detect a stale sender and prompt re-sync instead of showing garbage.
6. **Idempotency/ordering:** `alert_id` (UUID) for dedup on fanout; `ts` for ordering. Consider a short server-side dedup window — iOS/Android can both deliver a boundary crossing twice (re-registration, flapping).

**What the worker does NOT need:** any endpoint that accepts coordinates, any zone-evaluation logic, any plaintext names. If a proposed endpoint takes a lat/lng, it's wrong.

---

## 4. Testing strategy

### Web Preview — what it CAN verify

- Zone CRUD UI on the map (create/edit/delete, radius slider, MapTiler rendering).
- E2E encrypt/decrypt round-trip of the `safe_zones` blob (same test harness style as dashboard sync).
- Sync-engine plumbing for the new doc type (version bumps, conflict = last-writer-wins with version check).
- Alert feed UI rendering `geofence_enter/exit` from synthetic alerts.
- PIN gate around zone management (zones live in the caregiver control panel — already PIN-gated).
- Simulated push payload → tap routing → name resolution (inject a fake `RemoteMessage`).

### Web Preview — what it CANNOT verify (native only)

Actual enter/exit detection, terminated-state relaunch, reboot re-registration, background-permission flows, real FCM/APNs delivery, Doze/OEM behavior. **Do not let a green web Preview imply geofencing works.**

### Simulating enter/exit

- **iOS Simulator:** Features → Location → Custom Location / City Run / Freeway Drive, or attach a **GPX file** (Scheme → Edit Scheme → Options → Default Location; or Debug → Simulate Location while running) with waypoints that cross the zone boundary. Caveat: region monitoring in the simulator is approximate — treat simulator passes as smoke only; confirm on a real device via TestFlight.
- **Android Emulator:** Extended Controls (⋯) → Location → Routes; import a GPX/KML route that crosses the boundary and play it; or `adb emu geo fix <longitude> <latitude>` for manual jumps (jumps can confuse exit detection — prefer routes). Use a system image **with Google Play** (Play services must be present for `GeofencingClient`).
- **Field test (internal track / TestFlight, required before calling it done):** define a ~150 m zone, walk/drive across the boundary with the child device, measure alert latency to the caregiver device. Test: app foregrounded, backgrounded, swiped-away (terminated), and after reboot. Test the permission-degraded paths (When-In-Use only on iOS; foreground-only on Android) and confirm the caregiver panel shows the degraded state, not silence.

---

## 5. Top 5 risks / gotchas that could sink the schedule

1. **Play Store background-location review.** `ACCESS_BACKGROUND_LOCATION` requires a prominent in-app disclosure, a Play Console location declaration, and a feature-scoped justification. A rejection or policy back-and-forth can cost weeks. *Mitigate:* draft the disclosure copy and record the demo video before submission; keep the justification narrowly scoped to safe-zone alerts.
2. **iOS "Always" permission conversion.** Users who choose "While Using the App" silently lose terminated-state monitoring, and iOS may take minutes to deliver exit events. If the caregiver doesn't understand this, they'll report "alerts don't work." *Mitigate:* in-app education at zone-setup time, Settings deep link, and an honest degraded-mode banner — never silent failure.
3. **Silent push is not a wakeup guarantee.** Force-quit iOS apps never wake for data-only pushes; APNs throttles background pushes by budget. Any design that *depends* on waking the caregiver app will miss alerts. *Mitigate:* the generic-visible-notification + resolve-on-open pattern (§2).
4. **Android OEM battery killers + Doze vs. the alert upload.** Geofence *detection* runs in Play services (robust), but our alert POST runs in our process and can be deferred or killed on aggressive OEM skins. *Mitigate:* keep the geofence callback under ~10 s (decrypt ID → single HTTPS POST), add a battery-exemption prompt in the caregiver panel, and a WorkManager retry for failed uploads. Never require a foreground service in the hot path.
5. **E2E key rotation + offline child.** Caregiver changes password → sync key changes → zone blobs re-encrypted. A child device that's offline through the rotation holds a stale blob and stale registered geofences. *Mitigate:* `key_version` in sync metadata; child re-registers geofences on every zone-blob version change and on every app start; alerts carry `key_version` so the caregiver side can flag "child needs to sync" instead of displaying a zone name it can't decrypt.

---

## 6. Suggested build order (for planning, not a commitment)

1. Worker: FCM token registry + `geofence_*` alert kinds + fanout (test with curl + a fake token).
2. App: `safe_zones` doc type in the sync engine + E2E round-trip tests + caregiver zone CRUD UI (web Preview-verifiable).
3. App: child-side zone pull → `native_geofence` registration → alert POST on enter/exit.
4. Caregiver push: token registration, tap routing, resolve-on-open local notifications.
5. Permission flows + degraded-mode UX on both platforms.
6. Native verification battery: simulator/emulator routes, then TestFlight/internal-track field test (foreground / background / terminated / reboot / permission-denied).
7. Play Console location declaration + App Store justification copy.

*Open product questions for Adam (not answered here): default zone radius, whether exits should also notify when the caregiver's app has never been opened on their device (no token — worker should surface "caregiver device not registered for alerts"), and whether dwell alerts are in scope.*
