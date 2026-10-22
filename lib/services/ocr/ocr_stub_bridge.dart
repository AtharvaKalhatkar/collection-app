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
  static Future<OcrExtractedText?> extractTextFromBase64(String base64Image) async {
    return null;
  }
}

