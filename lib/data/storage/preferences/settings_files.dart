import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:phonolite_app/data/storage/windows_app_storage.dart';

/// Resolves settings files without owning their formats or error policies.
///
/// [directoryProvider] returns the settings directory itself, allowing tests
/// and alternate hosts to keep persistence away from the user's profile.
class SettingsFiles {
  final Future<Directory> Function()? directoryProvider;
  final bool cacheFirst;

  const SettingsFiles({this.cacheFirst = false, this.directoryProvider});

  Future<File> resolve(String name, {bool createDirectory = false}) async {
    final directory = await (directoryProvider?.call() ?? defaultDirectory(cacheFirst: cacheFirst));

    if (createDirectory) {
      await directory.create(recursive: true);
    }

    return File(_join(directory.path, name));
  }

  /// The settings directory used when no [directoryProvider] is given.
  ///
  /// Windows keeps settings under Roaming AppData, falling back to the support
  /// directory when `APPDATA` is unset. Other platforms use a `Phonolite`
  /// folder in the support directory, or in the cache directory first when
  /// [cacheFirst] is set and the cache is available.
  static Future<Directory> defaultDirectory({
    bool cacheFirst = false,
    String? operatingSystem,
    Map<String, String>? environment,
    Future<Directory> Function()? cacheDirectoryProvider,
    Future<Directory> Function()? supportDirectoryProvider,
  }) async {
    final supportDirectory = supportDirectoryProvider ?? getApplicationSupportDirectory;

    if ((operatingSystem ?? Platform.operatingSystem) == 'windows') {
      return WindowsAppStorage.directory(environment: environment) ?? await supportDirectory();
    }

    if (cacheFirst) {
      try {
        final cache = await (cacheDirectoryProvider ?? getApplicationCacheDirectory)();

        return Directory(_join(cache.path, 'Phonolite'));
      } catch (_) {
        // Preserve the legacy shuffle-settings fallback policy.
      }
    }

    final support = await supportDirectory();

    return Directory(_join(support.path, 'Phonolite'));
  }

  static String _join(String directory, String name) {
    if (directory.isEmpty || directory.endsWith(Platform.pathSeparator)) {
      return '$directory$name';
    }

    return '$directory${Platform.pathSeparator}$name';
  }
}
