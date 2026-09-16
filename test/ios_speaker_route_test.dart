import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:onevoz/services/ios_speaker_route.dart';
import 'package:onevoz/services/tts_service.dart';

void main() {
  // FlutterTts() registers a method-call handler in its constructor, which
  // needs the test binding up front.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('IosSpeakerRoute contract (the actual fix)', () {
    test('flutter_tts path uses playAndRecord + defaultToSpeaker', () {
      expect(
        IosSpeakerRoute.ttsCategory,
        IosTextToSpeechAudioCategory.playAndRecord,
      );
      // defaultToSpeaker is the whole fix: without it iOS routes
      // playAndRecord audio to the earpiece during a phone call.
      expect(
        IosSpeakerRoute.ttsOptions,
        contains(IosTextToSpeechAudioCategoryOptions.defaultToSpeaker),
      );
      expect(
        IosSpeakerRoute.ttsOptions,
        contains(IosTextToSpeechAudioCategoryOptions.mixWithOthers),
      );
      // BT headsets / AirPlay keep working; we only change the default.
      expect(
        IosSpeakerRoute.ttsOptions,
        contains(IosTextToSpeechAudioCategoryOptions.allowBluetooth),
      );
      expect(
        IosSpeakerRoute.ttsOptions,
        contains(IosTextToSpeechAudioCategoryOptions.allowAirPlay),
      );
      expect(
        IosSpeakerRoute.ttsMode,
        IosTextToSpeechAudioMode.spokenAudio,
      );
    });

    test('audioplayers path uses playAndRecord + defaultToSpeaker', () {
      final ios = IosSpeakerRoute.speakerAudioContext.iOS;
      expect(ios.category, AVAudioSessionCategory.playAndRecord);
      expect(
        ios.options,
        contains(AVAudioSessionOptions.defaultToSpeaker),
      );
      expect(
        ios.options,
        contains(AVAudioSessionOptions.mixWithOthers),
      );
      expect(
        ios.options,
        contains(AVAudioSessionOptions.allowBluetooth),
      );
      expect(
        ios.options,
        contains(AVAudioSessionOptions.allowAirPlay),
      );
    });
  });

  group('IosSpeakerRoute wiring', () {
    test('routeToSpeaker runs both the TTS and player config steps', () async {
      var ttsCalls = 0;
      var playerCalls = 0;
      FlutterTts? seenEngine;
      final route = IosSpeakerRoute(
        configureTts: (engine) async {
          ttsCalls++;
          seenEngine = engine;
        },
        configurePlayers: () async {
          playerCalls++;
        },
      );
      final engine = FlutterTts();
      await route.routeToSpeaker(engine);
      expect(ttsCalls, 1);
      expect(playerCalls, 1);
      expect(seenEngine, same(engine));
    });

    test('a failing config step never throws (speech must not break)',
        () async {
      final route = IosSpeakerRoute(
        configureTts: (_) async => throw StateError('tts exploded'),
        configurePlayers: () async => throw StateError('players exploded'),
      );
      await route.routeToSpeaker(FlutterTts()); // must not throw
    });

    test('player step still runs when the TTS step throws', () async {
      var playerCalls = 0;
      final route = IosSpeakerRoute(
        configureTts: (_) async => throw StateError('tts exploded'),
        configurePlayers: () async {
          playerCalls++;
        },
      );
      await route.routeToSpeaker(FlutterTts());
      expect(playerCalls, 1);
    });
  });

  group('TtsService.configureSpeakerRoute platform guard', () {
    test('does nothing on non-iOS platforms', () async {
      final tts = TtsService();
      var calls = 0;
      tts.iosSpeakerRoute = IosSpeakerRoute(
        configureTts: (_) async => calls++,
        configurePlayers: () async => calls++,
      );
      await tts.configureSpeakerRoute();
      expect(calls, 0);
    });

    test('routes on iOS', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final tts = TtsService();
        var ttsCalls = 0;
        var playerCalls = 0;
        tts.iosSpeakerRoute = IosSpeakerRoute(
          configureTts: (_) async => ttsCalls++,
          configurePlayers: () async => playerCalls++,
        );
        await tts.configureSpeakerRoute();
        expect(ttsCalls, 1);
        expect(playerCalls, 1);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
