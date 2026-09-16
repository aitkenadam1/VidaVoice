import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/dashboard.dart';
import 'dashboard_service.dart';
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
  });

  final ProxyClient _proxy;
  final ProfileService _profiles;
  final DashboardService _dashboards;
  final Future<SharedPreferences> Function() _prefsFactory;

  /// Called after every mutation (merge, mirror change, sync-state update)
  /// so UI can rebuild.
  VoidCallback? onChanged;

  void _notify() => onChanged?.call();

  static const _kLastVersion = 'vidavoice.sync.lastVersion';
  static const _kLastSyncedAt = 'vidavoice.sync.lastSyncedAt';
  static const _kMirror = 'vidavoice.sync.mirrorActiveProfile';
  static const _kMirrorUpdatedAt = 'vidavoice.sync.mirrorUpdatedAt';

  /// PBKDF2 iteration count for the sync key. Production value; tests pass
  /// a small count for speed via [deriveSyncKey]'s parameter.
  static const defaultPbkdf2Iterations = 600000;

  List<int>? _key;
  int _lastSeenRemoteVersion = 0;
  bool _mirror = false;

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

  bool get mirrorActiveProfile => _mirror;

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
      _notify();
    } catch (_) {}
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
            'updatedAt': p.updatedAt.toIso8601String(),
          },
      ],
      'dashboards': dashboards,
    };
  }

  /// Uploads the current local state as a new encrypted blob.
  /// Best-effort: throws [ProxyException] on transport/server errors —
  /// callers decide whether to surface it.
  Future<void> pushNow() async {
    final key = _key;
    if (key == null || !_proxy.hasToken) return;
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
        updatedAt: updatedAt,
      );
      result.profilesChanged = true;
    }
  }

  Future<void> _mergeDashboard(
    String syncKey,
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

  int _parseInt(Object? v, int fallback) =>
      v is int ? v : (v is num ? v.toInt() : fallback);

  bool _parseBool(Object? v, bool fallback) => v is bool ? v : fallback;

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

  bool get changed => profilesChanged || dashboardsChanged || activeChanged;
}

/// An AES-GCM encrypted blob, base64-encoded for transport.
class EncryptedBlob {
  const EncryptedBlob({required this.ciphertext, required this.nonce});

  /// base64(ciphertext ‖ 16-byte GCM tag).
  final String ciphertext;

  /// base64(12-byte nonce).
  final String nonce;
}
