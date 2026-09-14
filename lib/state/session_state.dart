import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_config.dart';
import '../models/word.dart';
import '../services/language_pack_service.dart';
import '../services/profile_service.dart';
import '../services/symbol_service.dart';
import '../services/tts_service.dart';

enum BootStatus { loading, ready, error }

/// App-wide session state: current language pack, sentence under
/// construction, TTS voice settings, symbols, profiles, onboarding flag.
class SessionState extends ChangeNotifier {
  final TtsService tts = TtsService();
  final SymbolService symbols = SymbolService();
  final ProfileService profiles = ProfileService();

  BootStatus status = BootStatus.loading;
  String bootError = '';
  String currentLocale = AppConfig.defaultLocale;

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
      _prefs = await SharedPreferences.getInstance();
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
      await tts.init(
        language: pack.ttsLocale,
        rate:
            _prefs!.getDouble('vidavoice.speechRate') ??
            AppConfig.defaultSpeechRate,
        pitch:
            _prefs!.getDouble('vidavoice.speechPitch') ??
            AppConfig.defaultSpeechPitch,
      );
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

  void tapWord(BoardItem item) {
    if (item.type == BoardItemType.folder) return;
    tts.speak(item.label);
    _sentenceIds.add(item.id);
    notifyListeners();
  }

  Future<void> speakText(String text) => tts.speak(text);

  void speakSentence() {
    final text = sentence.map((w) => w.label).join(' ');
    if (text.isNotEmpty) tts.speak(text);
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
