import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Counts taps per word id, persisted locally.
///
/// Powers the "Most used words" section in the Caregiver screen. Counts are
/// device-wide (not per profile) — they describe how the device is used.
class UsageService {
  static const _kCounts = 'vidavoice.usageCounts.v1';

  final Map<String, int> _counts = {};

  Map<String, int> get counts => Map.unmodifiable(_counts);

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
  }

  /// Record one tap on [wordId]. Persists immediately (the map is small).
  Future<void> recordTap(String wordId) async {
    _counts[wordId] = (_counts[wordId] ?? 0) + 1;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCounts, json.encode(_counts));
  }

  int countFor(String wordId) => _counts[wordId] ?? 0;

  int get totalTaps => _counts.values.fold(0, (a, b) => a + b);

  /// Top [n] word ids by tap count, most-tapped first.
  List<MapEntry<String, int>> top(int n) {
    final entries = _counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(n).toList();
  }

  Future<void> clear() async {
    _counts.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCounts);
  }
}
