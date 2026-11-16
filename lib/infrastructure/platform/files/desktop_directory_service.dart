import 'dart:io';

import 'package:flutter/services.dart';

class DesktopDirectoryService {
  final MethodChannel _channel;

  const DesktopDirectoryService({this._channel = const MethodChannel('phonolite/directories')});

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
