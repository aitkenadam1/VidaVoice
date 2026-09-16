# Phase 2B — Safe Zones: Design

**Status:** design (Adam approved build 2026-09-16; owner decisions below)
**Companion research:** `phase2b-research-geofencing.md` (platform landscape, native config, push gotchas)

## 1. Goal

Caregivers define named circular safe zones ("Home", "School") on a map.
The child's device watches those zones in the background and posts an
encrypted `geofence_enter` / `geofence_exit` alert when the child crosses a
boundary. The caregiver gets a push notification naming the child and the
zone — with no coordinates ever visible to the server or the push provider.

## 2. Non-negotiables (from Adam's standing rules)

- **E2E encryption everywhere it matters.** Zone definitions (name, center,
  radius) travel inside the existing encrypted sync blob. The server, FCM,
  and APNs only ever see opaque IDs.
- **Evaluation happens on the child's device.** Raw GPS never leaves the
  device for geofence purposes. Only the enter/exit *event* (encrypted)
  is uploaded.
- **Communication never breaks.** If location, push, or cloud fails, the
  AAC boards keep working. Geofencing degrades silently, never blocks.
- **No dead buttons.** Every control in the zone editor must work or say
  "Coming soon".
- **Preview deploy still needs Adam's MapTiler key** (transient paste for
  the `--dart-define` web rebuild). The zone editor reuses the hub map.

## 3. Architecture

```
Caregiver device (hub, PIN-gated)          Child device
┌──────────────────────────────┐          ┌──────────────────────────────┐
│ Zone editor (map)            │          │ native_geofence regions     │
│  name + center + radius      │  E2E     │  (opaque UUID per zone)      │
│         │                    │  blob    │         │                    │
│         ▼                    │◄────────►│  enter/exit (on-device)      │
│ DashboardSyncService.pushNow │  sync    │         │                    │
└──────────────────────────────┘          │         ▼                    │
                                          │ postAlert(geofence_enter/    │
                                          │   exit, ciphertext)          │
                                          └──────────┬───────────────────┘
                                                     │
                                          ┌────────▼────────┐
                                          │ Worker /v1/alerts│
                                          │ (kind = routing  │
                                          │  only, opaque)   │
                                          └────────┬────────┘
                                                   │ fanout
                                          ┌────────▼────────┐
                                          │ FCM / APNs push  │
                                          │ payload: zone_id │
                                          │ profile_id, ts   │
                                          │ (NO coords)      │
                                          └────────┬────────┘
                                                   │
                                          ┌────────▼──────────────────┐
                                          │ Caregiver device: resolve │
                                          │ "Brianna left Home" from  │
                                          │ local E2E zone blob, show │
                                          │ local notification        │
                                          └───────────────────────────┘
```

### Why this shape

- **Zone sync rides the existing E2E blob** (`DashboardSyncService`): zones
  become a new `safe_zones` doc type inside the encrypted payload, using
  the same per-family PBKDF2 sync key. No new worker endpoints, no new
  crypto, syncs to every family device automatically, `key_version`
  handling already exists for password rotation.
- **Alerts ride the existing alert pipeline**: `postAlert` already takes a
  plaintext `kind` for routing plus `ciphertext`/`nonce`. New kinds
  `geofence_enter` / `geofence_exit` need **zero worker changes** on the
  ingest path (the client already reserves these names in
  `LocationAlertKind`).
- **Geofencing is native, not DIY**: the `native_geofence` Flutter plugin
  (iOS `CLLocationManager` region monitoring + Android `GeofencingClient`).
  The OS owns the regions, so enter/exit fires even when the app is
  terminated, with no persistent GPS drain. Rejected: `geofence_service`
  (unmaintained), commercial background-tracking SDKs (overkill for
  proximity), custom background-location + manual radius checks (battery
  and Doze failure class). Limits are fine at family scale (iOS 20
  regions, Android 100).
- **Push is worker-driven, visible, resolve-on-open** (per research):
  data-only/silent pushes are unreliable on iOS (never wakes a force-quit
  app; APNs throttles them). The push carries only opaque IDs; the
  caregiver device decrypts the zone *name* locally from its synced blob
  and renders "Brianna left Home". Optional AES-GCM envelope so even the
  opaque IDs are ciphertext to FCM/APNs.

## 4. Zone data model (inside the E2E blob)

```json
"safe_zones": [
  {
    "id": "zone_<uuid>",        // opaque; also the native geofence id
    "name": "Home",             // encrypted at rest on server
    "lat": 40.123, "lng": -111.456,
    "radius_m": 300,
    "enabled": true,
    "notify_enter": true,
    "notify_exit": true,
    "updated_ts": 1758040000000
  }
]
```

- Coordinates live **only** inside the encrypted blob and on-device.
- The child device registers one native geofence per enabled zone, keyed
  by the opaque `id`. The OS never sees the name.

## 5. Caregiver UX (in the PIN-gated hub, Location section)

New "Safe zones" card in the hub's Location section:

1. **List** of zones: name, radius, enabled toggle. Tap → editor.
2. **Editor (map)**: long-press / tap to place center, slider or
   pinch to set radius (50 m – 2 km), name field, enter/exit notify
   toggles, save/delete. Reuses the hub's MapTiler map.
