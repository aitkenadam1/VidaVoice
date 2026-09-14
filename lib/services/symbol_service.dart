import 'dart:convert';

import 'package:flutter/services.dart';

/// Resolves ARASAAC pictograms for vocabulary words.
///
/// [load] reads `assets/symbols/manifest.json` (written by the symbol-fetch
/// script). [hasSymbol] is false for words without a pictogram — callers
/// fall back to the emoji in that case, so the board always renders.
class SymbolService {
  Set<String> _available = {};

  bool get hasAny => _available.isNotEmpty;
  int get count => _available.length;

  Future<void> load() async {
    try {
      final raw = await rootBundle.loadString('assets/symbols/manifest.json');
      final data = json.decode(raw) as Map<String, dynamic>;
      _available = Set<String>.from(
        (data['symbols'] as List).map((e) => e.toString()),
      );
    } catch (_) {
      _available = <String>{};
    }
  }

  bool hasSymbol(String wordId) => _available.contains(wordId);

  static String assetPath(String wordId) =>
      'assets/symbols/${wordId.replaceAll('.', '_')}.png';
}
