// Native geofencing tests.
//
// Covers the promises the Dart core makes (the OS side is exercised by
// the native field-test matrix):
// - the tracker never alerts on the first fix (silent baseline) and
//   never flaps in the GPS accuracy band;
// - only the assigned communicator device syncs regions / reports;
// - enter/exit events post ENCRYPTED alerts whose envelope carries
//   only opaque zone/profile ids;
// - the durable outbox survives outages and restarts, retries after
//   server errors, and drops poison (4xx) events;
// - region diffing follows zone edits (disabled/deleted zones leave
//   the OS monitor set).
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:onevoz/models/safe_zone.dart';
import 'package:onevoz/services/dashboard_service.dart';
import 'package:onevoz/services/dashboard_sync_service.dart';
import 'package:onevoz/services/elevenlabs_key_store.dart';
import 'package:onevoz/services/geofence_service.dart';
import 'package:onevoz/services/location_service.dart';
import 'package:onevoz/services/profile_service.dart';
import 'package:onevoz/services/proxy_client.dart';

class _FakeSecureStore implements SecureValueStore {
  final map = <String, String>{};

  @override
  Future<String?> read(String key) async => map[key];

  @override
  Future<void> write(String key, String value) async => map[key] = value;

  @override
  Future<void> delete(String key) async => map.remove(key);
}

class _FakeGps extends LocationService {
  _FakeGps(this.fix);

  GpsFix? fix;

  @override
  Future<GpsFix?> currentFix() async => fix;

  @override
  Future<bool> get hasPermission async => fix != null;
}

class _FakePlatform implements GeofencePlatform {
  final syncCalls = <List<GeofenceRegion>>[];
  final _controller = StreamController<GeofenceTransition>.broadcast();
  List<GeofenceTransition> pendingDrain = [];
  bool nativeOk = true;

  @override
  Future<bool> syncRegions(List<GeofenceRegion> regions) async {
    syncCalls.add(List.of(regions));
    return nativeOk;
  }

  @override
  Stream<GeofenceTransition> get transitions => _controller.stream;

  void emit(GeofenceTransition t) => _controller.add(t);

  @override
  Future<List<GeofenceTransition>> drainPending() async {
    final out = pendingDrain;
    pendingDrain = [];
    return out;
  }

  @override
  Future<String> permissionStatus() async => 'always';

  @override
  Future<String> requestBackgroundPermission() async => 'always';
}

SafeZone _zone({
  String id = 'zone_11111111-2222-4333-8444-555555555555',
  String name = 'Home',
  double lat = 40.7128,
  double lng = -74.0060,
  double radiusM = 300,
  bool enabled = true,
  bool notifyEnter = true,
  bool notifyExit = true,
}) =>
    SafeZone(
      id: id,
      name: name,
      lat: lat,
      lng: lng,
      radiusM: radiusM,
      enabled: enabled,
      notifyEnter: notifyEnter,
      notifyExit: notifyExit,
      updatedTs: DateTime.utc(2026, 9, 16, 12),
    );

GpsFix _fixAt(double lat, double lng, {double acc = 10}) => GpsFix(
      latitude: lat,
      longitude: lng,
      accuracyMeters: acc,
      timestamp: DateTime.utc(2026, 9, 16, 12),
    );

class _Harness {
  _Harness._();

  final requests = <http.Request>[];
  late DateTime now;
  late ProxyClient proxy;
  late ProxyAuthStore proxyAuth;
  late ProfileService profiles;
  late DashboardSyncService sync;
  late GeofenceService geo;
  late _FakePlatform platform;
  late _FakeGps gps;
  late List<int> key;
  late UserProfile profile;
  late String installId;

  /// HTTP status for /v1/alerts; null means "throw" (network outage).
  int? alertStatus = 200;

  static Future<_Harness> create({bool assign = true}) async {
    final h = _Harness._();
    SharedPreferences.setMockInitialValues({});
    h.now = DateTime.utc(2026, 9, 16, 12);
    h.proxy = ProxyClient(
      client: MockClient((req) async {
        h.requests.add(req);
        if (req.url.path == '/v1/alerts') {
          final s = h.alertStatus;
          if (s == null) throw http.ClientException('offline');
          return http.Response('{}', s);
        }
        return http.Response('{}', 200);
      }),
      baseUrl: 'https://proxy.test',
    );
    h.proxy.setToken('tok-test');
    h.proxyAuth = ProxyAuthStore(store: _FakeSecureStore());
    h.installId = await h.proxyAuth.installId();
    h.profiles = ProfileService();
    await h.profiles.load();
    h.profile = await h.profiles.addProfile('Mia');
    final dashboards = DashboardService();
    await dashboards.load();
    h.sync = DashboardSyncService(
      proxy: h.proxy,
      profiles: h.profiles,
      dashboards: dashboards,
      prefsFactory: SharedPreferences.getInstance,
    );
    h.key = List<int>.generate(32, (i) => i + 1);
    h.sync.setKey(h.key);
    await h.sync.upsertSafeZone(_zone());
    if (assign) {
      await h.sync.setDeviceAssignment(h.installId, h.profile.syncKey);
    }
    h.platform = _FakePlatform();
    h.gps = _FakeGps(null);
    h.geo = GeofenceService(
      proxy: h.proxy,
      proxyAuth: h.proxyAuth,
      profiles: h.profiles,
      dashboardSync: h.sync,
      gps: h.gps,
      prefsFactory: SharedPreferences.getInstance,
      platform: h.platform,
      clock: () => h.now,
      evalInterval: const Duration(days: 365),
    );
    return h;
  }

