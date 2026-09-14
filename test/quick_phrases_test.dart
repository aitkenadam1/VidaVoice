import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vidavoice/models/word.dart';
import 'package:vidavoice/services/tts_service.dart';
import 'package:vidavoice/state/session_state.dart';

/// TTS double: never touches the platform channel, records speech.
class _FakeTts extends TtsService {
  int speakCalls = 0;
  String? lastSpoken;

  @override
  Future<bool> init({
    required String language,
    double rate = 0.5,
    double pitch = 1.0,
  }) async => true;

  @override
  Future<void> setLanguage(String language) async {}

  @override
  Future<void> setRate(double rate) async {}

  @override
  Future<void> setPitch(double pitch) async {}

  @override
  Future<void> speak(String text) async {
    speakCalls++;
    lastSpoken = text;
  }

  @override
  Future<List<TtsVoice>> getVoices() async => const [];

  @override
  Future<void> setVoice(TtsVoice voice) async {}

  @override
  Future<void> clearVoice() async {}
}

/// Coverage for the Quick Phrases folder: pack shape, the folder-only
/// invariant for phrases, and tap behavior (speak whole, skip the
/// sentence bar, log to history).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  LanguagePack loadPack(String locale) {
    final raw = File('assets/lang/$locale.json').readAsStringSync();
    final pack = LanguagePack.fromJson(
      Map<String, dynamic>.from(json.decode(raw) as Map),
    );
    pack.validate();
    return pack;
  }

  Future<SessionState> makeSession() async {
    SharedPreferences.setMockInitialValues({});
    final session = SessionState(tts: _FakeTts());
    session.pack = loadPack('en');
    await session.history.load('test-profile');
    return session;
  }

  group('Phrases folder', () {
    test('exists in all three packs with 14 level-1 phrases', () {
      for (final locale in ['en', 'es', 'fr']) {
        final pack = loadPack(locale);
        final folder = pack.folders['folder.phrases'];
        expect(folder, isNotNull, reason: '$locale has no phrases folder');
        expect(folder!.words, hasLength(14), reason: locale);
        for (final word in folder.words) {
          expect(word.type, BoardItemType.phrase, reason: '${word.id}');
          expect(word.level, 1, reason: '${word.id} level');
        }
      }
    });

    test('phrase ids are identical across languages (motor planning)', () {
      final ids = <String, Set<String>>{};
      for (final locale in ['en', 'es', 'fr']) {
        ids[locale] = loadPack(locale)
            .folders['folder.phrases']!
            .words
            .map((w) => w.id)
            .toSet();
      }
      expect(ids['es'], ids['en']);
      expect(ids['fr'], ids['en']);
    });

    test('folder tile sits at row 6 col 4, level 1', () {
      final pack = loadPack('en');
      final tile = pack.itemAt(6, 4);
      expect(tile, isNotNull);
      expect(tile!.id, 'folder.phrases');
      expect(tile.type, BoardItemType.folder);
      expect(tile.level, 1);
    });

    test('validate() rejects a phrase on the home grid', () {
      final pack = loadPack('en');
      final bad = LanguagePack(
        locale: pack.locale,
        displayName: pack.displayName,
        ttsLocale: pack.ttsLocale,
        version: pack.version,
        gridColumns: pack.gridColumns,
        homeItems: [
          const BoardItem(
            id: 'phrase.bad',
            label: 'bad phrase',
            type: BoardItemType.phrase,
            category: 'core',
            row: 0,
            col: 0,
            emoji: '❌',
          ),
        ],
        folders: const {},
      );
      expect(() => bad.validate(), throwsA(isA<PackValidationError>()));
    });
  });

  group('Phrase taps', () {
    test('speaks the whole phrase without touching the sentence bar', () async {
      final session = await makeSession();
      final fake = session.tts as _FakeTts;
      final phrase = session.pack.wordById('phrase.ineedhelp');

      session.tapWord(phrase);

      expect(fake.speakCalls, 1);
      expect(fake.lastSpoken, 'I need help');
      expect(session.sentenceIds, isEmpty);
    });

    test('logs the phrase to history for replay', () async {
      final session = await makeSession();
      final phrase = session.pack.wordById('phrase.thankyou');

      session.tapWord(phrase);
      // history.record is fire-and-forget; let the microtask run.
      await Future<void>.delayed(Duration.zero);

      expect(session.history.entries, isNotEmpty);
      final entry = session.history.entries.first;
      expect(entry.ids, ['phrase.thankyou']);
      expect(entry.text, 'Thank you');
    });

    test('phrase tap does not disturb words already in the sentence', () async {
      final session = await makeSession();
      final word = session.pack.wordById('core.i');
      session.tapWord(word);
      expect(session.sentenceIds, ['core.i']);

      session.tapWord(session.pack.wordById('phrase.goodnight'));

      expect(session.sentenceIds, ['core.i']);
    });
  });
}
