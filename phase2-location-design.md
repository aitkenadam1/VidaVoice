# OneVoz Phase 2 — Location Services: Design

**Status:** DRAFT for Adam's review. Design only — no code changes.
**Date:** 2026-09-16
**Decision log:**
- 2026-09-16 — Adam approved MapLibre (flutter_map) over Google Maps (Decision 1).
- 2026-09-16 — Adam approved all remaining recommendations (Decisions 2–7):
  on-demand sharing first, 30-day history retention, 90-day alert retention,
  MapTiler hosted tiles, tappable maps link in emergency SMS, pre-authorized
  auto-share allowed. **Design fully approved — ready to build.**
**Context:** Phase 1 (live on `https://preview.onevoz.me`) has no real GPS by design.
`lib/services/location_service.dart` exposes a `LocationService` abstraction with a
`NoopLocationService`; the `{gps}` token in `composeEmergencySms` resolves to `''`
and the emergency screen shows "location unavailable" plus a "location sharing
arrives in a later update" strip. This doc designs the real thing.

## 1. Non-negotiable constraints (from Adam)

- **Offline-first.** Cloud failure never blocks communication. Location features
  degrade to "location unavailable" — never a dead button, never a crash.
- **E2E encryption.** Dashboard configs sync as opaque AES-GCM blobs the server
  never decrypts. Location is *more* sensitive than board content: the server
  stores only ciphertext+nonce, never plaintext coordinates. Caregiver devices
  decrypt with the family key (PBKDF2-SHA256, 600k iterations, per-family
  `sync_salt`, AES-GCM-256 — the exact scheme in
  `lib/services/dashboard_sync_service.dart`, reused, not reinvented).
- **No content in logs.** The proxy's audit trail records no utterance text by
  design; location history gets the same treatment — coordinates never appear in
  logs, error messages, push payloads, or admin views.
- **COPPA.** Users include children under 13. Parental consent, data
  minimization, retention limits, no third-party sharing of a child's location.
  (Details in §9.)
- **Device licensing.** 3 devices per family (Plus adds 1). Location sharing is
  per registered device; a removed device's location data is purged and its
  uploads rejected.
- **No half-building.** If a platform can't do it (web has no background
  execution or push), the design says so plainly and the UI says so honestly.

## 2. Architecture: device-side first, server as dumb encrypted relay

The core decision: **the server never sees a plaintext coordinate.** All
intelligence (position capture, geofence evaluation, history assembly) runs on
the family's own devices. The Cloudflare worker is an authenticated,
rate-limited blob store plus a push fan-out that routes on *plaintext event
kinds only* (`geofence_exit`, `share_started`), never on location content.

This mirrors the dashboard-sync pattern that already passed review
(`PUT/GET /v1/sync/dashboards`, `GET /v1/sync/salt`), so the security argument
is already settled: same key derivation, same "ciphertext never logged" rule,
same family-scoped bearer auth.

## 3. Sharing model

**Recommendation: on-demand time-boxed sessions first (Phase 2A), opt-in
continuous background later (Phase 2B).**

- **2A — On-demand "Share my location".** The child's device (or the caregiver,
  remotely requesting) starts a sharing session: 15 / 30 / 60 minutes or "until
  turned off". While active, the device uploads an encrypted position ping every
  60 seconds (foreground) to `PUT /v1/sync/location/latest`. Any caregiver
  device with the family key polls and decrypts. When the timer expires or the
  caregiver stops it, uploads stop and the server keeps only the last-known
  blob (marked stale after 24h).
- **2B — Continuous background + geofencing.** Same pipeline, but the child's
  device keeps uploading in the background (native only — see §8) and evaluates
  geofences locally.

Why not continuous-first: 24/7 background location is the most
battery-expensive, most permission-hostile (Google Play subjects
`ACCESS_BACKGROUND_LOCATION` to a policy review with prominent disclosure),
and most COPPA-sensitive mode. On-demand sessions are complete and useful on
their own — "share for the walk home from school" — and they work on web,
where background execution doesn't exist.

Per-profile opt-in, controlled by the caregiver in the caregiver-gated section:
location sharing defaults **OFF** for every profile; turning it on is an
explicit caregiver action per child, recorded with a timestamp (consent
record, §9).

