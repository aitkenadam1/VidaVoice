import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Routes all spoken audio through the iPhone loudspeaker — including
/// during a cellular phone call.
///
/// The calling feature's designed flow is: call on speakerphone -> switch
/// back to OneVoz -> tap phrase cards -> the other party hears the phrases.
/// During a phone call iOS routes third-party app audio to the earpiece
/// receiver unless the app's audio session is playAndRecord +
/// defaultToSpeaker, so without this the remote party hears nothing.
///
/// Both speech plugins share one AVAudioSession, and audioplayers applies
/// ITS global context (default: .playback) to that shared session — so
/// both flutter_tts (system voice) and audioplayers (Kokoro neural +
/// ElevenLabs/managed cloud voices) must be configured, or the player
/// paths silently clobber the routing back.
///
/// iOS native only. The web build is a deliberate no-op: Safari exposes
/// no audio-route API, so the web app cannot force the loudspeaker
/// during a call.
class IosSpeakerRoute {
  IosSpeakerRoute({
    Future<void> Function(FlutterTts engine)? configureTts,
    Future<void> Function()? configurePlayers,
  }) : _configureTts = configureTts ?? _defaultConfigureTts,
       _configurePlayers = configurePlayers ?? _defaultConfigurePlayers;

  final Future<void> Function(FlutterTts engine) _configureTts;
  final Future<void> Function() _configurePlayers;

  /// flutter_tts (system voice) routing. Locked as static consts so tests
  /// pin the contract: playAndRecord + defaultToSpeaker is the whole fix.
  static const ttsCategory = IosTextToSpeechAudioCategory.playAndRecord;

  static const ttsOptions = <IosTextToSpeechAudioCategoryOptions>[
    IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
    IosTextToSpeechAudioCategoryOptions.mixWithOthers,
    IosTextToSpeechAudioCategoryOptions.allowBluetooth,
    IosTextToSpeechAudioCategoryOptions.allowAirPlay,
  ];

  static const ttsMode = IosTextToSpeechAudioMode.spokenAudio;

  /// audioplayers (Kokoro neural + cloud voices) routing. Exposed as a
  /// getter so tests can assert the exact context handed to the plugin.
  static AudioContext get speakerAudioContext => AudioContext(
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.playAndRecord,
      options: {
        AVAudioSessionOptions.defaultToSpeaker,
        AVAudioSessionOptions.mixWithOthers,
        AVAudioSessionOptions.allowBluetooth,
        AVAudioSessionOptions.allowAirPlay,
      },
    ),
  );

  /// Applies the loudspeaker routing. Never throws: audio routing must
  /// never break speech — worst case the phrases play through whatever
  /// route was already configured.
  Future<void> routeToSpeaker(FlutterTts engine) async {
    try {
      await _configureTts(engine);
    } catch (_) {}
    try {
      await _configurePlayers();
    } catch (_) {}
  }

  static Future<void> _defaultConfigureTts(FlutterTts engine) =>
      engine.setIosAudioCategory(ttsCategory, ttsOptions, ttsMode);

  static Future<void> _defaultConfigurePlayers() =>
      AudioPlayer.global.setAudioContext(speakerAudioContext);
}
