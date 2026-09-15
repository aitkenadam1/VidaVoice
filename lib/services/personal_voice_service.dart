import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Outcome of asking iOS for Personal Voice access.
enum PersonalVoiceStatus {
  authorized,
  denied,
  notDetermined,
  unsupported,
  unknown,
}

/// Apple's Personal Voice (iOS 17+): a user-created, on-device voice built
/// in Settings → Accessibility → Personal Voice. It is free, private, and
/// works offline — but iOS hides it from third-party apps until the app
/// explicitly requests authorization via a native channel
/// ("vidavoice/personal_voice", implemented in AppDelegate.swift).
/// flutter_tts alone can never surface it.
class PersonalVoiceService {
  static const _channel = MethodChannel('vidavoice/personal_voice');

  /// True only where a Personal Voice can exist (iPhone/iPad, not web).
  /// Whether the OS version supports it is answered by the native side.
  static bool get isPlatformSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Asks iOS for Personal Voice access. Shows the system prompt on first
  /// call; later calls return the stored decision. Never throws.
  Future<PersonalVoiceStatus> requestAuthorization() async {
    if (!isPlatformSupported) return PersonalVoiceStatus.unsupported;
    try {
      final raw = await _channel.invokeMethod<String>('requestAuthorization');
      return PersonalVoiceStatus.values.firstWhere(
        (s) => s.name == raw,
        orElse: () => PersonalVoiceStatus.unknown,
      );
    } on MissingPluginException {
      // Native side not present (tests, unexpected hosts).
      return PersonalVoiceStatus.unsupported;
    } catch (_) {
      return PersonalVoiceStatus.unknown;
    }
  }
}
