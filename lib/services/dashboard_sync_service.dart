import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/dashboard.dart';
import '../models/calling_safety.dart';
import '../models/safe_zone.dart';
import 'dashboard_service.dart';
import 'elevenlabs_key_store.dart';
import 'profile_service.dart';
import 'proxy_client.dart';

/// End-to-end encrypted dashboard + profile sync across a family's devices.
///
/// PRIVACY CONTRACT (hard requirement): the synced payload contains the
/// family's AAC dashboard content — the child's words and phrases. It is
/// encrypted ON THIS DEVICE before upload and decrypted only on the
/// caregiver's devices. The server stores the blob opaquely: it never
/// decrypts, inspects, logs, analyzes, or returns anything but the stored
/// bytes. Plaintext dashboard/profile words must NEVER be sent to any
/// endpoint except inside this encrypted blob.
///
/// Key: PBKDF2-SHA256 (600k iterations) over the caregiver's password
/// with the per-family server salt, producing a 256-bit AES-GCM key. Only
/// a device where the caregiver typed the password can read the blob.
///
/// Merge policy: per-item last-write-wins, matched by [UserProfile.syncKey]
/// first with a case-insensitive name fallback (which adopts the synced
/// key so identities converge). No tombstones in v1: a profile deleted on
/// one device is NOT deleted on the others — for an AAC app, resurrecting
/// a deleted board is safer than propagating a mistaken delete.
class DashboardSyncService {
  DashboardSyncService({
    required this._proxy,
    required this._profiles,
    required this._dashboards,
    required this._prefsFactory,
    this._secureStore,
  });

  final ProxyClient _proxy;
  final ProfileService _profiles;
  final DashboardService _dashboards;
  final Future<SharedPreferences> Function() _prefsFactory;

  /// At-rest encryption (review m4): safe-zone definitions and device
  /// assignments are location data — they must not sit in plaintext
  /// SharedPreferences. When a secure store is wired (production), the
  /// five keys below persist there; a value still in prefs migrates on
  /// first read. Without one (tests), prefs remain the fallback.
  final SecureValueStore? _secureStore;

  /// Called after every mutation (merge, mirror change, sync-state update)
  /// so UI can rebuild.
  VoidCallback? onChanged;

  void _notify() => onChanged?.call();

  static const _kLastVersion = 'vidavoice.sync.lastVersion';
  static const _kLastSyncedAt = 'vidavoice.sync.lastSyncedAt';
  static const _kMirror = 'vidavoice.sync.mirrorActiveProfile';
  static const _kMirrorUpdatedAt = 'vidavoice.sync.mirrorUpdatedAt';

  /// Phase 2B safe zones: family-wide, stored as a JSON list inside the
  /// encrypted blob (doc type `safe_zones`) and mirrored in local prefs
  /// so zones survive restarts before the first pull completes.
  static const _kSafeZones = 'vidavoice.sync.safeZones';

  /// Device → communicator-profile assignments (install id → profile
  /// syncKey). Family-wide, inside the encrypted blob like safe zones,
  /// so every caregiver device agrees which device serves which
  /// communicator. The value is the profile's stable cross-device
  /// [UserProfile.syncKey] — never a local profile id, which means
  /// nothing on any other device. Both stay opaque to the server: they
  /// travel only inside the ciphertext.
  static const _kDeviceAssignments = 'vidavoice.sync.deviceAssignments';

  /// Tombstone/metadata companions for safe zones and device
  /// assignments (see the state fields below).
  static const _kSafeZoneTombstones = 'vidavoice.sync.safeZoneTombstones';
  static const _kAssignmentMeta = 'vidavoice.sync.deviceAssignmentMeta';
  static const _kAssignmentTombstones =
      'vidavoice.sync.deviceAssignmentTombstones';

  /// PBKDF2 iteration count for the sync key. Production value; tests pass
  /// a small count for speed via [deriveSyncKey]'s parameter.
  static const defaultPbkdf2Iterations = 600000;

  List<int>? _key;
  int _lastSeenRemoteVersion = 0;
  bool _mirror = false;

  /// Family-wide safe zones (Phase 2B). Kept in memory, persisted to
  /// local prefs, and published inside the encrypted payload.
  final List<SafeZone> _zones = [];

  /// Deleted-zone tombstones (zone id → when it was deleted). Without
  /// these, a zone deleted on one device would be re-adopted from any
  /// other device's stale blob on the next merge. Tombstones travel
  /// inside the encrypted payload like the zones themselves and are
  /// kept indefinitely (a handful of ids — negligible size).
  final Map<String, DateTime> _zoneTombstones = {};

  /// install_id → profile syncKey assignments. Kept in memory,
  /// persisted to local prefs, and published inside the encrypted
  /// payload.
  final Map<String, String> _deviceAssignments = {};

  /// Per-install assignment timestamps (ms) and cleared-assignment
  /// tombstones. Merges are last-write-wins per install; without the
  /// tombstones, clearing an assignment on one device would be undone
  /// by any other device re-publishing its older copy.
  final Map<String, int> _assignmentUpdatedMs = {};
  final Map<String, int> _assignmentTombstones = {};