## 4. Caregiver map

**Where it lives:** a new "Location" section inside `CaregiverScreen` (the
caregiver-gated hub). Never on the child board. The child-facing UI gets only
two things: a sharing status indicator ("Sharing location with Mom · 23 min
left · Stop") and the emergency-screen GPS line.

**What it shows:**
- Live position of each device currently sharing (decrypted client-side),
  with accuracy radius and "updated N min ago / stale" honesty labels.
- History trail for a selected device and time window (decrypted points from
  `GET /v1/sync/location/points`).
- Geofence list (home, school, custom) with enter/exit alert toggles.
- "Request location" — sends a push to the child's device asking it to start
  a 15-minute share (the child device auto-starts only if the caregiver
  pre-authorized auto-share for that profile; otherwise it prompts — no silent
  tracking without prior consent).

**Map SDK recommendation: MapLibre via `flutter_map` — not Google Maps.**

| | MapLibre / flutter_map | Google Maps (`google_maps_flutter`) |
|---|---|---|
| Key / billing | None. No API key, no billing account | API key + billing account; ~$7/1k map loads after $200/mo credit |
| Child-location data to third party | Tile requests only (IP visible to tile CDN — disclosable, minimizable) | Position context rendered on Google tiles; key must be per-platform restricted |
| Offline | Full offline tile packs — aligns with offline-first | ToS restricts bulk/offline tile caching |
| Satellite imagery | Via provider (MapTiler) | Best-in-class, familiar UX |
| Web support | Excellent (works in Preview today) | Works, heavier |

Google Maps is the more familiar UX, but it adds a billing account, API-key
rotation burden, and weaker offline story to a nonprofit-priced family app.
**Recommendation: `flutter_map` + MapLibre vector tiles via MapTiler**
(generous free tier: 100k tile requests/mo; a family app won't touch it).
Self-hosted OSM tiles remain an option later for full data control.

> **Implementation note (Phase 2A, 2026-09-16):** the caregiver map ships
> with MapTiler **raster** tiles (`streets-v2/{z}/{x}/{y}.png`) rendered by
> `flutter_map`'s built-in `TileLayer`, not vector tiles. Rationale: vector
> rendering needs an extra package plus Mapbox-style parsing for zero
> user-visible gain in Phase 2A (a street map with position + accuracy circle
> + trail renders identically), and Adam's approved decision #5 reads
> "MapTiler-hosted map tiles". The MapTiler key, attribution, and privacy
> posture are unchanged. If vector rendering (crisper zoom, smaller
> payloads) is wanted later, it can replace the `TileLayer` without touching
> the sharing, encryption, or alert protocol.

## 5. Geofencing

**Evaluation happens on the child's device, not the server.** Server-side
evaluation would require plaintext coordinates on the worker — a direct
violation of the E2E promise. Instead:

1. Caregiver defines safe zones (home, school, custom circle, name + radius)
   on their device.
2. Zones sync as an E2E blob (`PUT /v1/sync/geofences`) to the child's device,
   which decrypts with the family key.
3. The child's device evaluates enter/exit locally (native: `GeofencingClient`
   on Android, region monitoring on iOS; web/2A: checked on each foreground
   ping).
4. On a transition, the child's device uploads an **encrypted alert event**
   (`POST /v1/alerts {install_id, kind: "geofence_exit", ciphertext, nonce}`)
   where `kind` is plaintext (so the worker can route push) and everything
   else — which zone, coordinates, timestamp detail — is ciphertext.
5. The worker fans out a push to the family's caregiver devices. **Push
   payloads carry no location** — just "Geofence alert — open OneVoz". The app
   fetches and decrypts on open. Google/Apple never see a coordinate.

Web limitation (stated plainly): no background execution, so web gets
geofence checks only while the tab is open. Full geofencing is native-only
(2B).

## 6. Alert history

- **What's recorded:** encrypted alert events (geofence enter/exit, share
  start/stop, SOS). Plaintext columns: `id`, `family_id`, `device_install_id`,
  `kind`, `ts`. Encrypted columns: `ciphertext`, `nonce` (zone name,
  coordinates, message).
