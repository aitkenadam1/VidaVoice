import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dashboard_sync_service.dart';
import 'location_service.dart';
import 'profile_service.dart';
import 'proxy_client.dart';

/// Alert event kinds used in Phase 2A. `kind` is plaintext on the wire
/// (routing only — the worker never sees coordinates); everything
/// sensitive rides inside the AES-GCM ciphertext.
class LocationAlertKind {
  static const sos = 'sos';
  static const locationRequest = 'location_request';
  static const shareStarted = 'share_started';
  static const shareStopped = 'share_stopped';

  /// Phase 2B geofence event kinds. The child's device will send these
  /// once native geofence watching lands; client-side only for now — the
  /// worker ingest update ships separately.
  static const geofenceEnter = 'geofence_enter';
  static const geofenceExit = 'geofence_exit';

  /// Reserved for a later phase. Never sent yet.
  static const geofenceDwell = 'geofence_dwell';

  /// The only kinds the 2A client ever sends or honors.
  static const allowed2A = {
    sos,
    locationRequest,
    shareStarted,
    shareStopped,
  };

  /// Kinds the Phase 2B client may send once child-side geofence
  /// watching lands (P2). Client-side only for now: the worker's
  /// ALERT_KINDS validation accepts these separately.
  static const allowed2B = {
    geofenceEnter,
    geofenceExit,
  };
}

/// An active on-demand location share session.
class ShareSession {
  ShareSession({
    required this.profileId,
    required this.startedAt,
    required this.endsAt,
  });

  /// Local profile id sharing.
  final String profileId;
  final DateTime startedAt;

  /// When the session stops itself. Null = "until stopped".
  final DateTime? endsAt;
}

/// A caregiver "Request location" alert awaiting the child's answer.
class IncomingLocationRequest {
  IncomingLocationRequest({required this.receivedAt, required this.alertTs});

  final DateTime receivedAt;
  final int alertTs;
}

/// Plain-language failure starting or running a share session.
/// Never carries coordinates — messages are safe to show and log.
class LocationShareException implements Exception {
  LocationShareException(this.message);
  final String message;
  @override
  String toString() => 'LocationShareException: $message';
}

/// Phase 2A on-demand location sharing.
///
/// - Sessions are time-boxed (15/30/60 min) or "until stopped", per the
///   approved design. While active, this device uploads an encrypted
///   position ping every 60s (foreground only — the web has no background
///   execution) to `PUT /v1/sync/location/latest` and batches history
///   points every 5 min to `POST /v1/sync/location/points`.
/// - E2E: every payload is encrypted on-device with the family sync key
///   ([DashboardSyncService.encrypt], same PBKDF2-SHA256 600k +
///   AES-GCM-256 scheme). The server stores ciphertext+nonce opaquely.
/// - Sharing requires the caregiver's per-profile opt-in
///   ([UserProfile.locationSharingEnabled]); OFF by default. The service
///   enforces this even if the UI is bypassed.
/// - SOS ([uploadSos]) skips the opt-in: an SOS always uploads one
///   encrypted position + alert, because the child explicitly asked for
///   help. Stated in the caregiver consent copy.
/// - Best-effort networking: a failed ping is skipped, not retried
///   aggressively, and cloud failure never blocks communication —
///   failures surface as [lastError] for the UI, never as crashes.
/// - In-memory only: a session ends when the app closes. Nothing about
///   an active session is persisted (no silent tracking across restarts).
class LocationShareService extends ChangeNotifier {
  LocationShareService({
    required this._proxy,
    required this._proxyAuth,
    required this._profiles,
    required this._dashboardSync,
    required this._gps,
    required this._prefsFactory,
    DateTime Function()? clock,
    Duration? pingInterval,
    Duration? flushInterval,
    Duration? pollInterval,
  }) : _clock = clock ?? DateTime.now,
       _pingInterval = pingInterval ?? const Duration(seconds: 60),
       _flushInterval = flushInterval ?? const Duration(minutes: 5),
       _pollInterval = pollInterval ?? const Duration(seconds: 60);

  final ProxyClient _proxy;
  final ProxyAuthStore _proxyAuth;
  final ProfileService _profiles;
  final DashboardSyncService _dashboardSync;
  final LocationService _gps;
  final Future<SharedPreferences> Function() _prefsFactory;
  final DateTime Function() _clock;
  final Duration _pingInterval;
  final Duration _flushInterval;
  final Duration _pollInterval;

  static const _kLastAlertPoll = 'onevoz.location.lastAlertPollMs';
  static const _kLastHandledRequest = 'onevoz.location.lastHandledRequestTs';

