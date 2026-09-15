import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One fallback candidate from the 10,000-concept vocabulary.
///
/// [label] is the locale's display text; [level] (1-3) is the vocabulary
/// level from the curated list — lower levels are the more basic words, so
/// the deterministic fallback order is level-first, then alphabetical.
class VocabLabel {
  const VocabLabel({required this.label, this.level = 3});

  final String label;
  final int level;
}

/// Deterministic, fully on-device prediction engine for Type mode.
///
/// Two signals, in a fixed order — the communicator's own spoken history
/// first, the 10,000-concept vocabulary as fallback — then a small stable
/// set of suggestions. There is no generative model, no network, and no
/// analytics: [learn] and [suggest] touch only SharedPreferences and
/// memory.
///
/// Learned ranks live in a SEPARATE store from the raw spoken history
/// (`vidavoice.predictionRanks.<profileId>.v1`, one blob per profile) and
/// are learned ONLY from that profile's intentionally-spoken messages —
/// never from drafts, keystrokes, or any other profile. Clearing history
/// never touches ranks; resetting ranks never touches history.
///
/// Ranking is deliberately boring and documented here so tests can pin
/// it:
/// * Tokens are lowercased, split on whitespace, with edge punctuation
///   stripped (accents survive — es/fr labels keep theirs).
/// * Partial word (typing "wa"): learned completions first (count desc,
///   then most-recently-learned, then alphabetical), then vocab labels
///   with the same prefix (level asc, then alphabetical).
/// * Complete context (typing "I want␣"): words that followed the last
///   word in history (count desc, recency, alphabetical), then the most
///   basic vocab words not already suggested.
/// * Empty field: most frequent sentence-starting words from history,
///   then the most basic vocab words.
class PredictionService {
  /// How many suggestions [suggest] returns at most.
  static const maxSuggestions = 5;

  static String _key(String profileId) =>
      'vidavoice.predictionRanks.$profileId.v1';

  /// In-memory ranks per profile. A profile's ranks are only ever loaded
  /// from / saved to its OWN key — cross-profile leakage is impossible by
  /// construction, and a test pins it.
  final Map<String, _ProfileRanks> _ranks = {};

  /// Load (or reload) the learned ranks for [profileId]. Unknown profiles
  /// start empty; corrupt blobs start empty rather than breaking boot.
  Future<void> load(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    final ranks = _ProfileRanks();
    final raw = prefs.getString(_key(profileId));
    if (raw != null) {
      try {
        ranks.fromJson(Map<String, dynamic>.from(json.decode(raw) as Map));
      } on FormatException {
        // Corrupt blob: start fresh.
      }
    }
    _ranks[profileId] = ranks;
  }

