import '../models/word.dart';

/// One word-finder hit: the word plus where it lives, in caregiver language.
class WordMatch {
  const WordMatch({required this.item, required this.location});

  final BoardItem item;

  /// e.g. "Home · row 3" or "Folder: Food".
  final String location;
}

/// Case-insensitive substring search over the current pack's labels.
///
/// Read-only: never mutates the pack or the session. Searches home-grid
/// words and folder words; folder tiles themselves are not hits.
List<WordMatch> findWords(LanguagePack pack, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final hits = <WordMatch>[];
  for (final item in pack.homeItems) {
    if (item.isFolder) continue;
    if (item.label.toLowerCase().contains(q)) {
      // Rows are 0-based in the pack; caregivers count from 1.
      hits.add(
        WordMatch(item: item, location: 'Home · row ${item.row + 1}'),
      );
    }
  }
  for (final folder in pack.folders.values) {
    for (final word in folder.words) {
      if (word.label.toLowerCase().contains(q)) {
        hits.add(WordMatch(item: word, location: 'Folder: ${folder.label}'));
      }
    }
  }
  return hits;
}