  /// Wire format version of the encrypted position payload. Bumped only
  /// with a deliberate migration — old app versions ignore unknown `v`.
  static const payloadVersion = 1;

  ShareSession? _session;
  Timer? _pingTimer;
  Timer? _flushTimer;
  Timer? _expiryTimer;
  Timer? _pollTimer;

  /// Points buffered for the next batched history upload. Capped at
  /// [_maxBufferedPoints]: on a long outage an "until stopped" session
  /// must not accumulate memory without bound. Oldest points are dropped
  /// first; the latest position is uploaded separately every ping, so the
  /// caregiver map still converges when connectivity returns.
  final List<Map<String, String>> _pointBuffer = [];

  /// Buffer cap, aligned with the server's 500-points/day/device limit.
  /// At one ping per minute this holds roughly 8 hours of outage.
  static const int _maxBufferedPoints = 500;

  /// Server batch limit for POST /v1/sync/location/points.
  static const int _flushBatchSize = 200;

  int _latestVersion = 0;
  IncomingLocationRequest? _pendingRequest;

  /// Plain-language outcome of the last failed operation (never contains
  /// coordinates). Null when everything is fine.
  String? lastError;

  /// When the last ping succeeded, for "updated N min ago" honesty labels.
  DateTime? lastPingAt;

  ShareSession? get session => _session;
  bool get isSharing => _session != null;
  IncomingLocationRequest? get pendingRequest => _pendingRequest;

  /// Time left in the session, or null for "until stopped" / no session.
  Duration? get timeLeft {
    final s = _session;
    if (s == null || s.endsAt == null) return null;
    final left = s.endsAt!.difference(_clock());
    return left.isNegative ? Duration.zero : left;
  }

  /// Starts sharing [profileId]'s location for [duration] (null = until
  /// the caregiver or child stops it). Throws [LocationShareException]
  /// with a UI-safe message when sharing isn't allowed or possible.
  Future<void> startSession({
    required String profileId,
    Duration? duration,
  }) async {
    final profile = _profiles.profiles
        .where((p) => p.id == profileId)
        .firstOrNull;
    if (profile == null) {
      throw LocationShareException('That profile no longer exists.');
    }
    if (!profile.locationSharingEnabled) {
      throw LocationShareException(
        'Location sharing is turned off for ${profile.name}. '
        'A caregiver can turn it on in Caregiver settings.',
      );
    }
    if (!_proxy.hasToken) {
      throw LocationShareException(
        'Sign in to share location. Your messages still work offline.',
      );
    }
    final key = _dashboardSync.keyBytes;
    if (key == null) {
      throw LocationShareException(
        'Location sharing needs the family sync key — sign in again.',
      );
    }
    await stopSession(quiet: true);
    lastError = null;
    final now = _clock();
    _session = ShareSession(
      profileId: profileId,
      startedAt: now,
      endsAt: duration == null ? null : now.add(duration),
    );
    _pingTimer = Timer.periodic(_pingInterval, (_) => _ping());
    _flushTimer = Timer.periodic(_flushInterval, (_) => _flushPoints());
    if (duration != null) {
      _expiryTimer = Timer(duration, () => stopSession());
    }
    notifyListeners();
    // First ping right away so the caregiver map isn't empty for a minute.
    await _ping();
    await _postShareAlert(LocationAlertKind.shareStarted, profileId);
  }

  /// Stops the active session (no-op when none). Flushes buffered points
  /// and posts a `share_stopped` alert on the way out (best-effort).
  Future<void> stopSession({bool quiet = false}) async {
    if (_session == null) return;
    final profileId = _session!.profileId;
    _pingTimer?.cancel();
    _flushTimer?.cancel();
    _expiryTimer?.cancel();
    _pingTimer = _flushTimer = _expiryTimer = null;
    _session = null;
    notifyListeners();
    await _flushPoints();
    if (!quiet) {
      await _postShareAlert(LocationAlertKind.shareStopped, profileId);
    }
  }

