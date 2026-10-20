// Caregiver word limits for Type mode: a built-in profanity list plus
// the caregiver's own per-profile words, with pure matching helpers.
//
// Everything here is a pure function of its inputs — no I/O, no state —
// so the filtering rules are pinned directly by unit tests. Matching
// is whole-word, case-insensitive, and punctuation-tolerant: only a
// complete word token equal to a blocked word matches, so a blocked
// substring inside a longer innocent word ("class", "damnation",
// "shiitake") NEVER triggers.
//
// Scope (also documented where it is enforced, in SessionState and
// TypeBoardScreen): limits apply ONLY to free-typed text and its
// predictions, and only while the active profile has them enabled.
// Caregiver-curated board buttons are never filtered — the words on a
// home board are there because a caregiver put them there.

/// The replacement shown and spoken in place of a blocked word.
const blockedWordMask = '•••';

/// Curated mainstream English profanity, with common inflections
/// (whole-word matching means variants must be listed to count).
/// Deliberately not exhaustive — the caregiver's custom list covers
/// anything family-specific.
const List<String> builtInBlockedWords = [
  'arse', 'arsehole', 'ass', 'asses', 'asshole', 'assholes',
  'bastard', 'bastards', 'bitch', 'bitches', 'bitching', 'bollocks',
  'bullshit',
  'cock', 'cocks', 'crap', 'cum', 'cunt', 'cunts',
  'damn', 'damned', 'dammit', 'dick', 'dicks', 'dildo',
  'dumbass',
  'fag', 'faggot', 'fuck', 'fucked', 'fucker', 'fuckers', 'fucking',
  'fucks',
  'goddamn', 'goddamnit',
  'hell',
  'jackass', 'jerkoff', 'jizz',
  'motherfucker', 'motherfucking',
  'nigger', 'nigga',
  'piss', 'pissed', 'porn', 'porno', 'pussy',
  'retard', 'retarded',
  'shit', 'shits', 'shitty', 'shitting', 'slut', 'sluts',
  'whore', 'whores',
];

final Set<String> _builtIn = {
  for (final w in builtInBlockedWords) normalizeBlockedWord(w),
};

/// A word token: letters/digits (any script) with interior apostrophes,
/// so "don't" is one token while surrounding punctuation is not part
/// of the word ("damn!" tokenizes to "damn").
final RegExp _wordPattern = RegExp(r"[\p{L}\p{N}]+(?:'[\p{L}]+)?", unicode: true);

/// Normalizes one word for comparison and storage: trimmed, lowercased.
String normalizeBlockedWord(String word) => word.trim().toLowerCase();

/// Normalizes a caregiver-entered list: each entry trimmed and
/// lowercased, empties dropped, duplicates removed (first wins).
List<String> normalizeBlockedWords(Iterable<String> words) {
  final seen = <String>{};
  final out = <String>[];
  for (final raw in words) {
    final w = normalizeBlockedWord(raw);
    if (w.isEmpty || !seen.add(w)) continue;
    out.add(w);
  }
  return out;
}

Set<String> _blockedSet(Iterable<String> custom) => {
  ..._builtIn,
  for (final w in custom) normalizeBlockedWord(w),
};

bool _tokenBlocked(String token, Set<String> blocked) {
  var t = token.toLowerCase();
  if (blocked.contains(t)) return true;
  // Possessive form of a blocked word ("damn's") still counts.
  if (t.endsWith("'s")) {
    t = t.substring(0, t.length - 2);
    if (blocked.contains(t)) return true;
  }
  return false;
}

/// Whether [word] — a single word, any case, edge punctuation allowed —
/// is blocked by the built-in list or the caregiver's [custom] words.
bool isBlockedWord(String word, {Iterable<String> custom = const []}) {
  final match = _wordPattern.firstMatch(word.trim());
  if (match == null) return false;
  return _tokenBlocked(match.group(0)!, _blockedSet(custom));
}

/// Whether any word in [text] is blocked.
bool containsBlockedWord(String text, {Iterable<String> custom = const []}) {
  final blocked = _blockedSet(custom);
  for (final m in _wordPattern.allMatches(text)) {
    if (_tokenBlocked(m.group(0)!, blocked)) return true;
  }
  return false;
}

/// [text] with every blocked word replaced by [blockedWordMask].
/// Spacing and punctuation are preserved exactly; text with no blocked
/// words comes back unchanged.
String maskBlockedWords(String text, {Iterable<String> custom = const []}) {
  final blocked = _blockedSet(custom);
  return text.replaceAllMapped(_wordPattern, (m) {
    final token = m.group(0)!;
    return _tokenBlocked(token, blocked) ? blockedWordMask : token;
  });
}

/// [suggestions] with blocked entries removed. A multi-word suggestion
/// is removed when ANY of its words is blocked — a phrase containing a
/// blocked word must not be offered either.
List<String> filterBlockedSuggestions(
  List<String> suggestions, {
  Iterable<String> custom = const [],
}) {
  final blocked = _blockedSet(custom);
  return [
    for (final s in suggestions)
      if (!_wordPattern
          .allMatches(s)
          .any((m) => _tokenBlocked(m.group(0)!, blocked)))
        s,
  ];
}
