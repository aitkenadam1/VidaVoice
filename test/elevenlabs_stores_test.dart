import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onevoz/services/elevenlabs_key_store.dart';
import 'package:onevoz/services/elevenlabs_service.dart';
import 'package:onevoz/services/elevenlabs_voice_store.dart';

/// In-memory stand-in for the platform secure storage.
class _FakeSecureStore implements SecureValueStore {
  final _map = <String, String>{};
  @override
  Future<void> delete(String key) async => _map.remove(key);
  @override
  Future<String?> read(String key) async => _map[key];
  @override
  Future<void> write(String key, String value) async => _map[key] = value;
}

void main() {
  group('ElevenLabsKeyStore', () {
    test('saves, reads (trimmed), and clears the key', () async {
      final store = ElevenLabsKeyStore(store: _FakeSecureStore());
      expect(await store.readKey(), isNull);
      await store.saveKey('  sk-live  ');
      expect(await store.readKey(), 'sk-live');
      await store.clearKey();
      expect(await store.readKey(), isNull);
    });

    test('saving a blank key clears it', () async {
      final store = ElevenLabsKeyStore(store: _FakeSecureStore());
      await store.saveKey('sk-live');
      await store.saveKey('   ');
      expect(await store.readKey(), isNull);
    });
  });

  group('ElevenLabsVoiceStore', () {
    ElevenLabsVoiceStore voices() => ElevenLabsVoiceStore(
      prefsFactory: () async => await SharedPreferences.getInstance(),
    );

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
    });

    test('add/load/remove round-trip per profile', () async {
      final store = voices();
      const v = SavedElevenLabsVoice(id: 'cv-1', name: 'Maya', locale: 'en');
      await store.add('p-1', v);
      var loaded = await store.load('p-1');
      expect(loaded.map((e) => e.id), ['cv-1']);

      // Other profiles are untouched.
      expect(await store.load('p-2'), isEmpty);

      // Re-adding the same id replaces, not duplicates.
      await store.add(
        'p-1',
        const SavedElevenLabsVoice(id: 'cv-1', name: 'Maya 2', locale: 'en'),
      );
      loaded = await store.load('p-1');
      expect(loaded.length, 1);
      expect(loaded.first.name, 'Maya 2');

      await store.remove('p-1', 'cv-1');
      expect(await store.load('p-1'), isEmpty);
    });

    test('corrupt storage reads as empty', () async {
      SharedPreferences.setMockInitialValues({
        'vidavoice.elevenlabs.voices.p-1.v1': 'not-json{{{',
      });
      expect(await voices().load('p-1'), isEmpty);
    });

    test('clearProfile drops only that profile', () async {
      final store = voices();
      const v = SavedElevenLabsVoice(id: 'cv-1', name: 'Maya', locale: 'en');
      await store.add('p-1', v);
      await store.add('p-2', v);
      await store.clearProfile('p-1');
      expect(await store.load('p-1'), isEmpty);
      expect((await store.load('p-2')).isNotEmpty, isTrue);
    });
  });
}
