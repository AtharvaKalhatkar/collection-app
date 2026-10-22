// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:js' as js;

class OcrExtractedText {
  final String fullText;
  final String headerText;
  final String footerText;

  const OcrExtractedText({
    required this.fullText,
    this.headerText = '',
    this.footerText = '',
  });

  bool get isEmpty =>
      fullText.trim().isEmpty &&
      headerText.trim().isEmpty &&
      footerText.trim().isEmpty;
}

class OcrBridge {
  static Future<OcrExtractedText?> extractTextFromBase64(String base64Image) {
    final completer = Completer<OcrExtractedText?>();

    try {
      if (!js.context.hasProperty('extractBillTextFromBase64')) {
        completer.complete(null);
        return completer.future;
      }

      js.context.callMethod('extractBillTextFromBase64', [
        base64Image,
        (dynamic responseJsonStr) {
          try {
            if (responseJsonStr != null) {
              final Map<String, dynamic> data =
                  jsonDecode(responseJsonStr.toString()) as Map<String, dynamic>;
              final full = data['text']?.toString() ?? '';
              final header = data['headerText']?.toString() ?? '';
              final footer = data['footerText']?.toString() ?? '';

              if (full.isNotEmpty || header.isNotEmpty || footer.isNotEmpty) {
                completer.complete(OcrExtractedText(
                  fullText: full,
                  headerText: header,
                  footerText: footer,
                ));
                return;
              }
            }
          } catch (_) {}
          completer.complete(null);
        }
      ]);
    } catch (e) {
      completer.complete(null);
    }

    return completer.future.timeout(
      const Duration(seconds: 40),
      onTimeout: () => null,
    );
  }
}



