import 'file_download_stub.dart'
    if (dart.library.html) 'file_download_web.dart' as impl;

Future<void> downloadFile({
  required List<int> bytes,
  required String fileName,
  required String mimeType,
}) async {
  await impl.downloadFileImpl(
    bytes: bytes,
    fileName: fileName,
    mimeType: mimeType,
  );
}
