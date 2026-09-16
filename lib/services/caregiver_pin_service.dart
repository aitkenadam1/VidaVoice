import 'elevenlabs_key_store.dart';

/// The caregiver gate PIN: a short device-local secret that keeps little
/// fingers out of the caregiver hub (location, calling & safety, devices,
/// dashboard editing, …).
///
/// This is deliberately NOT the account password — it's a fast local gate
/// for a shared family device, so the caregiver isn't typing a long
/// password every time they open the hub. The account password remains the
/// root credential: it's what resets a forgotten PIN.
///
/// The PIN lives in the platform keychain/keystore (never in
/// SharedPreferences, never in logs). Comparison is constant-time.
class CaregiverPinService {
  CaregiverPinService({SecureValueStore? store})
    : _store = store ?? PlatformSecureValueStore();

  static const storageKey = 'onevoz.caregiver.pin';

  /// The PIN is exactly 4 digits: short enough to tap quickly, long
  /// enough that a child guessing at random is unlikely to land it
  /// (1 in 10,000 per try, and tries are manual).
  static const pinLength = 4;

  final SecureValueStore _store;

  /// Whether a PIN has been set on this device.
  Future<bool> hasPin() async => (await _store.read(storageKey)) != null;

  /// Stores [pin]. Throws [ArgumentError] unless it is exactly 4 digits.
  Future<void> setPin(String pin) async {
    _validate(pin);
    await _store.write(storageKey, pin);
  }

  /// True when [pin] matches the stored PIN. False when no PIN is set.
  Future<bool> verify(String pin) async {
    final saved = await _store.read(storageKey);
    if (saved == null) return false;
    if (pin.length != saved.length) return false;
    var diff = 0;
    for (var i = 0; i < saved.length; i++) {
      diff |= saved.codeUnitAt(i) ^ pin.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// Removes the PIN (used after a password-verified reset).
  Future<void> clearPin() async => _store.delete(storageKey);

  static void _validate(String pin) {
    final digitsOnly = RegExp(r'^\d+$');
    if (pin.length != pinLength || !digitsOnly.hasMatch(pin)) {
      throw ArgumentError('PIN must be exactly $pinLength digits');
    }
  }
}