  /// When the mirror flag was last changed locally. The flag itself is
  /// last-write-wins across devices, like profile/dashboard content.
  DateTime? _mirrorUpdatedAt;
  Timer? _pushTimer;

  /// Auto-push stays off until the first pull completes (boot/sign-in),
  /// so a stale local state can never clobber a newer server blob before
  /// we've seen it.
  bool autoPushEnabled = false;

  /// Last completed sync time, for the caregiver UI.
  DateTime? lastSyncedAt;

  /// Human-readable outcome of the last sync attempt, for the UI.
  String? lastMessage;

  bool get hasKey => _key != null && _key!.length == 32;

  /// The raw 32-byte sync key, for sibling E2E services (e.g. location
  /// sharing) that encrypt blobs the server stores opaquely under the
  /// same no-content guarantee. Null when no key is derived. Callers must
  /// never log, transmit, or persist these bytes outside an encrypted blob.
  List<int>? get keyBytes => _key == null ? null : List<int>.of(_key!);

  bool get mirrorActiveProfile => _mirror;

  /// The family's safe zones (Phase 2B). Unmodifiable; mutate through
  /// [upsertSafeZone]/[removeSafeZone] so persistence, sync, and
  /// listeners stay consistent.
  List<SafeZone> get safeZones => List.unmodifiable(_zones);

  /// Adds or replaces a zone by id, persists locally, and notifies
  /// listeners. Callers push explicitly (e.g. [pushNow]) when they want
  /// the change published immediately.
  Future<void> upsertSafeZone(SafeZone zone) async {
    final problems = zone.validate();
    if (problems.isNotEmpty) {
      throw ArgumentError('Invalid safe zone: ${problems.join(' ')}');
    }
    final next = [for (final z in _zones) if (z.id != zone.id) z, zone]
      ..sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    _zones
      ..clear()
      ..addAll(next);
    await _persistZones();
    _notify();
  }

  /// Removes a zone by id and records a tombstone, so the deletion
  /// propagates: other devices drop their copies instead of the zone
  /// being re-adopted from a stale blob on the next merge. A zone only
  /// comes back if it is edited AFTER the deletion (newer updatedTs).
  Future<void> removeSafeZone(String id) async {
    _zones.removeWhere((z) => z.id == id);
    _zoneTombstones[id] = DateTime.now();
    await _persistZones();
    await _persistZoneTombstones();
    _notify();
  }

  /// Reads a sensitive key from the secure store when wired. A value
  /// still in plaintext prefs (pre-m4 install) is returned and migrated
  /// up best-effort. Null store → prefs only.
  Future<String?> _secureGet(String key) async {
    final store = _secureStore;
    if (store != null) {
      try {
        final v = await store.read(key);
        if (v != null) return v;
      } catch (_) {}
    }
    String? legacy;
    try {
      final prefs = await _prefsFactory();
      legacy = prefs.getString(key);
    } catch (_) {}
    if (store != null && legacy != null) {
      try {
        await store.write(key, legacy);
        final prefs = await _prefsFactory();
        await prefs.remove(key);
      } catch (_) {}
    }
    return legacy;
  }

  /// Writes a sensitive key to the secure store when wired (and evicts
  /// any plaintext prefs copy). On a store failure the plaintext copy is
  /// dropped so reads never come back stale; prefs stay the last resort.
  Future<void> _secureSet(String key, String value) async {
    final store = _secureStore;
    if (store != null) {
      try {
        await store.write(key, value);
        final prefs = await _prefsFactory();
        await prefs.remove(key);
        return;
      } catch (_) {
        try {
          await store.delete(key);
        } catch (_) {}
      }
    }
    final prefs = await _prefsFactory();
    await prefs.setString(key, value);
  }

  Future<void> _persistZones() async {
    try {
      await _secureSet(
        _kSafeZones,
        json.encode([for (final z in _zones) z.toJson()]),
      );
    } catch (_) {}
  }

  Future<void> _persistZoneTombstones() async {
    try {
      await _secureSet(
        _kSafeZoneTombstones,
        json.encode({
          for (final e in _zoneTombstones.entries)
            e.key: e.value.millisecondsSinceEpoch,
        }),
      );
    } catch (_) {}
  }

  /// Parses zone tombstones out of a payload (list of {id, deleted_ts})
  /// or local prefs ({id: deleted_ms}). Malformed entries are skipped.
  Map<String, DateTime> _parseZoneTombstones(Object? raw) {
    final out = <String, DateTime>{};
    void put(String id, Object? v) {
      if (id.isEmpty) return;
      DateTime? ts;
      if (v is int) {
        ts = DateTime.fromMillisecondsSinceEpoch(v);
      } else if (v is num) {
        ts = DateTime.fromMillisecondsSinceEpoch(v.toInt());
      } else if (v is String) {
        ts = DateTime.tryParse(v);
      }
      if (ts != null) out[id] = ts;
    }

    if (raw is List) {
      for (final entry in raw) {
        if (entry is! Map) continue;
        put(entry['id']?.toString() ?? '', entry['deleted_ts']);
      }
    } else if (raw is Map) {
      for (final entry in raw.entries) {
        put(entry.key.toString(), entry.value);
      }
    }
    return out;
  }

