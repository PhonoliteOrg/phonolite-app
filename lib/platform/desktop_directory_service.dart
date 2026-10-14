import 'dart:io';

import 'package:flutter/services.dart';

class DesktopDirectoryService {
  const DesktopDirectoryService({
    MethodChannel channel = const MethodChannel('phonolite/directories'),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<void> openDirectory(String path) async {
    if (path.isEmpty) {
      throw ArgumentError.value(path, 'path', 'A folder path is required.');
    }
    final directory = Directory(path).absolute;
    // A storage location may not exist yet before the first download.
    await directory.create(recursive: true);
    await _channel.invokeMethod<void>('openDirectory', directory.path);
  }
}