  /// One-shot encrypted position upload for SOS. Works even when no
  /// session is active and sharing is off — the child explicitly asked
  /// for help. Also posts the `sos` alert event. Best-effort: failures
  /// set [lastError] and never block the emergency flow.
  Future<void> uploadSos() async {
    if (!_proxy.hasToken) return;
    final key = _dashboardSync.keyBytes;
    if (key == null) return;
    try {
      final installId = await _proxyAuth.installId();
      final fix = await _gps.currentFix();
      final ts = _clock().millisecondsSinceEpoch;
      final payload = fix == null
          ? {'v': payloadVersion, 'ts': ts, 'unavailable': true}
          : {
              'v': payloadVersion,
              'lat': fix.latitude,
              'lon': fix.longitude,
              'acc': fix.accuracyMeters,
              'ts': ts,
            };
      final blob = await DashboardSyncService.encrypt(
        key,
        json.encode(payload),
      );
      if (fix != null) {
        await _proxy.putLocationLatest(
          installId: installId,
          ciphertext: blob.ciphertext,
          nonce: blob.nonce,
          version: ts,
        );
      }
      await _proxy.postAlert(
        installId: installId,
        kind: LocationAlertKind.sos,
        ciphertext: blob.ciphertext,
        nonce: blob.nonce,
      );
    } catch (_) {
      lastError = 'Could not send the SOS location update.';
      notifyListeners();
    }
  }

  /// Caregiver side: asks [targetInstallId] (the child's device) to start
  /// sharing. The child's device picks the alert up on its next poll
  /// (Phase 2A has no push): it auto-starts a 15-minute session only when
  /// a profile pre-authorized auto-share, otherwise it prompts. Never
  /// silent tracking — the request itself is visible in alert history.
  Future<void> requestLocation(String targetInstallId) async {
    if (!_proxy.hasToken) {
      throw LocationShareException('Sign in to request location.');
    }
    final key = _dashboardSync.keyBytes;
    if (key == null) {
      throw LocationShareException('Sign in again to request location.');
    }
    try {
      final fromId = await _proxyAuth.installId();
      final ts = _clock().millisecondsSinceEpoch;
      final blob = await DashboardSyncService.encrypt(
        key,
        json.encode({'v': payloadVersion, 'from': fromId, 'ts': ts}),
      );
      await _proxy.postAlert(
        installId: targetInstallId,
        kind: LocationAlertKind.locationRequest,
        ciphertext: blob.ciphertext,
        nonce: blob.nonce,
      );
    } catch (_) {
      throw LocationShareException(
        'Could not send the location request. Check your connection.',
      );
    }
  }

