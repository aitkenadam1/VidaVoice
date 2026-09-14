import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One spoken sentence in the history: the word ids (language-independent,
/// so a sentence can be reloaded even after a language switch), the spoken
/// text, the locale it was spoken in, and when.
class HistoryEntry {
  HistoryEntry({
    required this.ids,
    required this.text,
    required this.locale,
    required this.spokenAt,
  });

  final List<String> ids;
  final String text;
  final String locale;
  final DateTime spokenAt;

  Map<String, dynamic> toJson() => {
    'ids': ids,
    'text': text,
    'locale': locale,
    'spokenAt': spokenAt.millisecondsSinceEpoch,
  };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    final ids = (json['ids'] as List).map((e) => e as String).toList();
    return HistoryEntry(
      ids: ids,
      text: json['text'] as String,
      locale: json['locale'] as String,
      spokenAt: DateTime.fromMillisecondsSinceEpoch(
        (json['spokenAt'] as num).toInt(),
      ),
    );
  }
}

/// Per-profile history of recently spoken sentences, stored locally.
///
/// Newest entries come first from [entries]. The list is capped at
/// [maxEntries] — old entries are dropped, never persisted beyond that.
class HistoryService {
  static const maxEntries = 50;

  static String _key(String profileId) => 'vidavoice.history.$profileId.v1';

  final List<HistoryEntry> _entries = [];

  /// Newest first.
  List<HistoryEntry> get entries => List.unmodifiable(_entries);

  Future<void> load(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    _entries.clear();
    final raw = prefs.getString(_key(profileId));
    if (raw == null) return;
    try {
      final decoded = json.decode(raw) as List;
      for (final rawEntry in decoded) {
        final entry = HistoryEntry.fromJson(
          Map<String, dynamic>.from(rawEntry as Map),
        );
        if (entry.ids.isNotEmpty && entry.text.isNotEmpty) {
          _entries.add(entry);
        }
      }
      // Stored newest-first; keep the cap even for blobs written by hand.
      _entries.sort((a, b) => b.spokenAt.compareTo(a.spokenAt));
      if (_entries.length > maxEntries) {
        _entries.removeRange(maxEntries, _entries.length);
      }
    } on FormatException {
      // Corrupt blob: start fresh rather than breaking boot.
      _entries.clear();
    }
  }

  Future<void> record(
    String profileId,
    List<String> ids,
    String text,
    String locale,
  ) async {
    if (ids.isEmpty || text.isEmpty) return;
    _entries.insert(
      0,
      HistoryEntry(
        ids: List.of(ids),
        text: text,
        locale: locale,
        spokenAt: DateTime.now(),
      ),
    );
    if (_entries.length > maxEntries) {
      _entries.removeRange(maxEntries, _entries.length);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(profileId),
      json.encode(_entries.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> clear(String profileId) async {
    _entries.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(profileId));
  }
}
