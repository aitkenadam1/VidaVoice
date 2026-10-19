import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onevoz/models/word.dart';
import 'package:onevoz/services/elevenlabs_audio.dart';
import 'package:onevoz/services/profile_service.dart';
import 'package:onevoz/services/proxy_client.dart';
import 'package:onevoz/services/tts_service.dart';
import 'package:onevoz/state/session_state.dart';

/// Speech prefetch: composing a sentence starts its cloud synthesis in
/// the background so Speak is instant. Pins the contracts:
/// * prefetch warms the same cache speak() reads — no second request;
/// * speak() awaits an in-flight prefetch instead of duplicating it;
/// * prefetch failures are silent and never open/block the speak path;
/// * prefetch no-ops for on-device voices;
/// * Build-mode composition triggers a debounced prefetch of the strip.
class _FakeElevenAudio extends ElevenLabsAudioPlayer {
  final played = <Uint8List>[];
  @override
  Future<void> playBytes(Uint8List bytes) async {
    played.add(bytes);
  }

  @override
  Future<void> stop() async {}
}

const _proxyVoice = TtsVoice(
  name: 'Cloud Maya',
  locale: 'en',
  proxyVoiceId: 'pv-1',
);

void main() {
  final engineSpoken = <String>[];

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
              engineSpoken.add(call.arguments.toString());
              return 1;
            default:
              return null;
          }
        });
  });

  setUp(() => engineSpoken.clear());

  /// Counting speech backend. [gate] can hold /v1/speech responses open
  /// to exercise the in-flight path.
  ({TtsService tts, _FakeElevenAudio player, List<String> speechTexts})
  makeTts({Completer<void>? gate, bool failSpeech = false}) {
    final speechTexts = <String>[];
    final player = _FakeElevenAudio();
    final proxy = ProxyClient(
      client: MockClient((req) async {
        if (req.url.path == '/v1/speech') {
          speechTexts.add(
            (json.decode(req.body) as Map<String, dynamic>)['text'] as String,
          );
          if (gate != null) await gate.future;
          if (failSpeech) {
            return http.Response('{"error":"boom"}', 500);
          }
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
        return http.Response.bytes(Uint8List.fromList([1, 2, 3]), 200);
      }),
      baseUrl: 'https://proxy.test',
    );
    proxy.setToken('tok-1');
    final tts = TtsService();
    tts.proxy = proxy;
    tts.proxyProfileIdProvider = () => 'p1';
    tts.elevenAudioPlayer = player;
    tts.currentVoice = _proxyVoice;
    return (tts: tts, player: player, speechTexts: speechTexts);
  }

  test(
    'prefetch warms the cache; speak reuses it without a new request',
    () async {
      final h = makeTts();
      await h.tts.prefetch('I want juice');
      expect(h.speechTexts, ['I want juice']);
      expect(h.player.played, isEmpty); // prefetch never plays

      await h.tts.speak('I want juice');
      expect(h.speechTexts, ['I want juice']); // still one request
      expect(h.player.played, hasLength(1));
    },
  );

  test(
    'speak awaits an in-flight prefetch instead of duplicating it',
    () async {
      final gate = Completer<void>();
      final h = makeTts(gate: gate);
      final prefetching = h.tts.prefetch('hello there');
      // Let the request actually start before speaking.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final speaking = h.tts.speak('hello there');
      gate.complete();
      await Future.wait([prefetching, speaking]);
      expect(h.speechTexts, ['hello there']); // exactly one request
      expect(h.player.played, hasLength(1));
    },
  );

  test(
    'prefetch failure is silent; speak still falls back to device voice',
    () async {
      final h = makeTts(failSpeech: true);
      await h.tts.init(language: 'en-US'); // engine ready for the fallback
      await h.tts.prefetch('anything'); // must not throw
      await h.tts.speak('anything');
      expect(h.player.played, isEmpty);
      expect(engineSpoken.join(), contains('anything'));
    },
  );

  test('prefetch no-ops for on-device voices', () async {
    final h = makeTts();
    h.tts.currentVoice = const TtsVoice(name: 'Local', locale: 'en-US');
    await h.tts.prefetch('hello');
    expect(h.speechTexts, isEmpty);
  });

  test(
    'build-mode composition prefetches the composed strip, debounced',
    () async {
      SharedPreferences.setMockInitialValues({});
      final h = makeTts();
      final raw = File('assets/lang/en.json').readAsStringSync();
      final pack = LanguagePack.fromJson(
        Map<String, dynamic>.from(json.decode(raw) as Map),
      );
      pack.validate();
      final session = SessionState(tts: h.tts, proxy: h.tts.proxy);
      // The constructor wires the provider to the session's server-profile
      // list (empty without sign-in); point it at the test profile so the
      // managed-voice path is live, as it is for a signed-in family.
      h.tts.proxyProfileIdProvider = () => 'p1';
      session.pack = pack;
      session.status = BootStatus.ready;
      session.onboardingComplete = true;
      session.proxySignedIn = true;
      await session.profiles.load();
      await session.profiles.setCommunicationMode(
        session.profiles.active!.id,
        CommunicationMode.build,
      );

      session.buildAdd(pack.wordById('core.i'));
      session.buildAdd(pack.wordById('core.want'));
      // Inside the debounce window: nothing yet.
      expect(h.speechTexts, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      // Only the final composed text was fetched — not the intermediate.
      expect(h.speechTexts, ['I want']);

      // Speak now plays from the warmed cache — no second request.
      session.buildSpeak();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(h.speechTexts, ['I want']);
      expect(h.player.played, hasLength(1));
    },
  );
}
