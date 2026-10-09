import 'dart:convert';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

class ImageCompressHelper {
  /// Compresses raw image bytes to an HD crystal-clear JPEG base64 string.
  /// Preserves ultra-sharp text and numbers on paper bills while keeping document size safe.
  static String compressToBase64(Uint8List rawBytes, {int maxDimension = 2048, int quality = 88}) {
    // If the image is already lightweight (<= 600 KB), directly encode to preserve 100% original sharpness
    // and avoid lossy pure-Dart CPU decoding on mobile browsers
    if (rawBytes.lengthInBytes <= 600000) {
      return base64Encode(rawBytes);
    }

    try {
      final decoded = img.decodeImage(rawBytes);
      if (decoded == null) {
        return base64Encode(rawBytes);
      }

      img.Image processed = decoded;

      // Downscale only if dimensions exceed maxDimension (2048px ensures pin-sharp invoice text)
      if (processed.width > maxDimension || processed.height > maxDimension) {
        if (processed.width >= processed.height) {
          processed = img.copyResize(processed, width: maxDimension, interpolation: img.Interpolation.cubic);
        } else {
          processed = img.copyResize(processed, height: maxDimension, interpolation: img.Interpolation.cubic);
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
