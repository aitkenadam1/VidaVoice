import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vidavoice/models/word.dart';

/// Guards the motor-planning invariant: every shipped language pack must
/// parse, validate (2-tap budget), and keep every core word at a FIXED
/// position. Run from the project root: `flutter test`.
///
/// Word ids and grid positions are identical across locales — bilingual
/// users keep the same motor position in every language.
void main() {
  LanguagePack loadPack(String locale) {
    final raw = File('assets/lang/$locale.json').readAsStringSync();
    return LanguagePack.fromJson(
      Map<String, dynamic>.from(json.decode(raw) as Map),
    );
  }

  for (final locale in ['en', 'es', 'fr']) {
    group('language pack: $locale', () {
      late LanguagePack pack;

      setUpAll(() => pack = loadPack(locale));

      test('pack validates: 2-tap budget and fixed positions hold', () {
        pack.validate();
      });

      test('home grid holds 242 core words at unique fixed positions', () {
        final words = pack.homeItems.where((i) => !i.isFolder).toList();
        expect(words.length, 242);
        final cells = words.map((w) => '${w.row}:${w.col}').toSet();
        expect(
          cells.length,
          words.length,
          reason: 'Two words share a grid cell — motor-planning violation.',
        );
      });

      test('every folder tile resolves to a non-empty word list', () {
        for (final item in pack.homeItems.where((i) => i.isFolder)) {
          expect(pack.folders.containsKey(item.id), isTrue, reason: item.id);
          expect(pack.folders[item.id]!.words, isNotEmpty, reason: item.id);
        }
      });

      test('folder vocabulary is substantive (>40 words)', () {
        final count = pack.folders.values.fold<int>(
          0,
          (n, f) => n + f.words.length,
        );
        expect(count, greaterThan(40));
      });

      test('wordById resolves home and folder words', () {
        expect(pack.wordById('core.want').label, isNotEmpty);
        expect(pack.wordById('food.apple').label, isNotEmpty);
      });
    });
  }

  test('en, es and fr share identical ids and grid positions', () {
    final en = loadPack('en');
    final enCells = {
      for (final i in en.homeItems) i.id: '${i.row}:${i.col}:${i.type}',
    };
    for (final locale in ['es', 'fr']) {
      final pack = loadPack(locale);
      final cells = {
        for (final i in pack.homeItems) i.id: '${i.row}:${i.col}:${i.type}',
      };
      expect(
        cells,
        enCells,
        reason:
            'Motor positions must be identical across languages (ids drifted in $locale).',
      );
    }
  });
}
