import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

import '../app_config.dart';
import '../models/word.dart';
import '../services/language_pack_service.dart';
import '../services/profile_service.dart';
import '../services/symbol_service.dart';
import '../services/tts_service.dart';
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
  SessionState({Future<SharedPreferences> Function()? prefsFactory, TtsService? tts})
    : _prefsFactory = prefsFactory ?? SharedPreferences.getInstance,
      tts = tts ?? TtsService();

  final Future<SharedPreferences> Function() _prefsFactory;
  final TtsService tts;
  final SymbolService symbols = SymbolService();
  final ProfileService profiles = ProfileService();
  final UsageService usage = UsageService();
  final HistoryService history = HistoryService();
  final FirstWeekPlanService plan = FirstWeekPlanService();

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

  /// Highest vocabulary level currently revealed on the board (1-3).
  ///
  /// Caregiver-controlled, and deliberately NOT in Settings: revealing
  /// vocabulary is a clinical decision, not a preference. Raising it only ever
  /// fills in empty cells — no word already on the board moves.
  int unlockedLevel = LanguagePack.minSupportedLevel;

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
      await usage.load();
      await history.load(profiles.active?.id ?? '');
      await plan.load(profiles.active?.id ?? '');
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
    pack = await LanguagePackService.loadPack(locale);
    await tts.setLanguage(pack.ttsLocale);
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
    tts.speak(item.label);
    _sentenceIds.add(item.id);
    // Fire-and-forget: usage counts must never block a tap.
    unawaited(usage.recordTap(item.id));
    notifyListeners();
  }

  Future<void> speakText(String text) => tts.speak(text);

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