  /// Learn from one intentionally-spoken message. The caller (SessionState)
  /// is responsible for calling this ONLY when the profile's
  /// predictionEnabled is true and ONLY with text the communicator chose
  /// to speak — never drafts or keystrokes.
  Future<void> learn(String profileId, String text, String locale) async {
    final tokens = tokenize(text);
    if (tokens.isEmpty) return;
    final ranks = _ranks.putIfAbsent(profileId, _ProfileRanks.new);
    ranks.learn(tokens);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(profileId), json.encode(ranks.toJson()));
  }

  /// Ordered suggestions for the current [text] being composed.
  ///
  /// Pure function of the loaded ranks + [vocab]: no I/O, no network, no
  /// randomness. [vocab] is injected (the app loads the bundled 10k
  /// labels; tests inject stubs), which keeps this deterministic and
  /// testable without asset loading.
  List<String> suggest({
    required String profileId,
    required String text,
    required String locale,
    List<VocabLabel> vocab = const [],
    int limit = maxSuggestions,
  }) {
    final ranks = _ranks[profileId];
    final out = <String>[];
    final seen = <String>{};

    void add(String word) {
      final key = word.toLowerCase();
      if (key.isEmpty || seen.contains(key)) return;
      if (out.length >= limit) return;
      seen.add(key);
      out.add(word);
    }

    if (text.trim().isEmpty) {
      // Nothing typed yet: most frequent sentence starters, then the
      // most basic vocab words.
      if (ranks != null) {
        for (final w in ranks.topStarts(limit)) {
          add(w);
        }
      }
      for (final v in vocab) {
        add(v.label);
        if (out.length >= limit) break;
      }
      return out;
    }

    final endsWithSpace = RegExp(r'\s$').hasMatch(text);
    final tokens = tokenize(text);
    if (tokens.isEmpty) {
      for (final v in vocab) {
        add(v.label);
        if (out.length >= limit) break;
      }
      return out;
    }

    if (endsWithSpace) {
      // Next-word prediction: words that followed the last typed word.
      final prev = tokens.last;
      if (ranks != null) {
        for (final w in ranks.topFollowers(prev, limit)) {
          add(w);
        }
      }
      for (final v in vocab) {
        add(v.label);
        if (out.length >= limit) break;
      }
      return out;
    }

    // Partial word: complete it — learned completions first, then vocab.
    final prefix = tokens.last;
    if (ranks != null) {
      for (final w in ranks.topCompletions(prefix, limit)) {
        add(w);
      }
    }
    final lowerPrefix = prefix.toLowerCase();
    for (final v in vocab) {
      if (v.label.toLowerCase().startsWith(lowerPrefix)) add(v.label);
      if (out.length >= limit) break;
    }
    return out;
  }

  /// Forget everything learned for [profileId]. The profile's spoken
  /// history is a different store and is NEVER touched here.
  Future<void> reset(String profileId) async {
    _ranks.remove(profileId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(profileId));
  }

  /// Test seam: how many distinct words [profileId] has learned.
  int learnedWordCount(String profileId) =>
      _ranks[profileId]?.wordCount.length ?? 0;

  /// Lowercase, whitespace-split, edge-punctuation-stripped tokens.
  /// Public so tests can pin the normalization contract.
  static List<String> tokenize(String text) {
    final tokens = <String>[];
    for (final raw in text.toLowerCase().split(RegExp(r'\s+'))) {
      final token = raw.replaceAll(
        RegExp(r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$', unicode: true),
        '',
      );
      if (token.isNotEmpty) tokens.add(token);
    }
    return tokens;
  }
}

/// Per-profile learned ranks: unigram counts (for prefix completion),
/// bigram followers (for next-word prediction), and sentence starters
/// (for the empty-field case). Each carries a recency sequence so ties
/// break deterministically toward what was spoken most recently.
class _ProfileRanks {
  /// Monotonic per learn() call; the recency tie-break.
  int seq = 0;

  final Map<String, int> wordCount = {};
  final Map<String, int> wordSeq = {};
  final Map<String, Map<String, int>> followers = {};
  final Map<String, int> followerSeq = {};
  final Map<String, int> starts = {};
  final Map<String, int> startSeq = {};

  /// Hard caps keep the blob small; eviction is deterministic
  /// (lowest count, oldest, then alphabetical — see [_evict]).
  static const maxWords = 2000;
  static const maxContexts = 2000;
  static const maxFollowersPerContext = 100;

  void learn(List<String> tokens) {
    seq++;
    final first = tokens.first;
    starts[first] = (starts[first] ?? 0) + 1;
    startSeq[first] = seq;
    for (var i = 0; i < tokens.length; i++) {
      final word = tokens[i];
      wordCount[word] = (wordCount[word] ?? 0) + 1;
      wordSeq[word] = seq;
      if (i > 0) {
        final prev = tokens[i - 1];
        final map = followers.putIfAbsent(prev, () => {});
        map[word] = (map[word] ?? 0) + 1;
        followerSeq['$prev\x00$word'] = seq;
      }
    }
    _evict();
  }

  void _evict() {
    _evictMap(wordCount, wordSeq, maxWords);
    if (followers.length > maxContexts) {
      final ordered = followers.keys.toList()
        ..sort(_contextOrder);
      for (final k in ordered.take(followers.length - maxContexts)) {
        followers.remove(k);
      }
    }
    for (final entry in followers.entries) {
      if (entry.value.length > maxFollowersPerContext) {
        _evictMap(entry.value, {}, maxFollowersPerContext, prefix: entry.key);
      }
    }
    if (starts.length > maxWords) _evictMap(starts, startSeq, maxWords);
  }

