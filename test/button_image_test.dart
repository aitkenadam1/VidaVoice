import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:onevoz/services/button_image.dart';

/// Builds a solid-color test image of the given size.
List<int> makePng(int w, int h) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(200, 80, 40));
  return img.encodePng(image);
}

void main() {
  test('large photo is downscaled to the max side', () {
    final prepared = ButtonImage.prepare(makePng(2000, 1500));
    expect(prepared, isNotNull);
    final bytes = base64.decode(prepared!);
    // JPEG magic.
    expect(bytes[0], 0xFF);
    expect(bytes[1], 0xD8);
    final decoded = img.decodeImage(bytes)!;
    final longest = decoded.width > decoded.height
        ? decoded.width
        : decoded.height;
    expect(longest, lessThanOrEqualTo(ButtonImage.maxSide));
    expect(bytes.length, lessThanOrEqualTo(ButtonImage.maxBytes));
  });

  test('small image is kept (not upscaled)', () {
    final prepared = ButtonImage.prepare(makePng(100, 60));
    expect(prepared, isNotNull);
    final decoded = img.decodeImage(base64.decode(prepared!))!;
    expect(decoded.width, 100);
    expect(decoded.height, 60);
  });

  test('garbage bytes return null', () {
    expect(ButtonImage.prepare([1, 2, 3, 4]), isNull);
    expect(ButtonImage.prepare([]), isNull);
    expect(ButtonImage.prepare('not an image'.codeUnits), isNull);
  });
}
