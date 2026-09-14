import 'package:flutter/material.dart';

import '../models/word.dart';
import '../services/symbol_service.dart';

/// Shows the ARASAAC pictogram for [item] when one was downloaded,
/// otherwise falls back to the emoji from the language pack.
class SymbolImage extends StatelessWidget {
  const SymbolImage({
    super.key,
    required this.item,
    required this.hasSymbol,
    this.size = 38,
  });

  final BoardItem item;
  final bool hasSymbol;
  final double size;

  @override
  Widget build(BuildContext context) {
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
