import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

Future<void> shareOrDownloadImageImpl(
  Uint8List imageBytes, {
  String filename = 'bill_image.jpg',
  String title = 'Bill Photo',
}) async {
  try {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(12),
        build: (pw.Context context) {
          return pw.Center(
            child: pw.Image(
              pw.MemoryImage(imageBytes),
              fit: pw.BoxFit.contain,
            ),
          );
        },
      ),
    );
    await Printing.sharePdf(
      bytes: await doc.save(),
      filename: filename.endsWith('.pdf') ? filename : '$filename.pdf',
    );
  } catch (_) {}
}
