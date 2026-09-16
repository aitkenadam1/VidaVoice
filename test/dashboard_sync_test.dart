import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:onevoz/models/dashboard.dart';
import 'package:onevoz/services/dashboard_service.dart';
import 'package:onevoz/services/dashboard_sync_service.dart';
import 'package:onevoz/services/elevenlabs_key_store.dart';
import 'package:onevoz/services/profile_service.dart';
import 'package:onevoz/services/proxy_client.dart';
import 'package:onevoz/services/tts_service.dart';
import 'package:onevoz/state/session_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory keychain double for ProxyAuthStore.
class _FakeSecureStore implements SecureValueStore {
  final map = <String, String>{};

  @override
  Future<String?> read(String key) async => map[key];

  @override
  Future<void> write(String key, String value) async => map[key] = value;

  @override
  Future<void> delete(String key) async => map.remove(key);
}

class _FakeTts extends TtsService {
  @override
  Future<bool> init({
    required String language,
    double rate = 0.5,
    double pitch = 1.0,
  }) async => true;

  @override
  Future<void> speak(String text) async {}
}

/// Fake voice-proxy backend: sync blob store, salt, auth, and device
/// registration. Lets tests drive the full encrypted-sync flow without a
/// network.
class _FakeSyncServer {
  Map<String, dynamic>? stored;
  int version = 0;
  String? lastSyncMethod;
  String? lastSyncBody;
  bool deviceLimit = false;

  String get saltB64 =>
      base64.encode(utf8.encode('0123456789abcdef0123456789abcdef'));

  Map<String, dynamic> _authBody() => {
    'token': 'tok-1',
    'token_type': 'Bearer',
    'expires_in': 3600,
    'family_id': 'fam-1',
    'profile_ids': ['p1'],
    'caregiver_id': 'cg-1',
    'sync_salt': saltB64,
  };

  Future<http.Response> handler(http.Request req) async {
    final path = req.url.path;
    if (path == '/v1/sync/dashboards') {
      if (req.method == 'PUT') {
        lastSyncMethod = req.method;
        lastSyncBody = req.body;
        final body = json.decode(req.body) as Map<String, dynamic>;
        version += 1;
        stored = {...body, 'version': version};
        return http.Response(json.encode({'version': version}), 200);
      }
      if (req.method == 'GET') {
        if (stored == null) {
          return http.Response(json.encode({'error': 'no_sync_data'}), 404);
        }
        return http.Response(json.encode(stored), 200);
      }
    }
    if (path == '/v1/sync/salt' && req.method == 'GET') {
      return http.Response(json.encode({'sync_salt': saltB64}), 200);
    }
    if (path == '/v1/auth/login' && req.method == 'POST') {
      return http.Response(json.encode(_authBody()), 200);
    }
    if (path == '/v1/devices/register' && req.method == 'POST') {
      if (deviceLimit) {
        return http.Response(
          json.encode({
            'error': {
              'code': 'DEVICE_LIMIT_REACHED',
              'message': 'All device licenses are in use.',
            },
          }),
          403,
        );
      }
      return http.Response(
        json.encode({
          'device': {'install_id': 'install-1'},
          'device_slots': 3,
          'subscription_tier': 'base',
          'devices_used': 1,
        }),
        201,
      );
    }
    return http.Response('not found', 404);
  }

  ProxyClient client() {
    final proxy = ProxyClient(
      client: MockClient(handler),
      baseUrl: 'https://proxy.test',
    );
    proxy.setToken('tok-test');
    return proxy;
  }
}

/// One simulated device: fresh local store, its own services, one sync
/// engine sharing the family's key. Mirrors a separate physical device.
Future<
  ({
    DashboardSyncService sync,
    ProfileService profiles,
    DashboardService dashboards,
  })
