import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Prepares a caregiver-picked image for storage on a button.
///
/// Phone photos are far too big to live in SharedPreferences as base64,
/// so the image is decoded, downscaled so its longest side is at most
/// [maxSide] px, and re-encoded as JPEG. Returns the base64 payload, or
/// null when the bytes are not a readable image.
class ButtonImage {
  /// Longest side of the stored image — big enough to look crisp on a
  /// button, small enough to keep dashboards portable.
  static const maxSide = 256;

  /// JPEG quality for the stored image: legible symbols, small payload.
  static const jpegQuality = 82;

  /// Upper bound on the stored payload. Anything still bigger than this
  /// after downscaling is rejected rather than bloating storage.
  static const maxBytes = 250 * 1024;

  static String? prepare(List<int> bytes) {
    img.Image? decoded;
    try {
      decoded = img.decodeImage(Uint8List.fromList(bytes));
    } catch (_) {
      return null;
    }
    if (decoded == null) return null;
    final longest = decoded.width > decoded.height
        ? decoded.width
        : decoded.height;
    final img.Image resized = longest > maxSide
        ? img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? maxSide : null,
            height: decoded.height > decoded.width ? maxSide : null,
          )
        : decoded;
    List<int> encoded;
    try {
      encoded = img.encodeJpg(resized, quality: jpegQuality);
    } catch (_) {
      return null;
    }
    if (encoded.isEmpty || encoded.length > maxBytes) return null;
    return base64.encode(encoded);
  }
}
