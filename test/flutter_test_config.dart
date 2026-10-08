import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test bootstrap: the platform secure storage (keychain/keystore) does
/// not exist under flutter_test. Without a handler, calls into its method
/// channel never complete inside a widget test's fake-async zone, which
/// hangs any test whose flow touches encrypted storage. Answering with a
/// fast PlatformException makes the storage layer degrade to its
/// plaintext-prefs fallback (its designed no-store behavior) — the same
/// outcome a missing plugin produces at runtime, just promptly. Tests
/// that need a WORKING secure store inject an in-memory
/// SecureValueStore directly instead.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    throw PlatformException(
      code: 'secure_storage_unavailable_in_tests',
      message: 'flutter_secure_storage has no backend under flutter_test',
    );
  });
  await testMain();
}
