import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_tts/flutter_tts.dart';

import '../app_config.dart';

/// A speakable voice exposed by the TTS engine.
class TtsVoice {
  const TtsVoice({required this.name, required this.locale});

  /// Engine voice name, e.g. "Microsoft David - English (United States)".
  final String name;

  /// BCP-47-ish locale tag as reported by the engine, e.g. "en-US".
  final String locale;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TtsVoice && name == other.name && locale == other.locale;

  @override
  int get hashCode => Object.hash(name, locale);

  @override
  String toString() => '$name ($locale)';
}

/// Thin wrapper around flutter_tts with app-level defaults.
class TtsService {
  /// Lazily created: constructing a [TtsService] (or a test fake of one)
  /// must not touch the platform channel before the binding exists.
  FlutterTts? _tts;
  FlutterTts get _engine => _tts ??= FlutterTts();
  bool _ready = false;

  double rate = AppConfig.defaultSpeechRate;
  double pitch = AppConfig.defaultSpeechPitch;

  /// The explicitly chosen voice, if any. Null means the engine default.
  TtsVoice? currentVoice;

  /// Last language passed to init/setLanguage — used to re-bind the engine
  /// default voice when a choice is cleared.
  String _lastLanguage = 'en-US';

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
    _lastLanguage = language;
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
    // A voice chosen before the engine was ready (restored preference)
    // is applied now that the engine is confirmed.
    if (_ready && currentVoice != null) {
      await setVoice(currentVoice!);
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
    _lastLanguage = language;
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

  /// Engine voices, normalized to [TtsVoice]. Never throws — returns [] when
  /// the engine reports none or the platform call fails.
  Future<List<TtsVoice>> getVoices() async {
    try {
      final voices = await _engine.getVoices;
      if (voices is! List) return const [];
      return voices
          .whereType<Map>()
          .map(
            (v) => TtsVoice(
              name: v['name']?.toString() ?? 'Voice',
              locale: v['locale']?.toString() ?? '',
            ),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Switch to [voice] immediately. Recorded even before init() confirms an
  /// engine, so a restored choice is never lost — it is applied to the
  /// engine as soon as one is ready.
  Future<void> setVoice(TtsVoice voice) async {
    currentVoice = voice;
    if (_ready) {
      try {
        await _engine.setVoice({'name': voice.name, 'locale': voice.locale});
      } catch (_) {
        // Engine rejected the voice — the choice stays recorded for the UI
        // and speech continues on the previous voice.
      }
    }
  }

  /// Forget any explicit choice; the engine default speaks again.
  /// Re-applies the language to re-bind the engine's default voice for it.
  Future<void> clearVoice() async {
    currentVoice = null;
    if (_ready) {
      try {
        await _engine.setLanguage(_lastLanguage);
      } catch (_) {}
    }
  }
}
