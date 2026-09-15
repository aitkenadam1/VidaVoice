import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:onevoz/services/elevenlabs_audio.dart';
import 'package:onevoz/services/elevenlabs_service.dart';
import 'package:onevoz/services/tts_service.dart';

class _FakeElevenAudio extends ElevenLabsAudioPlayer {
  final played = <Uint8List>[];
  @override
  Future<void> playBytes(Uint8List bytes) async {
    played.add(bytes);
  }
}

ElevenLabsService _service(
  Future<http.Response> Function(http.Request) handler,
) => ElevenLabsService(apiKey: 'test-key', httpClient: MockClient(handler));

void main() {
  group('timeouts (Blocker 1)', () {
    test(
      'a stalled synthesize becomes an ElevenLabsException, not a hang',
      () async {
        final svc = _service((_) => Completer<http.Response>().future);
        await expectLater(
          svc.synthesize(text: 'hello', voiceId: 'v1'),
          throwsA(
            isA<ElevenLabsException>().having(
              (e) => e.message,
              'message',
              contains('too long'),
            ),
          ),
        );
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test('a stalled voice list also surfaces instead of hanging', () async {
      final svc = _service((_) => Completer<http.Response>().future);
      await expectLater(svc.listVoices(), throwsA(isA<ElevenLabsException>()));
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  group('cloneVoice failure surface (Blocker 2)', () {
    test(
      'a missing sample file throws ElevenLabsException, never raw',
      () async {
        final svc = _service((_) async => http.Response('', 500));
        await expectLater(
          svc.cloneVoice(
            name: 'Maya',
            samples: const [
              VoiceSample(path: '/does/not/exist.wav', duration: Duration.zero),
            ],
          ),
          throwsA(isA<ElevenLabsException>()),
        );
      },
    );

    test('a mid-upload connection reset is wrapped, not leaked', () async {
      // fromPath succeeds (file exists) but send throws a raw error,
      // like bytesToString would on a reset connection.
      final tmp = await File('${Directory.systemTemp.path}/vv-sample.wav')
          .create();
      await tmp.writeAsBytes(List.filled(64, 0));
      try {
        final svc = ElevenLabsService(
          apiKey: 'test-key',
          httpClient: _ThrowingClient(),
        );
        await expectLater(
          svc.cloneVoice(
            name: 'Maya',
            samples: [VoiceSample(path: tmp.path, duration: Duration.zero)],
          ),
          throwsA(isA<ElevenLabsException>()),
        );
      } finally {
        await tmp.delete();
      }
    });
  });

  group('deleteVoice', () {
    test('sends DELETE to /v1/voices/{id}', () async {
      http.Request? seen;
      final svc = _service((req) async {
        seen = req;
        return http.Response('', 200);
      });
      await svc.deleteVoice('abc123');
      expect(seen?.method, 'DELETE');
      expect(seen?.url.path, '/v1/voices/abc123');
    });

    test('a missing voice surfaces as ElevenLabsException', () async {
      final svc = _service((_) async => http.Response('{"detail":"x"}', 404));
      await expectLater(
        svc.deleteVoice('gone'),
        throwsA(isA<ElevenLabsException>()),
      );
    });
  });

  group('cloud billing cache', () {
    TtsService makeTts(void Function() onCall) {
      final tts = TtsService();
      tts.elevenLabs = ElevenLabsService(
        apiKey: 'test-key',
        httpClient: MockClient((_) async {
          onCall();
          return http.Response.bytes(Uint8List.fromList([1, 2, 3]), 200);
        }),
      );
      tts.elevenAudioPlayer = _FakeElevenAudio();
      return tts;
    }

    const voice = TtsVoice(
      name: 'Maya',
      locale: 'en',
      elevenLabsVoiceId: 'cv-1',
    );
    const other = TtsVoice(
      name: 'Narrator',
      locale: 'en',
      elevenLabsVoiceId: 'cv-2',
    );

    test('re-tapping the same button does not re-bill', () async {
      var calls = 0;
      final tts = makeTts(() => calls++);
      await tts.setVoice(voice);
      await tts.speak('more');
      await tts.speak('more');
      await tts.speak('more');
      expect(calls, 1);
      expect((tts.elevenAudioPlayer as _FakeElevenAudio).played, hasLength(3));
    });

    test(
      'different text still bills; different voice bills separately',
      () async {
        var calls = 0;
        final tts = makeTts(() => calls++);
        await tts.setVoice(voice);
        await tts.speak('more');
        await tts.speak('juice');
        expect(calls, 2);
        await tts.setVoice(other);
        await tts.speak('more');
        expect(calls, 3);
      },
    );
  });

  group('SavedElevenLabsVoice.createdByApp', () {
    test('round-trips through JSON', () {
      const v = SavedElevenLabsVoice(
        id: 'v1',
        name: 'Maya',
        locale: 'en',
        createdByApp: true,
      );
      final back = SavedElevenLabsVoice.fromJson(v.toJson());
      expect(back.createdByApp, isTrue);
      expect(back.id, 'v1');
    });

    test('legacy entries without the field default to false', () {
      final back = SavedElevenLabsVoice.fromJson({
        'id': 'v1',
        'name': 'Maya',
        'locale': 'en',
      });
      expect(back.createdByApp, isFalse);
    });
  });
}

/// Client whose send throws a raw transport error (connection reset).
class _ThrowingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw const SocketException('connection reset');
  }
}
