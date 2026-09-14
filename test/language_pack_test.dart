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

      test('home grid holds 282 core words at unique fixed positions', () {
        final words = pack.homeItems.where((i) => !i.isFolder).toList();
        expect(words.length, 282);
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

      test('every word declares a level in 1..3', () {
        for (final item in pack.homeItems) {
          expect(
            item.level,
            inInclusiveRange(
              LanguagePack.minSupportedLevel,
              LanguagePack.maxSupportedLevel,
            ),
            reason: item.id,
          );
        }
        for (final folder in pack.folders.values) {
          for (final word in folder.words) {
            expect(
              word.level,
              inInclusiveRange(
                LanguagePack.minSupportedLevel,
                LanguagePack.maxSupportedLevel,
              ),
              reason: word.id,
            );
          }
        }
      });

      test('all three levels are actually populated', () {
        final levels = pack.homeItems
            .where((i) => !i.isFolder)
            .map((i) => i.level)
            .toSet();
        expect(levels, {1, 2, 3});
        expect(pack.maxLevel, LanguagePack.maxSupportedLevel);
      });

      test('level 1 alone is a usable board', () {
        final starter = pack.homeItems
            .where((i) => !i.isFolder && i.level == 1)
            .toList();
        expect(
          starter.length,
          greaterThanOrEqualTo(40),
          reason: 'A starter board needs enough core words to say something.',
        );
        // The words a first message is built from must never be locked away.
        for (final id in [
          'core.want',
          'core.more',
          'core.stop',
          'core.help',
          'core.go',
          'core.yes',
          'core.no',
        ]) {
          expect(pack.wordById(id).level, 1, reason: id);
        }
      });

      test('folder tiles are never locked', () {
        for (final tile in pack.homeItems.where((i) => i.isFolder)) {
          expect(tile.level, LanguagePack.minSupportedLevel, reason: tile.id);
          // Visible even at the lowest unlocked level, or the level-1 words
          // inside them become unreachable.
          expect(tile.visibleAt(LanguagePack.minSupportedLevel), isTrue);
        }
      });

      test('every folder still has level-1 words behind it', () {
        for (final folder in pack.folders.values) {
          expect(
            folder.words.any((w) => w.level == 1),
            isTrue,
            reason: '${folder.id} would open onto an empty grid at level 1.',
          );
        }
      });

      test('progressive reveal NEVER moves a visible word', () {
        // The invariant the whole feature rests on: raising the unlocked level
        // only fills empty cells. A word visible at level N must be at the
        // exact same (row, col) at every level >= N.
        for (var level = 1; level <= LanguagePack.maxSupportedLevel; level++) {
          for (final item in pack.homeItems) {
            if (!item.visibleAt(level)) continue;
            expect(
              pack.itemAt(item.row, item.col, unlockedLevel: level)?.id,
              item.id,
              reason:
                  '${item.id} is not at (${item.row}, ${item.col}) '
                  'when level $level is unlocked.',
            );
          }
        }
      });

      test('locked cells read as empty, and unlock without displacing', () {
        final locked = pack.homeItems.firstWhere((i) => i.level == 3);
        expect(
          pack.itemAt(locked.row, locked.col, unlockedLevel: 1),
          isNull,
          reason: 'A level-3 word must be invisible at level 1.',
        );
        expect(
          pack.itemAt(locked.row, locked.col, unlockedLevel: 3)?.id,
          locked.id,
          reason: 'and must appear in that same cell once unlocked.',
        );
      });

      test('the set of visible words grows monotonically', () {
        Set<String> visibleAt(int level) => pack.homeItems
            .where((i) => i.visibleAt(level))
            .map((i) => i.id)
            .toSet();
        final one = visibleAt(1);
        final two = visibleAt(2);
        final three = visibleAt(3);
        expect(two.containsAll(one), isTrue, reason: 'level 2 dropped a word');
        expect(
          three.containsAll(two),
          isTrue,
          reason: 'level 3 dropped a word',
        );
        expect(three.length, greaterThan(two.length));
        expect(two.length, greaterThan(one.length));
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

  test('en, es and fr share identical levels', () {
    final en = loadPack('en');
    Map<String, int> levels(LanguagePack pack) => {
      for (final i in pack.homeItems) i.id: i.level,
      for (final f in pack.folders.values)
        for (final w in f.words) w.id: w.level,
    };
    final enLevels = levels(en);
    for (final locale in ['es', 'fr']) {
      expect(
        levels(loadPack(locale)),
        enLevels,
        reason:
            'A bilingual child must not have the board change shape when '
            'they switch language ($locale drifted).',
      );
    }
  });
}
