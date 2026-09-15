import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Abstraction over secret storage so the key store is unit-testable
/// without a platform channel.
abstract class SecureValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Platform keychain (iOS) / keystore (Android) backing.
class PlatformSecureValueStore implements SecureValueStore {
  PlatformSecureValueStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// The caregiver's own ElevenLabs API key (bring-your-own-key).
///
/// Cloud voice usage is billed to the caregiver's ElevenLabs account, so
/// the key is a billing credential: it lives in the platform secure
/// storage, never in SharedPreferences, never in backups, never in logs.
class ElevenLabsKeyStore {
  ElevenLabsKeyStore({SecureValueStore? store})
    : _store = store ?? PlatformSecureValueStore();

  static const storageKey = 'vidavoice.elevenlabs.apiKey';

  final SecureValueStore _store;

  Future<String?> readKey() async {
    try {
      final key = await _store.read(storageKey);
      if (key == null || key.trim().isEmpty) return null;
      return key.trim();
    } catch (_) {
      return null;
    }
  }

  /// Saves [key], or clears the stored key when it is blank.
  Future<void> saveKey(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      await clearKey();
      return;
    }
    await _store.write(storageKey, trimmed);
  }

  Future<void> clearKey() => _store.delete(storageKey);
}