  int _contextOrder(String a, String b) {
    final ca = _contextCount(a);
    final cb = _contextCount(b);
    if (ca != cb) return ca.compareTo(cb);
    return a.compareTo(b);
  }

  int _contextCount(String context) {
    var n = 0;
    for (final c in followers[context]!.values) {
      n += c;
    }
    return n;
  }

  /// Drop the lowest-priority entries until [counts] fits [cap].
  /// Priority: count asc, recency asc, word asc — deterministic.
  void _evictMap(
    Map<String, int> counts,
    Map<String, int> recency,
    int cap, {
    String? prefix,
  }) {
    if (counts.length <= cap) return;
    final ordered = counts.keys.toList()
      ..sort((a, b) {
        final ca = counts[a]!;
        final cb = counts[b]!;
        if (ca != cb) return ca.compareTo(cb);
        final ra = prefix != null
            ? followerSeq['$prefix\x00$a'] ?? 0
            : recency[a] ?? 0;
        final rb = prefix != null
            ? followerSeq['$prefix\x00$b'] ?? 0
            : recency[b] ?? 0;
        if (ra != rb) return ra.compareTo(rb);
        return a.compareTo(b);
      });
    for (final k in ordered.take(counts.length - cap)) {
      counts.remove(k);
    }
  }

  List<String> _ranked(
    Map<String, int> counts,
    Map<String, int> recency,
    int limit,
  ) {
    final ordered = counts.keys.toList()
      ..sort((a, b) {
        final ca = counts[a]!;
        final cb = counts[b]!;
        if (ca != cb) return cb.compareTo(ca); // count desc
        final ra = recency[a] ?? 0;
        final rb = recency[b] ?? 0;
        if (ra != rb) return rb.compareTo(ra); // recency desc
        return a.compareTo(b); // alphabetical
      });
    return ordered.take(limit).toList();
  }

  /// Words starting with [prefix], learned-completion order.
  List<String> topCompletions(String prefix, int limit) {
    final lower = prefix.toLowerCase();
    final matches = <String, int>{};
    final recency = <String, int>{};
    wordCount.forEach((word, count) {
      if (word.startsWith(lower)) {
        matches[word] = count;
        recency[word] = wordSeq[word] ?? 0;
      }
    });
    return _ranked(matches, recency, limit);
  }

  /// Words that followed [prev] in spoken messages, bigram order.
  List<String> topFollowers(String prev, int limit) {
    final map = followers[prev.toLowerCase()];
    if (map == null) return const [];
    final recency = <String, int>{};
    map.forEach((word, _) {
      recency[word] = followerSeq['${prev.toLowerCase()}\x00$word'] ?? 0;
    });
    return _ranked(map, recency, limit);
  }

  /// Most frequent sentence-starting words.
  List<String> topStarts(int limit) => _ranked(starts, startSeq, limit);

  Map<String, dynamic> toJson() => {
    'seq': seq,
    'wordCount': wordCount,
    'wordSeq': wordSeq,
    'followers': followers,
    'followerSeq': followerSeq,
    'starts': starts,
    'startSeq': startSeq,
  };

  void fromJson(Map<String, dynamic> json) {
    seq = (json['seq'] as num?)?.toInt() ?? 0;
    _readInto(wordCount, json['wordCount']);
    _readInto(wordSeq, json['wordSeq']);
    final f = json['followers'];
    if (f is Map) {
      f.forEach((k, v) {
        if (v is Map) {
          final map = <String, int>{};
          _readInto(map, v);
          followers[k as String] = map;
        }
      });
    }
    _readInto(followerSeq, json['followerSeq']);
    _readInto(starts, json['starts']);
    _readInto(startSeq, json['startSeq']);
  }

  static void _readInto(Map<String, int> target, Object? raw) {
    if (raw is! Map) return;
    raw.forEach((k, v) {
      if (v is num) target[k as String] = v.toInt();
    });
  }
}
