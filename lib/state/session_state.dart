import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:async';

import '../app_config.dart';
import '../models/dashboard.dart';
import '../models/word.dart';
import '../services/dashboard_service.dart';
import '../services/elevenlabs_key_store.dart';
import '../services/elevenlabs_service.dart';
import '../services/elevenlabs_voice_store.dart';
import '../services/language_pack_service.dart';
import '../services/profile_service.dart';
import '../services/symbol_override_service.dart';
import '../services/symbol_service.dart';
import '../services/tts_service.dart';
import '../services/kokoro_tts_service.dart';
import '../services/usage_service.dart';
import '../services/history_service.dart';
import '../services/first_week_plan_service.dart';

enum BootStatus { loading, ready, error }

/// App-wide session state: current language pack, sentence under
/// construction, TTS voice settings, symbols, profiles, onboarding flag.
class SessionState extends ChangeNotifier {
  /// Test seam: inject fakes so widget tests can boot a [SessionState]
  /// without touching platform channels (SharedPreferences / flutter_tts).
  /// Production always uses the default — no behavior change.
  SessionState({
    Future<SharedPreferences> Function()? prefsFactory,
    TtsService? tts,
  }) : _prefsFactory = prefsFactory ?? SharedPreferences.getInstance,
       tts = tts ?? TtsService();

  final Future<SharedPreferences> Function() _prefsFactory;
  final TtsService tts;
  final SymbolService symbols = SymbolService();
  final ProfileService profiles = ProfileService();
  final UsageService usage = UsageService();
  final HistoryService history = HistoryService();
  final FirstWeekPlanService plan = FirstWeekPlanService();
  final DashboardService dashboards = DashboardService();
  final SymbolOverrideService symbolOverrides = SymbolOverrideService();

  /// The caregiver's own ElevenLabs API key (secure storage) and the
  /// per-profile saved cloud voices. Null key = cloud voices unavailable.
  final ElevenLabsKeyStore elevenLabsKeys = ElevenLabsKeyStore();
  final ElevenLabsVoiceStore elevenLabsVoices = ElevenLabsVoiceStore();

  BootStatus status = BootStatus.loading;
  String bootError = '';
  String currentLocale = AppConfig.defaultLocale;

  /// False when the device has no TTS engine or voice data. The board still
  /// boots — only the voice is missing, and the UI says so with a banner.
  bool ttsAvailable = true;

  /// The "no voice" banner is dismissible per session.
  bool ttsBannerDismissed = false;

  void dismissTtsBanner() {
    ttsBannerDismissed = true;
    notifyListeners();
  }

  late LanguagePack pack;

  final List<String> _sentenceIds = [];
  List<String> get sentenceIds => List.unmodifiable(_sentenceIds);
  List<BoardItem> get sentence =>
      _sentenceIds.map((id) => pack.wordById(id)).toList();

  double buttonScale = 1.0;
  bool onboardingComplete = false;

  /// The caregiver-set image (base64) for [itemId] on the active profile,
  /// or null when the standard symbol applies. Keeps board call sites to
  /// one lookup.
  String? symbolOverrideFor(String itemId) {
    final id = profiles.active?.id;
    if (id == null) return null;
    return symbolOverrides.imageFor(id, itemId);
  }

  /// Tell listeners the symbol overrides changed so boards re-read them.
  void symbolsChanged() => notifyListeners();

  /// Highest vocabulary level currently revealed on the board (1-3).
  ///
  /// Caregiver-controlled, and deliberately NOT in Settings: revealing
  /// vocabulary is a clinical decision, not a preference. Raising it only ever
  /// fills in empty cells — no word already on the board moves.
  int unlockedLevel = LanguagePack.minSupportedLevel;

  /// Whether the active profile's personal dashboard replaces the home
  /// board. An enabled but empty dashboard never takes over — the user
  /// must never be stranded on a blank board.
  bool get showDashboard {
    if (_dashboardBypassed) return false;
    final id = profiles.active?.id;
    if (id == null) return false;
    final dashboard = dashboards.forProfile(id);
    return dashboard != null && dashboard.enabled && dashboard.cells.isNotEmpty;
  }

