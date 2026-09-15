import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../services/button_image.dart';

/// Caregiver-readable failure from the photo picker.
class ButtonImageException implements Exception {
  ButtonImageException(this.message);
  final String message;

  @override
  String toString() => 'ButtonImageException: $message';
}

/// Opens the photo picker and returns the picked image prepared for button
/// storage (downscaled, base64). Returns null when the caregiver cancels.
/// Throws [ButtonImageException] with a plain-language message when the
/// picked file can't be used.
Future<String?> pickButtonImage() async {
  final List<PlatformFile> files;
  try {
    files = await FilePicker.pickFiles(type: FileType.image);
  } catch (e) {
    throw ButtonImageException('Could not open the photo picker: $e');
  }
  if (files.isEmpty) return null; // user cancelled
  Uint8List bytes;
  try {
    bytes = await files.single.readAsBytes();
  } catch (e) {
    throw ButtonImageException('Could not read that photo: $e');
  }
  if (bytes.isEmpty) {
    throw ButtonImageException('That photo is empty — try another one.');
  }
  final prepared = ButtonImage.prepare(bytes);
  if (prepared == null) {
    throw ButtonImageException(
      'That file could not be used as a button image — '
      'try a JPG or PNG photo.',
    );
  }
  return prepared;
}
