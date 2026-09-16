// Phase 2A location sharing tests.
//
// Covers the pieces the design promises:
// - the LocationService contract (fix → coords, unavailable → null);
// - session start/stop/expiry with the per-profile opt-in enforced;
// - default-off + migration safety for the new profile fields;
// - auto-share on `location_request` only with explicit pre-authorization;
// - E2E encryption of position payloads (server sees ciphertext only);
// - SOS uploads one position even when sharing is off;
// - the history buffer is capped during a long outage;
// - the caregiver map shows an honest missing-key state without a build
//   `--dart-define=MAPTILER_KEY`.
//
// The MapTiler key is never referenced here: tests run without
// `--dart-define`, so `String.fromEnvironment('MAPTILER_KEY')` is empty and
// the "not configured" UI branch is exercised honestly.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:onevoz/services/dashboard_service.dart';
import 'package:onevoz/services/dashboard_sync_service.dart';
import 'package:onevoz/services/elevenlabs_key_store.dart';
import 'package:onevoz/services/location_service.dart';
import 'package:onevoz/services/location_share_service.dart';
import 'package:onevoz/services/profile_service.dart';
import 'package:onevoz/services/proxy_client.dart';
import 'package:onevoz/services/tts_service.dart';
import 'package:onevoz/state/session_state.dart';
import 'package:onevoz/widgets/location_section.dart';

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

  final GpsFix? fix;

  @override
  Future<GpsFix?> currentFix() async => fix;

  @override
  Future<bool> get hasPermission async => fix != null;
}

class _FakeTts extends TtsService {
  @override
  Future<bool> init({
    required String language,
    double rate = 0.5,
    double pitch = 1.0,
  }) async => true;

  @override
  Future<void> setLanguage(String language) async {}

  @override
  Future<void> setRate(double rate) async {}

  @override
  Future<void> setPitch(double pitch) async {}

  @override
  Future<void> speak(String text) async {}

  @override
  Future<List<TtsVoice>> getVoices() async => const [];

  @override
  Future<void> setVoice(TtsVoice voice) async {}

  @override
  Future<void> clearVoice() async {}
}

GpsFix get _fix => GpsFix(
  latitude: 40.7128,
  longitude: -74.006,
  accuracyMeters: 12,
  timestamp: DateTime.utc(2026, 9, 16, 12),
);

/// Test harness: a signed-in family with a sync key, an opt-in-able
/// profile service, a fake clock, and a request-recording proxy.
class _Harness {
  _Harness._();

  final requests = <http.Request>[];
  late DateTime now;
  late ProxyClient proxy;
  late ProxyAuthStore proxyAuth;
  late ProfileService profiles;
  late DashboardSyncService sync;
  late LocationShareService share;
  late List<int> key;

  /// Return a JSON map to answer the request, or throw to simulate an
  /// outage for that endpoint.
  Map<String, dynamic>? Function(http.Request)? responder;

  int get nowMs => now.millisecondsSinceEpoch;

  static Future<_Harness> create({
    GpsFix? fix,
    Duration pingInterval = const Duration(milliseconds: 50),
    Duration flushInterval = const Duration(minutes: 5),
    Duration pollInterval = const Duration(minutes: 5),
  }) async {
    final h = _Harness._();
    SharedPreferences.setMockInitialValues({});
    h.now = DateTime.utc(2026, 9, 16, 12);
    h.proxy = ProxyClient(
      client: MockClient((req) async {
        h.requests.add(req);
        final r = h.responder?.call(req);
        if (r != null) return http.Response(json.encode(r), 200);
        return http.Response('{}', 200);
      }),
      baseUrl: 'https://proxy.test',
    );
    h.proxy.setToken('tok-test');
    h.proxyAuth = ProxyAuthStore(store: _FakeSecureStore());
    h.profiles = ProfileService();
    await h.profiles.load();
    final dashboards = DashboardService();
    await dashboards.load();
    h.sync = DashboardSyncService(
      proxy: h.proxy,
      profiles: h.profiles,
      dashboards: dashboards,
      prefsFactory: SharedPreferences.getInstance,
    );
    // Fixed 32-byte key: no PBKDF2 in tests, same AES-GCM-256 as prod.
    h.key = List<int>.generate(32, (i) => i + 1);
    h.sync.setKey(h.key);
    h.share = LocationShareService(
      proxy: h.proxy,
      proxyAuth: h.proxyAuth,
      profiles: h.profiles,
      dashboardSync: h.sync,
      gps: _FakeGps(fix),
      prefsFactory: SharedPreferences.getInstance,
      clock: () => h.now,
      pingInterval: pingInterval,
      flushInterval: flushInterval,
      pollInterval: pollInterval,
    );
    return h;
  }

