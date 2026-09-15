import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_tts/flutter_tts.dart';

import '../app_config.dart';
import 'elevenlabs_audio.dart';
import 'elevenlabs_service.dart';
import 'kokoro_tts_service.dart';
import 'proxy_client.dart';

/// A speakable voice exposed by the TTS engine.
///
/// System voices come from flutter_tts ([kokoroVoiceId],
/// [elevenLabsVoiceId] and [proxyVoiceId] are null). Kokoro voices are
/// on-device neural voices ([kokoroVoiceId] is the voice id, e.g.
/// 'af_bella'); they only appear when the Kokoro model pack is downloaded.
/// ElevenLabs voices are cloud voices on the caregiver's own ElevenLabs
/// account ([elevenLabsVoiceId] is the voice id); they need an API key and
/// internet, and any failure falls back to the on-device voices. Managed
/// ("included") cloud voices ([proxyVoiceId] is the opaque voice id from
/// the family's proxy entitlement) need a signed-in VidaVoice account and
/// internet; any failure falls back to the on-device voices.
class TtsVoice {
  const TtsVoice({
    required this.name,
    required this.locale,
    this.kokoroVoiceId,
    this.elevenLabsVoiceId,
    this.proxyVoiceId,
  });

  /// Engine voice name, e.g. "Microsoft David - English (United States)".
  /// Kokoro voices are named "Kokoro Bella" (from the voice display name).
  final String name;

  /// BCP-47-ish locale tag as reported by the engine, e.g. "en-US".
  final String locale;

  /// Non-null for Kokoro on-device voices.
  final String? kokoroVoiceId;

  /// Non-null for ElevenLabs cloud voices.
  final String? elevenLabsVoiceId;

  /// Non-null for managed ("included") cloud voices: the opaque voice id
  /// from the family's proxy entitlement.
  final String? proxyVoiceId;

  /// True for Kokoro on-device neural voices.
  bool get isKokoro => kokoroVoiceId != null;

  /// True for ElevenLabs cloud voices.
  bool get isElevenLabs => elevenLabsVoiceId != null;

  /// True for managed ("included") cloud voices.
  bool get isProxy => proxyVoiceId != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TtsVoice &&
          name == other.name &&
          locale == other.locale &&
          kokoroVoiceId == other.kokoroVoiceId &&
          elevenLabsVoiceId == other.elevenLabsVoiceId &&
          proxyVoiceId == other.proxyVoiceId;

  @override
  int get hashCode =>
      Object.hash(name, locale, kokoroVoiceId, elevenLabsVoiceId, proxyVoiceId);

  @override
  String toString() => '$name ($locale)';
}

/// Thin wrapper around flutter_tts with app-level defaults, plus routing
/// to the Kokoro on-device neural backend when a Kokoro voice is selected.
class TtsService {
  /// Lazily created: constructing a [TtsService] (or a test fake of one)
  /// must not touch the platform channel before the binding exists.
  /// [kokoro] is likewise side-effect free at construction.
  TtsService({KokoroTtsService? kokoro})
    : _kokoro = kokoro ?? KokoroTtsService();

  FlutterTts? _tts;
  FlutterTts get _engine => _tts ??= FlutterTts();
  bool _ready = false;

  final KokoroTtsService _kokoro;

  /// The on-device neural TTS backend (model download, worker, playback).
  KokoroTtsService get kokoro => _kokoro;

  /// The ElevenLabs cloud backend, when the caregiver entered an API key.
  /// Null means cloud voices are unavailable; speech falls back to
  /// on-device voices. Set by SessionState whenever the key changes.
  ElevenLabsService? elevenLabs;

  /// The managed voice backend client. Null (or a client with no token)
  /// means managed cloud voices are unavailable; speech falls back to
  /// on-device voices. Set by SessionState at construction and on sign-in.
  ProxyClient? proxy;

  /// Supplies the active communicator profile id for managed-voice
  /// synthesis (the contract requires a profile_id per request). Wired by
  /// SessionState; null means "no profile" and the proxy branch is skipped.
  String? Function()? proxyProfileIdProvider;

  /// Player for cloud-voice audio. A settable seam so tests can observe
  /// routing without platform channels.
  ElevenLabsAudioPlayer elevenAudioPlayer = ElevenLabsAudioPlayer();

