import 'package:flutter_test/flutter_test.dart';
import 'package:onevoz/services/caregiver_pin_service.dart';
import 'package:onevoz/services/elevenlabs_key_store.dart';

/// In-memory stand-in for the platform keychain.
class _FakeSecureStore implements SecureValueStore {
  final map = <String, String>{};

  @override
  Future<String?> read(String key) async => map[key];

  @override
  Future<void> write(String key, String value) async => map[key] = value;

  @override
  Future<void> delete(String key) async => map.remove(key);
}

void main() {
  group('CaregiverPinService', () {
    test('hasPin is false before any PIN is set', () async {
      final pin = CaregiverPinService(store: _FakeSecureStore());
      expect(await pin.hasPin(), isFalse);
    });

    test('set then verify round-trips a 4-digit PIN', () async {
      final pin = CaregiverPinService(store: _FakeSecureStore());
      await pin.setPin('4829');
      expect(await pin.hasPin(), isTrue);
      expect(await pin.verify('4829'), isTrue);
      expect(await pin.verify('4828'), isFalse);
      expect(await pin.verify(''), isFalse);
    });

    test('verify is false when no PIN is set', () async {
      final pin = CaregiverPinService(store: _FakeSecureStore());
      expect(await pin.verify('1234'), isFalse);
    });

    test('rejects non-4-digit PINs', () async {
      final pin = CaregiverPinService(store: _FakeSecureStore());
      for (final bad in ['123', '12345', 'abcd', '12 4', '', '12-4']) {
        expect(() => pin.setPin(bad), throwsArgumentError);
      }
      expect(await pin.hasPin(), isFalse);
    });

    test('clearPin removes the gate', () async {
      final pin = CaregiverPinService(store: _FakeSecureStore());
      await pin.setPin('0000');
      await pin.clearPin();
      expect(await pin.hasPin(), isFalse);
      expect(await pin.verify('0000'), isFalse);
    });

    test('setting a new PIN replaces the old one', () async {
      final pin = CaregiverPinService(store: _FakeSecureStore());
      await pin.setPin('1111');
      await pin.setPin('2222');
      expect(await pin.verify('2222'), isTrue);
      expect(await pin.verify('1111'), isFalse);
    });
  });
}
