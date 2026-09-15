import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidavoice/services/personal_voice_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('vidavoice/personal_voice');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void mockNative(String? reply) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'requestAuthorization');
      return reply;
    });
  }

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('each native status string parses to the matching enum', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final cases = {
      'authorized': PersonalVoiceStatus.authorized,
      'denied': PersonalVoiceStatus.denied,
      'notDetermined': PersonalVoiceStatus.notDetermined,
      'unsupported': PersonalVoiceStatus.unsupported,
    };
    for (final entry in cases.entries) {
      mockNative(entry.key);
      expect(
        await PersonalVoiceService().requestAuthorization(),
        entry.value,
        reason: entry.key,
      );
    }
  });

  test('unknown native strings map to unknown, never throw', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    mockNative('weird-future-status');
    expect(
      await PersonalVoiceService().requestAuthorization(),
      PersonalVoiceStatus.unknown,
    );
  });

  test('null native reply maps to unknown', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    mockNative(null);
    expect(
      await PersonalVoiceService().requestAuthorization(),
      PersonalVoiceStatus.unknown,
    );
  });

  test('missing plugin (no native side) reports unsupported', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    // No mock handler: MissingPluginException.
    expect(
      await PersonalVoiceService().requestAuthorization(),
      PersonalVoiceStatus.unsupported,
    );
  });

  test(
    'off iOS the platform is reported unsupported without a channel call',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      var called = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        called = true;
        return 'authorized';
      });
      expect(
        await PersonalVoiceService().requestAuthorization(),
        PersonalVoiceStatus.unsupported,
      );
      expect(called, isFalse);
    },
  );
}
