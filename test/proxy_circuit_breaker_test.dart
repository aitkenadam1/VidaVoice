import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:voicesimple/services/elevenlabs_audio.dart';
import 'package:voicesimple/services/elevenlabs_key_store.dart';
import 'package:voicesimple/services/elevenlabs_service.dart';
import 'package:voicesimple/services/proxy_client.dart';
import 'package:voicesimple/services/tts_service.dart';
import 'package:voicesimple/state/session_state.dart';

/// Player double: never touches a platform channel.
class _FakeElevenAudio extends ElevenLabsAudioPlayer {
  final played = <Uint8List>[];
  @override
  Future<void> playBytes(Uint8List bytes) async {
    played.add(bytes);
  }

  @override
  Future<void> stop() async {}
}

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

/// ElevenLabs double with controllable behavior.
class _FakeElevenLabs extends ElevenLabsService {
  _FakeElevenLabs() : super(apiKey: 'test-key');

  int calls = 0;
  Future<Uint8List> Function()? behavior;

  @override
  Future<Uint8List> synthesize({
    required String text,
    required String voiceId,
  }) async {
    calls++;
    final b = behavior;
    if (b != null) return b();
    throw Exception('boom');
  }
}

void main() {
  /// Speech that reached the on-device engine (flutter_tts channel mock).
  final spoken = <String>[];

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'), (
          call,
        ) async {
          switch (call.method) {
            case 'getVoices':
              return [
                {'name': 'Test Voice', 'locale': 'en-US'},
              ];
            case 'speak':
              spoken.add(call.arguments.toString());
              return 1;
            default:
              return null;
          }
        });
  });

  setUp(() {
    spoken.clear();
  });

  const proxyVoice = TtsVoice(
    name: 'Cloud Maya',
    locale: 'en',
    proxyVoiceId: 'pv-1',
  );

  const elevenVoice = TtsVoice(
    name: 'EL Sarah',
    locale: 'en',
    elevenLabsVoiceId: 'el-1',
  );

  Future<http.Response> speechOk(
    http.Request req, {
    List<int> audio = const [7, 7, 7],
  }) async {
    if (req.url.path == '/v1/speech') {
      return http.Response(
        json.encode({
          'request_id': 'r1',
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
    return http.Response.bytes(Uint8List.fromList(audio), 200);
  }

  Future<http.Response> unauthorized(http.Request req) async =>
      http.Response(
        json.encode({
          'error': {'code': 'unauthorized', 'message': 'Expired.'},
        }),
        401,
      );

  /// Models the real two-step fetch: POST /v1/speech returns a signed
  /// audio URL, then the client GETs the audio bytes. [failSpeech] only
  /// fails the speech POST; the audio GET always succeeds.
  Future<http.Response> Function(http.Request) proxyHandler({
    required bool Function() failSpeech,
    required void Function() onSpeechRequest,
  }) {
    return (req) async {
      if (req.url.path == '/v1/speech') {
        onSpeechRequest();
        if (failSpeech()) return http.Response('boom', 500);
        return speechOk(req);
      }
      return http.Response.bytes(Uint8List.fromList([7, 7, 7]), 200);
    };
  }

  /// A proxy-voiced TTS with a short-cooldown breaker for fast tests.
  Future<TtsService> readyProxyTts({
    required Future<http.Response> Function(http.Request) handler,
    Duration cooldown = const Duration(milliseconds: 80),
    int maxFailures = 3,
  }) async {
    final tts = TtsService();
    final proxy = ProxyClient(
      client: MockClient(handler),
      baseUrl: 'https://proxy.test',
    );
    proxy.setToken('tok-1');
    tts.proxy = proxy;
    tts.proxyProfileIdProvider = () => 'p1';
    tts.elevenAudioPlayer = _FakeElevenAudio();
    tts.proxyBreaker = CloudCircuitBreaker(
      maxFailures: maxFailures,
      cooldown: cooldown,
    );
    expect(await tts.init(language: 'en-US'), isTrue);
    await tts.setVoice(proxyVoice);
    return tts;
  }

  group('CloudCircuitBreaker', () {
    test('closed initially; trips after maxFailures consecutive failures', () {
      final b = CloudCircuitBreaker(maxFailures: 3);
      expect(b.isOpen, isFalse);
      b.recordFailure();
      b.recordFailure();
      expect(b.isOpen, isFalse);
      b.recordFailure();
      expect(b.isOpen, isTrue);
    });

    test('stays open during the cooldown, half-opens after', () async {
      final b = CloudCircuitBreaker(
        maxFailures: 2,
        cooldown: const Duration(milliseconds: 60),
      );
      b.recordFailure();
      b.recordFailure();
      expect(b.isOpen, isTrue);
      await Future.delayed(const Duration(milliseconds: 90));
      expect(b.isOpen, isFalse); // cooldown elapsed: probe allowed
    });

    test('a success resets the consecutive count', () {
      final b = CloudCircuitBreaker(maxFailures: 3);
      b.recordFailure();
      b.recordFailure();
      b.recordSuccess();
      expect(b.consecutiveFailures, 0);
      b.recordFailure();
      b.recordFailure();
      expect(b.isOpen, isFalse);
    });
  });

  group('proxy path circuit breaker', () {
    test('after maxFailures the cloud is skipped, no request is made',
        () async {
      var requests = 0;
      final tts = await readyProxyTts(
        handler: (_) async {
          requests++;
          return http.Response('boom', 500);
        },
      );
      await tts.speak('one');
      await tts.speak('two');
      await tts.speak('three');
      expect(requests, 3);
      expect(tts.proxyBreaker.isOpen, isTrue);
      // Fourth tap: no network attempt at all, straight to on-device.
      await tts.speak('four');
      expect(requests, 3);
      expect(spoken, ['one', 'two', 'three', 'four']);
    });

    test('breaker recovers after the cooldown: probe succeeds, closes',
        () async {
      var requests = 0;
      var fail = true;
      final tts = await readyProxyTts(
        handler: proxyHandler(
          failSpeech: () => fail,
          onSpeechRequest: () => requests++,
        ),
      );
      await tts.speak('one');
      await tts.speak('two');
      await tts.speak('three');
      expect(tts.proxyBreaker.isOpen, isTrue);
      // The backend comes back; after the cooldown a probe goes through.
      fail = false;
      await Future.delayed(const Duration(milliseconds: 120));
      await tts.speak('five');
      expect(requests, 4); // the probe
      expect(tts.proxyBreaker.isOpen, isFalse);
      final player = tts.elevenAudioPlayer as _FakeElevenAudio;
      expect(player.played, hasLength(1)); // probe audio played
    });

    test('a success between failures resets the count', () async {
      var requests = 0;
      var speechCount = 0;
      final tts = await readyProxyTts(
        // Fail, fail, succeed, fail, fail — never 3 in a row.
        handler: proxyHandler(
          failSpeech: () => ++speechCount != 3,
          onSpeechRequest: () => requests++,
        ),
      );
      // Use distinct texts so the client cache never serves a hit.
      await tts.speak('a');
      await tts.speak('b');
      await tts.speak('c'); // success: resets the count
      await tts.speak('d');
      await tts.speak('e');
      expect(tts.proxyBreaker.isOpen, isFalse);
      expect(requests, 5);
    });

    test('cached audio still plays while the breaker is open', () async {
      var requests = 0;
      var fail = false;
      final tts = await readyProxyTts(
        handler: proxyHandler(
          failSpeech: () => fail,
          onSpeechRequest: () => requests++,
        ),
      );
      await tts.speak('cached'); // succeeds and fills the client cache
      expect(requests, 1);
      fail = true;
      await tts.speak('x1');
      await tts.speak('x2');
      await tts.speak('x3');
      expect(tts.proxyBreaker.isOpen, isTrue);
      final before = requests;
      // The cached utterance plays without any network attempt.
      await tts.speak('cached');
      expect(requests, before);
      final player = tts.elevenAudioPlayer as _FakeElevenAudio;
      expect(player.played, hasLength(2));
      expect(spoken, ['x1', 'x2', 'x3']); // only the failures fell back
    });
  });

  group('401 handling', () {
    test('401 on the speech path fires onProxyUnauthorized', () async {
      var unauthorizedCalls = 0;
      final tts = await readyProxyTts(handler: unauthorized);
      tts.onProxyUnauthorized = () async {
        unauthorizedCalls++;
      };
      await tts.speak('Hello');
      expect(unauthorizedCalls, 1);
      // Speech still fell back to on-device — never silence.
      expect(spoken, ['Hello']);
    });

    test('SessionState wires onProxyUnauthorized to signOut', () async {
      final proxy = ProxyClient(
        client: MockClient((_) async => http.Response('unused', 500)),
        baseUrl: 'https://proxy.test',
      );
      final session = SessionState(
        tts: TtsService(),
        proxy: proxy,
        proxyAuth: ProxyAuthStore(store: _FakeSecureStore()),
      );
      expect(session.tts.onProxyUnauthorized, isNotNull);
      // Simulate what the speech path does on a 401.
      proxy.setToken('tok-1');
      session.proxySignedIn = true;
      await session.tts.onProxyUnauthorized!();
      expect(session.proxy.hasToken, isFalse);
      expect(session.proxySignedIn, isFalse);
    });
  });

  group('ElevenLabs path circuit breaker', () {
    Future<TtsService> readyElevenTts(_FakeElevenLabs fake) async {
      final tts = TtsService();
      tts.elevenLabs = fake;
      tts.elevenAudioPlayer = _FakeElevenAudio();
      tts.elevenLabsBreaker = CloudCircuitBreaker(
        maxFailures: 3,
        cooldown: const Duration(milliseconds: 80),
      );
      expect(await tts.init(language: 'en-US'), isTrue);
      await tts.setVoice(elevenVoice);
      return tts;
    }

    test('after maxFailures synthesize is not called again', () async {
      final fake = _FakeElevenLabs();
      final tts = await readyElevenTts(fake);
      await tts.speak('one');
      await tts.speak('two');
      await tts.speak('three');
      expect(fake.calls, 3);
      expect(tts.elevenLabsBreaker.isOpen, isTrue);
      await tts.speak('four');
      expect(fake.calls, 3);
      expect(spoken, ['one', 'two', 'three', 'four']);
    });

    test('breaker recovers after the cooldown', () async {
      final fake = _FakeElevenLabs();
      final tts = await readyElevenTts(fake);
      await tts.speak('one');
      await tts.speak('two');
      await tts.speak('three');
      expect(tts.elevenLabsBreaker.isOpen, isTrue);
      fake.behavior = () async => Uint8List.fromList([9, 9]);
      await Future.delayed(const Duration(milliseconds: 120));
      await tts.speak('five');
      expect(fake.calls, 4);
      expect(tts.elevenLabsBreaker.isOpen, isFalse);
      final player = tts.elevenAudioPlayer as _FakeElevenAudio;
      expect(player.played.single, [9, 9]);
    });
  });
}