  /// A zone survives its tombstone only when it was mutated after the
  /// deletion (a genuine later edit — never a stale copy).
  bool _zoneSurvives(SafeZone z, Map<String, DateTime> tombstones) {
    final t = tombstones[z.id];
    return t == null || z.updatedTs.isAfter(t);
  }

  List<SafeZone> _parseZones(Object? raw) {
    final out = <SafeZone>[];
    if (raw is! List) return out;
    for (final entry in raw) {
      if (entry is! Map) continue;
      try {
        out.add(SafeZone.fromJson(Map<String, dynamic>.from(entry)));
      } catch (_) {
        // One bad zone must not abort the whole merge.
      }
    }
    return out;
  }

  /// Translates an assignment value to the profile's stable syncKey.
  /// Blobs written before assignments carried sync identity hold LOCAL
  /// profile ids, which only mean something on the device that created
  /// them; when this device knows that local id, the value upgrades so
  /// it converges family-wide. A value that already is a syncKey — or
  /// that matches nothing known here — passes through untouched: it
  /// may resolve once the profile itself syncs in.
  String _normalizeAssignmentValue(String value) {
    if (_profiles.bySyncKey(value) != null) return value;
    for (final p in _profiles.profiles) {
      if (p.id == value) return p.syncKey;
    }
    return value;
  }

  /// Normalizes every stored assignment value in place. Returns true
  /// when at least one value changed (callers re-persist/publish then).
  bool _normalizeAssignments() {
    var changed = false;
    for (final installId in _deviceAssignments.keys.toList()) {
      final v = _normalizeAssignmentValue(_deviceAssignments[installId]!);
      if (v != _deviceAssignments[installId]) {
        _deviceAssignments[installId] = v;
        changed = true;
      }
    }
    return changed;
  }

  /// The family's device → profile assignments (install id → profile
  /// syncKey). Unmodifiable; mutate through [setDeviceAssignment] so
  /// persistence, sync, and listeners stay consistent.
  Map<String, String> get deviceAssignments =>
      Map.unmodifiable(_deviceAssignments);

