import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/word.dart';
import '../services/symbol_service.dart';

/// Shows the symbol for [item]: a caregiver-set custom image first, then
/// the ARASAAC pictogram when one was downloaded, otherwise the emoji
/// from the language pack.
class SymbolImage extends StatelessWidget {
  const SymbolImage({
    super.key,
    required this.item,
    required this.hasSymbol,
    this.overrideData,
    this.size = 38,
  });

  final BoardItem item;
  final bool hasSymbol;

  /// Base64 image from a per-profile caregiver override. Takes precedence
  /// over the standard symbol; corrupt data falls through to the default.
  final String? overrideData;
  final double size;

  @override
  Widget build(BuildContext context) {
    final override = overrideData;
    if (override != null) {
      try {
        return Image.memory(
          base64.decode(override),
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => _defaultSymbol(),
        );
      } catch (_) {
        // Corrupt override: fall through to the standard symbol.
      }
    }
    return _defaultSymbol();
  }

  Widget _defaultSymbol() {
    if (hasSymbol) {
      return Image.asset(
        SymbolService.assetPath(item.id),
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => _emojiFallback(),
      );
    }
    return _emojiFallback();
  }

  Widget _emojiFallback() =>
      Text(item.emoji, style: TextStyle(fontSize: size * 0.85));
}
