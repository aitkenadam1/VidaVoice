// Push-token registration lifecycle tests.
//
// Covers the client half of the safe-zone fanout contract:
// - start() registers the current token with install id, platform,
//   and the device role (caregiver-preferred fanout data);
// - token rotations re-register; unchanged tokens don't re-post;
// - role changes force a re-register so fanout data stays current;
// - sign-out / session expiry unregisters (best-effort, 404-friendly);
// - when no token exists (push unconfigured yet), nothing is posted
//   and nothing crashes.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:onevoz/services/device_role_service.dart';
import 'package:onevoz/services/elevenlabs_key_store.dart';
import 'package:onevoz/services/push_token_service.dart';
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

class _FakeSource implements PushTokenSource {
  _FakeSource(this.token);

  String? token;
  final _refreshes = StreamController<String>.broadcast();

  @override
  Future<String?> currentToken() async => token;

  @override
  Stream<String> get tokenRefreshes => _refreshes.stream;

  void rotate(String next) {
    token = next;
    _refreshes.add(next);
  }

  @override
  Future<String?> requestPermissionAndToken() async => token;
}

class _Harness {
  _Harness._();

  final requests = <http.Request>[];
  late ProxyClient proxy;
  late ProxyAuthStore proxyAuth;
  late _FakeSource source;
  late PushTokenService service;
  DeviceRole? role = DeviceRole.caregiver;
  int pushStatus = 200;
  late String installId;

  static Future<_Harness> create({String? token = 'fcm-token-1'}) async {
    final h = _Harness._();
    h.proxy = ProxyClient(
      client: MockClient((req) async {
        h.requests.add(req);
        if (req.url.path.startsWith('/v1/devices/push-token')) {
          return http.Response('{}', h.pushStatus);
        }
        return http.Response('{}', 200);
      }),
      baseUrl: 'https://proxy.test',
    );
    h.proxy.setToken('tok-test');
    h.proxyAuth = ProxyAuthStore(store: _FakeSecureStore());
    h.installId = await h.proxyAuth.installId();
    h.source = _FakeSource(token);
    h.service = PushTokenService(
      proxy: h.proxy,
      proxyAuth: h.proxyAuth,
      role: () => h.role,
      source: h.source,
      platformName: () => 'android',
    );
    return h;
  }

  List<http.Request> get posts => requests
      .where((r) => r.method == 'POST' && r.url.path == '/v1/devices/push-token')
      .toList();

  List<http.Request> get deletes => requests
      .where((r) =>
          r.method == 'DELETE' && r.url.path.startsWith('/v1/devices/push-token/'))
      .toList();

  Future<void> settle() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('start registers token with install, platform, and role', () async {
    final h = await _Harness.create();
    await h.service.start();
    await h.settle();
    expect(h.posts, hasLength(1));
    final body = json.decode(h.posts.single.body) as Map;
    expect(body['install_id'], h.installId);
    expect(body['fcm_token'], 'fcm-token-1');
    expect(body['platform'], 'android');
    expect(body['role'], 'caregiver');
    await h.service.stop();
  });

  test('no token available → nothing posted, no crash', () async {
    final h = await _Harness.create(token: null);
    await h.service.start();
    await h.settle();
    expect(h.posts, isEmpty);
    await h.service.stop();
  });

  test('rotation re-registers; same-token refresh is deduped', () async {
    final h = await _Harness.create();
    await h.service.start();
    await h.settle();
    expect(h.posts, hasLength(1));
    h.source.rotate('fcm-token-1'); // unchanged value
    await h.settle();
    expect(h.posts, hasLength(1));
    h.source.rotate('fcm-token-2');
    await h.settle();
    expect(h.posts, hasLength(2));
    expect(json.decode(h.posts.last.body)['fcm_token'], 'fcm-token-2');
    await h.service.stop();
  });

  test('role change force re-registers with the new role', () async {
    final h = await _Harness.create();
    h.role = null; // role question not answered yet at first sign-in
    await h.service.start();
    await h.settle();
    expect(h.posts, hasLength(1));
    expect(json.decode(h.posts.single.body)['role'], isNull);
    h.role = DeviceRole.communicator;
    await h.service.refreshRegistration();
    await h.settle();
    expect(h.posts, hasLength(2));
    expect(json.decode(h.posts.last.body)['role'], 'communicator');
    await h.service.stop();
  });

  test('stop with unregister deletes the server registration', () async {
    final h = await _Harness.create();
    await h.service.start();
    await h.settle();
    await h.service.stop(unregister: true);
    expect(h.deletes, hasLength(1));
    expect(h.deletes.single.url.path,
        '/v1/devices/push-token/${h.installId}');
  });

  test('unregister tolerates 404 (never registered server-side)',
      () async {
    final h = await _Harness.create();
    h.pushStatus = 404;
    await h.service.start();
    await h.service.stop(unregister: true); // must not throw
    expect(h.deletes, hasLength(1));
  });

  test('server failure on register is swallowed and retried later',
      () async {
    final h = await _Harness.create();
    h.pushStatus = 500;
    await h.service.start();
    await h.settle();
    expect(h.posts, hasLength(1));
    h.pushStatus = 200;
    h.source.rotate('fcm-token-2');
    await h.settle();
    expect(h.posts, hasLength(2)); // retry happened on rotation
    await h.service.stop();
  });
}
