import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:voicesimple/services/elevenlabs_key_store.dart';
import 'package:voicesimple/services/proxy_client.dart';

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

ProxyClient clientWith(Future<http.Response> Function(http.Request) handler) =>
    ProxyClient(client: MockClient(handler), baseUrl: 'https://proxy.test');

Map<String, dynamic> authBody() => {
  'token': 'tok-1',
  'token_type': 'Bearer',
  'expires_in': 3600,
  'family_id': 'fam-1',
  'profile_ids': ['p1', 'p2'],
  'caregiver_id': 'cg-1',
};

void main() {
  group('proxyUuid4', () {
    test('generates version-4 UUIDs', () {
      final a = proxyUuid4();
      final b = proxyUuid4();
      expect(a, isNot(equals(b)));
      final re = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      expect(re.hasMatch(a), isTrue);
      expect(re.hasMatch(b), isTrue);
    });
  });

  group('auth', () {
    test('signup 201 parses token, family, and profile ids', () async {
      var authed = false;
      final client = clientWith((req) async {
        expect(req.url.path, '/v1/auth/signup');
        final body = json.decode(req.body) as Map<String, dynamic>;
        expect(body['email'], 'a@b.c');
        expect(body['username'], 'maya_mom');
        expect(body['password'], 'long-enough-password');
        authed = req.headers['authorization'] == null;
        return http.Response(json.encode(authBody()), 201);
      });
      final result = await client.signup(
        email: 'a@b.c',
        username: 'maya_mom',
        password: 'long-enough-password',
      );
      expect(result.token, 'tok-1');
      expect(result.familyId, 'fam-1');
      expect(result.profileIds, ['p1', 'p2']);
      expect(authed, isTrue); // no bearer header before sign-in
    });

    test('login 200 parses the same shape', () async {
      final client = clientWith((req) async {
        expect(req.url.path, '/v1/auth/login');
        return http.Response(json.encode(authBody()), 200);
      });
      final result = await client.login(
        identifier: 'maya_mom',
        password: 'long-enough-password',
      );
      expect(result.token, 'tok-1');
      expect(result.familyId, 'fam-1');
    });

    test('401 invalid_credentials carries the server code', () async {
      final client = clientWith(
        (_) async => http.Response(
          json.encode({
            'error': {'code': 'invalid_credentials', 'message': 'Nope.'},
          }),
          401,
        ),
      );
      try {
        await client.login(identifier: 'x', password: 'wrong-password-1');
        fail('expected ProxyException');
      } on ProxyException catch (e) {
        expect(e.code, 'invalid_credentials');
        expect(e.message, 'Nope.');
        expect(e.statusCode, 401);
      }
    });

    test('409 email_taken preserves the code', () async {
      final client = clientWith(
        (_) async => http.Response(
          json.encode({
            'error': {'code': 'email_taken', 'message': 'Taken.'},
          }),
          409,
        ),
      );
      try {
        await client.signup(
          email: 'a@b.c',
          username: 'u',
          password: 'long-enough-password',
        );
        fail('expected ProxyException');
      } on ProxyException catch (e) {
        expect(e.code, 'email_taken');
      }
    });
  });

  group('synthesize', () {
    test(
      'speech 200 follows the signed audio url with the bearer token',
      () async {
        final audio = Uint8List.fromList([1, 2, 3, 4]);
        String? audioAuth;
        final client = clientWith((req) async {
          if (req.url.path == '/v1/speech') {
            expect(req.headers['authorization'], 'Bearer tok-1');
            final body = json.decode(req.body) as Map<String, dynamic>;
            expect(body['voice_id'], 'pv-1');
            expect(body['text'], 'Hello');
            expect(body['request_id'], isNotEmpty);
            expect(body['profile_id'], 'p1');
            return http.Response(
              json.encode({
                'request_id': body['request_id'],
                'audio': {
                  'url': 'https://cdn.test/a.mp3',
                  'expires_in': 300,
                  'content_type': 'audio/mpeg',
                },
                'source': 'elevenlabs',
                'fallback_allowed': true,
              }),
              200,
            );
          }
          if (req.url.host == 'cdn.test') {
            audioAuth = req.headers['authorization'];
            return http.Response.bytes(audio, 200);
          }
          return http.Response('not found', 404);
        });
        client.setToken('tok-1');
        final bytes = await client.synthesize(
          requestId: proxyUuid4(),
          profileId: 'p1',
          voiceId: 'pv-1',
          text: 'Hello',
        );
        expect(bytes, audio);
        // The signed URL fetch carries the bearer token (contract).
        expect(audioAuth, 'Bearer tok-1');
      },
    );

    test('429 quota_exceeded is fallbackAllowed', () async {
      final client = clientWith(
        (_) async => http.Response(
          json.encode({
            'request_id': 'r1',
            'error': {
              'code': 'quota_exceeded',
              'message': 'Monthly quota used up.',
              'category': 'quota',
            },
            'source': 'none',
            'fallback_allowed': true,
          }),
          429,
        ),
      );
      client.setToken('tok-1');
      try {
        await client.synthesize(
          requestId: 'r1',
          profileId: 'p1',
          voiceId: 'pv-1',
          text: 'Hello',
        );
        fail('expected ProxyException');
      } on ProxyException catch (e) {
        expect(e.code, 'quota_exceeded');
        expect(e.fallbackAllowed, isTrue);
      }
    });

    test('502 provider_unavailable is fallbackAllowed', () async {
      final client = clientWith(
        (_) async => http.Response(
          json.encode({
            'error': {'code': 'provider_unavailable', 'message': 'Down.'},
            'fallback_allowed': true,
          }),
          502,
        ),
      );
      client.setToken('tok-1');
      try {
        await client.synthesize(
          requestId: 'r1',
          profileId: 'p1',
          voiceId: 'pv-1',
          text: 'Hello',
        );
        fail('expected ProxyException');
      } on ProxyException catch (e) {
        expect(e.code, 'provider_unavailable');
        expect(e.fallbackAllowed, isTrue);
      }
    });

    test('timeout becomes an unreachable ProxyException', () async {
      // A handler that never answers: the client's 5s timeout must fire.
      final client = clientWith((_) => Completer<http.Response>().future);
      client.setToken('tok-1');
      try {
        await client.synthesize(
          requestId: 'r1',
          profileId: 'p1',
          voiceId: 'pv-1',
          text: 'Hello',
        );
        fail('expected ProxyException');
      } on ProxyException catch (e) {
        expect(e.code, 'unreachable');
        expect(e.fallbackAllowed, isTrue);
      }
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('socket error becomes an unreachable ProxyException', () async {
      final client = clientWith(
        (_) async => throw const SocketException('no route'),
      );
      client.setToken('tok-1');
      try {
        await client.synthesize(
          requestId: 'r1',
          profileId: 'p1',
          voiceId: 'pv-1',
          text: 'Hello',
        );
        fail('expected ProxyException');
      } on ProxyException catch (e) {
        expect(e.code, 'unreachable');
      }
    });

    test('synthesize without a token throws unauthorized', () async {
      final client = clientWith((_) async => http.Response('{}', 200));
      try {
        await client.synthesize(
          requestId: 'r1',
          profileId: 'p1',
          voiceId: 'pv-1',
          text: 'Hello',
        );
        fail('expected ProxyException');
      } on ProxyException catch (e) {
        expect(e.code, 'unauthorized');
      }
    });
  });

  group('entitlement and usage', () {
    test('getEntitlement parses voices and quota', () async {
      final client = clientWith((req) async {
        expect(req.url.path, '/v1/voice-entitlement');
        expect(req.headers['authorization'], 'Bearer tok-1');
        return http.Response(
          json.encode({
            'family_id': 'fam-1',
            'voices': [
              {'id': 'pv-1', 'name': 'Maya', 'locale': 'en', 'version': 'v3'},
            ],
            'quota': {
              'monthly_cap': 500000,
              'used': 1200,
              'remaining': 498800,
              'per_minute_limit': 10000,
              'source': 'nonprofit',
              'period_start': '2026-09-01',
            },
          }),
          200,
        );
      });
      client.setToken('tok-1');
      final ent = await client.getEntitlement();
      expect(ent.voices, hasLength(1));
      expect(ent.voices.single.id, 'pv-1');
      expect(ent.monthlyCap, 500000);
      expect(ent.used, 1200);
      expect(ent.remaining, 498800);
    });

    test('getUsageSummary parses counts without utterance text', () async {
      // The contract guarantees no utterance text is ever included: assert
      // on the wire body the client accepts.
      const wireBody =
          '{"family_id":"fam-1",'
          '"period":{"start":"2026-09-01","end":"2026-10-01"},'
          '"quota":{"monthly_cap":500000,"used":42,"remaining":499958},'
          '"requests":{"total":10,"cache_hits":7,"provider_calls":3,'
          '"throttled":0,"errors":0,"avg_latency_ms":812}}';
      expect(wireBody, isNot(contains('utterance')));
      final client = clientWith((_) async => http.Response(wireBody, 200));
      client.setToken('tok-1');
      final usage = await client.getUsageSummary();
      expect(usage.used, 42);
      expect(usage.total, 10);
      expect(usage.cacheHits, 7);
      expect(usage.avgLatencyMs, 812);
    });
  });

  group('devices', () {
    test('registerDevice 201 parses the registration', () async {
      final client = clientWith((req) async {
        expect(req.url.path, '/v1/devices/register');
        final body = json.decode(req.body) as Map<String, dynamic>;
        expect(body['install_id'], 'install-1');
        return http.Response(
          json.encode({
            'device': {
              'install_id': 'install-1',
              'device_name': 'iPad',
              'platform': 'ios',
              'created_at': '2026-09-15T10:00:00Z',
              'last_seen_at': '2026-09-15T10:00:00Z',
            },
            'device_slots': 3,
            'subscription_tier': 'base',
            'devices_used': 1,
          }),
          201,
        );
      });
      client.setToken('tok-1');
      final reg = await client.registerDevice(
        installId: 'install-1',
        deviceName: 'iPad',
        platform: 'ios',
      );
      expect(reg.deviceSlots, 3);
      expect(reg.subscriptionTier, 'base');
      expect(reg.devicesUsed, 1);
      expect(reg.device.deviceName, 'iPad');
    });

    test(
      'registerDevice 403 preserves DEVICE_LIMIT_REACHED and the message',
      () async {
        const serverMessage = 'All 3 device slots are in use.';
        final client = clientWith(
          (_) async => http.Response(
            json.encode({
              'error': {
                'code': 'DEVICE_LIMIT_REACHED',
                'message': serverMessage,
              },
              'device_slots': 3,
              'subscription_tier': 'base',
              'devices_used': 3,
            }),
            403,
          ),
        );
        client.setToken('tok-1');
        try {
          await client.registerDevice(installId: 'install-9');
          fail('expected ProxyException');
        } on ProxyException catch (e) {
          expect(e.code, 'DEVICE_LIMIT_REACHED');
          expect(e.message, serverMessage);
        }
      },
    );

    test('listDevices parses the device list', () async {
      final client = clientWith((req) async {
        expect(req.url.path, '/v1/devices');
        return http.Response(
          json.encode({
            'device_slots': 4,
            'subscription_tier': 'plus',
            'devices_used': 2,
            'devices': [
              {
                'install_id': 'a',
                'device_name': 'iPad',
                'platform': 'ios',
                'last_seen_at': '2026-09-15T10:00:00Z',
              },
              {'install_id': 'b', 'platform': 'android'},
            ],
          }),
          200,
        );
      });
      client.setToken('tok-1');
      final list = await client.listDevices();
      expect(list.deviceSlots, 4);
      expect(list.subscriptionTier, 'plus');
      expect(list.devices, hasLength(2));
      expect(list.devices[1].deviceName, isNull);
    });

    test('deleteDevice 404 maps to device_not_found', () async {
      final client = clientWith((req) async {
        expect(req.method, 'DELETE');
        return http.Response(
          json.encode({
            'error': {'code': 'device_not_found', 'message': 'Gone.'},
          }),
          404,
        );
      });
      client.setToken('tok-1');
      try {
        await client.deleteDevice('missing');
        fail('expected ProxyException');
      } on ProxyException catch (e) {
        expect(e.code, 'device_not_found');
      }
    });
  });

  group('ProxyAuthStore', () {
    test('save/read/clear round-trips the token and family id', () async {
      final store = ProxyAuthStore(store: _FakeSecureStore());
      expect(await store.readToken(), isNull);
      await store.save(
        ProxyAuthResult(token: 'tok-9', familyId: 'fam-9', profileIds: ['p1']),
      );
      expect(await store.readToken(), 'tok-9');
      expect(await store.readFamilyId(), 'fam-9');
      await store.clear();
      expect(await store.readToken(), isNull);
      expect(await store.readFamilyId(), isNull);
    });

    test('installId is generated once and stable', () async {
      final fake = _FakeSecureStore();
      final store = ProxyAuthStore(store: fake);
      final first = await store.installId();
      final second = await store.installId();
      expect(first, second);
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(first),
        isTrue,
      );
      // Clearing the account keeps the install id (no slot burned on
      // re-sign-in).
      await store.save(
        ProxyAuthResult(token: 't', familyId: 'f', profileIds: const []),
      );
      await store.clear();
      expect(await store.installId(), first);
    });
  });
}
