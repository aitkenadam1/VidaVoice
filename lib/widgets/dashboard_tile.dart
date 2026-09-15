import 'dart:convert';

import 'package:flutter/material.dart';

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
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _symbol(38 * scale),
              const SizedBox(height: 2),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12 * scale),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
