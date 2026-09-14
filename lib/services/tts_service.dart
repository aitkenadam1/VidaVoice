import 'package:flutter_tts/flutter_tts.dart';

import '../app_config.dart';

/// Thin wrapper around flutter_tts with app-level defaults.
class TtsService {
  final FlutterTts _tts = FlutterTts();
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
    await _tts.setSharedInstance(true);
    await _tts.setLanguage(language);
    await _tts.setSpeechRate(rate);
    await _tts.setPitch(pitch);
    await _tts.awaitSpeakCompletion(true);
    _ready = true;
  }

  Future<void> setLanguage(String language) async {
    if (_ready) await _tts.setLanguage(language);
  }

  Future<void> setRate(double rate) async {
    this.rate = rate;
    if (_ready) await _tts.setSpeechRate(rate);
  }

  Future<void> setPitch(double pitch) async {
    this.pitch = pitch;
    if (_ready) await _tts.setPitch(pitch);
  }

  Future<void> speak(String text) async {
    if (_ready && text.trim().isNotEmpty) {
      await _tts.speak(text);
    }
  }
}
