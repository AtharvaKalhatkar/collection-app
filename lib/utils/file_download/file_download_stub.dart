import 'dart:typed_data';
import 'package:printing/printing.dart';

Future<void> downloadFileImpl({
  required List<int> bytes,
  required String fileName,
  required String mimeType,
}) async {
  try {
    await Printing.sharePdf(
      bytes: Uint8List.fromList(bytes),
      filename: fileName,
    );
  } catch (_) {
    // Graceful fallback if share cannot be invoked
  }
}
