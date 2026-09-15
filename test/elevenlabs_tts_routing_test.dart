import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:voicesimple/services/elevenlabs_audio.dart';
import 'package:voicesimple/services/elevenlabs_service.dart';
import 'package:voicesimple/services/tts_service.dart';

class _FakeElevenAudio extends ElevenLabsAudioPlayer {
  final played = <Uint8List>[];
  var stops = 0;
  @override
  Future<void> playBytes(Uint8List bytes) async {
    played.add(bytes);
  }

  @override
  Future<void> stop() async {
    stops++;
  }
}

void main() {
  TtsService ttsWith(Future<http.Response> Function(http.Request) handler) {
    final tts = TtsService();
    tts.elevenLabs = ElevenLabsService(
      apiKey: 'k',
      httpClient: MockClient(handler),
    );
    tts.elevenAudioPlayer = _FakeElevenAudio();
    return tts;
  }

  const cloud = TtsVoice(name: 'Maya', locale: 'en', elevenLabsVoiceId: 'cv-1');

  test('cloud voice speaks through ElevenLabs and plays the audio', () async {
    final bytes = Uint8List.fromList([9, 9, 9]);
    final tts = ttsWith((_) async => http.Response.bytes(bytes, 200));
    await tts.setVoice(cloud);
    await tts.speak('Hello');
    final fake = tts.elevenAudioPlayer as _FakeElevenAudio;
    expect(fake.played, hasLength(1));
    expect(fake.played.single, bytes);
  });

  test(
    'cloud failure never silences: speak does not throw, nothing plays',
    () async {
      final tts = ttsWith((_) async => http.Response('nope', 500));
      await tts.setVoice(cloud);
      await tts.speak('Hello'); // must not throw
      final fake = tts.elevenAudioPlayer as _FakeElevenAudio;
      expect(fake.played, isEmpty);
    },
  );

  test('cloud voice with no backend configured falls back silently', () async {
    final tts = TtsService();
    tts.elevenAudioPlayer = _FakeElevenAudio();
    await tts.setVoice(cloud);
    await tts.speak('Hello'); // must not throw
    expect((tts.elevenAudioPlayer as _FakeElevenAudio).played, isEmpty);
  });

  test('stop halts cloud playback too', () async {
    final tts = ttsWith((_) async => http.Response.bytes(Uint8List(0), 200));
    await tts.stop();
    expect((tts.elevenAudioPlayer as _FakeElevenAudio).stops, 1);
  });

  test('TtsVoice equality distinguishes cloud voice ids', () {
    expect(cloud, isNot(const TtsVoice(name: 'Maya', locale: 'en')));
    expect(
      cloud,
      const TtsVoice(name: 'Maya', locale: 'en', elevenLabsVoiceId: 'cv-1'),
    );
    expect(cloud.isElevenLabs, isTrue);
    expect(const TtsVoice(name: 'Maya', locale: 'en').isElevenLabs, isFalse);
  });
}
