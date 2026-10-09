import 'dart:typed_data';
import 'image_share_stub.dart' if (dart.library.html) 'image_share_web.dart';

class ImageShareHelper {
  /// Shares the image using native system share sheet (WhatsApp, Telegram, etc.)
  /// or downloads to device if system share sheet is unavailable.
  static Future<void> shareOrDownloadImage(
    Uint8List imageBytes, {
    String filename = 'bill_photo.jpg',
    String title = 'Bill Photo',
  }) async {
    await shareOrDownloadImageImpl(imageBytes, filename: filename, title: title);
  }
}
