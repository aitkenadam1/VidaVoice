import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Counts taps per word id, persisted locally.
///
/// Powers the "Most used words" section in the Caregiver screen. Counts are
/// device-wide (not per profile) — they describe how the device is used.
///
/// In addition to lifetime counts, [recordTap] also files each tap into a
/// per-day bucket so the caregiver hub can show activity summaries
/// (taps today, streaks, top words this week). Day buckets older than 60
/// days are pruned on load.
class UsageService {
  UsageService({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  static const _kCounts = 'vidavoice.usageCounts.v1';
  static const _kDays = 'vidavoice.usageDays.v1';

  /// How many days of per-day buckets are kept.
  static const dayRetention = 60;

  final Map<String, int> _counts = {};

  /// Local-date key (yyyy-MM-dd) -> word id -> taps.
  final Map<String, Map<String, int>> _days = {};

  Map<String, int> get counts => Map.unmodifiable(_counts);

  static String _dayKey(DateTime when) =>
      '${when.year.toString().padLeft(4, '0')}-'
      '${when.month.toString().padLeft(2, '0')}-'
      '${when.day.toString().padLeft(2, '0')}';

  String get _todayKey => _dayKey(_clock());

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _counts.clear();
    final raw = prefs.getString(_kCounts);
    if (raw != null) {
      try {
        final decoded = json.decode(raw) as Map;
        decoded.forEach((key, value) {
          if (key is String && value is int && value > 0) {
            _counts[key] = value;
          }
        });
      } on FormatException {
        // Corrupt blob: start fresh rather than breaking boot.
        _counts.clear();
      }
    }
    _days.clear();
    final rawDays = prefs.getString(_kDays);
    if (rawDays != null) {
      try {
        final decoded = json.decode(rawDays) as Map;
        decoded.forEach((dayKey, words) {
          if (dayKey is String && words is Map) {
            final bucket = <String, int>{};
            words.forEach((wordId, count) {
              if (wordId is String && count is int && count > 0) {
                bucket[wordId] = count;
              }
            });
            if (bucket.isNotEmpty) _days[dayKey] = bucket;
          }
        });
      } on FormatException {
        _days.clear();
      }
    }
    _pruneOldDays();
    // Persist the prune so the blob never grows unbounded.
    await _persistDays(prefs);
  }

  void _pruneOldDays() {
    final cutoff = _dayKey(_clock().subtract(const Duration(days: dayRetention)));
    _days.removeWhere((day, _) => day.compareTo(cutoff) < 0);
  }

  Future<void> _persistDays(SharedPreferences prefs) async {
    await prefs.setString(_kDays, json.encode(_days));
  }

  /// Record one tap on [wordId]. Persists immediately (the maps are small).
  Future<void> recordTap(String wordId) async {
    _counts[wordId] = (_counts[wordId] ?? 0) + 1;
    final today = _days.putIfAbsent(_todayKey, () => <String, int>{});
    today[wordId] = (today[wordId] ?? 0) + 1;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCounts, json.encode(_counts));
    await _persistDays(prefs);
  }

  int countFor(String wordId) => _counts[wordId] ?? 0;

  int get totalTaps => _counts.values.fold(0, (a, b) => a + b);

  /// Top [n] word ids by tap count, most-tapped first.
  List<MapEntry<String, int>> top(int n) {
    final entries = _counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(n).toList();
  }

  /// Total taps recorded today.
  int tapsToday() => _dayTotal(_todayKey);

  /// Distinct words tapped today.
  int wordsToday() => _days[_todayKey]?.length ?? 0;

  int _dayTotal(String dayKey) =>
      (_days[dayKey]?.values ?? const <int>[]).fold(0, (a, b) => a + b);

  /// Consecutive calendar days with at least one tap, counting back from
  /// today. A quiet today doesn't break it — the streak counts from the
  /// most recent day with taps (so 0 taps today + taps yesterday = streak
  /// starting yesterday).
  int tapStreak() {
    var streak = 0;
    var day = _clock();
    // If today is quiet, the streak may still be alive from yesterday.
    if (_dayTotal(_dayKey(day)) == 0) {
      day = day.subtract(const Duration(days: 1));
    }
    while (_dayTotal(_dayKey(day)) > 0) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// Top [n] word ids over the last [days] calendar days (including today),
  /// most-tapped first. Days before that are ignored — this is the weekly
  /// view, not the lifetime view.
  List<MapEntry<String, int>> topSinceDays(int days, int n) {
    assert(days > 0);
    final cutoff = _dayKey(
      _clock().subtract(Duration(days: days - 1)),
    );
    final totals = <String, int>{};
    _days.forEach((day, bucket) {
      if (day.compareTo(cutoff) >= 0) {
        bucket.forEach((wordId, count) {
          totals[wordId] = (totals[wordId] ?? 0) + count;
        });
      }
    });
    final entries = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(n).toList();
  }

  Future<void> clear() async {
    _counts.clear();
    _days.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCounts);
    await prefs.remove(_kDays);
  }
}