  List<http.Request> get alertPosts =>
      requests.where((r) => r.url.path == '/v1/alerts').toList();

  Future<void> settle() async {
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GeofenceTracker', () {
    test('first confident fix is a silent baseline, flips alert', () {
      final tracker = GeofenceTracker();
      final zone = _zone();
      // Baseline: confidently inside (fix at center, acc 10).
      var out = tracker.onFix([zone], _fixAt(40.7128, -74.0060), DateTime.utc(2026));
      expect(out, isEmpty);
      // Move ~1.1 km north: confidently outside → exit event.
      out = tracker.onFix([zone], _fixAt(40.7228, -74.0060), DateTime.utc(2026));
      expect(out, hasLength(1));
      expect(out.single.inside, isFalse);
      // Back inside → enter event.
      out = tracker.onFix([zone], _fixAt(40.7128, -74.0060), DateTime.utc(2026));
      expect(out, hasLength(1));
      expect(out.single.inside, isTrue);
    });

    test('accuracy band holds state instead of flapping', () {
      final tracker = GeofenceTracker();
      final zone = _zone(radiusM: 100);
      tracker.onFix([zone], _fixAt(40.7128, -74.0060), DateTime.utc(2026));
      // ~95 m north with ±50 m accuracy: inside the uncertainty band
      // (95+50 > 100 and 95-50 < 100) → no transition.
      final out = tracker.onFix(
        [zone],
        _fixAt(40.71366, -74.0060, acc: 50),
        DateTime.utc(2026),
      );
      expect(out, isEmpty);
      expect(tracker.state[zone.id], isTrue);
    });

    test('notify flags gate events but state still tracks', () {
      final tracker = GeofenceTracker();
      final zone = _zone(notifyEnter: false);
      tracker.onFix([zone], _fixAt(40.7228, -74.0060), DateTime.utc(2026));
      final out = tracker.onFix([zone], _fixAt(40.7128, -74.0060), DateTime.utc(2026));
      expect(out, isEmpty); // enter suppressed
      expect(tracker.state[zone.id], isTrue); // but state tracked
      final exit = tracker.onFix([zone], _fixAt(40.7228, -74.0060), DateTime.utc(2026));
      expect(exit, hasLength(1)); // exit still reported
    });

    test('zones removed from tracking drop their state', () {
      final tracker = GeofenceTracker();
      final zone = _zone();
      final other = _zone(id: 'zone_22222222-2222-4333-8444-555555555555');
      tracker.onFix([zone, other], _fixAt(40.7128, -74.0060), DateTime.utc(2026));
      tracker.retainOnly({zone.id});
      expect(tracker.state, {zone.id: true});
    });
  });

  group('GeofenceOutboxEntry', () {
    test('json round-trips and rejects malformed entries', () {
      const e = GeofenceOutboxEntry(
        eventId: 'evt-1',
        zoneId: 'zone_x',
        profileSyncKey: 'key-1',
        kind: 'geofence_exit',
        tsMs: 1726000000000,
      );
      final back = GeofenceOutboxEntry.fromJson(e.toJson());
      expect(back?.eventId, 'evt-1');
      expect(back?.kind, 'geofence_exit');
      expect(GeofenceOutboxEntry.fromJson({'id': ''}), isNull);
      expect(
        GeofenceOutboxEntry.fromJson(
            {'id': 'a', 'zone': 'z', 'profile': 'p', 'kind': 'x', 'ts': 1}),
        isNull,
      );
    });
  });

  group('GeofenceService', () {
    test('unassigned device never syncs regions and never reports',
        () async {
      final h = await _Harness.create(assign: false);
      await h.geo.start();
      await h.settle();
      expect(h.geo.isWatching, isFalse);
      expect(h.platform.syncCalls, isEmpty); // nothing to diff yet
      h.gps.fix = _fixAt(40.7128, -74.0060);
      await h.sync.upsertSafeZone(_zone());
      h.geo.onSyncChanged();
      await h.settle();
      expect(h.platform.syncCalls.expand((c) => c), isEmpty);
      expect(h.alertPosts, isEmpty);
      await h.geo.stop();
    });

    test('assigned device syncs enabled zones and posts encrypted exit',
        () async {
      final h = await _Harness.create();
      await h.geo.start();
      await h.settle();
      expect(h.geo.isWatching, isTrue);
      // Only the enabled zone registered.
      expect(h.platform.syncCalls.last, hasLength(1));
      expect(h.platform.syncCalls.last.single.id, _zone().id);

      // OS reports enter (silent baseline) then exit (alert).
      h.platform.emit(GeofenceTransition(
        zoneId: _zone().id,
        inside: true,
        ts: h.now,
      ));
      await h.settle();
      expect(h.alertPosts, isEmpty);
      h.platform.emit(GeofenceTransition(
        zoneId: _zone().id,
        inside: false,
        ts: h.now,
      ));
      await h.settle();
      expect(h.alertPosts, hasLength(1));
      final body = json.decode(h.alertPosts.single.body) as Map;
      expect(body['kind'], 'geofence_exit');
      // F4: envelope carries the outbox event id the worker dedups on.
      expect((body['envelope'] as Map)['event_id'], isNotEmpty);
      expect(body['envelope'], {
        'zone_id': _zone().id,
        'profile_id': h.profile.syncKey,
        'event_id': (body['envelope'] as Map)['event_id'],
      });
      // Server-visible fields carry no names or coordinates…
      expect(body.keys.toSet(),
          {'install_id', 'kind', 'ciphertext', 'nonce', 'ts', 'envelope'});
      // …but the caregiver payload decrypts to the friendly names.
      final plain = await DashboardSyncService.decrypt(
        h.key,
        body['ciphertext'] as String,
        body['nonce'] as String,
      );
      final payload = json.decode(plain) as Map;
      expect(payload['zoneName'], 'Home');
      expect(payload['profileName'], 'Mia');
      expect(payload['eventId'], isNotEmpty);
      // Envelope dedup key == the encrypted payload's event id (F4).
      expect((body['envelope'] as Map)['event_id'], payload['eventId']);
      expect(h.geo.pendingEvents, 0);
      await h.geo.stop();
    });

    test('outbox survives an outage and a restart, then delivers',
        () async {
      final h = await _Harness.create();
      h.alertStatus = null; // offline
      await h.geo.start();
      await h.settle();
      h.platform.emit(GeofenceTransition(
          zoneId: _zone().id, inside: true, ts: h.now));
      h.platform.emit(GeofenceTransition(
          zoneId: _zone().id, inside: false, ts: h.now));
      await h.settle();
      expect(h.alertPosts, hasLength(1)); // the failed attempt
      expect(h.geo.pendingEvents, 1);
      await h.geo.stop();

      // Relaunch: a fresh service over the same prefs must retry.
      h.alertStatus = 200;
      final before = h.alertPosts.length;
      final geo2 = GeofenceService(
        proxy: h.proxy,
        proxyAuth: h.proxyAuth,
        profiles: h.profiles,
        dashboardSync: h.sync,
        gps: h.gps,
        prefsFactory: SharedPreferences.getInstance,
        platform: h.platform,
        clock: () => h.now,
        evalInterval: const Duration(days: 365),
      );
      await geo2.start();
      await h.settle();
      expect(h.alertPosts.length, greaterThan(before));
      expect(geo2.pendingEvents, 0);
      await geo2.stop();
    });

    test('poison (4xx) events drop instead of wedging the outbox',
        () async {
      final h = await _Harness.create();
      h.alertStatus = 400;
      await h.geo.start();
      await h.settle();
      h.platform.emit(GeofenceTransition(
          zoneId: _zone().id, inside: true, ts: h.now));
      h.platform.emit(GeofenceTransition(
          zoneId: _zone().id, inside: false, ts: h.now));
      await h.settle();
      expect(h.geo.pendingEvents, 0); // dropped, not retained
      await h.geo.stop();
    });

    test('disabling a zone removes it from the OS region set', () async {
      final h = await _Harness.create();
      await h.geo.start();
      await h.settle();
      expect(h.platform.syncCalls.last, hasLength(1));
      await h.sync.upsertSafeZone(_zone(enabled: false));
      h.geo.onSyncChanged();
      await h.settle();
      expect(h.platform.syncCalls.last, isEmpty);
      await h.geo.stop();
    });

    test('local evaluation drives events when the OS monitor is absent',
        () async {
      final h = await _Harness.create();
      h.platform.nativeOk = false; // channel-less platform
      await h.geo.start();
      await h.settle();
      expect(h.geo.nativeActive, isFalse);

      // First fix: silent baseline inside. Second: outside → exit.
      h.gps.fix = _fixAt(40.7128, -74.0060);
      await h.geo.debugEvaluateOnce();
      h.gps.fix = _fixAt(40.7228, -74.0060);
      await h.geo.debugEvaluateOnce();
      await h.settle();
      expect(h.alertPosts.map((r) => json.decode(r.body)['kind']),
          ['geofence_exit']);
      await h.geo.stop();
    });
  });
}
