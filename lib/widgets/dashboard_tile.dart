import 'dart:convert';

import 'package:flutter/material.dart';

import 'word_button.dart';

/// One custom (non-vocabulary) dashboard cell: imported image or emoji
/// above the label. Vocabulary cells reuse the standard word button;
/// this tile is only for caregiver-authored and imported buttons.
class DashboardTile extends StatelessWidget {
  const DashboardTile({
    super.key,
    required this.label,
    this.emoji = '🔤',
    this.imageData,
    this.color,
    this.scale = 1.0,
    required this.onTap,
  });

  final String label;
  final String emoji;
  final String? imageData;
  final int? color;
  final double scale;
  final VoidCallback onTap;

  Widget _symbol(double size) {
    if (imageData != null) {
      try {
        final bytes = base64.decode(imageData!);
        return Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => _emojiFallback(size),
        );
      } catch (_) {
        // Corrupt image data: fall through to the emoji.
      }
    }
    return _emojiFallback(size);
  }

  Widget _emojiFallback(double size) =>
      Text(emoji, style: TextStyle(fontSize: size * 0.85));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: color != null ? Color(color!) : scheme.surfaceContainerHighest,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final sizes = fluidTileSizes(constraints, scale);
              return FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(height: sizes.icon, child: _symbol(sizes.icon)),
                    const SizedBox(height: 2),
                    SizedBox(
                      width: constraints.maxWidth,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          label,
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(fontSize: sizes.font),
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
