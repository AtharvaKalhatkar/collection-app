// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:typed_data';
import 'package:url_launcher/url_launcher.dart';

Future<void> shareOrDownloadImageImpl(
  Uint8List imageBytes, {
  String filename = 'bill_image.jpg',
  String title = 'Bill Photo',
}) async {
  // 1. Try Native Web Share API with Files (Android Chrome, Safari on iOS)
  // This opens the system share sheet with WhatsApp directly at the top!
  bool sharedSuccessfully = false;
  try {
    final nav = js.context['navigator'];
    if (nav != null && nav.hasProperty('canShare')) {
      final file = html.File([imageBytes], filename, {'type': 'image/jpeg'});
      final shareData = js.JsObject.jsify({
        'files': [file],
        'title': title,
        'text': title,
      });

      final canShare = nav.callMethod('canShare', [shareData]);
      if (canShare == true) {
        nav.callMethod('share', [shareData]);
        sharedSuccessfully = true;
        return;
      }
    }
  } catch (e) {
    final errStr = e.toString().toLowerCase();
    // If user explicitly dismissed or cancelled the share dialog, respect their action
    if (errStr.contains('abort') || errStr.contains('cancel')) {
      return;
    }
  }

  // 2. Fallback for Desktop browsers or browsers without Web Share files support:
  if (!sharedSuccessfully) {
    // Save HD image to downloads
    _triggerDownload(imageBytes, filename);

    // Open WhatsApp so the user can send to any contact
    try {
      final text = Uri.encodeComponent('$title\n(HD Bill photo saved to your gallery/downloads)');
      final waUri = Uri.parse('whatsapp://send?text=$text');
      final waWebUri = Uri.parse('https://api.whatsapp.com/send?text=$text');
      if (await canLaunchUrl(waUri)) {
        await launchUrl(waUri, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(waWebUri)) {
        await launchUrl(waWebUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }
}

void _triggerDownload(Uint8List imageBytes, String filename) {
  try {
    final blob = html.Blob([imageBytes], 'image/jpeg');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..target = '_blank';
    anchor.click();
    Future.delayed(const Duration(seconds: 2), () {
      html.Url.revokeObjectUrl(url);
    });
  } catch (_) {}
}
