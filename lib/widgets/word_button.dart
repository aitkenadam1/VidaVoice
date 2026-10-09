import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/word.dart';
import 'symbol_image.dart';

/// Symbol + label sizes that fit inside a tile of size [c], scaled by the
/// caregiver's button-size setting ([scale]).
///
/// Tile CONTENT is fluid even though tile POSITIONS are not: the same
/// 8-column board renders on a phone and a wall display, so the pictogram
/// and label grow or shrink with the cell they are given. The label is
/// sized so icon + gap + one label line always fits the cell height —
/// tiles can never overflow into their neighbours, and (with the
/// scale-down fit at the call site) a word is never split across lines.
({double icon, double font}) fluidTileSizes(BoxConstraints c, double scale) {
  final w = c.maxWidth.isFinite ? c.maxWidth : 96.0;
  final h = c.maxHeight.isFinite ? c.maxHeight : 104.0;
  var font = (w * 0.17).clamp(8.0, 15.0) * scale;
  var labelH = font * 1.45;
  var icon = (h - 2 - labelH).clamp(12.0, 72.0);
  icon = math.min(icon, (64.0 * scale).clamp(20.0, 84.0));
  // If the icon floor still leaves no room, shrink the label to fit:
  // fitting inside the cell always wins over a preferred size.
  if (icon + 2 + labelH > h) {
    font = ((h - 2 - icon) / 1.35).clamp(6.0, font);
    labelH = font * 1.35;
  }
  return (icon: icon, font: font);
}

/// One tappable vocabulary cell: ARASAAC pictogram (or emoji fallback)
/// above the word label. Folder tiles are tinted differently.
///
/// [scale] comes from Settings → button size. The grid *layout* never
/// changes — word positions stay fixed for motor planning. The symbol
/// and label size DO follow the cell (see [fluidTileSizes]), so the
/// board looks right on any device from the first launch.
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final sizes = fluidTileSizes(constraints, scale);
              // Scale-down fit as the guarantee: if font metrics ever
              // exceed the budget, the tile shrinks a hair instead of
              // overflowing into its neighbours.
              return FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Fixed layout height: an emoji glyph's painted box can
                    // exceed its nominal size; the layout must not.
                    SizedBox(
                      height: sizes.icon,
                      child: SymbolImage(
                        item: item,
                        hasSymbol: hasSymbol,
                        overrideData: imageOverride,
                        size: sizes.icon,
                      ),
                    ),
                    const SizedBox(height: 2),
                    SizedBox(
                      width: constraints.maxWidth,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          item.label,
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: sizes.font,
                            fontWeight: isFolder
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
