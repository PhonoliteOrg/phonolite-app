import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Resolves settings files without owning their formats or error policies.
///
/// [directoryProvider] returns the settings directory itself, allowing tests
/// and alternate hosts to keep persistence away from the user's profile.
class SettingsFiles {
  final Future<Directory> Function()? directoryProvider;
  final bool cacheFirst;

  const SettingsFiles({this.cacheFirst = false, this.directoryProvider});

  Future<File> resolve(String name, {bool createDirectory = false}) async {
    final directory = await (directoryProvider?.call() ?? _defaultDirectory());

    if (createDirectory) {
      await directory.create(recursive: true);
    }

    return File(_join(directory.path, name));
  }

  Future<Directory> _defaultDirectory() async {
    if (cacheFirst) {
      try {
        final cache = await getApplicationCacheDirectory();

        return Directory(_join(cache.path, 'Phonolite'));
      } catch (_) {
        // Preserve the legacy shuffle-settings fallback policy.
      }
    }

    if (Platform.isWindows) {
      final appData = cacheFirst ? Platform.environment['LOCALAPPDATA'] : Platform.environment['APPDATA'];

      if (appData != null && appData.trim().isNotEmpty) {
        return Directory(_join(appData, 'Phonolite'));
      }
    }

    final support = await getApplicationSupportDirectory();

    return Directory(_join(support.path, 'Phonolite'));
  }

  String _join(String directory, String name) {
    if (directory.isEmpty || directory.endsWith(Platform.pathSeparator)) {
      return '$directory$name';
    }

    return '$directory${Platform.pathSeparator}$name';
  }
}
