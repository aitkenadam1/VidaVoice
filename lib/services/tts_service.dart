import 'package:flutter/foundation.dart' show kIsWeb;
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

  /// True once a working TTS engine has been confirmed. Stays false when the
  /// device has no TTS engine or voice data (common on bare Fire tablets) —
  /// the app must still boot and the board must still work; only the voice
  /// is missing.
  bool get isAvailable => _ready;

  /// Best-effort init. Returns true when a working TTS engine was found.
  ///
  /// Never throws: callers treat a false return as "no voice", not as a
  /// boot failure.
  Future<bool> init({
    required String language,
    double rate = AppConfig.defaultSpeechRate,
    double pitch = AppConfig.defaultSpeechPitch,
  }) async {
    this.rate = rate;
    this.pitch = pitch;
    try {
      // iOS/macOS-only API (no-op on Android). The web plugin does not
      // implement it and throws Unimplemented — which must not poison init
      // on web, so it is skipped there.
      if (!kIsWeb) await _engine.setSharedInstance(true);
      // Web quirk: speechSynthesis.getVoices() returns an empty list until
      // the browser fires voiceschanged (async, after page load). Without
      // this wait, the language binding below sees no voices and the probe
      // below misreads "not loaded yet" as "no TTS" — the app would go
      // permanently silent on web.
      if (kIsWeb) await _waitForWebVoices();
      await _engine.setLanguage(language);
      await _engine.setSpeechRate(rate);
      await _engine.setPitch(pitch);
      await _engine.awaitSpeakCompletion(true);
      // Probe: throws when no TTS engine is installed, and returns an empty
      // list when the engine has no usable voices. Either way there is
      // nothing to speak with.
      final voices = await _engine.getVoices;
      _ready = voices is List && voices.isNotEmpty;
    } catch (_) {
      _ready = false;
    }
    return _ready;
  }

  /// Polls for the browser's asynchronously-loading voice list (web only).
  /// Returns as soon as voices appear, or after ~3s when the browser
  /// genuinely has none. Native platforms answer immediately, so this is
  /// skipped there — no added boot latency on devices without TTS.
  Future<void> _waitForWebVoices() async {
    for (var i = 0; i < 15; i++) {
      final voices = await _engine.getVoices;
      if (voices is List && voices.isNotEmpty) return;
      await Future.delayed(const Duration(milliseconds: 200));
    }
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