3. **Save** → updates the E2E blob → `pushNow()` → every family device
   (including the child's) pulls the new zones on next sync and
   re-registers native geofences.
4. Honest states: "Syncing zones…", "Zones need location permission on
   the child's device", per-zone "active / permission missing".

No zone UI on the child's boards. Ever.

## 6. Child device behavior

- On sync pull (or boot with cached zones): diff desired vs registered
  native geofences; add/update/remove.
- On native enter/exit callback: build the encrypted alert payload
  `{zone_id, profile_id, event: enter|exit, ts}` with the family sync
  key → `postAlert(kind: geofence_enter|exit, ...)`.
- **Upload must survive app kill**: the native callback has ~10 s on
  Android (BroadcastReceiver window). Strategy: write the event to a
  durable outbox first, attempt immediate upload, retry on next foreground
  / WorkManager window. An event that can't upload is never dropped
  silently — it stays queued.
- If location permission is denied/downgraded on the child device:
  geofences can't register; the caregiver hub shows "needs permission on
  child's device" (from the last known state, never a live probe that
  leaks presence).

## 7. Push notifications (the owner decision)

**Recommended: worker-driven visible push.**

- New worker state: FCM/APNs **device-token registry** (endpoint for the
  app to register/refresh its token; tokens are per-install, not secrets,
  but stored server-side only for fanout).
- On a new alert with kind `geofence_enter`/`geofence_exit`, the worker
  fans out to the family's caregiver installs (not the child's own
  install): payload `{alert_id, kind, zone_id, profile_id, ts}`.
- Caregiver app: background handler resolves IDs → names from the local
  E2E blob → posts the local notification "Brianna left Home · 3:42 PM".
  Tapping opens the hub's location section (behind the PIN gate, as
  always).
- Needs from Adam at build time: FCM server credentials + APNs key
  (Apple Developer membership already assumed for TestFlight).

**Alternative (not recommended): polling + local notifications.**
Zero worker changes — the caregiver app already polls `/v1/alerts` and
could raise a local notification itself. But iOS background polling is
unreliable and Android Doze delays it; alerts would arrive late or only
when the app is opened. Safe zones that notify "whenever" aren't safe
zones. Kept as a graceful fallback if push is unavailable.

## 8. Native config checklist

**iOS** (`Info.plist`): `NSLocationWhenInUseUsageDescription`,
`NSLocationAlwaysAndWhenInUseUsageDescription`; request WhenInUse first,
then Always (conversion prompt); `remote-notification` background mode;
precise-location check (iOS 14+); 20-region cap; expect exit-event lag
(document in UX copy, not a bug to chase).

**Android** (`AndroidManifest`): `ACCESS_FINE_LOCATION`,
`ACCESS_BACKGROUND_LOCATION`, `RECEIVE_BOOT_COMPLETED`,
`POST_NOTIFICATIONS`; Android 14 `FOREGROUND_SERVICE_LOCATION` +
`foregroundServiceType="location"`; sequential runtime requests
(foreground → background, with a Settings deep-link for "Allow all the
time" on Android 11+); handle `ApiException 1004`; re-register geofences
on boot.

**Play Store**: background-location permission triggers Play review —
needs the in-app disclosure + privacy-policy wording (we have legal
pages at voice.onevoz.me/privacy; they need a location section).

## 9. Worker changes (only for the recommended push path)

1. `device_push_tokens` table + register/refresh/delete endpoints.
2. Fanout on alert ingest for geofence kinds (and later: SOS).
3. FCM + APNs sender with the opaque payload contract.
4. Admin visibility: token counts per family (no token values in logs).

No changes to alert ingest, zone storage (E2E blob), or auth.

## 10. Testing plan

**Web Preview can verify:** zone CRUD UI, E2E encrypt/decrypt round-trip,
sync push/pull of zones, alert feed rendering, push-routing logic with
simulated payloads. **It cannot verify** real enter/exit, terminated-app
relaunch, or actual push delivery.

**Native (required before calling it done):** iOS simulator GPX routes,
Android emulator extended controls / `adb emu geo fix`; then a
TestFlight + internal-track field matrix: foreground / background /
terminated / reboot / permission-denied × enter / exit. Adam's devices
are the field lab — he'll get builds with a stated test script.

## 11. Top risks

1. **Play Store background-location review** — mitigation: in-app
   disclosure, privacy-policy update, request only on the child device
   flow.
2. **iOS "Always" permission conversion** — many users stop at WhenInUse;
   mitigation: explain-then-ask UX, hub shows "needs Always on child's
   device".
3. **Exit-event lag** (both platforms) — mitigation: honest UX copy, no
   fake precision.
4. **Android OEM battery killers vs. the alert upload** — mitigation:
   durable outbox + retry, never fire-and-forget.
5. **E2E key rotation with an offline child** — mitigation: `key_version`
   in the blob; old key retained until all installs ack (existing sync
   machinery).

## 12. Owner decisions needed

1. **Push approach**: real-time worker push (recommended) vs polling
   fallback. (Needs FCM/APNs credentials from Adam either way for the
   real thing.)
2. **Default zone radius**: 300 m is the working default; Adam may want
   200 / 500.
3. **Dwell alerts** ("still at School 30 min after pickup time"): in
   scope or later?
4. **Field testing**: Adam's iPad + a phone on TestFlight/internal-track
   with the stated test script — needs his OK to enroll the builds.

## 13. Build phases (after decisions)

- **P1 — Zones data + sync + hub editor UI** (Flutter only; verifiable on
  web Preview): model, E2E blob field, hub Safe-zones card + map editor,
  tests.
- **P2 — Child-side geofencing** (native plugin + permissions + outbox):
  needs native builds; simulator/emulator verification.
- **P3 — Worker push fanout + token registry**: needs Adam's FCM/APNs
  credentials.
- **P4 — Field test matrix** on TestFlight/internal-track, then Preview
  deploy of the web build.
