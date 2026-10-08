import 'dart:convert';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

class ImageCompressHelper {
  /// Compresses raw image bytes to a high-efficiency JPEG base64 string (typically ~25-45 KB).
  /// This prevents localStorage quota overflow on Web and speeds up sync/rendering.
  static String compressToBase64(Uint8List rawBytes, {int maxDimension = 650, int quality = 60}) {
    // If the image is already lightweight (<= 300 KB), directly encode to avoid heavy pure-Dart CPU
    // decoding and Out-Of-Memory crashes on mobile browsers (which caused reload to blue screen)
    if (rawBytes.lengthInBytes <= 300000) {
      return base64Encode(rawBytes);
    }

    try {
      final decoded = img.decodeImage(rawBytes);
      if (decoded == null) {
        return base64Encode(rawBytes);
      }

      img.Image processed = decoded;

      // Downscale if dimensions exceed maxDimension
      if (processed.width > maxDimension || processed.height > maxDimension) {
        if (processed.width >= processed.height) {
          processed = img.copyResize(processed, width: maxDimension);
        } else {
          processed = img.copyResize(processed, height: maxDimension);
        }
      }

      final jpgBytes = img.encodeJpg(processed, quality: quality);
      return base64Encode(jpgBytes);
    } catch (_) {
      // Fallback to raw base64 if decoding fails
      return base64Encode(rawBytes);
    }
  }

  /// Safely decodes base64 strings, stripping any data URI prefix or whitespace.
  /// Returns null if string is empty, invalid, or corrupted.
  static Uint8List? safeBase64Decode(String? input) {
    if (input == null) return null;
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    try {
      String clean = trimmed;
      if (clean.contains('base64,')) {
        clean = clean.split('base64,').last;
      }
      clean = clean.replaceAll('\n', '').replaceAll('\r', '').replaceAll(' ', '');
      return base64Decode(clean);
    } catch (_) {
      return null;
    }
  }
}