  /// Assigns the device [installId] to a communicator profile, or
  /// clears the assignment when [profileKey] is null. [profileKey] is
  /// the profile's stable syncKey; a local profile id is also accepted
  /// and upgraded, so older callers and blobs migrate transparently.
  /// Persists locally and notifies listeners; callers push explicitly
  /// (e.g. [pushNow]) when they want the change published immediately.
  Future<void> setDeviceAssignment(String installId, String? profileKey) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (profileKey == null || profileKey.isEmpty) {
      // Clearing records a tombstone: without one, any device still
      // holding the old assignment would resurrect it on the next merge.
      _deviceAssignments.remove(installId);
      _assignmentUpdatedMs.remove(installId);
      _assignmentTombstones[installId] = nowMs;
    } else {
      _deviceAssignments[installId] = _normalizeAssignmentValue(profileKey);
      _assignmentUpdatedMs[installId] = nowMs;
    }
    await _persistAssignments();
    _notify();
  }

  Future<void> _persistAssignments() async {
    try {
      await _secureSet(
        _kDeviceAssignments,
        json.encode(_deviceAssignments),
      );
      await _secureSet(
        _kAssignmentMeta,
        json.encode(_assignmentUpdatedMs),
      );
      await _secureSet(
        _kAssignmentTombstones,
        json.encode(_assignmentTombstones),
      );
    } catch (_) {}
  }

  /// Parses an install-id → milliseconds map (assignment meta /
  /// tombstones) out of a payload or local prefs blob. Malformed
  /// entries are skipped, never fatal.
  Map<String, int> _parseMsMap(Object? raw) {
    final out = <String, int>{};
    if (raw is! Map) return out;
    for (final entry in raw.entries) {
      final k = entry.key.toString();
      final v = entry.value;
      final ms = v is int ? v : (v is num ? v.toInt() : null);
      if (k.isNotEmpty && ms != null) out[k] = ms;
    }
    return out;
  }

  /// Parses the device_assignments map out of a payload or local prefs
  /// blob. Malformed entries are skipped, never fatal.
  Map<String, String> _parseAssignments(Object? raw) {
    final out = <String, String>{};
    if (raw is! Map) return out;
    for (final entry in raw.entries) {
      final k = entry.key.toString();
      final v = entry.value?.toString() ?? '';
      if (k.isNotEmpty && v.isNotEmpty) out[k] = v;
    }
    return out;
  }

  void setKey(List<int> key) {
    _key = List<int>.of(key);
  }

  void clearKey() {
    _key = null;
    _pushTimer?.cancel();
    autoPushEnabled = false;
  }

  /// Loads the persisted mirror flag and last-sync timestamp.
  Future<void> loadPersisted() async {
    try {
      final prefs = await _prefsFactory();
      _mirror = prefs.getBool(_kMirror) ?? false;
      final mirrorAt = prefs.getInt(_kMirrorUpdatedAt);
      _mirrorUpdatedAt = mirrorAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(mirrorAt);
      final at = prefs.getInt(_kLastSyncedAt);
      lastSyncedAt = at == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(at);
      _lastSeenRemoteVersion = prefs.getInt(_kLastVersion) ?? 0;
      // Sensitive keys (zones/assignments) come from the secure store
      // when wired; _secureGet migrates any legacy plaintext copy (m4).
      _zoneTombstones
        ..clear()
        ..addAll(
          _parseZoneTombstones(
            _tryDecodeZones(await _secureGet(_kSafeZoneTombstones)),
          ),
        );
      _zones
        ..clear()
        ..addAll(
          _parseZones(
            _tryDecodeZones(await _secureGet(_kSafeZones)),
          ).where((z) => _zoneSurvives(z, _zoneTombstones)),
        );
      _assignmentUpdatedMs
        ..clear()
        ..addAll(
          _parseMsMap(_tryDecodeZones(await _secureGet(_kAssignmentMeta))),
        );
      _assignmentTombstones
        ..clear()
        ..addAll(
          _parseMsMap(
            _tryDecodeZones(await _secureGet(_kAssignmentTombstones)),
          ),
        );
      _deviceAssignments
        ..clear()
        ..addAll(
          _parseAssignments(
            _tryDecodeZones(await _secureGet(_kDeviceAssignments)),
          ),
        );
      // A locally-cleared assignment stays cleared even if the values
      // blob still holds a stale copy: tombstones win ties at load.
      for (final installId in _deviceAssignments.keys.toList()) {
        final tomb = _assignmentTombstones[installId];
        if (tomb != null && tomb >= (_assignmentUpdatedMs[installId] ?? 0)) {
          _deviceAssignments.remove(installId);
          _assignmentUpdatedMs.remove(installId);
        }
      }
      // Migrate legacy local-id values to syncKeys when the profiles
      // they name are already known on this device. Best-effort at
      // this stage of boot — merge/push normalize again once profiles
      // have fully loaded and converged.
      if (_normalizeAssignments()) await _persistAssignments();
      _notify();
    } catch (_) {}
  }

  /// Local prefs hold a JSON string; tolerate anything corrupt by
  /// treating it as "no zones".
  Object? _tryDecodeZones(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return json.decode(raw);
    } catch (_) {
      return null;
    }
  }

  /// Derives the 32-byte sync key from the caregiver password and the
  /// server-issued per-family salt (base64).
  static Future<List<int>> deriveSyncKey(
    String password,
    String saltB64, {
    int iterations = defaultPbkdf2Iterations,
  }) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    final derived = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: base64.decode(saltB64),
    );
    return await derived.extractBytes();
  }

  /// AES-GCM-256 encryption with a fresh random 12-byte nonce. Returns
  /// base64 (ciphertext‖mac) and base64 nonce.
  static Future<EncryptedBlob> encrypt(
    List<int> key,
    String payloadJson,
  ) async {
    final algorithm = AesGcm.with256bits();
    final secretKey = await algorithm.newSecretKeyFromBytes(key);
    final nonce = algorithm.newNonce();
    final box = await algorithm.encrypt(
      utf8.encode(payloadJson),
      secretKey: secretKey,
      nonce: nonce,
    );
    final combined = Uint8List.fromList(box.cipherText + box.mac.bytes);
    return EncryptedBlob(
      ciphertext: base64.encode(combined),
      nonce: base64.encode(nonce),
    );
  }

  /// Decrypts a blob produced by [encrypt]. Throws on wrong key or
  /// tampered data (callers must never merge the result on failure).
  static Future<String> decrypt(
    List<int> key,
    String ciphertextB64,
    String nonceB64,
  ) async {
    final algorithm = AesGcm.with256bits();
    final secretKey = await algorithm.newSecretKeyFromBytes(key);
    final combined = base64.decode(ciphertextB64);
    final nonce = base64.decode(nonceB64);
    // Wire format is ciphertext || tag; the tag is the last 16 bytes.
    const tagLen = 16;
    if (combined.length < tagLen) {
      throw const FormatException('sync blob too short');
    }
    final cipher = combined.sublist(0, combined.length - tagLen);
    final tag = combined.sublist(combined.length - tagLen);
    final box = SecretBox(cipher, nonce: nonce, mac: Mac(tag));
    final clear = await algorithm.decrypt(box, secretKey: secretKey);
    return utf8.decode(clear);
  }

  /// Builds the plaintext payload. This exact structure is what gets
  /// encrypted — nothing here ever leaves the device unencrypted.
  Map<String, dynamic> buildPayload() {
    final active = _profiles.active;
    final dashboards = <String, dynamic>{};
    for (final p in _profiles.profiles) {
      final d = _dashboards.forProfile(p.id);
      if (d != null) dashboards[p.syncKey] = d.toJson();
    }
    return {
      'version': 1,
      'updatedAt': DateTime.now().toIso8601String(),
      'mirrorActiveProfile': _mirror,
      'mirrorUpdatedAt': _mirrorUpdatedAt?.toIso8601String(),
      'activeProfileSyncKey': active?.syncKey,
      'activeProfileName': active?.name,
      'profiles': [
        for (final p in _profiles.profiles)
          {
            'syncKey': p.syncKey,
            'name': p.name,
            'mode': p.communicationMode.name,
            'buildMaxSymbols': p.buildMaxSymbols,
            'predictionEnabled': p.predictionEnabled,
            'nudgePreference': p.modeNudgePreference.name,
            // Phase 1 calling & safety rides the encrypted blob with the
            // rest of the per-profile content — never plaintext.
            'contacts': p.contacts.map((c) => c.toJson()).toList(),
            'callPhrases': p.callPhrases.map((cp) => cp.toJson()).toList(),
            'emergency': p.emergency.toJson(),
            'safety': p.safety.toJson(),
            // Phase 2A location opt-in + consent record ride the encrypted
            // blob with the rest of the per-profile content — never
            // plaintext. All devices agree on whether sharing is allowed.
            'locationSharingEnabled': p.locationSharingEnabled,
            'locationSharingConsentAt':
                p.locationSharingConsentAt?.toIso8601String(),
            'locationAutoShare': p.locationAutoShare,
            'updatedAt': p.updatedAt.toIso8601String(),
          },
      ],
      'dashboards': dashboards,
      // Phase 2B safe zones: family-wide zone definitions. Coordinates
      // and names live ONLY inside this encrypted blob — the server
      // stores the ciphertext opaquely, exactly like dashboard words.
      'safe_zones': [for (final z in _zones) z.toJson()],
      // Deleted-zone tombstones, so a deletion on one device is not
      // undone by another device's stale copy on the next merge.
      'safe_zone_tombstones': [
        for (final e in _zoneTombstones.entries)
          {'id': e.key, 'deleted_ts': e.value.millisecondsSinceEpoch},
      ],
      // Device → communicator-profile assignments (install id →
      // profile syncKey). Meaningless outside the family — encrypted
      // like everything else in this payload.
      'device_assignments': Map<String, String>.of(_deviceAssignments),
      // Per-install assignment timestamps + clear tombstones: merges
      // are last-write-wins per install, and a cleared assignment
      // stays cleared (see _mergeInner).
      'device_assignment_meta': Map<String, int>.of(_assignmentUpdatedMs),
      'device_assignment_tombstones': Map<String, int>.of(
        _assignmentTombstones,
      ),
    };
  }

  /// Uploads the current local state as a new encrypted blob.
  /// Best-effort: throws [ProxyException] on transport/server errors —
  /// callers decide whether to surface it.
  Future<void> pushNow() async {
    final key = _key;
    if (key == null || !_proxy.hasToken) return;
    // Publish syncKeys, never local profile ids: upgrade anything a
    // legacy blob left behind now that profiles are loaded.
    if (_normalizeAssignments()) await _persistAssignments();
    final prefs = await _prefsFactory();
    final blob = await encrypt(key, json.encode(buildPayload()));
    final nextVersion =
        math.max(prefs.getInt(_kLastVersion) ?? 0, _lastSeenRemoteVersion) + 1;
    final res = await _proxy.putDashboardBlob(
      ciphertext: blob.ciphertext,
      nonce: blob.nonce,
      version: nextVersion,
    );
    final stored = (res['version'] as num?)?.toInt() ?? nextVersion;
    await prefs.setInt(_kLastVersion, stored);
    _lastSeenRemoteVersion = math.max(_lastSeenRemoteVersion, stored);
    await _recordSync(prefs, 'Dashboards synced.');
  }

  /// Downloads and merges the family's blob. Returns what changed.
  /// A 404 (never synced) is a no-op, not an error.
  Future<DashboardSyncResult> pullNow() async {
    final result = DashboardSyncResult();
    final key = _key;
    if (key == null || !_proxy.hasToken) return result;
    final prefs = await _prefsFactory();
    final blob = await _proxy.getDashboardBlob();
    if (blob == null) return result;
    final version = (blob['version'] as num?)?.toInt() ?? 0;
    _lastSeenRemoteVersion = math.max(_lastSeenRemoteVersion, version);
    final ciphertext = blob['ciphertext']?.toString() ?? '';
    final nonce = blob['nonce']?.toString() ?? '';
    if (ciphertext.isEmpty || nonce.isEmpty) return result;
    late Map<String, dynamic> payload;
    try {
      final clear = await decrypt(key, ciphertext, nonce);
      payload = json.decode(clear) as Map<String, dynamic>;
    } catch (_) {
      // Wrong key or corrupt/tampered blob: never merge. (Happens if the
      // password was changed on another device — there is no password
      // change flow yet, so this should be rare.)
      await _recordSync(
        prefs,
        'Couldn\u2019t read the synced dashboards on this device.',
      );
      return result;
    }
    await _merge(payload, result);
    if (result.changed) {
      await _recordSync(prefs, 'Dashboards synced.');
    }
    return result;
  }

  /// Pull-then-push: converge with the family blob, then publish local
  /// state. Used after sign-in and for the manual "Sync now" button.
  Future<DashboardSyncResult> syncNow() async {
    final result = await pullNow();
    await pushNow();
    return result;
  }

  /// Schedules a debounced push (2s) after a local change. No-op until
  /// [autoPushEnabled] (set after the first pull) and only while signed
  /// in with a key — sync failures here are silent by design. Also a
  /// no-op while a remote merge is applying: the merge already reflects
  /// the server's content, so an echo push would just waste a write.
  void schedulePush() {
    if (_applyingRemote) return;
    if (!autoPushEnabled || !hasKey || !_proxy.hasToken) return;
    _pushTimer?.cancel();
    _pushTimer = Timer(const Duration(seconds: 2), () {
      unawaited(pushNow().then((_) {}, onError: (_) {}));
    });
  }

  /// Whether a debounced push is currently scheduled. Observability hook
  /// for tests and (later) UI; not part of the sync protocol.
  bool get hasScheduledPush => _pushTimer?.isActive ?? false;

  /// The caregiver's mirror toggle: when on, the active profile follows
  /// across devices. Persisted locally, synced inside the payload so all
  /// devices agree, and pushed immediately.
  Future<void> setMirror(bool value) async {
    _mirror = value;
    _mirrorUpdatedAt = DateTime.now();
    try {
      final prefs = await _prefsFactory();
      await prefs.setBool(_kMirror, value);
      await prefs.setInt(
        _kMirrorUpdatedAt,
        _mirrorUpdatedAt!.millisecondsSinceEpoch,
      );
    } catch (_) {}
    await pushNow();
    _notify();
  }

  Future<void> _recordSync(SharedPreferences prefs, String message) async {
    lastSyncedAt = DateTime.now();
    lastMessage = message;
    try {
      await prefs.setInt(_kLastSyncedAt, lastSyncedAt!.millisecondsSinceEpoch);
    } catch (_) {}
    _notify();
  }

  /// True while [_merge] is applying remote-originated changes to local
  /// state. Local mutation callbacks (wired to [schedulePush] by the
  /// session) must not fire for remote changes: the merge already
  /// reflects the server's content, so scheduling a push would echo the
  /// same bytes back and could ping-pong between devices.
  bool _applyingRemote = false;

  /// Merges a decrypted payload into local state. Per-item last-write-wins
  /// on [updatedAt]; unknown syncKeys with a matching local name are
  /// adopted (identity convergence); truly unknown profiles are created.
  /// Deleted profiles are deliberately NOT propagated (no tombstones).
  Future<void> _merge(
    Map<String, dynamic> payload,
    DashboardSyncResult result,
  ) async {
    _applyingRemote = true;
    try {
      await _mergeInner(payload, result);
    } finally {
      _applyingRemote = false;
    }
  }

  Future<void> _mergeInner(
    Map<String, dynamic> payload,
    DashboardSyncResult result,
  ) async {
    // The mirror flag is last-write-wins by timestamp: a caregiver who
    // toggled it while offline must not lose to a stale remote value.
    // Blobs written before the timestamp existed keep the old
    // remote-wins behavior.
    final rawMirrorAt = payload['mirrorUpdatedAt'];
    final remoteMirrorAt = rawMirrorAt is String
        ? DateTime.tryParse(rawMirrorAt)
        : null;
    final localMirrorAt = _mirrorUpdatedAt;
    if (remoteMirrorAt == null ||
        localMirrorAt == null ||
        remoteMirrorAt.isAfter(localMirrorAt)) {
      _mirror = payload['mirrorActiveProfile'] == true;
      _mirrorUpdatedAt = remoteMirrorAt ?? DateTime.now();
      try {
        final prefs = await _prefsFactory();
        await prefs.setBool(_kMirror, _mirror);
        await prefs.setInt(
          _kMirrorUpdatedAt,
          _mirrorUpdatedAt!.millisecondsSinceEpoch,
        );
      } catch (_) {}
    }

    final rawProfiles = payload['profiles'];
    if (rawProfiles is List) {
      for (final entry in rawProfiles) {
        if (entry is! Map) continue;
        try {
          await _mergeProfile(Map<String, dynamic>.from(entry), result);
        } catch (_) {
          // One bad profile entry must not abort the whole merge.
        }
      }
    }

    final rawDashboards = payload['dashboards'];
    if (rawDashboards is Map) {
      for (final entry in rawDashboards.entries) {
        final syncKey = entry.key;
        if (syncKey is! String || entry.value is! Map) continue;
        try {
          await _mergeDashboard(
            syncKey,
            Map<String, dynamic>.from(entry.value),
            result,
          );
        } catch (_) {
          // One bad dashboard must not abort the whole merge.
        }
      }
    }

    // Phase 2B safe zones: merge by id, last-writer-wins on updated_ts.
    // Family-wide — not per-profile. Bad zone entries are skipped, never
    // fatal to the merge. Tombstones merge per-id (latest deletion
    // wins) and filter the result, so a zone deleted anywhere stays
    // deleted everywhere unless it was edited after the deletion.
    final remoteZones = _parseZones(payload['safe_zones']);
    if (payload.containsKey('safe_zones') ||
        payload.containsKey('safe_zone_tombstones')) {
      final mergedTombs = Map<String, DateTime>.of(_zoneTombstones);
      for (final e
          in _parseZoneTombstones(payload['safe_zone_tombstones']).entries) {
        final cur = mergedTombs[e.key];
        if (cur == null || e.value.isAfter(cur)) mergedTombs[e.key] = e.value;
      }
      final merged = SafeZone.merge(_zones, remoteZones)
          .where((z) => _zoneSurvives(z, mergedTombs))
          .toList();
      final tombsChanged = !_sameTombstones(_zoneTombstones, mergedTombs);
      if (!_sameZones(_zones, merged) || tombsChanged) {
        _zones
          ..clear()
          ..addAll(merged);
        _zoneTombstones
          ..clear()
          ..addAll(mergedTombs);
        await _persistZones();
        await _persistZoneTombstones();
        result.safeZonesChanged = true;
      }
    }

    // Device → profile assignments: per-install last-write-wins by
    // assignment timestamp; a clear tombstone at or after the winning
    // write deletes the assignment, so cleared assignments cannot be
    // resurrected by a stale device re-publishing its older copy.
    // Blobs without meta (pre-timestamp writers) count as ts 0, so any
    // current-build write wins over them. Migration-safe: blobs
    // without the key leave local assignments untouched.
    if (payload.containsKey('device_assignments')) {
      final remote = _parseAssignments(payload['device_assignments']);
      final remoteMeta = _parseMsMap(payload['device_assignment_meta']);
      final mergedTombs = Map<String, int>.of(_assignmentTombstones);
      for (final e
          in _parseMsMap(payload['device_assignment_tombstones']).entries) {
        final cur = mergedTombs[e.key];
        if (cur == null || e.value > cur) mergedTombs[e.key] = e.value;
      }
      final merged = <String, String>{};
      final mergedMeta = <String, int>{};
      final installs = <String>{
        ..._deviceAssignments.keys,
        ...remote.keys,
        ..._assignmentUpdatedMs.keys,
        ...remoteMeta.keys,
        ...mergedTombs.keys,
      };
      for (final install in installs) {
        // Winning write: newest stamp; ties go to the remote side,
        // matching the long-standing policy.
        String? winner;
        var winnerTs = -1;
        final localVal = _deviceAssignments[install];
        if (localVal != null) {
          winner = localVal;
          winnerTs = _assignmentUpdatedMs[install] ?? 0;
        }
        final remoteVal = remote[install];
        if (remoteVal != null) {
          final remoteTs = remoteMeta[install] ?? 0;
          if (remoteTs >= winnerTs) {
            winner = remoteVal;
            winnerTs = remoteTs;
          }
        }
        final tomb = mergedTombs[install];
        if (winner != null && (tomb == null || winnerTs > tomb)) {
          merged[install] = winner;
          mergedMeta[install] = winnerTs;
        }
      }
      // Upgrade legacy local-id values (ours, or a pre-sync-identity
      // writer's) now that this payload's profiles have merged, so the
      // result is comparable and resolvable on every device.
      for (final k in merged.keys.toList()) {
        merged[k] = _normalizeAssignmentValue(merged[k]!);
      }
      if (!_sameAssignments(_deviceAssignments, merged) ||
          !_sameMsMap(_assignmentUpdatedMs, mergedMeta) ||
          !_sameMsMap(_assignmentTombstones, mergedTombs)) {
        final valuesChanged = !_sameAssignments(_deviceAssignments, merged);
        _deviceAssignments
          ..clear()
          ..addAll(merged);
        _assignmentUpdatedMs
          ..clear()
          ..addAll(mergedMeta);
        _assignmentTombstones
          ..clear()
          ..addAll(mergedTombs);
        await _persistAssignments();
        if (valuesChanged) result.assignmentsChanged = true;
      }
    }

    // Active profile follows only when the family enabled mirroring.
    if (_mirror) {
      final key = payload['activeProfileSyncKey'];
      final name = payload['activeProfileName']?.toString();
      final target = (key is String && key.isNotEmpty)
          ? (_profiles.bySyncKey(key) ??
                (name != null ? _profiles.byName(name) : null))
          : null;
      if (target != null && target.id != _profiles.active?.id) {
        await _profiles.setActive(target.id);
        result.activeChanged = true;
      }
    }
  }

  Future<void> _mergeProfile(
    Map<String, dynamic> entry,
    DashboardSyncResult result,
  ) async {
    final syncKey = entry['syncKey']?.toString() ?? '';
    final name = entry['name']?.toString() ?? 'My Voice';
    if (syncKey.isEmpty) return;
    final updatedAt = _parseDate(entry['updatedAt']);

    var local = _profiles.bySyncKey(syncKey);
    if (local == null) {
      // Name fallback: a profile created on another device before sync
      // keys existed. Adopt the synced key so both devices converge on
      // one identity instead of flip-flopping by name forever.
      local = _profiles.byName(name);
      if (local != null) {
        await _profiles.adoptSyncKey(local, syncKey);
      }
    }
    if (local == null) {
      final created = await _profiles.addImportedProfile(
        syncKey: syncKey,
        name: name,
      );
      await _profiles.applySyncedSettings(
        created,
        name: name,
        mode: _parseMode(entry['mode']),
        buildMaxSymbols: _parseInt(entry['buildMaxSymbols'], 4),
        predictionEnabled: _parseBool(entry['predictionEnabled'], true),
        nudgePreference: _parseNudge(entry['nudgePreference']),
        contacts: _parseContacts(entry['contacts']),
        callPhrases: _parseCallPhrases(entry['callPhrases']),
        emergency: _parseEmergency(entry['emergency']),
        safety: _parseSafety(entry['safety']),
        locationSharingEnabled: _parseBool(entry['locationSharingEnabled'], false),
        locationSharingConsentAt: _parseDateOrNull(entry['locationSharingConsentAt']),
        locationAutoShare: _parseBool(entry['locationAutoShare'], false),
        updatedAt: updatedAt,
      );
      result.profilesChanged = true;
      return;
    }
    if (updatedAt.isAfter(local.updatedAt)) {
      await _profiles.applySyncedSettings(
        local,
        name: name,
        mode: _parseMode(entry['mode']),
        buildMaxSymbols: _parseInt(entry['buildMaxSymbols'], 4),
        predictionEnabled: _parseBool(entry['predictionEnabled'], true),
        nudgePreference: _parseNudge(entry['nudgePreference']),
        contacts: _parseContacts(entry['contacts']),
        callPhrases: _parseCallPhrases(entry['callPhrases']),
        emergency: _parseEmergency(entry['emergency']),
        safety: _parseSafety(entry['safety']),
        locationSharingEnabled: _parseBool(entry['locationSharingEnabled'], false),
        locationSharingConsentAt: _parseDateOrNull(entry['locationSharingConsentAt']),
        locationAutoShare: _parseBool(entry['locationAutoShare'], false),
        updatedAt: updatedAt,
      );
      result.profilesChanged = true;
    }
  }

  /// Order-insensitive zone equality for merge change detection.
  bool _sameZones(List<SafeZone> a, List<SafeZone> b) {
    if (a.length != b.length) return false;
    final byId = {for (final z in b) z.id: z};
    for (final z in a) {
      if (byId[z.id] != z) return false;
    }
    return true;
  }

  bool _sameAssignments(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  bool _sameMsMap(Map<String, int> a, Map<String, int> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  bool _sameTombstones(Map<String, DateTime> a, Map<String, DateTime> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  Future<void> _mergeDashboard(    String syncKey,
    Map<String, dynamic> json,
    DashboardSyncResult result,
  ) async {
    final parsed = PersonalDashboard.fromJson(json);
    final localProfile = _profiles.bySyncKey(syncKey);
    if (localProfile == null) return; // profile merge above creates it first
    final local = _dashboards.forProfile(localProfile.id);
    if (local == null || parsed.updatedAt.isAfter(local.updatedAt)) {
      await _dashboards.replaceFor(localProfile.id, parsed);
      result.dashboardsChanged = true;
    }
  }

  DateTime _parseDate(Object? v) =>
      v is String ? (DateTime.tryParse(v) ?? DateTime.now()) : DateTime.now();

  /// Phase 2A location consent: null when never enabled (migration-safe).
  DateTime? _parseDateOrNull(Object? v) =>
      v is String ? DateTime.tryParse(v) : null;

  int _parseInt(Object? v, int fallback) =>
      v is int ? v : (v is num ? v.toInt() : fallback);

  bool _parseBool(Object? v, bool fallback) => v is bool ? v : fallback;

  /// Phase 1 calling & safety parsers: migration-safe (missing key ->
  /// empty list / defaults) and non-throwing (malformed entries skipped).
  List<SafetyContact> _parseContacts(Object? v) {
    final out = <SafetyContact>[];
    if (v is! List) return out;
    for (final entry in v) {
      if (entry is! Map) continue;
      try {
        out.add(SafetyContact.fromJson(Map<String, dynamic>.from(entry)));
      } catch (_) {}
    }
    return out;
  }

  List<CallPhrase> _parseCallPhrases(Object? v) {
    final out = <CallPhrase>[];
    if (v is! List) return out;
    for (final entry in v) {
      if (entry is! Map) continue;
      try {
        out.add(CallPhrase.fromJson(Map<String, dynamic>.from(entry)));
      } catch (_) {}
    }
    return out;
  }

  EmergencyProfileData _parseEmergency(Object? v) {
    if (v is Map) {
      try {
        return EmergencyProfileData.fromJson(Map<String, dynamic>.from(v));
      } catch (_) {}
    }
    return const EmergencyProfileData();
  }

  SafetySettings _parseSafety(Object? v) {
    if (v is Map) {
      try {
        return SafetySettings.fromJson(Map<String, dynamic>.from(v));
      } catch (_) {}
    }
    return const SafetySettings();
  }

  CommunicationMode _parseMode(Object? v) => switch (v) {
    'build' => CommunicationMode.build,
    'type' => CommunicationMode.type,
    _ => CommunicationMode.tap,
  };

  ModeNudgePreference _parseNudge(Object? v) => switch (v) {
    'paused' => ModeNudgePreference.paused,
    'off' => ModeNudgePreference.off,
    _ => ModeNudgePreference.allowed,
  };
}

/// What a pull merged into local state.
class DashboardSyncResult {
  bool profilesChanged = false;
  bool dashboardsChanged = false;
  bool activeChanged = false;

  /// Phase 2B: a pull added, updated, or reordered safe zones.
  bool safeZonesChanged = false;

  /// A pull changed device → profile assignments.
  bool assignmentsChanged = false;

  bool get changed =>
      profilesChanged ||
      dashboardsChanged ||
      activeChanged ||
      safeZonesChanged ||
      assignmentsChanged;
}

/// An AES-GCM encrypted blob, base64-encoded for transport.
class EncryptedBlob {
  const EncryptedBlob({required this.ciphertext, required this.nonce});

  /// base64(ciphertext ‖ 16-byte GCM tag).
  final String ciphertext;

  /// base64(12-byte nonce).
  final String nonce;
}
