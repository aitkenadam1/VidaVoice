import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/word.dart';

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
}
