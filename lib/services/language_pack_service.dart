import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/word.dart';
import 'prediction_service.dart';

/// Loads versioned language packs from the app bundle.
///
/// Adding a language = drop `assets/lang/<locale>.json` into the bundle and
/// list the locale in [AppConfig.supportedLocales]. No code changes needed.
class LanguagePackService {
  static Future<LanguagePack> loadPack(String locale) async {
    final raw = await rootBundle.loadString('assets/lang/$locale.json');
    final pack = LanguagePack.fromJson(
      Map<String, dynamic>.from(json.decode(raw) as Map),
    );
    pack.validate(); // fail fast: a broken pack must never ship
    return pack;
  }

  /// Compact 10,000-concept vocabulary labels for Type-mode prediction
  /// fallback (`assets/lang/vocab10k.json`, generated from
  /// data/vocab10k/curated.json).
  ///
  /// Fully offline: a bundled asset, never fetched. Unknown locales fall
  /// back to English; a missing or corrupt asset yields an empty list so
  /// Type mode still works (history-first suggestions are unaffected).
  static Future<List<VocabLabel>> loadVocabLabels(String locale) async {
    try {
      final raw = await rootBundle.loadString('assets/lang/vocab10k.json');
      final decoded = Map<String, dynamic>.from(json.decode(raw) as Map);
      final locales = Map<String, dynamic>.from(decoded['labels'] as Map);
      final list = locales[locale] ?? locales['en'];
      if (list is! List) return const [];
      final labels = <VocabLabel>[];
      for (final entry in list) {
        if (entry is! List || entry.isEmpty) continue;
        final label = entry[0];
        if (label is! String || label.isEmpty) continue;
        final level = entry.length > 1 && entry[1] is num
            ? (entry[1] as num).toInt()
            : 3;
        labels.add(VocabLabel(label: label, level: level));
      }
      return labels;
    } catch (_) {
      return const [];
    }
  }
}