  List<http.Request> get latestPuts => requests
      .where((r) => r.url.path == '/v1/sync/location/latest')
      .toList();

  List<http.Request> get pointPosts => requests
      .where((r) => r.url.path == '/v1/sync/location/points')
      .toList();

  List<http.Request> get alertPosts =>
      requests.where((r) => r.url.path == '/v1/alerts').toList();

  bool alertKindPosted(String kind) => alertPosts.any(
    (r) => (json.decode(r.body) as Map)['kind'] == kind,
  );

  void dispose() => share.dispose();
}

void main() {
  group('LocationService contract', () {
    test('a fix formats to 6-decimal coords', () async {
      expect(await _FakeGps(_fix).currentCoords(), '40.712800,-74.006000');
    });

    test('an unavailable fix falls back to null (never throws)', () async {
      const gps = NoopLocationService();
      expect(await gps.currentCoords(), isNull);
      expect(await gps.currentFix(), isNull);
      expect(await gps.hasPermission, isFalse);
    });
  });

  group('share sessions', () {
    test('startSession uploads an encrypted latest ping', () async {
      final h = await _Harness.create(fix: _fix);
      final p = await h.profiles.addProfile('Maya');
      p.locationSharingEnabled = true;
      p.locationSharingConsentAt = DateTime.utc(2026, 9, 16);

      await h.share.startSession(
        profileId: p.id,
        duration: const Duration(minutes: 15),
      );
      expect(h.share.isSharing, isTrue);

      expect(h.latestPuts, isNotEmpty);
      final body = json.decode(h.latestPuts.first.body) as Map<String, dynamic>;
      // Opaque wire format only: the server must never see coordinates.
      expect(body.keys.toSet(), {
        'install_id',
        'ciphertext',
        'nonce',
        'version',
      });
      expect(h.latestPuts.first.body.contains('40.7128'), isFalse);

      // The caregiver-visible share_started alert went out too.
      expect(h.alertKindPosted('share_started'), isTrue);
      h.dispose();
    });

    test('the latest payload decrypts to the position with the family key',
        () async {
      final h = await _Harness.create(fix: _fix);
      final p = await h.profiles.addProfile('Maya');
      p.locationSharingEnabled = true;

      await h.share.startSession(profileId: p.id);
      final body = json.decode(h.latestPuts.first.body) as Map;
      final clear = await DashboardSyncService.decrypt(
        h.key,
        body['ciphertext'] as String,
        body['nonce'] as String,
      );
      final payload = json.decode(clear) as Map;
      expect(payload['lat'], closeTo(40.7128, 1e-9));
      expect(payload['lon'], closeTo(-74.006, 1e-9));
      h.dispose();
    });

    test('startSession refuses when the profile has not opted in', () async {
      final h = await _Harness.create(fix: _fix);
      final p = await h.profiles.addProfile('Maya');
      // Opt-in left off (the default).

      expect(
        () => h.share.startSession(profileId: p.id),
        throwsA(isA<LocationShareException>()),
      );
      expect(h.share.isSharing, isFalse);
      expect(h.requests, isEmpty); // nothing reached the network
      h.dispose();
    });

    test('stopSession ends sharing and posts share_stopped', () async {
      final h = await _Harness.create(fix: _fix);
      final p = await h.profiles.addProfile('Maya');
      p.locationSharingEnabled = true;

      await h.share.startSession(profileId: p.id);
      await h.share.stopSession();
      expect(h.share.isSharing, isFalse);
      expect(h.alertKindPosted('share_stopped'), isTrue);
      h.dispose();
    });

    test('a timed session stops itself after its duration', () async {
      final h = await _Harness.create(fix: _fix);
      final p = await h.profiles.addProfile('Maya');
      p.locationSharingEnabled = true;

      await h.share.startSession(
        profileId: p.id,
        duration: const Duration(milliseconds: 80),
      );
      expect(h.share.isSharing, isTrue);
      await Future.delayed(const Duration(milliseconds: 400));
      expect(h.share.isSharing, isFalse);
      h.dispose();
    });

    test('timeLeft follows the injected clock', () async {
      final h = await _Harness.create(fix: _fix);
      final p = await h.profiles.addProfile('Maya');
      p.locationSharingEnabled = true;

      await h.share.startSession(
        profileId: p.id,
        duration: const Duration(minutes: 15),
      );
      expect(h.share.timeLeft, isNotNull);
      expect(h.share.timeLeft!.inMinutes, 15);
      h.now = h.now.add(const Duration(minutes: 16));
      expect(h.share.timeLeft, Duration.zero);
      h.dispose();
    });

    test('a ping with no fix is skipped, not fatal', () async {
      final h = await _Harness.create(); // no fix: GPS unavailable
      final p = await h.profiles.addProfile('Maya');
      p.locationSharingEnabled = true;

      await h.share.startSession(profileId: p.id);
      expect(h.share.isSharing, isTrue);
      await Future.delayed(const Duration(milliseconds: 200));
      // Session survives; nothing was uploaded.
      expect(h.share.isSharing, isTrue);
      expect(h.latestPuts, isEmpty);
      h.dispose();
    });
  });

  group('defaults and migration', () {
    test('location sharing defaults off for new profiles', () async {
      final h = await _Harness.create();
      final p = await h.profiles.addProfile('Maya');
      expect(p.locationSharingEnabled, isFalse);
      expect(p.locationAutoShare, isFalse);
      expect(p.locationSharingConsentAt, isNull);
      h.dispose();
    });

    test('pre-2A sync payloads migrate to off without throwing', () {
      final p = UserProfile.fromJson({'id': 'x', 'name': 'Old'});
      expect(p.locationSharingEnabled, isFalse);
      expect(p.locationAutoShare, isFalse);
      expect(p.locationSharingConsentAt, isNull);
    });
  });

  group('incoming location requests', () {
    Future<_Harness> harnessWithRequest({
      required bool autoShare,
    }) async {
      final h = await _Harness.create(fix: _fix);
      final p = await h.profiles.addProfile('Maya');
      p.locationSharingEnabled = true;
      p.locationAutoShare = autoShare;
      final myId = await h.proxyAuth.installId();
      h.responder = (req) {
        if (req.url.path == '/v1/alerts' && req.method == 'GET') {
          return {
            'alerts': [
              {
                'kind': 'location_request',
                'install_id': myId,
                'ts': h.nowMs - 60000,
                'ciphertext': 'e',
                'nonce': 'f',
              },
            ],
          };
        }
        return null;
      };
      return h;
    }

    test('auto-starts a 15-minute session when pre-authorized', () async {
      final h = await harnessWithRequest(autoShare: true);
      h.share.beginPolling();
      for (var i = 0; i < 100 && !h.share.isSharing; i++) {
        await Future.delayed(const Duration(milliseconds: 20));
      }
      expect(h.share.isSharing, isTrue);
      expect(h.share.pendingRequest, isNull);
      expect(
        h.share.session!.endsAt!.difference(h.share.session!.startedAt),
        const Duration(minutes: 15),
      );
      h.dispose();
    });

    test('prompts the child when auto-share is not pre-authorized', () async {
      final h = await harnessWithRequest(autoShare: false);
      h.share.beginPolling();
      for (var i = 0; i < 100 && h.share.pendingRequest == null; i++) {
        await Future.delayed(const Duration(milliseconds: 20));
      }
      expect(h.share.isSharing, isFalse);
      expect(h.share.pendingRequest, isNotNull);

      // The child accepts: a 15-minute session for the opted-in profile.
      await h.share.acceptRequest();
      expect(h.share.isSharing, isTrue);
      expect(h.share.pendingRequest, isNull);
      h.dispose();
    });

    test('dismissing the request prompts nothing and shares nothing',
        () async {
      final h = await harnessWithRequest(autoShare: false);
      h.share.beginPolling();
      for (var i = 0; i < 100 && h.share.pendingRequest == null; i++) {
        await Future.delayed(const Duration(milliseconds: 20));
      }
      h.share.dismissRequest();
      expect(h.share.pendingRequest, isNull);
      expect(h.share.isSharing, isFalse);
      expect(h.latestPuts, isEmpty);
      h.dispose();
    });
  });

  group('SOS', () {
    test('uploadSos sends one position + alert even when sharing is off',
        () async {
      final h = await _Harness.create(fix: _fix);
      await h.profiles.addProfile('Maya'); // opted out, no session

      await h.share.uploadSos();

      expect(h.share.isSharing, isFalse);
      expect(h.latestPuts.length, 1);
      expect(h.alertKindPosted('sos'), isTrue);
      h.dispose();
    });
  });

  group('outage behavior', () {
    test('the history buffer is capped during a long outage', () async {
      // PUT latest succeeds but the history endpoint is down: points
      // accumulate in the buffer until the cap, then oldest are dropped.
      final h = await _Harness.create(
        fix: _fix,
        pingInterval: const Duration(milliseconds: 2),
        flushInterval: const Duration(milliseconds: 30),
      );
      final p = await h.profiles.addProfile('Maya');
      p.locationSharingEnabled = true;
      var outage = true;
      h.responder = (req) {
        if (outage && req.url.path == '/v1/sync/location/points') {
          throw http.ClientException('offline');
        }
        return null;
      };

      await h.share.startSession(profileId: p.id);
      // Wait until well past 500 pings (the buffer cap).
      for (var i = 0; i < 300 && h.latestPuts.length < 620; i++) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      expect(h.latestPuts.length, greaterThan(500));

      // Recovery: the capped buffer flushes in <=200-point chunks and the
      // total recovered history never exceeds the 500-point cap. (Requests
      // are recorded before the simulated outage throws, so only count
      // posts made after the outage ended.)
      final outagePosts = h.pointPosts.length;
      final putsBefore = h.latestPuts.length;
      outage = false;
      for (var i = 0; i < 100 && h.pointPosts.length == outagePosts; i++) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      await Future.delayed(const Duration(milliseconds: 500));
      // Pings keep arriving during the drain; each successful PUT adds
      // exactly one buffered point, so the recovered total is bounded by
      // the 500-point cap plus whatever arrived after the outage ended.
      final putsAfter = h.latestPuts.length;
      var total = 0;
      for (final post in h.pointPosts.sublist(outagePosts)) {
        final body = json.decode(post.body) as Map;
        final points = (body['points'] as List).length;
        expect(points, lessThanOrEqualTo(200));
        total += points;
      }
      expect(total, lessThanOrEqualTo(500 + (putsAfter - putsBefore)));
      expect(total, greaterThan(0));
      h.dispose();
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  group('caregiver map', () {
    test('resolveMapCenter prefers live, then my fix, then US fallback',
        () {
      // A shared live position wins (caregiver view).
      expect(
        LocationSection.resolveMapCenter(
          liveCenter: const LatLng(40.7, -74.0),
          myFix: const LatLng(40.5, -112.0),
        ),
        (const LatLng(40.7, -74.0), 13),
      );
      // No live data: the device's own fix still zooms in instead of
      // showing the whole country.
      expect(
        LocationSection.resolveMapCenter(
          myFix: const LatLng(40.5, -112.0),
        ),
        (const LatLng(40.5, -112.0), 13),
      );
      // Nothing known: whole-US fallback at zoom 3.
      expect(
        LocationSection.resolveMapCenter(),
        (const LatLng(39.5, -98.35), 3),
      );
    });

    testWidgets('shows the honest missing-key state without a MapTiler key',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final proxy = ProxyClient(
        client: MockClient((req) async {
          if (req.url.path == '/v1/devices') {
            return http.Response(json.encode({'devices': []}), 200);
          }
          if (req.url.path == '/v1/alerts') {
            return http.Response(json.encode({'alerts': []}), 200);
          }
          return http.Response('{}', 200);
        }),
        baseUrl: 'https://proxy.test',
      );
      proxy.setToken('tok-test');
      final session = SessionState(
        tts: _FakeTts(),
        proxy: proxy,
        proxyAuth: ProxyAuthStore(store: _FakeSecureStore()),
      );
      await session.profiles.load();
      session.proxySignedIn = true;

      await tester.pumpWidget(
        ChangeNotifierProvider<SessionState>.value(
          value: session,
          // The caregiver screen hosts this section in a ListView; the
          // test viewport is fixed-height, so give it a scroller too.
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: LocationSection()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No --dart-define in tests, so the key is empty: the section must
      // say so plainly instead of rendering a broken map.
      expect(find.textContaining('MapTiler key'), findsOneWidget);
      session.dispose();
    });
  });
}
