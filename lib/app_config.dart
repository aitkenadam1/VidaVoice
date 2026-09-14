/// Single source of truth for app identity.
///
/// To rename the app, change [appDisplayName] here — every screen reads it
/// from here rather than hard-coding a string.
class AppConfig {
  static const String appDisplayName = 'VidaVoice';
  static const String appTagline = 'Every voice matters.';
  static const String packageId = 'org.vidacarefoundation.vidavoice';

  /// Locale codes with a bundled pack under assets/lang/<code>.json.
  /// To add a language: drop in the JSON file and list it here.
  static const List<String> supportedLocales = ['en', 'es', 'fr'];
  static const String defaultLocale = 'en';
  static const Map<String, String> localeNames = {
    'en': 'English',
    'es': 'Español',
    'fr': 'Français',
  };

  /// Voice defaults (persisted per device once changed).
  static const double defaultSpeechRate = 0.5;
  static const double defaultSpeechPitch = 1.0;

  /// Button-size options: Small / Medium / Large.
  static const List<double> buttonScales = [0.85, 1.0, 1.2];
  static const List<String> buttonScaleNames = ['Small', 'Medium', 'Large'];
}