- **Where:** `alert_events` D1 table; caregiver devices fetch
  `GET /v1/alerts?since=` and decrypt locally. Admin views see kinds and
  counts only — never content.
- **Retention:** 90 days, then hard-deleted by a scheduled worker cron
  (default; Adam decides — see Decisions). Family erasure
  (`DELETE /admin/v1/families/{id}`) already exists and must cascade to all
  location tables.
- **SOS alerts** (child-triggered from the emergency screen) skip the sharing
  opt-in: an SOS always uploads one encrypted position + alert, because the
  child explicitly asked for help. This is stated in the consent copy.

## 7. Emergency flow integration

`EmergencyScreen` already calls `locationService.currentCoords()` in
`initState` and threads `_gps` through `composeEmergencySms` and the bystander
card. Phase 2 changes only the implementation behind the abstraction:

- New `GpsLocationService implements LocationService` (geolocator plugin):
  returns `"40.7128,-74.0060"` (and accuracy); returns `null` on denied
  permission, timeout (10s cap — the emergency screen must never hang), or web
  without permission.
- `composeEmergencySms`: the GPS segment becomes
  `GPS: 40.7128,-74.0060. Map: https://maps.google.com/?q=40.7128,-74.0060`
  — a tappable link is genuinely useful to dispatchers/first responders and
  costs ~40 chars. Omitted entirely when null (current honest behavior kept).
- The "location sharing arrives in a later update" strip is replaced by a live
  strip: "GPS ready" / "Location unavailable — texts will use your saved
  address".
- Bystander card: shows coordinates or "location unavailable" (already
  handled).

## 8. Push infrastructure (native only — not web)

Real-time geofence/emergency alerts need FCM (Android) + APNs (iOS) via
`firebase_messaging`. This is the heaviest infra in Phase 2:

- **Worker side:** FCM v1 API (service-account JSON in worker secrets) +
  APNs token-based auth (.p8 key in secrets). New `push_tokens` table
  (`install_id`, `platform`, `token`, `updated_at`); endpoints
  `POST /v1/push-tokens` / `DELETE /v1/push-tokens/{install_id}`.
- **App side:** native builds with Firebase configured, `UIBackgroundModes`
  (`remote-notification`, `location`) on iOS, `ACCESS_FINE_LOCATION` /
  `ACCESS_BACKGROUND_LOCATION` + `FOREGROUND_SERVICE_LOCATION` on Android.
  **Google Play will require a prominent in-app disclosure and a background-
  location declaration review** — plan for a review round, not a silent
  approval.
- **What works where (explicit):**
  - *Web Preview:* on-demand sharing while the tab is open, live map,
    history trail, geofence checks in foreground. **No background uploads,
    no push, no background geofence alerts.** The UI says exactly this.
  - *Native (App Store / Play):* everything, including background sharing,
    OS-level geofencing, and push alerts.

## 9. COPPA & privacy

- **Consent:** the account holder is the verified caregiver (email/username +
  password account). Location sharing is OFF by default per profile; enabling
  it is an explicit caregiver toggle with a plain-language disclosure
  ("OneVoz will record [child]'s location while sharing is on…"). The toggle
  timestamp is stored (locally + in the encrypted profile blob) as the
  consent record. No data is collected directly from the child — every
  location feature is caregiver-configured.
- **Minimization:** no 24/7 passive collection in 2A; uploads only during an
  active session; 60s cadence (not 1s); accuracy capped at ~100m for history
  (exact fix only for live view and SOS).
- **Retention:** last-known blob marked stale after 24h; history points 30
  days; alerts 90 days (both Adam-decided, §12); hard delete via cron +
  cascade on family erasure.
- **No third-party sharing of child location:** coordinates never go to
  Google/Apple except the IP-visible tile fetches inherent to any map
  (disclosed in the privacy policy; MapTiler DPA). Push payloads contain no
  location. No analytics SDK sees location.
- **Privacy policy must be rewritten.** `src/legal/privacy.ts` currently
  states "We do **not** collect … location" — Phase 2 makes that false. The
  update adds a Location section: what's collected, when, retention, the
  child's controls (via caregiver), and the tile-provider disclosure. Ship
  the policy update *with* the feature, not after.

