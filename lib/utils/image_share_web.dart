// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

Future<void> shareOrDownloadImageImpl(
  Uint8List imageBytes, {
  String filename = 'bill_image.jpg',
  String title = 'Bill Photo',
}) async {
  try {
    final blob = html.Blob([imageBytes], 'image/jpeg');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..target = '_blank';
    anchor.click();
    // Allow brief time for browser to register download click before revoking
    await Future.delayed(const Duration(seconds: 1));
    html.Url.revokeObjectUrl(url);
  } catch (_) {}
}