  /// Cache of cloud-synthesized utterances, keyed by "$voiceId::$text".
  /// Every ElevenLabs call is billed per character, and board taps repeat
  /// the same short labels constantly — without this, re-tapping "more" a
  /// hundred times bills a hundred syntheses. Bounded FIFO: the core
  /// vocabulary is a few hundred short strings.
  static const _cloudCacheMax = 300;
  final Map<String, Uint8List> _cloudAudioCache = <String, Uint8List>{};

  void _storeCloudAudio(String key, Uint8List bytes) {
    _cloudAudioCache.remove(key);
    while (_cloudAudioCache.length >= _cloudCacheMax) {
      _cloudAudioCache.remove(_cloudAudioCache.keys.first);
    }
    _cloudAudioCache[key] = bytes;
  }

  /// Cache of managed-voice utterances, keyed by `proxy::<voiceId>::<text>`.
  /// Smaller than the BYO cache: managed quotas are shared per family per
  /// month, so repeats must not re-bill. Bounded FIFO.
  static const _proxyCacheMax = 100;
  final Map<String, Uint8List> _proxyAudioCache = <String, Uint8List>{};

  void _storeProxyAudio(String key, Uint8List bytes) {
    _proxyAudioCache.remove(key);
    while (_proxyAudioCache.length >= _proxyCacheMax) {
      _proxyAudioCache.remove(_proxyAudioCache.keys.first);
    }
    _proxyAudioCache[key] = bytes;
  }

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
    if (text.trim().isEmpty) return;
    final voice = currentVoice;
    if (voice != null && voice.isProxy) {
      final svc = proxy;
      final profileId = proxyProfileIdProvider?.call();
      if (svc != null &&
          svc.hasToken &&
          profileId != null &&
          profileId.isNotEmpty) {
        try {
          // Shared family quota: serve repeats from the cache so a child
          // re-tapping the same button doesn't re-bill the same utterance.
          final cacheKey = 'proxy::${voice.proxyVoiceId}::$text';
          final cached = _proxyAudioCache[cacheKey];
          if (cached != null) {
            await elevenAudioPlayer.playBytes(cached);
            return;
          }
          final audio = await svc.synthesize(
            requestId: proxyUuid4(),
            profileId: profileId,
            voiceId: voice.proxyVoiceId!,
            text: text,
          );
          _storeProxyAudio(cacheKey, audio);
          await elevenAudioPlayer.playBytes(audio);
          return;
        } catch (_) {
          // Managed voice unavailable (offline, quota, session expired):
          // fall through to the on-device voices rather than going silent.
        }
      }
    }
    if (voice != null && voice.isElevenLabs) {
      final svc = elevenLabs;
      if (svc != null) {
        try {
          // Billed per character: serve repeats from the cache so a child
          // re-tapping the same button doesn't re-bill the same utterance.
          final cacheKey = '${voice.elevenLabsVoiceId}::$text';
          final cached = _cloudAudioCache[cacheKey];
          if (cached != null) {
            await elevenAudioPlayer.playBytes(cached);
            return;
          }
          final audio = await svc.synthesize(
            text: text,
            voiceId: voice.elevenLabsVoiceId!,
          );
          _storeCloudAudio(cacheKey, audio);
          await elevenAudioPlayer.playBytes(audio);
          return;
        } catch (_) {
          // Cloud voice unavailable (no internet, bad key, quota, timeout):
          // fall through to the on-device voices rather than going silent.
        }
      }
    }
    if (voice != null && voice.isKokoro) {
      final kv = kokoroVoiceById(voice.kokoroVoiceId!);
      if (kv != null) {
        final ok = await _kokoro.speak(
          text,
          voice: kv,
          speed: KokoroTtsService.rateToSpeed(rate),
        );
        if (ok) return;
      }
      // Kokoro unavailable (model missing, engine failed): fall through to
      // the system voice rather than going silent.
    }
    if (_ready) {
      await _engine.speak(text);
    }
  }

  /// Stop any in-flight speech on all backends. Never throws.
  Future<void> stop() async {
    await elevenAudioPlayer.stop();
    try {
      await _kokoro.stop();
    } catch (_) {}
    if (_ready) {
      try {
        await _engine.stop();
      } catch (_) {}
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
    // Kokoro, ElevenLabs and managed-proxy voices are not system-engine
    // voices: poking flutter_tts with a nonexistent voice name would be
    // pointless at best, and that engine is exactly the fallback used when
    // they fail, so leave it alone.
    if (_ready && !voice.isKokoro && !voice.isElevenLabs && !voice.isProxy) {
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
