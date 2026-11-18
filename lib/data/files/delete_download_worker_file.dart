import 'dart:io';

Future<void> deleteDownloadWorkerFile(String path) async {
  final file = File(path);

  if (await file.exists()) {
    await file.delete();
  }
}