## 10. Backend: endpoints & schema

All `/v1/*` routes require the family bearer token; family scope comes from
the token, never client claims (existing convention). New migration
`0006_location.sql`:

```sql
-- Latest encrypted position per device: last-write-wins, like dashboard_blobs.
CREATE TABLE IF NOT EXISTS location_latest (
  family_id        TEXT NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  device_install_id TEXT NOT NULL,            -- FK to devices(install_id)
  ciphertext       TEXT NOT NULL,             -- base64 AES-GCM, opaque
  nonce            TEXT NOT NULL,             -- base64, 12 bytes
  version          INTEGER NOT NULL,
  updated_at       INTEGER NOT NULL,          -- unix ms
  PRIMARY KEY (family_id, device_install_id)
);

-- Encrypted history points. Server never decrypts; TTL-cleaned by cron.
CREATE TABLE IF NOT EXISTS location_points (
  id               TEXT PRIMARY KEY,
  family_id        TEXT NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  device_install_id TEXT NOT NULL,
  ciphertext       TEXT NOT NULL,
  nonce            TEXT NOT NULL,
  ts               INTEGER NOT NULL          -- unix ms, point time
);
CREATE INDEX IF NOT EXISTS idx_loc_points ON location_points (family_id, device_install_id, ts);

-- Caregiver-defined safe zones, E2E blob (same shape as dashboard_blobs).
CREATE TABLE IF NOT EXISTS geofence_blobs (
  family_id  TEXT PRIMARY KEY REFERENCES families(id) ON DELETE CASCADE,
  ciphertext TEXT NOT NULL,
  nonce      TEXT NOT NULL,
  version    INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

-- Alert events: kind is PLAINTEXT for push routing; content is ciphertext.
CREATE TABLE IF NOT EXISTS alert_events (
  id               TEXT PRIMARY KEY,
  family_id        TEXT NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  device_install_id TEXT NOT NULL,
  kind             TEXT NOT NULL,  -- geofence_enter | geofence_exit | share_started | share_stopped | sos
  ciphertext       TEXT NOT NULL,
  nonce            TEXT NOT NULL,
  ts               INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_alerts ON alert_events (family_id, ts);

-- Push routing tokens (device identifiers; plaintext by necessity).
CREATE TABLE IF NOT EXISTS push_tokens (
  install_id TEXT PRIMARY KEY REFERENCES devices(install_id) ON DELETE CASCADE,
  platform   TEXT NOT NULL,  -- android | ios
  token      TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);
```

Endpoints (all family-token authed, same validation discipline as
`src/routes/sync.ts` — base64/nonce/version checks, ciphertext never logged):

| Method | Path | Purpose |
|---|---|---|
| PUT | `/v1/sync/location/latest` | `{install_id, ciphertext, nonce, version}` — one ping |
| GET | `/v1/sync/location/latest?install_id=` | Latest blob / 404 |
| POST | `/v1/sync/location/points` | Batch `{install_id, points: [{ciphertext, nonce, ts}]}` (≤500/batch) |
| GET | `/v1/sync/location/points?install_id=&since=&until=` | Paginated encrypted history |
| PUT/GET | `/v1/sync/geofences` | E2E safe-zone blob |
| POST | `/v1/alerts` | `{install_id, kind, ciphertext, nonce}` → 200 + push fan-out |
| GET | `/v1/alerts?since=` | Alert list (kinds plaintext, content encrypted) |
| POST/DELETE | `/v1/push-tokens` | FCM/APNs token register/remove |

**Abuse/rate limits** (KV, existing `ratelimit.ts` pattern): latest-ping ≤ 1/min
per device; points batch ≤ 500/day/device; alerts ≤ 60/hour/family. No voice-
credit cost — location is abuse-limited, not quota-limited. Oversized blobs
rejected with 413 (same 5MB discipline as dashboard sync; location blobs are
bytes, so this is a formality).

**Device-delete cascade:** deleting a device (`DELETE /v1/devices/{id}`)
deletes its `location_latest` row, rejects further uploads from that
`install_id`, and removes its push token.

