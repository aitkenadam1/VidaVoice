import 'package:flutter/material.dart';

import '../models/word.dart';
import 'symbol_image.dart';

/// One tappable vocabulary cell: ARASAAC pictogram (or emoji fallback)
/// above the word label. Folder tiles are tinted differently.
///
/// [scale] comes from Settings → button size. The grid *layout* never
/// changes — word positions stay fixed for motor planning.
class WordButton extends StatelessWidget {
  const WordButton({
    super.key,
    required this.item,
    required this.onTap,
    this.scale = 1.0,
    this.hasSymbol = false,
    this.imageOverride,
  });

  final BoardItem item;
  final VoidCallback onTap;
  final double scale;
  final bool hasSymbol;

  /// Per-profile caregiver image for this button (base64). Null keeps the
  /// standard symbol.
  final String? imageOverride;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isFolder = item.type == BoardItemType.folder;
    return Card(
      color: isFolder
          ? scheme.secondaryContainer
          : scheme.surfaceContainerHighest,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SymbolImage(
                item: item,
                hasSymbol: hasSymbol,
                overrideData: imageOverride,
                size: 38 * scale,
              ),
              const SizedBox(height: 2),
              Text(
                item.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12 * scale,
                  fontWeight: isFolder ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