  /// Starts the alert poll loop (call after sign-in). Picks up caregiver
  /// `location_request` alerts for this device.
  void beginPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _pollAlerts());
    _pollAlerts();
  }

  /// Stops polling (call on sign-out). Does not stop an active session —
  /// use [stopSession] for that.
  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    _flushTimer?.cancel();
    _expiryTimer?.cancel();
    stopPolling();
    super.dispose();
  }

  /// The child accepted an incoming request: start a 15-minute session
  /// for the active profile when it's opted in.
  Future<void> acceptRequest() async {
    final req = _pendingRequest;
    _pendingRequest = null;
    notifyListeners();
    if (req == null) return;
    final active = _profiles.active;
    if (active == null || !active.locationSharingEnabled) {
      lastError = 'Location sharing is turned off for this profile.';
      notifyListeners();
      return;
    }
    try {
      await startSession(
        profileId: active.id,
        duration: const Duration(minutes: 15),
      );
    } on LocationShareException catch (e) {
      lastError = e.message;
      notifyListeners();
    }
  }

  /// The child dismissed an incoming request.
  void dismissRequest() {
    _pendingRequest = null;
    notifyListeners();
  }

  Future<void> _ping() async {
    final s = _session;
    if (s == null) return;
    if (s.endsAt != null && _clock().isAfter(s.endsAt!)) {
      await stopSession();
      return;
    }
    final key = _dashboardSync.keyBytes;
    if (key == null || !_proxy.hasToken) return;
    try {
      final fix = await _gps.currentFix();
      if (fix == null) return; // no fix this round — try again next ping
      final installId = await _proxyAuth.installId();
      final ts = _clock().millisecondsSinceEpoch;
      final blob = await DashboardSyncService.encrypt(
        key,
        json.encode({
          'v': payloadVersion,
          'lat': fix.latitude,
          'lon': fix.longitude,
          'acc': fix.accuracyMeters,
          'ts': ts,
        }),
      );
      final version = ts > _latestVersion ? ts : _latestVersion + 1;
      _latestVersion = version;
      await _proxy.putLocationLatest(
        installId: installId,
        ciphertext: blob.ciphertext,
        nonce: blob.nonce,
        version: version,
      );
      lastPingAt = _clock();
      lastError = null;
      // History points are capped at ~100m accuracy (COPPA minimization):
      // 3 decimal degrees ≈ 111m.
      final pointBlob = await DashboardSyncService.encrypt(
        key,
        json.encode({
          'v': payloadVersion,
          'lat': _round3(fix.latitude),
          'lon': _round3(fix.longitude),
          'ts': ts,
        }),
      );
      _pointBuffer.add({
        'ciphertext': pointBlob.ciphertext,
        'nonce': pointBlob.nonce,
        'ts': '$ts',
      });
      if (_pointBuffer.length > _maxBufferedPoints) {
        _pointBuffer.removeRange(0, _pointBuffer.length - _maxBufferedPoints);
      }
      notifyListeners();
    } catch (_) {
      // Best-effort: a failed ping is skipped, never fatal. The session
      // keeps going so a brief network drop doesn't kill sharing.
      lastError = 'Location upload failed — retrying.';
      notifyListeners();
    }
  }

  Future<void> _flushPoints() async {
    if (_pointBuffer.isEmpty) return;
    if (!_proxy.hasToken) return;
    final key = _dashboardSync.keyBytes;
    if (key == null) return;
    try {
      final installId = await _proxyAuth.installId();
      // Chunk at the server's per-request batch limit; drop only what the
      // server accepted so a 429 mid-flush doesn't lose the whole buffer.
      while (_pointBuffer.isNotEmpty) {
        final chunk = _pointBuffer.take(_flushBatchSize).map(
          (p) => {
            'ciphertext': p['ciphertext']!,
            'nonce': p['nonce']!,
            'ts': int.parse(p['ts']!),
          },
        ).toList();
        await _proxy.postLocationPoints(installId: installId, points: chunk);
        _pointBuffer.removeRange(0, chunk.length);
      }
    } catch (_) {
      // Keep the (capped) buffer; the next flush retries.
    }
  }

  Future<void> _postShareAlert(String kind, String profileId) async {
    final key = _dashboardSync.keyBytes;
    if (key == null || !_proxy.hasToken) return;
    try {
      final installId = await _proxyAuth.installId();
      // The profile name is recorded at share time: the local profile id
      // is meaningless on other devices, so the caregiver UI shows this
      // snapshot instead of trying to resolve it.
      final profileName = _profiles.profiles
          .where((p) => p.id == profileId)
          .firstOrNull
          ?.name;
      final blob = await DashboardSyncService.encrypt(
        key,
        json.encode({
          'v': payloadVersion,
          'profile': profileId,
          'profileName': profileName,
          'ts': _clock().millisecondsSinceEpoch,
        }),
      );
      await _proxy.postAlert(
        installId: installId,
        kind: kind,
        ciphertext: blob.ciphertext,
        nonce: blob.nonce,
      );
    } catch (_) {
      // Alert history is nice-to-have; sharing works without it.
    }
  }

  Future<void> _pollAlerts() async {
    if (!_proxy.hasToken) return;
    try {
      final prefs = await _prefsFactory();
      final since = prefs.getInt(_kLastAlertPoll) ?? 0;
      final nowMs = _clock().millisecondsSinceEpoch;
      final alerts = await _proxy.getAlerts(sinceMs: since);
      if (alerts.isNotEmpty) {
        final myId = await _proxyAuth.installId();
        final lastHandled = prefs.getInt(_kLastHandledRequest) ?? 0;
        for (final a in alerts) {
          final ts = (a['ts'] as num?)?.toInt() ?? 0;
          if (a['kind'] == LocationAlertKind.locationRequest &&
              a['install_id']?.toString() == myId &&
              ts > lastHandled &&
              nowMs - ts < const Duration(minutes: 10).inMilliseconds) {
            await prefs.setInt(_kLastHandledRequest, ts);
            await _handleLocationRequest();
          }
        }
      }
      await prefs.setInt(_kLastAlertPoll, nowMs);
    } catch (_) {
      // Poll failures are silent — the next poll retries.
    }
  }

  Future<void> _handleLocationRequest() async {
    // Auto-start only when a profile BOTH opted into sharing AND
    // pre-authorized auto-share. Otherwise the child is prompted —
    // never silent tracking without prior consent.
    final auto = _profiles.profiles.where(
      (p) => p.locationSharingEnabled && p.locationAutoShare,
    );
    if (auto.isNotEmpty && !isSharing) {
      try {
        await startSession(
          profileId: auto.first.id,
          duration: const Duration(minutes: 15),
        );
        return;
      } catch (_) {
        // Fall through to the prompt.
      }
    }
    final active = _profiles.active;
    if (active != null && active.locationSharingEnabled && !isSharing) {
      _pendingRequest = IncomingLocationRequest(
        receivedAt: _clock(),
        alertTs: _clock().millisecondsSinceEpoch,
      );
      notifyListeners();
    }
  }

  static double _round3(double v) => double.parse(v.toStringAsFixed(3));
}
