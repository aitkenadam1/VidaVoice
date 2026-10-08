import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/safe_zone.dart';
import 'dashboard_sync_service.dart';
import 'elevenlabs_key_store.dart';
import 'location_service.dart';
import 'location_share_service.dart' show LocationAlertKind;
import 'profile_service.dart';
import 'proxy_client.dart';

/// One OS-level (or locally evaluated) geofence region: the opaque zone
/// id plus geometry. Names never cross this boundary — the OS and the
/// server only ever see the opaque id.
class GeofenceRegion {
  const GeofenceRegion({
    required this.id,
    required this.lat,
    required this.lng,
    required this.radiusM,
  });

  final String id;
  final double lat;
  final double lng;
  final double radiusM;

  Map<String, dynamic> toMap() => {
        'id': id,
        'lat': lat,
        'lng': lng,
        'radiusM': radiusM,
      };

  @override
  bool operator ==(Object other) =>
      other is GeofenceRegion &&
      other.id == id &&
      other.lat == lat &&
      other.lng == lng &&
      other.radiusM == radiusM;

  @override
  int get hashCode => Object.hash(id, lat, lng, radiusM);
}

/// A confirmed inside/outside flip for one zone.
class GeofenceTransition {
  const GeofenceTransition({
    required this.zoneId,
    required this.inside,
    required this.ts,
  });

  final String zoneId;
  final bool inside;
  final DateTime ts;
}

/// Platform bridge for OS geofence monitoring (Android GeofencingClient,
/// iOS CLRegion). The native side registers regions with the OS, which
/// keeps watching while the app is backgrounded or terminated, and
/// stores transitions it cannot deliver immediately so Dart can drain
/// them on the next launch (reboot restore lives on both sides: the OS
/// keeps the regions, we re-sync the desired set on start).
abstract class GeofencePlatform {
  /// Replaces the OS-registered region set with [regions]. Returns true
  /// when native monitoring is active; false when unavailable (web,
  /// missing permission, unsupported OS) so the service can fall back
  /// to local evaluation while the app is alive.
  Future<bool> syncRegions(List<GeofenceRegion> regions);

  /// Transitions observed while the app was running.
  Stream<GeofenceTransition> get transitions;

  /// Transitions the OS observed while no Dart engine was alive.
  Future<List<GeofenceTransition>> drainPending();

  /// 'always' | 'whenInUse' | 'denied' | 'unsupported'
  Future<String> permissionStatus();

  /// Asks for background ("always") monitoring permission. Never throws.
  Future<String> requestBackgroundPermission();
}

