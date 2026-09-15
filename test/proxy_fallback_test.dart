import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:voicesimple/services/elevenlabs_audio.dart';
import 'package:voicesimple/services/proxy_client.dart';
import 'package:voicesimple/services/tts_service.dart';

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

void main() {
  /// Speech that reached the on-device engine (flutter_tts channel mock).
  final spoken = <String>[];

  /// Every flutter_tts method invoked — to prove cloud voices never poke
  /// the system engine's voice choice.
  final engineMethods = <String>[];

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'), (
          call,
        ) async {
          engineMethods.add(call.method);
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
    engineMethods.clear();
  });

  TtsService ttsWithProxy(
    Future<http.Response> Function(http.Request) handler, {
    bool withToken = true,
    String? Function()? profileIdProvider,
  }) {
    final tts = TtsService();
    final proxy = ProxyClient(
      client: MockClient(handler),
      baseUrl: 'https://proxy.test',
    );
    if (withToken) proxy.setToken('tok-1');
    tts.proxy = proxy;
    tts.proxyProfileIdProvider = profileIdProvider ?? () => 'p1';
    tts.elevenAudioPlayer = _FakeElevenAudio();
    return tts;
  }

  Future<http.Response> speechOk(
    http.Request req,
    List<Uint8List> out, {
    required List<int> audio,
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
    out.add(Uint8List.fromList(audio));
    return http.Response.bytes(Uint8List.fromList(audio), 200);
  }

  const proxyVoice = TtsVoice(
    name: 'Cloud Maya',
    locale: 'en',
    proxyVoiceId: 'pv-1',
  );

  Future<TtsService> readyTts(
    Future<http.Response> Function(http.Request) handler, {
    bool withToken = true,
    String? Function()? profileIdProvider,
  }) async {
    final tts = ttsWithProxy(
      handler,
      withToken: withToken,
      profileIdProvider: profileIdProvider,
    );
    expect(await tts.init(language: 'en-US'), isTrue);
    await tts.setVoice(proxyVoice);
    return tts;
  }

  test('proxy voice plays cloud audio; on-device stays silent', () async {
    final fetched = <Uint8List>[];
    final tts = await readyTts(
      (req) => speechOk(req, fetched, audio: [7, 7, 7]),
    );
    await tts.speak('Hello');
    final player = tts.elevenAudioPlayer as _FakeElevenAudio;
    expect(player.played, hasLength(1));
    expect(player.played.single, [7, 7, 7]);
    expect(spoken, isEmpty);
  });

  test('proxy failure falls back to on-device speech, never silence', () async {
    final tts = await readyTts((_) async => http.Response('boom', 500));
    await tts.speak('Hello'); // must not throw
    final player = tts.elevenAudioPlayer as _FakeElevenAudio;
    expect(player.played, isEmpty);
    expect(spoken, ['Hello']);
  });

  test('429 quota_exceeded falls back to on-device speech', () async {
    final tts = await readyTts(
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
    await tts.speak('Hello');
    final player = tts.elevenAudioPlayer as _FakeElevenAudio;
    expect(player.played, isEmpty);
    expect(spoken, ['Hello']);
  });

  test('401 unauthorized falls back to on-device speech', () async {
    final tts = await readyTts(
      (_) async => http.Response(
        json.encode({
          'error': {'code': 'unauthorized', 'message': 'Expired.'},
        }),
        401,
      ),
    );
    await tts.speak('Hello');
    final player = tts.elevenAudioPlayer as _FakeElevenAudio;
    expect(player.played, isEmpty);
    expect(spoken, ['Hello']);
  });

  test('proxy voice with no token falls back to on-device', () async {
    final tts = await readyTts(
      (_) async => http.Response('unused', 500),
      withToken: false,
    );
    await tts.speak('Hello');
    final player = tts.elevenAudioPlayer as _FakeElevenAudio;
    expect(player.played, isEmpty);
    expect(spoken, ['Hello']);
  });

  test('proxy voice with no profile id falls back to on-device', () async {
    final tts = await readyTts(
      (_) async => http.Response('unused', 500),
      profileIdProvider: () => null,
    );
    await tts.speak('Hello');
    final player = tts.elevenAudioPlayer as _FakeElevenAudio;
    expect(player.played, isEmpty);
    expect(spoken, ['Hello']);
  });

  test('proxy repeats are served from the client cache', () async {
    var speechCalls = 0;
    final tts = await readyTts((req) async {
      if (req.url.path == '/v1/speech') {
        speechCalls++;
        return http.Response(
          json.encode({
            'request_id': 'r1',
            'audio': {
              'url': 'https://cdn.test/a.mp3',
              'expires_in': 300,
              'content_type': 'audio/mpeg',
            },
            'source': 'cache',
            'fallback_allowed': true,
          }),
          200,
        );
      }
      return http.Response.bytes(Uint8List.fromList([3]), 200);
    });
    await tts.speak('Hi');
    await tts.speak('Hi');
    expect(speechCalls, 1); // one synthesis, not two
    final player = tts.elevenAudioPlayer as _FakeElevenAudio;
    expect(player.played, hasLength(2));
    expect(spoken, isEmpty);
  });

  test(
    'proxy voice does not leak into the system engine voice choice',
    () async {
      final tts = TtsService();
      tts.elevenAudioPlayer = _FakeElevenAudio();
      expect(await tts.init(language: 'en-US'), isTrue);
      await tts.setVoice(proxyVoice);
      // flutter_tts setVoice must never be called for a proxy voice — it is
      // not a system voice, and that engine is the fallback path.
      expect(engineMethods, isNot(contains('setVoice')));
    },
  );
}