  /// Session-only escape hatch: the communicator asked for the full board.
  /// The caregiver's enable/disable setting is untouched and rules again
  /// on profile switch, language switch, or next boot. [restoreDashboard]
  /// brings the dashboard back within the session.
  bool _dashboardBypassed = false;

  void bypassDashboard() {
    _dashboardBypassed = true;
    notifyListeners();
  }

  void restoreDashboard() {
    _dashboardBypassed = false;
    notifyListeners();
  }

  /// True when the dashboard is bypassed but still available to return to.
  bool get canRestoreDashboard {
    if (!_dashboardBypassed) return false;
    final id = profiles.active?.id;
    if (id == null) return false;
    final dashboard = dashboards.forProfile(id);
    return dashboard != null && dashboard.enabled && dashboard.cells.isNotEmpty;
  }

  SharedPreferences? _prefs;

  Future<void> boot() async {
    status = BootStatus.loading;
    notifyListeners();
    try {
      _prefs = await _prefsFactory();
      final savedLocale = _prefs!.getString('vidavoice.locale');
      currentLocale =
          (savedLocale != null &&
              AppConfig.supportedLocales.contains(savedLocale))
          ? savedLocale
          : AppConfig.defaultLocale;
      buttonScale = _prefs!.getDouble('vidavoice.buttonScale') ?? 1.0;
      onboardingComplete =
          _prefs!.getBool('vidavoice.onboardingComplete') ?? false;
      unlockedLevel = _clampLevel(
        _prefs!.getInt('vidavoice.unlockedLevel') ??
            LanguagePack.minSupportedLevel,
      );

      pack = await LanguagePackService.loadPack(currentLocale);
      // Throws PackValidationError on any violation — boot must fail fast.
      pack.validate();
      await symbols.load();
      await profiles.load();
      await dashboards.load();
      // Heal pre-fallback cells (stored with wordId but no label) while
      // their words still resolve — see DashboardService.backfillLabels.
      await dashboards.backfillLabels(pack);
      await symbolOverrides.load();
      await usage.load();
      await history.load(profiles.active?.id ?? '');
      await plan.load(profiles.active?.id ?? '');
      // Wire the ElevenLabs cloud backend when the caregiver entered an API
      // key. Best-effort like TTS itself: a missing key only means cloud
      // voices are unavailable, never a boot failure.
      await refreshElevenLabs();
      // TTS is best-effort and NEVER fails boot: a device with no voice
      // engine (bare Fire tablet, missing voice data) still gets the full
      // board, plus a banner explaining the missing voice.
      ttsBannerDismissed = false;
      try {
        ttsAvailable = await tts.init(
          language: pack.ttsLocale,
          rate:
              _prefs!.getDouble('vidavoice.speechRate') ??
              AppConfig.defaultSpeechRate,
          pitch:
              _prefs!.getDouble('vidavoice.speechPitch') ??
              AppConfig.defaultSpeechPitch,
        );
      } catch (_) {
        ttsAvailable = false;
      }
      // Restore the caregiver's voice choice for this language, if the
      // engine still has that voice installed.
      await _applySavedVoice();
      status = BootStatus.ready;
    } catch (e) {
      status = BootStatus.error;
      bootError = e.toString();
    }
    notifyListeners();
  }

  Future<void> setSpeechRate(double rate) async {
    await tts.setRate(rate);
    await _prefs?.setDouble('vidavoice.speechRate', rate);
  }

  Future<void> setSpeechPitch(double pitch) async {
    await tts.setPitch(pitch);
    await _prefs?.setDouble('vidavoice.speechPitch', pitch);
  }

  /// (Re)reads the ElevenLabs API key from secure storage and wires the
  /// cloud backend into [tts]. Call after the key is saved or cleared.
  /// Never throws: without a key the backend is simply unavailable.
  Future<void> refreshElevenLabs() async {
    try {
      final key = await elevenLabsKeys.readKey();
      tts.elevenLabs = (key == null || key.isEmpty)
          ? null
          : ElevenLabsService(apiKey: key);
    } catch (_) {
      tts.elevenLabs = null;
    }
    notifyListeners();
  }

