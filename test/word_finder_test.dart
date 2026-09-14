import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vidavoice/models/word.dart';
import 'package:vidavoice/services/word_finder.dart';

/// Word finder search logic. Run from the project root: `flutter test`.
void main() {
  late LanguagePack pack;

  setUpAll(() {
    final raw = File('assets/lang/en.json').readAsStringSync();
    pack = LanguagePack.fromJson(
      Map<String, dynamic>.from(json.decode(raw) as Map),
    );
    pack.validate();
  });

  test('empty query returns nothing', () {
    expect(findWords(pack, ''), isEmpty);
    expect(findWords(pack, '   '), isEmpty);
  });

  test('finds a home-grid word with its row', () {
    final hits = findWords(pack, 'want');
    expect(hits.map((h) => h.item.id), contains('core.want'));
    final want = hits.firstWhere((h) => h.item.id == 'core.want');
    expect(want.location, startsWith('Home · row '));
  });

  test('search is case-insensitive and substring-based', () {
    final lower = findWords(pack, 'want');
    final upper = findWords(pack, 'WANT');
    expect(
      upper.map((h) => h.item.id).toSet(),
      lower.map((h) => h.item.id).toSet(),
    );
    final partial = findWords(pack, 'app');
    expect(partial.map((h) => h.item.id), contains('food.apple'));
  });

  test('finds folder words with the folder name', () {
    final hits = findWords(pack, 'apple');
    final apple = hits.firstWhere((h) => h.item.id == 'food.apple');
    expect(apple.location, 'Folder: Food');
  });

  test('folder tiles are never hits', () {
    // "Food" is a folder tile label; no word is labeled "food".
    final hits = findWords(pack, 'food');
    expect(hits.where((h) => h.item.isFolder), isEmpty);
  });

  test('no match returns empty', () {
    expect(findWords(pack, 'xyzzyplugh'), isEmpty);
  });

  test('hits carry the vocabulary level', () {
    final hits = findWords(pack, 'want');
    for (final hit in hits) {
      expect(
        hit.item.level,
        inInclusiveRange(
          LanguagePack.minSupportedLevel,
          LanguagePack.maxSupportedLevel,
        ),
      );
    }
  });
}