## 11. Battery & data

- 2A foreground: 60s GPS cadence ≈ negligible (<2%/hr on modern phones);
  batched point uploads (every 5 min) rather than per-ping POSTs.
- 2B background: iOS significant-change + region monitoring (OS-managed, the
  cheapest option); Android `PRIORITY_BALANCED_POWER_ACCURACY` + GeofencingClient.
  Continuous high-accuracy background is explicitly *not* offered — no
  legitimate family-safety use case needs 1s GPS, and it would drain a phone
  by lunch.
- Payloads are tiny (a few hundred bytes of ciphertext per ping).

## 12. Phased rollout within Phase 2

- **2A — On-demand sharing + caregiver map (web + native).** `GpsLocationService`,
  share sessions, `location_latest`/`location_points`, caregiver map with
  flutter_map, emergency `{gps}` filled in. Shippable to Preview and genuinely
  useful. No push, no background, no geofencing.
- **2B — Background + geofencing + push (native only).** Background location
  permission flows, OS geofencing, FCM/APNs wiring, `alert_events`, alert
  history UI, SOS push. Requires App Store / Play builds; cannot be verified
  on the web Preview — needs TestFlight/internal-track testing with Adam.
- **2C (optional, later):** self-hosted tiles, family location sharing
  between two caregiver accounts, location in the "what-to-say" phrase
  cards (`{gps}` in `resolvePlaceholders` already supports it).

## 13. What changes in existing code (no code in this doc)

- `lib/services/location_service.dart`: add `GpsLocationService`
  (geolocator); keep `NoopLocationService` for web-without-permission and
  tests. `EmergencyScreen` already injects the service — no screen changes
  needed for the SMS path, only the "later update" strip copy.
- `CaregiverScreen`: new "Location" section (gated, collapsed by default).
- `pubspec.yaml`: `geolocator`, `flutter_map`, `latlong2`, `firebase_messaging`
  (2B), `flutter_local_notifications` (2B, foreground alert display).
- Proxy: `src/routes/location.ts` (new), `src/lib/push.ts` (new, 2B),
  migration `0006_location.sql`, cron for TTL cleanup, privacy policy rewrite.

## 14. DECISIONS NEEDED FROM ADAM

1. **Map SDK: MapLibre (recommended) vs Google Maps.** Recommendation:
   MapLibre via `flutter_map` — no API key, no billing account, offline tile
   packs fit offline-first, and no child-location context on Google's tiles.
   Tradeoff: Google Maps has more familiar satellite imagery and UX.
2. **Sharing model: on-demand sessions (recommended) vs continuous
   background.** Recommendation: on-demand first (2A) — "share for the walk
   home" covers the real use cases, works on web, sips battery, and is the
   least COPPA-sensitive. Tradeoff: no always-on awareness until 2B.
3. **History retention: 30 days (recommended) vs longer/shorter.**
   Recommendation: 30 days — enough for "where was she last Tuesday", short
   enough to defend. Tradeoff: longer helps pattern review, but every extra
   day is extra sensitive data at rest.
4. **Alert retention: 90 days (recommended) vs longer/shorter.**
   Recommendation: 90 days for geofence/SOS alerts. Tradeoff: same as (3).
5. **Tile provider: MapTiler hosted (recommended) vs self-hosted OSM.**
   Recommendation: MapTiler — free tier covers a family app 100x over, zero
   ops. Tradeoff: self-hosting gives full data control but is a server to
   run and pay for.
6. **Emergency SMS: include a tappable maps link (recommended) vs
   coordinates only.** Recommendation: include
   `https://maps.google.com/?q=lat,lon` — dispatchers tap, nobody retypes
   coordinates in a crisis. Tradeoff: ~40 extra characters in a 160-char SMS
   segment.
7. **Auto-share on "Request location": allow the caregiver to pre-authorize
   auto-start (recommended) vs always prompt the child's device.**
   Recommendation: allow pre-authorization per profile (explicit opt-in, in
   the consent copy) — a prompt nobody hears defeats the safety purpose.
   Tradeoff: "always prompt" is the stricter privacy posture, but a missed
   prompt in an emergency is worse.
