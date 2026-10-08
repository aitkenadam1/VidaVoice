// TEMPORARY probe — not part of the suite.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:onevoz/services/device_role_service.dart';
import 'package:onevoz/services/elevenlabs_key_store.dart';
import 'package:onevoz/services/push_token_service.dart';
import 'package:onevoz/services/proxy_client.dart';
import 'package:onevoz/state/session_state.dart';

class _FakeSecureStore2 implements SecureValueStore {
  final map = <String, String>{};
  @override
  Future<String?> read(String key) async => map[key];
  @override
  Future<void> write(String key, String value) async => map[key] = value;
  @override
  Future<void> delete(String key) async => map.remove(key);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('probe push lifecycle', () async {
    SharedPreferences.setMockInitialValues({});
    final proxy = ProxyClient(
      client: MockClient((req) async {
        // ignore: avoid_print
        print('REQ ${req.method} ${req.url.path}');
        return http.Response('{}', 200);
      }),
      baseUrl: 'https://proxy.test',
    );
    proxy.setToken('tok-1');
    final auth = ProxyAuthStore(store: _FakeSecureStore2());
    var role = DeviceRole.caregiver;
    final svc = PushTokenService(
      proxy: proxy,
      proxyAuth: auth,
      role: () => role,
    );
    // ignore: avoid_print
    print('starting');
    await svc.start().timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        // ignore: avoid_print
        print('START TIMED OUT');
      },
    );
    // ignore: avoid_print
    print('started');
    await svc.stop(unregister: true).timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        // ignore: avoid_print
        print('STOP TIMED OUT');
      },
    );
    // ignore: avoid_print
    print('stopped');
  }, timeout: const Timeout(Duration(seconds: 60)));
}