/// MethodChannel bridge to the native geofence implementations.
/// Channel contract mirrors the platform APIs 1:1; every call degrades
/// to "unsupported" on platforms without an implementation (web,
/// desktop, tests without a mock handler).
class MethodChannelGeofencePlatform implements GeofencePlatform {
  MethodChannelGeofencePlatform({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'vidavoice/geofence';
  final MethodChannel _channel;
  final _transitions = StreamController<GeofenceTransition>.broadcast();

  /// Handler registration is lazy: constructing this object in a bare
  /// unit test (no WidgetsFlutterBinding) must not touch the binary
  /// messenger. The first real use (stream listen or method call)
  /// registers it, by which point the app binding exists.
  bool _handlerReady = false;

  void _ensureHandler() {
    if (_handlerReady) return;
    _handlerReady = true;
    _channel.setMethodCallHandler(_onNativeCall);
  }

  Future<dynamic> _onNativeCall(MethodCall call) async {
    if (call.method == 'onTransition') {
      final args = call.arguments;
      if (args is Map) {
        final zoneId = args['zoneId']?.toString() ?? '';
        final kind = args['transition']?.toString() ?? '';
        final tsMs = (args['ts'] as num?)?.toInt();
        if (zoneId.isNotEmpty && (kind == 'enter' || kind == 'exit')) {
          _transitions.add(GeofenceTransition(
            zoneId: zoneId,
            inside: kind == 'enter',
            ts: tsMs == null
                ? DateTime.now()
                : DateTime.fromMillisecondsSinceEpoch(tsMs),
          ));
        }
      }
    }
    return null;
  }

  @override
  Future<bool> syncRegions(List<GeofenceRegion> regions) async {
    _ensureHandler();
    try {
      final ok = await _channel.invokeMethod<bool>('syncRegions', {
        'regions': [for (final r in regions) r.toMap()],
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<GeofenceTransition> get transitions {
    _ensureHandler();
    return _transitions.stream;
  }

  @override
  Future<List<GeofenceTransition>> drainPending() async {
    try {
      final raw =
          await _channel.invokeMethod<List<dynamic>>('drainPending');
      return [
        for (final e in raw ?? const [])
          if (e is Map && (e['zoneId']?.toString() ?? '').isNotEmpty)
            GeofenceTransition(
              zoneId: e['zoneId'].toString(),
              inside: e['transition']?.toString() == 'enter',
              ts: DateTime.fromMillisecondsSinceEpoch(
                  (e['ts'] as num?)?.toInt() ?? 0),
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<String> permissionStatus() async {
    try {
      return await _channel.invokeMethod<String>('permissionStatus') ??
          'unsupported';
    } catch (_) {
      return 'unsupported';
    }
  }

  @override
  Future<String> requestBackgroundPermission() async {
    try {
      return await _channel
              .invokeMethod<String>('requestBackgroundPermission') ??
          'unsupported';
    } catch (_) {
      return 'unsupported';
    }
  }
}

/// One queued geofence event, waiting for durable upload. Only opaque
/// ids + kind + timestamp persist — names stay inside the ciphertext
/// produced at send time, exactly like the location-share payloads.
class GeofenceOutboxEntry {
  const GeofenceOutboxEntry({
    required this.eventId,
    required this.zoneId,
    required this.profileSyncKey,
    required this.kind,
    required this.tsMs,
  });

  final String eventId;
  final String zoneId;
  final String profileSyncKey;

  /// LocationAlertKind.geofenceEnter / geofenceExit.
  final String kind;
  final int tsMs;

  Map<String, dynamic> toJson() => {
        'id': eventId,
        'zone': zoneId,
        'profile': profileSyncKey,
        'kind': kind,
        'ts': tsMs,
      };

  static GeofenceOutboxEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id']?.toString() ?? '';
    final zone = raw['zone']?.toString() ?? '';
    final profile = raw['profile']?.toString() ?? '';
    final kind = raw['kind']?.toString() ?? '';
    final ts = (raw['ts'] as num?)?.toInt() ?? 0;
    if (id.isEmpty || zone.isEmpty || profile.isEmpty || ts <= 0) {
      return null;
    }
    if (kind != LocationAlertKind.geofenceEnter &&
        kind != LocationAlertKind.geofenceExit) {
      return null;
    }
    return GeofenceOutboxEntry(
      eventId: id,
      zoneId: zone,
      profileSyncKey: profile,
      kind: kind,
      tsMs: ts,
    );
  }
}

/// Haversine distance in meters between two coordinates.
double geofenceDistanceM(double lat1, double lng1, double lat2, double lng2) {
  const earthM = 6371000.0;
  final dLat = _rad(lat2 - lat1);
  final dLng = _rad(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(lat1)) *
          math.cos(_rad(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return earthM * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _rad(double deg) => deg * math.pi / 180.0;

/// Per-zone inside/outside tracker with accuracy-aware hysteresis.
///
/// A fix only moves a zone's state when the position is *confidently*
/// inside (distance + accuracy inside the radius) or confidently
/// outside (distance − accuracy beyond the radius); fixes in the
/// uncertainty band hold the previous state, so GPS jitter at a fence
/// boundary cannot flap alerts. The first confident reading establishes
/// the baseline silently — a child already at home when watching starts
/// must not generate an "arrived" alert.
class GeofenceTracker {
  GeofenceTracker({Map<String, bool>? initialState})
      : _inside = Map.of(initialState ?? const {});

  final Map<String, bool> _inside;

  /// zone id → currently inside. Zones with no confident reading yet
  /// are absent (unknown).
  Map<String, bool> get state => Map.unmodifiable(_inside);

  /// Feeds one fix; returns the transitions it confirms (usually empty).
  List<GeofenceTransition> onFix(
    Iterable<SafeZone> zones,
    GpsFix fix,
    DateTime now,
  ) {
    final out = <GeofenceTransition>[];
    for (final z in zones) {
      final d = geofenceDistanceM(fix.latitude, fix.longitude, z.lat, z.lng);
      final acc = fix.accuracyMeters;
      bool? confident;
      if (d + acc <= z.radiusM) {
        confident = true;
      } else if (d - acc >= z.radiusM) {
        confident = false;
      }
      if (confident == null) continue;
      final was = _inside[z.id];
      if (was == null) {
        _inside[z.id] = confident; // silent baseline
      } else if (was != confident) {
        _inside[z.id] = confident;
        if ((confident && z.notifyEnter) || (!confident && z.notifyExit)) {
          out.add(GeofenceTransition(zoneId: z.id, inside: confident, ts: now));
        }
      }
    }
    return out;
  }

  /// Applies a transition reported by the OS monitor. Returns true
  /// when it is a real flip worth alerting on (same silent-baseline
  /// rule as [onFix]).
  bool applyOsTransition(SafeZone zone, GeofenceTransition t) {
    final was = _inside[t.zoneId];
    _inside[t.zoneId] = t.inside;
    if (was == null || was == t.inside) return false;
    return t.inside ? zone.notifyEnter : zone.notifyExit;
  }

  /// Replaces the tracked state (used when restoring persisted state
  /// after a relaunch, so a restart inside a zone stays silent).
  void restoreState(Map<String, bool> state) {
    _inside
      ..clear()
      ..addAll(state);
  }

  void retainOnly(Set<String> zoneIds) {
    _inside.removeWhere((id, _) => !zoneIds.contains(id));
  }
}

/// Watches safe zones for ONE communicator device and reports
/// enter/exit events to the family.
///
/// Lifecycle: constructed with the session, [start]ed once signed in.
/// It activates only when this install is assigned to a profile (the
/// caregiver's designation of "this device is the child's communicator");
/// unassigned/caregiver devices never watch and never report. All
/// failures are silent by contract — monitoring must never block or
/// degrade AAC communication.
class GeofenceService {
  GeofenceService({
    required this._proxy,
    required this._proxyAuth,
    required this._profiles,
    required this._dashboardSync,
    required this._gps,
    required this._prefsFactory,
    this._secureStore,
    GeofencePlatform? platform,
    DateTime Function()? clock,
    Duration? evalInterval,
  })  : _platform = platform ?? MethodChannelGeofencePlatform(),
        _clock = clock ?? DateTime.now,
        _evalInterval = evalInterval ?? const Duration(seconds: 60);

  final ProxyClient _proxy;
  final ProxyAuthStore _proxyAuth;
  final ProfileService _profiles;
  final DashboardSyncService _dashboardSync;
  final LocationService _gps;
  final Future<SharedPreferences> Function() _prefsFactory;

  /// At-rest encryption (review m4): the durable outbox and zone state
  /// carry zone/profile ids and must not sit in plaintext prefs when a
  /// secure store is wired. Legacy prefs values migrate on first read.
  final SecureValueStore? _secureStore;
  final GeofencePlatform _platform;
  final DateTime Function() _clock;
  final Duration _evalInterval;

  static const _kOutbox = 'vidavoice.geofence.outbox';
  static const _kZoneState = 'vidavoice.geofence.zoneState';

  /// Outbox cap: at a few transitions a day this is months of outage;
  /// oldest events drop first so a wedged queue can never grow forever.
  static const int _maxOutbox = 200;

  final GeofenceTracker _tracker = GeofenceTracker();
  final List<GeofenceOutboxEntry> _outbox = [];
  List<GeofenceRegion> _registered = const [];
  StreamSubscription<GeofenceTransition>? _osSub;
  Timer? _evalTimer;
  Timer? _retryTimer;
  bool _started = false;
  bool _nativeActive = false;
  bool _flushing = false;
  String? _profileSyncKey;

  /// Whether zone watching is live for this device right now.
  bool get isWatching => _started && _profileSyncKey != null;

  /// Whether the OS monitor (not just in-app evaluation) is active.
  bool get nativeActive => _nativeActive;

  int get pendingEvents => _outbox.length;

  /// Starts watching: loads durable state, resolves this device's
  /// assigned profile, syncs OS regions, drains transitions the OS saw
  /// while the app was dead, and begins local evaluation. [onSyncChanged]
  /// must be invoked by the owner whenever family sync state changes
  /// (zones edited, assignment changed) — DashboardSyncService is
  /// callback-based, not a ChangeNotifier.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      await _loadPersisted();
      _osSub = _platform.transitions.listen(_onOsTransition);
      await _refreshAssignmentAndRegions();
      for (final t in await _platform.drainPending()) {
        _handleTransition(t);
      }
      _evalTimer = Timer.periodic(_evalInterval, (_) => _evaluateOnce());
      unawaited(_flushOutbox());
    } catch (_) {
      // Monitoring is best-effort; never let it break the session.
    }
  }

  /// Re-resolves the assigned profile and re-diffs the OS region set
  /// after family sync state changed.
  void onSyncChanged() => unawaited(_refreshAssignmentAndRegions());

  Future<void> stop() async {
    _started = false;
    await _osSub?.cancel();
    _evalTimer?.cancel();
    _retryTimer?.cancel();
    try {
      await _platform.syncRegions(const []);
    } catch (_) {}
  }

  /// Re-resolves the assigned profile and re-diffs the OS region set.
  /// Called on start and whenever family sync state changes (zones
  /// edited, assignment changed, profile removed).
  Future<void> _refreshAssignmentAndRegions() async {
    if (!_started) return;
    try {
      final installId = await _proxyAuth.installId();
      _profileSyncKey = _dashboardSync.deviceAssignments[installId];
      final zones = _watchedZones();
      _tracker.retainOnly({for (final z in zones) z.id});
      final desired = [
        for (final z in zones)
          GeofenceRegion(id: z.id, lat: z.lat, lng: z.lng, radiusM: z.radiusM),
      ];
      if (!_sameRegions(_registered, desired)) {
        _nativeActive = await _platform.syncRegions(desired);
        _registered = desired;
      }
      await _persistZoneState();
    } catch (_) {}
  }

  /// Zones this device watches: family zones that are enabled. All
  /// enabled zones apply to the assigned communicator profile — zones
  /// are family-wide definitions in the sync model.
  List<SafeZone> _watchedZones() {
    if (_profileSyncKey == null) return const [];
    return [
      for (final z in _dashboardSync.safeZones)
        if (z.enabled) z,
    ];
  }

  void _onOsTransition(GeofenceTransition t) => _handleTransition(t);

  /// Test/debug entry point: runs one local-evaluation tick immediately
  /// instead of waiting for the interval timer. Same gating as the
  /// periodic path (no-op while the OS monitor is authoritative or the
  /// device is unassigned).
  Future<void> debugEvaluateOnce() => _evaluateOnce();

  /// One evaluation tick (fallback path): take a fix, run the tracker,
  /// queue confirmed transitions. Skipped while the OS monitor is
  /// authoritative so events can never double-report.
  Future<void> _evaluateOnce() async {
    if (!_started || _nativeActive || _profileSyncKey == null) return;
    try {
      final fix = await _gps.currentFix();
      if (fix == null) return;
      for (final t in _tracker.onFix(_watchedZones(), fix, _clock())) {
        _enqueue(t);
      }
      await _persistZoneState();
    } catch (_) {}
  }

  void _handleTransition(GeofenceTransition t) {
    final zones = {for (final z in _watchedZones()) z.id: z};
    final zone = zones[t.zoneId];
    if (zone == null || _profileSyncKey == null) return;
    try {
      if (_tracker.applyOsTransition(zone, t)) {
        _enqueue(GeofenceTransition(
          zoneId: t.zoneId,
          inside: t.inside,
          ts: t.ts,
        ));
      }
      unawaited(_persistZoneState());
    } catch (_) {}
  }

  void _enqueue(GeofenceTransition t) {
    _outbox.add(GeofenceOutboxEntry(
      eventId: _newEventId(),
      zoneId: t.zoneId,
      profileSyncKey: _profileSyncKey!,
      kind: t.inside
          ? LocationAlertKind.geofenceEnter
          : LocationAlertKind.geofenceExit,
      tsMs: t.ts.millisecondsSinceEpoch,
    ));
    while (_outbox.length > _maxOutbox) {
      _outbox.removeAt(0);
    }
    unawaited(_persistOutbox());
    unawaited(_flushOutbox());
  }

  /// Uploads queued events oldest-first. An event leaves the outbox
  /// only after the server accepts it; failures retain the queue and
  /// schedule a retry. Poison events (server rejected the request
  /// itself) are dropped so one bad entry can never wedge the queue —
  /// but network/server failures always retain.
  Future<void> _flushOutbox() async {
    if (_flushing || _outbox.isEmpty) return;
    final key = _dashboardSync.keyBytes;
    if (key == null || !_proxy.hasToken) return;
    _flushing = true;
    try {
      final installId = await _proxyAuth.installId();
      while (_outbox.isNotEmpty) {
        final entry = _outbox.first;
        final zone = _zoneById(entry.zoneId);
        final profile = _profiles.bySyncKey(entry.profileSyncKey);
        final blob = await DashboardSyncService.encrypt(
          key,
          json.encode({
            'v': 1,
            'profile': entry.profileSyncKey,
            'profileName': profile?.name,
            'zoneId': entry.zoneId,
            'zoneName': zone?.name,
            'kind': entry.kind,
            'eventId': entry.eventId,
            'ts': entry.tsMs,
          }),
        );
        try {
          await _proxy.postAlert(
            installId: installId,
            kind: entry.kind,
            ciphertext: blob.ciphertext,
            nonce: blob.nonce,
            ts: entry.tsMs,
            envelope: {
              'zone_id': entry.zoneId,
              'profile_id': entry.profileSyncKey,
              // Same UUID as the encrypted payload's eventId (F4): lets the
              // worker dedup durable-outbox retries instead of fanning the
              // same physical event out twice.
              'event_id': entry.eventId,
            },
          );
          _outbox.removeAt(0);
        } on ProxyException catch (e) {
          if (e.statusCode != null &&
              e.statusCode! >= 400 &&
              e.statusCode! < 500) {
            _outbox.removeAt(0); // poison: never retryable
          } else {
            rethrow;
          }
        }
      }
      await _persistOutbox();
    } catch (_) {
      _retryTimer?.cancel();
      _retryTimer = Timer(const Duration(seconds: 30), () {
        unawaited(_flushOutbox());
      });
    } finally {
      _flushing = false;
    }
  }

  SafeZone? _zoneById(String id) {
    for (final z in _dashboardSync.safeZones) {
      if (z.id == id) return z;
    }
    return null;
  }

  /// Secure-store read with plaintext-prefs migration (review m4).
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

  /// Secure-store write (review m4); evicts any plaintext prefs copy.
  /// On a store failure the plaintext copy is dropped so reads never
  /// come back stale; prefs stay the last resort.
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

  Future<void> _loadPersisted() async {
    try {
      final rawOutbox = await _secureGet(_kOutbox);
      if (rawOutbox != null && rawOutbox.isNotEmpty) {
        final decoded = json.decode(rawOutbox);
        if (decoded is List) {
          _outbox
            ..clear()
            ..addAll([
              for (final e in decoded) ?GeofenceOutboxEntry.fromJson(e),
            ]);
        }
      }
      final rawState = await _secureGet(_kZoneState);
      if (rawState != null && rawState.isNotEmpty) {
        final decoded = json.decode(rawState);
        if (decoded is Map) {
          _tracker.restoreState({
            for (final e in decoded.entries)
              if (e.value is bool) e.key.toString(): e.value as bool,
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _persistOutbox() async {
    try {
      await _secureSet(
        _kOutbox,
        json.encode([for (final e in _outbox) e.toJson()]),
      );
    } catch (_) {}
  }

  Future<void> _persistZoneState() async {
    try {
      await _secureSet(_kZoneState, json.encode(_tracker.state));
    } catch (_) {}
  }

  bool _sameRegions(List<GeofenceRegion> a, List<GeofenceRegion> b) {
    if (a.length != b.length) return false;
    final byId = {for (final r in b) r.id: r};
    for (final r in a) {
      if (byId[r.id] != r) return false;
    }
    return true;
  }

  static String _newEventId() {
    final r = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int n) => n.toRadixString(16).padLeft(2, '0');
    final s = bytes.map(hex).join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-'
        '${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
  }
}