>
_makeDevice(_FakeSyncServer server, List<int> key) async {
  SharedPreferences.setMockInitialValues({});
  final profiles = ProfileService();
  final dashboards = DashboardService();
  await profiles.load();
  await dashboards.load();
  final sync = DashboardSyncService(
    proxy: server.client(),
    profiles: profiles,
    dashboards: dashboards,
    prefsFactory: () async => await SharedPreferences.getInstance(),
  );
  await sync.loadPersisted();
  sync.setKey(key);
  return (sync: sync, profiles: profiles, dashboards: dashboards);
}

PersonalDashboard _dashboardFor(
  String profileId,
  String name, {
  DateTime? updatedAt,
}) => PersonalDashboard(
  id: 'd-$profileId',
  profileId: profileId,
  name: name,
  cells: const [],
  enabled: true,
  updatedAt: updatedAt,
);

void main() {
  const testIterations = 2000;
  String saltFor(String s) => base64.encode(utf8.encode(s));

  group('sync key derivation', () {
    test('is deterministic for the same password and salt', () async {
      final salt = saltFor('family-salt-00000000000000000001');
      final a = await DashboardSyncService.deriveSyncKey(
        'correct horse battery staple',
        salt,
        iterations: testIterations,
      );
      final b = await DashboardSyncService.deriveSyncKey(
        'correct horse battery staple',
        salt,
        iterations: testIterations,
      );
      expect(a, equals(b));
      expect(a.length, 32);
    });

    test('differs for a different password or salt', () async {
      final salt = saltFor('family-salt-00000000000000000001');
      final base = await DashboardSyncService.deriveSyncKey(
        'password-one',
        salt,
        iterations: testIterations,
      );
      final otherPassword = await DashboardSyncService.deriveSyncKey(
        'password-two',
        salt,
        iterations: testIterations,
      );
      final otherSalt = await DashboardSyncService.deriveSyncKey(
        'password-one',
        saltFor('family-salt-00000000000000000002'),
        iterations: testIterations,
      );
      expect(otherPassword, isNot(equals(base)));
      expect(otherSalt, isNot(equals(base)));
    });
  });

  group('blob encryption', () {
    test('round-trips through encrypt/decrypt', () async {
      final key = List<int>.generate(32, (i) => i);
      const payload = '{"profiles":[{"name":"Maya"}]}';
      final blob = await DashboardSyncService.encrypt(key, payload);
      final clear = await DashboardSyncService.decrypt(
        key,
        blob.ciphertext,
        blob.nonce,
      );
      expect(clear, payload);
    });

    test('decrypt fails with the wrong key', () async {
      final key = List<int>.generate(32, (i) => i);
      final wrong = List<int>.generate(32, (i) => 31 - i);
      final blob = await DashboardSyncService.encrypt(key, '{"a":1}');
      expect(
        () => DashboardSyncService.decrypt(wrong, blob.ciphertext, blob.nonce),
        throwsA(anything),
      );
    });

    test('decrypt fails on tampered ciphertext', () async {
      final key = List<int>.generate(32, (i) => i);
      final blob = await DashboardSyncService.encrypt(key, '{"a":1}');
      final raw = base64.decode(blob.ciphertext);
      raw[0] = raw[0] ^ 0xFF;
      expect(
        () => DashboardSyncService.decrypt(key, base64.encode(raw), blob.nonce),
        throwsA(anything),
      );
    });
  });

  group('sync wire protocol', () {
    test('push uses PUT and never sends plaintext words', () async {
      final server = _FakeSyncServer();
      final key = List<int>.filled(32, 7);
      final device = await _makeDevice(server, key);
      final profile = device.profiles.active!;
      await device.profiles.renameActive('Maya');
      await device.dashboards.replaceFor(
        profile.id,
        _dashboardFor(profile.id, 'Maya board'),
      );

      await device.sync.syncNow();

      expect(server.lastSyncMethod, 'PUT');
      expect(server.stored, isNotNull);
      expect(server.stored!['version'], 1);
      // The no-content promise: the PUT body must not contain any of the
      // family's words or names in the clear.
      expect(server.lastSyncBody, isNot(contains('Maya')));
      expect(server.lastSyncBody, isNot(contains('board')));
      expect(server.stored!['ciphertext'], isA<String>());
      expect(server.stored!['nonce'], isA<String>());
    });

    test('getDashboardBlob returns null on 404 (never synced)', () async {
      final server = _FakeSyncServer();
      final blob = await server.client().getDashboardBlob();
      expect(blob, isNull);
    });
  });

  group('cross-device merge', () {
    test('a second device pulls profiles and dashboards', () async {
      final server = _FakeSyncServer();
      final key = List<int>.filled(32, 7);

      final a = await _makeDevice(server, key);
      final profileA = a.profiles.active!;
      await a.profiles.renameActive('Maya');
      await a.dashboards.replaceFor(
        profileA.id,
        _dashboardFor(profileA.id, 'Maya board'),
      );
      await a.sync.syncNow();

      // Device B starts from a blank local store.
      final b = await _makeDevice(server, key);
      final result = await b.sync.pullNow();

      expect(result.changed, isTrue);
      final names = b.profiles.profiles.map((p) => p.name).toList();
      expect(names, contains('Maya'));
      final maya = b.profiles.profiles.firstWhere((p) => p.name == 'Maya');
      expect(maya.syncKey, profileA.syncKey);
      final board = b.dashboards.forProfile(maya.id);
      expect(board, isNotNull);
      expect(board!.name, 'Maya board');
      expect(board.enabled, isTrue);
    });

    test('the newer dashboard wins; the older one is ignored', () async {
      final server = _FakeSyncServer();
      final key = List<int>.filled(32, 7);

      final a = await _makeDevice(server, key);
      final profileA = a.profiles.active!;
      await a.profiles.renameActive('Maya');
      await a.dashboards.replaceFor(
        profileA.id,
        _dashboardFor(
          profileA.id,
          'v1 board',
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await a.sync.syncNow();

      // Device B pulls, then edits the board later (newer updatedAt).
      final b = await _makeDevice(server, key);
      await b.sync.pullNow();
      final mayaB = b.profiles.profiles.firstWhere((p) => p.name == 'Maya');
      await b.dashboards.replaceFor(
        mayaB.id,
        _dashboardFor(
          mayaB.id,
          'v2 board',
          updatedAt: DateTime.utc(2026, 2, 1),
        ),
      );
      await b.sync.pushNow();

      // Device C pulls: it must see the newer board.
      final c = await _makeDevice(server, key);
      await c.sync.pullNow();
      final mayaC = c.profiles.profiles.firstWhere((p) => p.name == 'Maya');
      expect(c.dashboards.forProfile(mayaC.id)!.name, 'v2 board');

      // An older blob pushed over it must not clobber the newer board:
      // inject a stale v0 payload straight into the server store.
      final stalePayload = {
        'v': 1,
        'mirrorActiveProfile': false,
        'activeSyncKey': profileA.syncKey,
        'profiles': [
          {
            'syncKey': profileA.syncKey,
            'name': 'Maya',
            'settings': {},
            'updatedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
          },
        ],
        'dashboards': {
          profileA.syncKey: _dashboardFor(
            profileA.id,
            'stale board',
            updatedAt: DateTime.utc(2025, 12, 1),
          ).toJson(),
        },
      };
      final blob = await DashboardSyncService.encrypt(
        key,
        json.encode(stalePayload),
      );
      server.version += 1;
      server.stored = {
        'ciphertext': blob.ciphertext,
        'nonce': blob.nonce,
        'version': server.version,
      };
      final after = await c.sync.pullNow();
      expect(after.changed, isFalse);
      expect(c.dashboards.forProfile(mayaC.id)!.name, 'v2 board');
    });

    test(
      'name fallback converges identity and honors newer remote settings',
      () async {
        final server = _FakeSyncServer();
        final key = List<int>.filled(32, 7);

        // Device A: "Maya" with a sync key and newer settings.
        final a = await _makeDevice(server, key);
        final profileA = a.profiles.active!;
        await a.profiles.renameActive('Maya');
        await a.profiles.setCommunicationMode(
          profileA.id,
          CommunicationMode.build,
        );
        await a.sync.syncNow();

        // Device B: a pre-sync legacy "Maya" — same name, a different sync
        // key, and older settings.
        final b = await _makeDevice(server, key);
        final legacy = b.profiles.active!;
        await b.profiles.renameActive('Maya');
        legacy.syncKey = 'legacy-sync-key';
        legacy.updatedAt = DateTime.utc(2020, 1, 1);

        await b.sync.pullNow();

        final mayaB = b.profiles.profiles.firstWhere((p) => p.name == 'Maya');
        // Identity converged on A's sync key without duplicating.
        expect(mayaB.syncKey, profileA.syncKey);
        expect(
          b.profiles.profiles.where((p) => p.name == 'Maya').length,
          1,
          reason: 'identity convergence must not duplicate the profile',
        );
        // The newer remote settings won: adopting the sync key must not
        // bump the local timestamp and corrupt last-write-wins.
        expect(mayaB.communicationMode, CommunicationMode.build);
      },
    );

    test('a rename propagates by sync key', () async {
      final server = _FakeSyncServer();
      final key = List<int>.filled(32, 7);

      final a = await _makeDevice(server, key);
      final profileA = a.profiles.active!;
      await a.profiles.renameActive('Maya');
      await a.sync.syncNow();

      final b = await _makeDevice(server, key);
      await b.sync.pullNow();

      // Rename on A; B pulls and must follow the identity, not the name.
      await a.profiles.renameActive('Maya R');
      await a.sync.syncNow();
      final result = await b.sync.pullNow();

      expect(result.changed, isTrue);
      final mayaB = b.profiles.profiles.firstWhere(
        (p) => p.syncKey == profileA.syncKey,
      );
      expect(mayaB.name, 'Maya R');
      expect(
        b.profiles.profiles.where((p) => p.syncKey == profileA.syncKey).length,
        1,
      );
    });

    test(
      'mirror toggle switches the active profile on other devices',
      () async {
        final server = _FakeSyncServer();
        final key = List<int>.filled(32, 7);

        final a = await _makeDevice(server, key);
        final first = a.profiles.active!;
        await a.profiles.renameActive('Maya');
        final second = await a.profiles.addProfile('Jordan');
        await a.profiles.setActive(second.id);
        await a.sync.setMirror(true);

        final b = await _makeDevice(server, key);
        await b.sync.pullNow();

        expect(b.sync.mirrorActiveProfile, isTrue);
        expect(b.profiles.active!.syncKey, second.syncKey);
        expect(b.profiles.active!.name, 'Jordan');
        expect(first.syncKey, isNot(second.syncKey));
      },
    );

    test('mirror flag follows the newer timestamp', () async {
      final server = _FakeSyncServer();
      final key = List<int>.filled(32, 7);

      final a = await _makeDevice(server, key);
      await a.sync.setMirror(true); // pushes (true, T1)
      final stale = Map<String, dynamic>.of(server.stored!);

      final b = await _makeDevice(server, key);
      await b.sync.pullNow();
      expect(b.sync.mirrorActiveProfile, isTrue);

      // B toggles off (newer). A stale remote blob must not override it.
      await Future.delayed(const Duration(milliseconds: 5));
      await b.sync.setMirror(false); // pushes (false, T2)
      server.stored = stale; // the old (true, T1) blob wins a server race
      await b.sync.pullNow();
      expect(
        b.sync.mirrorActiveProfile,
        isFalse,
        reason: 'a stale remote mirror must not override the newer local one',
      );

      // A genuinely newer remote toggle still propagates.
      await Future.delayed(const Duration(milliseconds: 5));
      await a.sync.setMirror(true); // pushes (true, T3)
      await b.sync.pullNow();
      expect(
        b.sync.mirrorActiveProfile,
        isTrue,
        reason: 'the newer remote mirror toggle propagates',
      );
    });
    test('a remote merge never schedules an echo push', () async {
      final server = _FakeSyncServer();
      final key = List<int>.filled(32, 7);

      final a = await _makeDevice(server, key);
      await a.profiles.renameActive('Maya');
      final second = await a.profiles.addProfile('Jordan');
      await a.profiles.setActive(second.id);
      await a.sync.setMirror(true); // pushes

      // Device B with the production wiring: local mutations schedule a
      // debounced push.
      final b = await _makeDevice(server, key);
      b.profiles.onChanged = () => b.sync.schedulePush();
      b.dashboards.onChanged = () => b.sync.schedulePush();
      b.sync.autoPushEnabled = true; // post-first-pull state

      final result = await b.sync.pullNow();
      expect(result.changed, isTrue);
      // The merge fires profiles.onChanged (active-profile switch via the
      // mirror toggle) — remote-originated changes must not schedule a
      // push back to the server.
      expect(
        b.sync.hasScheduledPush,
        isFalse,
        reason: 'remote merges must not schedule an echo push',
      );

      // Positive control: a genuine local edit still schedules a push.
      await b.profiles.renameActive('Maya R');
      expect(b.sync.hasScheduledPush, isTrue);
      b.sync.clearKey(); // cancel the pending debounce timer
    });

    test('a failed pull leaves the engine usable for a retry', () async {
      final server = _FakeSyncServer();
      final key = List<int>.filled(32, 7);

      // Seed the server from device A.
      final a = await _makeDevice(server, key);
      await a.profiles.renameActive('Maya');
      await a.sync.syncNow();

      // Device B whose first blob GET fails (offline blip), then recovers.
      SharedPreferences.setMockInitialValues({});
      final profiles = ProfileService();
      final dashboards = DashboardService();
      await profiles.load();
      await dashboards.load();
      var failNextGet = true;
      final flaky = ProxyClient(
        client: MockClient((http.Request req) async {
          if (failNextGet &&
              req.method == 'GET' &&
              req.url.path == '/v1/sync/dashboards') {
            failNextGet = false;
            throw ProxyException('boom', code: 'unreachable');
          }
          return server.handler(req);
        }),
        baseUrl: 'https://proxy.test',
      );
      flaky.setToken('tok-test');
      final sync = DashboardSyncService(
        proxy: flaky,
        profiles: profiles,
        dashboards: dashboards,
        prefsFactory: () async => await SharedPreferences.getInstance(),
      );
      await sync.loadPersisted();
      sync.setKey(key);
      // Like the session's post-boot finally: a failed first pull must not
      // disable auto-push forever.
      sync.autoPushEnabled = true;

      await expectLater(sync.pullNow(), throwsA(isA<ProxyException>()));
      expect(sync.hasKey, isTrue);

      // The retry converges normally.
      final result = await sync.pullNow();
      expect(result.changed, isTrue);
      expect(profiles.profiles.map((p) => p.name), contains('Maya'));
    });
  });

  group('device licensing', () {
    Future<SessionState> makeSession(_FakeSyncServer server) async {
      SharedPreferences.setMockInitialValues({});
      final session = SessionState(
        tts: _FakeTts(),
        proxy: ProxyClient(
          client: MockClient(server.handler),
          baseUrl: 'https://proxy.test',
        ),
        proxyAuth: ProxyAuthStore(store: _FakeSecureStore()),
      );
      await session.profiles.load();
      return session;
    }

    test('device cap keeps the session but sets the license block', () async {
      final server = _FakeSyncServer()..deviceLimit = true;
      final session = await makeSession(server);

      await session.signIn(
        identifier: 'caregiver@example.org',
        password: 'a-strong-password-1',
      );

      expect(session.proxySignedIn, isTrue);
      expect(session.deviceLicenseBlocked, isTrue);
    });

    test('retry clears the block once a slot frees up', () async {
      final server = _FakeSyncServer()..deviceLimit = true;
      final session = await makeSession(server);

      await session.signIn(
        identifier: 'caregiver@example.org',
        password: 'a-strong-password-1',
      );
      expect(session.deviceLicenseBlocked, isTrue);

      server.deviceLimit = false;
      await session.retryDeviceRegistration();
      expect(session.deviceLicenseBlocked, isFalse);
    });
  });
}