  /// Saved ElevenLabs voices for the active profile, as picker entries.
  Future<List<TtsVoice>> elevenLabsVoiceEntries() async {
    final id = profiles.active?.id;
    if (id == null) return const [];
    final saved = await elevenLabsVoices.load(id);
    final prefix = currentLocale.toLowerCase();
    final matching = saved
        .where((v) => v.locale.toLowerCase().startsWith(prefix))
        .toList();
    final list = matching.isNotEmpty ? matching : saved;
    return [
      for (final v in list)
        TtsVoice(name: v.name, locale: v.locale, elevenLabsVoiceId: v.id),
    ];
  }

  /// Engine voices for the current language, for the voice picker. Empty
  /// when TTS is unavailable. Falls back to the full engine list when no
  /// voice reports a matching locale (some engines report bare tags).
  /// Kokoro on-device neural voices are listed first when the model pack
  /// is downloaded.
  Future<List<TtsVoice>> loadVoices() async {
    if (!ttsAvailable) return const [];
    final all = await tts.getVoices();
    final prefix = currentLocale.toLowerCase();
    final matching = all
        .where((v) => v.locale.toLowerCase().startsWith(prefix))
        .toList();
    final system = matching.isNotEmpty ? matching : all;
    final kokoro = await _kokoroVoicesForLocale();
    final elevenLabs = await elevenLabsVoiceEntries();
    return [...kokoro, ...elevenLabs, ...system];
  }

  /// The on-device neural TTS backend (for the Settings download UI).
  KokoroTtsService get kokoro => tts.kokoro;

  /// Kokoro voices for [currentLocale] as picker entries. Empty when the
  /// platform can't run Kokoro (web) or the model pack isn't downloaded.
  Future<List<TtsVoice>> _kokoroVoicesForLocale() async {
    if (!KokoroTtsService.isSupported) return const [];
    if (!await tts.kokoro.isModelReady()) return const [];
    return kokoroVoices
        .where((v) => v.locale == currentLocale)
        .map(
          (v) => TtsVoice(
            name: 'Kokoro ${v.displayName}',
            locale: kokoroLocaleTag(v.locale),
            kokoroVoiceId: v.id,
          ),
        )
        .toList();
  }

  TtsVoice? get currentVoice => tts.currentVoice;

  String _voiceNameKey(String locale) => 'vidavoice.voice.$locale.name';
  String _voiceLocaleKey(String locale) => 'vidavoice.voice.$locale.locale';
  String _voiceKokoroKey(String locale) => 'vidavoice.voice.$locale.kokoro';
  String _voiceElevenLabsKey(String locale) =>
      'vidavoice.voice.$locale.elevenlabs';

  /// Persist and apply a voice choice for the current language.
  Future<void> setVoice(TtsVoice voice) async {
    await tts.setVoice(voice);
    await _prefs?.setString(_voiceNameKey(currentLocale), voice.name);
    await _prefs?.setString(_voiceLocaleKey(currentLocale), voice.locale);
    final kokoroId = voice.kokoroVoiceId;
    if (kokoroId != null) {
      await _prefs?.setString(_voiceKokoroKey(currentLocale), kokoroId);
      // Warm the engine now so the first real utterance isn't slow.
      unawaited(tts.kokoro.warmup());
    } else {
      await _prefs?.remove(_voiceKokoroKey(currentLocale));
    }
    final elevenId = voice.elevenLabsVoiceId;
    if (elevenId != null) {
      await _prefs?.setString(_voiceElevenLabsKey(currentLocale), elevenId);
    } else {
      await _prefs?.remove(_voiceElevenLabsKey(currentLocale));
    }
    notifyListeners();
  }

  /// Back to the engine default voice for the current language.
  Future<void> clearVoice() async {
    await tts.clearVoice();
    await _prefs?.remove(_voiceNameKey(currentLocale));
    await _prefs?.remove(_voiceLocaleKey(currentLocale));
    await _prefs?.remove(_voiceKokoroKey(currentLocale));
    await _prefs?.remove(_voiceElevenLabsKey(currentLocale));
    notifyListeners();
  }

