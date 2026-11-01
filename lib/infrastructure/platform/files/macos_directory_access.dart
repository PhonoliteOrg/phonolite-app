import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:phonolite_app/data/models/preferences/storage_access_restoration.dart';

class MacosDirectoryAccess {
  final MethodChannel _channel;

  const MacosDirectoryAccess({this._channel = const MethodChannel('phonolite/storage_access')});

  bool get isSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  Future<StorageAccessRestoration> restore() async {
    if (!isSupported) {
      return const StorageAccessRestoration();
    }

    final values = await _channel.invokeMapMethod<Object?, Object?>('restoreDirectories');

    return StorageAccessRestoration.fromPlatform(values ?? const {});
  }

  Future<String?> selectDirectory(String? initialPath) => _channel.invokeMethod<String>('selectDirectory', initialPath);
}
