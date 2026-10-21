import 'dart:io';

import 'package:crypto/crypto.dart';

Future<String> hashDownloadFile(String path) async {
  final digest = await sha256.bind(File(path).openRead()).first;

  return digest.toString().toLowerCase();
}

Future<void> deleteDownloadWorkerFile(String path) async {
  final file = File(path);

  if (await file.exists()) {
    await file.delete();
  }
}