  /// Re-applies the saved voice for [currentLocale], if the engine still
  /// has it. Returns true when a saved voice was applied. Best-effort: a
  /// missing or rejected voice keeps the default.
  Future<bool> _applySavedVoice() async {
    if (!ttsAvailable) return false;
    try {
      final name = _prefs?.getString(_voiceNameKey(currentLocale));
      final locale = _prefs?.getString(_voiceLocaleKey(currentLocale));
      if (name == null || locale == null) return false;
      // Kokoro voices aren't in the engine list — restore from the table.
      final kokoroId = _prefs?.getString(_voiceKokoroKey(currentLocale));
      if (kokoroId != null && kokoroId.isNotEmpty) {
        final kv = kokoroVoiceById(kokoroId);
        if (kv != null &&
            kv.locale == currentLocale &&
            await tts.kokoro.isModelReady()) {
          await tts.setVoice(
            TtsVoice(
              name: 'Kokoro ${kv.displayName}',
              locale: kokoroLocaleTag(kv.locale),
              kokoroVoiceId: kv.id,
            ),
          );
          unawaited(tts.kokoro.warmup());
          return true;
        }
        return false;
      }
      // ElevenLabs voices aren't in the engine list either — restore from
      // the profile's saved cloud voices. A missing entry (or no API key)
      // keeps the default; speech falls back on-device anyway.
      final elevenId = _prefs?.getString(_voiceElevenLabsKey(currentLocale));
      if (elevenId != null && elevenId.isNotEmpty) {
        final entries = await elevenLabsVoiceEntries();
        final match = entries.where((v) => v.elevenLabsVoiceId == elevenId);
        if (match.isNotEmpty) {
          await tts.setVoice(match.first);
          return true;
        }
        return false;
      }
      final voices = await tts.getVoices();
      final match = voices.where((v) => v.name == name && v.locale == locale);
      if (match.isNotEmpty) {
        await tts.setVoice(match.first);
        return true;
      }
    } catch (_) {}
    return false;
  }

  static int _clampLevel(int level) => level.clamp(
    LanguagePack.minSupportedLevel,
    LanguagePack.maxSupportedLevel,
  );

  /// Reveal vocabulary up to [level]. Words above it keep their cells — the
  /// cells are simply drawn empty — so unlocking never reshuffles the board.
  Future<void> setUnlockedLevel(int level) async {
    final next = _clampLevel(level);
    if (next == unlockedLevel) return;
    unlockedLevel = next;
    await _prefs?.setInt('vidavoice.unlockedLevel', next);
    notifyListeners();
  }

  Future<void> setButtonScale(double scale) async {
    buttonScale = scale;
    await _prefs?.setDouble('vidavoice.buttonScale', scale);
    notifyListeners();
  }

  /// Switch language pack + TTS locale. Clears the sentence because word
  /// labels are language-specific.
  Future<void> setLocale(String locale) async {
    if (!AppConfig.supportedLocales.contains(locale) ||
        locale == currentLocale) {
      return;
    }
    currentLocale = locale;
    _sentenceIds.clear();
    _dashboardBypassed = false;
    pack = await LanguagePackService.loadPack(locale);
    await tts.setLanguage(pack.ttsLocale);
    // A voice choice is per-language: apply the saved one for the new
    // language, or drop back to the engine default (the old language's
    // voice must not leak across).
    if (!await _applySavedVoice()) await tts.clearVoice();
    await _prefs?.setString('vidavoice.locale', locale);
    notifyListeners();
  }

  /// Reload per-profile data (sentence history, first-week plan) for the
  /// currently active profile. Call after the active profile changes.
  Future<void> reloadProfileData() async {
    await history.load(profiles.active?.id ?? '');
    await plan.load(profiles.active?.id ?? '');
  }

  /// Switch the active communicator profile and reload per-profile data
  /// (sentence history, first-week plan) for them.
  Future<void> switchProfile(String id) async {
    await profiles.setActive(id);
    _dashboardBypassed = false;
    await reloadProfileData();
    notifyListeners();
  }

