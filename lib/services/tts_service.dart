import 'package:flutter_tts/flutter_tts.dart';

import '../app_config.dart';

/// Thin wrapper around flutter_tts with app-level defaults.
class TtsService {
  /// Lazily created: constructing a [TtsService] (or a test fake of one)
  /// must not touch the platform channel before the binding exists.
  FlutterTts? _tts;
  FlutterTts get _engine => _tts ??= FlutterTts();
  bool _ready = false;

  double rate = AppConfig.defaultSpeechRate;
  double pitch = AppConfig.defaultSpeechPitch;

  Future<void> init({
    required String language,
    double rate = AppConfig.defaultSpeechRate,
    double pitch = AppConfig.defaultSpeechPitch,
  }) async {
    this.rate = rate;
    this.pitch = pitch;
    await _engine.setSharedInstance(true);
    await _engine.setLanguage(language);
    await _engine.setSpeechRate(rate);
    await _engine.setPitch(pitch);
    await _engine.awaitSpeakCompletion(true);
    _ready = true;
  }

  Future<void> setLanguage(String language) async {
    if (_ready) await _engine.setLanguage(language);
  }

  Future<void> setRate(double rate) async {
    this.rate = rate;
    if (_ready) await _engine.setSpeechRate(rate);
  }

  Future<void> setPitch(double pitch) async {
    this.pitch = pitch;
    if (_ready) await _engine.setPitch(pitch);
  }

  Future<void> speak(String text) async {
    if (_ready && text.trim().isNotEmpty) {
      await _engine.speak(text);
    }
  }
}