  /// Delete a communicator profile and everything stored for it — including
  /// its custom button images and saved cloud voices — then reload
  /// per-profile data for whoever is now active.
  Future<void> removeProfile(String id) async {
    await profiles.removeProfile(id);
    await symbolOverrides.removeProfile(id);
    await elevenLabsVoices.clearProfile(id);
    await reloadProfileData();
    notifyListeners();
  }

  Future<void> completeOnboarding(String name) async {
    final trimmed = name.trim();
    if (trimmed.isNotEmpty) {
      await profiles.renameActive(trimmed);
    }
    onboardingComplete = true;
    await _prefs?.setBool('vidavoice.onboardingComplete', true);
    notifyListeners();
  }

  Future<void> reopenOnboarding() async {
    onboardingComplete = false;
    await _prefs?.setBool('vidavoice.onboardingComplete', false);
    notifyListeners();
  }

  /// Sets the onboarding flag directly (used by profile-backup import so a
  /// restored value is reflected without re-running the wizard).
  Future<void> setOnboardingComplete(bool value) async {
    onboardingComplete = value;
    await _prefs?.setBool('vidavoice.onboardingComplete', value);
    notifyListeners();
  }

  void tapWord(BoardItem item) {
    if (item.type == BoardItemType.folder) return;
    if (item.type == BoardItemType.phrase) {
      speakPhrase(item);
      return;
    }
    tts.speak(item.label);
    _sentenceIds.add(item.id);
    // Fire-and-forget: usage counts must never block a tap.
    unawaited(usage.recordTap(item.id));
    notifyListeners();
  }

  /// Phrases are atomic utterances: spoken whole immediately and logged to
  /// history and usage, without touching the sentence bar. Caregivers see
  /// them in activity; replay speaks them again via [replayHistory].
  void speakPhrase(BoardItem item) {
    tts.speak(item.label);
    // Fire-and-forget: logging must never block or delay speech.
    unawaited(usage.recordTap(item.id));
    unawaited(
      history.record(
        profiles.active?.id ?? '',
        [item.id],
        item.label,
        currentLocale,
      ),
    );
  }

  Future<void> speakText(String text) => tts.speak(text);

  /// Taps a personal-dashboard cell. Vocabulary cells behave exactly as on
  /// the standard board (words join the sentence bar, phrases speak whole,
  /// taps count toward "most used"). Custom buttons are atomic: they speak
  /// their stored text immediately and never join the sentence bar — the
  /// sentence bar only holds vocabulary ids. A vocab reference whose word
  /// vanished from a newer pack falls back to its stored text instead of
  /// doing nothing.
  void tapDashboardCell(DashboardCell cell) {
    final wordId = cell.wordId;
    if (wordId != null) {
      try {
        tapWord(pack.wordById(wordId));
        return;
      } on Object {
        // Word removed from the pack — fall through to stored text.
      }
    }
    final text = cell.customText;
    if (text.isEmpty) return;
    tts.speak(text);
  }

  void speakSentence() {
    final text = sentence.map((w) => w.label).join(' ');
    if (text.isEmpty) return;
    tts.speak(text);
    // Fire-and-forget: history must never block or delay speech.
    unawaited(
      history.record(
        profiles.active?.id ?? '',
        List.of(_sentenceIds),
        text,
        currentLocale,
      ),
    );
  }

  /// Reload a history entry into the sentence bar and speak it again.
  /// Ids that no longer exist in the current pack are skipped; the pack's
  /// cells and positions are untouched.
  void replayHistory(HistoryEntry entry) {
    _sentenceIds.clear();
    for (final id in entry.ids) {
      try {
        pack.wordById(id);
        _sentenceIds.add(id);
      } on Object {
        // Word removed from a newer pack — skip it.
      }
    }
    notifyListeners();
    speakSentence();
  }

  void clearSentence() {
    _sentenceIds.clear();
    notifyListeners();
  }

  void undoLast() {
    if (_sentenceIds.isNotEmpty) {
      _sentenceIds.removeLast();
      notifyListeners();
    }
  }
}
