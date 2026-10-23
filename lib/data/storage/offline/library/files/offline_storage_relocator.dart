part of 'package:phonolite_app/data/storage/offline/library/offline_library.dart';

class _OfflineStorageRelocator {
  final OfflineLibraryStorage _host;

  _OfflineStorageRelocator(this._host);

  bool get _usesManagedStoragePaths => _host.baseDirectory == null && _host.settingsStorage.usesManagedStoragePaths;

  Future<OfflineStorageLocations> resolveStorageLocations() async {
    if (_usesManagedStoragePaths) {
      final defaultRoot = await _defaultOfflineRoot();

      await _host.settingsStorage.read();

      return OfflineStorageLocations(
        metadataDirectory: defaultRoot.path,
        downloadsDirectory: defaultRoot.path,
        metadataDirectoryIsDefault: true,
        downloadsDirectoryIsDefault: true,
      );
    }

    final settings = _host.baseDirectory == null && _host.metadataDirectory == null && _host.downloadsDirectory == null
        ? await _host.settingsStorage.read()
        : const OfflineStorageSettings();
    final configuredMetadata = _host.metadataDirectory?.absolute.path ?? settings.metadataDirectory;
    final configuredDownloads = _host.downloadsDirectory?.absolute.path ?? settings.downloadsDirectory;
    final defaultRoot = configuredMetadata == null || configuredDownloads == null ? await _defaultOfflineRoot() : null;
    final metadataPath = configuredMetadata ?? defaultRoot!.path;
    final downloadsPath = configuredDownloads ?? defaultRoot!.path;

    return OfflineStorageLocations(
      metadataDirectory: metadataPath,
      downloadsDirectory: downloadsPath,
      metadataDirectoryIsDefault: configuredMetadata == null,
      downloadsDirectoryIsDefault: configuredDownloads == null,
    );
  }

  Future<void> updateStorageLocations({
    Object? metadataDirectory = OfflineLibraryStorage._storageUnset,
    Object? downloadsDirectory = OfflineLibraryStorage._storageUnset,
  }) async {
    if (kIsWeb) {
      return;
    }

    if (_usesManagedStoragePaths) {
      await _host.settingsStorage.write(const OfflineStorageSettings());

      return;
    }

    final current = await _host.settingsStorage.read();

    await _host.close();

    final currentLocations = await _host.resolveStorageLocations();
    var next = current;

    if (metadataDirectory != OfflineLibraryStorage._storageUnset) {
      next = next.copyWith(metadataDirectory: _normalizeConfiguredDirectory(metadataDirectory as String?));
    }

    if (downloadsDirectory != OfflineLibraryStorage._storageUnset) {
      next = next.copyWith(downloadsDirectory: _normalizeConfiguredDirectory(downloadsDirectory as String?));
    }

    final defaultRoot = await _defaultOfflineRoot();
    final nextMetadataPath = next.metadataDirectory ?? defaultRoot.path;

    if (currentLocations.metadataDirectory != nextMetadataPath) {
      await _copyMetadataFilesIfNeeded(
        fromDirectory: Directory(currentLocations.metadataDirectory),
        toDirectory: Directory(nextMetadataPath),
      );
    }

    if (next.downloadsDirectory != null) {
      await Directory(next.downloadsDirectory!).create(recursive: true);
    }

    await _host.settingsStorage.write(next);
  }

  Future<void> migrateManagedStoragePathsIfNeeded() async {
    if (kIsWeb || !_usesManagedStoragePaths) {
      return;
    }

    final legacy = await _host.settingsStorage.readRaw();
    final legacyMetadataPath = legacy.metadataDirectory;
    final legacyDownloadsPath = legacy.downloadsDirectory;

    if (legacyMetadataPath == null && legacyDownloadsPath == null) {
      return;
    }

    final defaultRoot = await _defaultOfflineRoot();

    if (legacyMetadataPath != null) {
      try {
        await _copyMetadataFilesIfNeeded(fromDirectory: Directory(legacyMetadataPath), toDirectory: defaultRoot);
      } catch (err) {
        AppLogger.warning('Failed to migrate managed offline metadata storage: $err');
      }
    }

    if (legacyDownloadsPath != null) {
      try {
        await _copyServerDownloadDirectoriesIfNeeded(
          fromDirectory: Directory(legacyDownloadsPath),
          toDirectory: defaultRoot,
        );
      } catch (err) {
        AppLogger.warning('Failed to migrate managed offline download storage: $err');
      }
    }

    try {
      await _host.settingsStorage.write(const OfflineStorageSettings());
    } catch (err) {
      AppLogger.warning('Failed to clear migrated offline storage settings: $err');
    }
  }

  Future<Directory> _defaultOfflineRoot() async {
    final base = await _resolveBaseDirectory();

    return Directory(_host._join(base.path, OfflineLibraryStorage._rootDirName));
  }

  Future<Directory> _resolveBaseDirectory() async {
    final override = _host.baseDirectory;
    if (override != null) {
      return override;
    }

    final provider = _host.defaultDirectoryProvider;
    if (provider != null) {
      return provider();
    }

    if (Platform.isWindows) {
      return WindowsAppStorage.directory() ?? await getApplicationSupportDirectory();
    }

    final supportDir = await getApplicationSupportDirectory();

    return Directory(_host._join(supportDir.path, 'Phonolite'));
  }

  Future<void> _copyMetadataFilesIfNeeded({required Directory fromDirectory, required Directory toDirectory}) async {
    if (fromDirectory.absolute.path == toDirectory.absolute.path) {
      return;
    }

    await toDirectory.create(recursive: true);

    for (final fileName in [OfflineLibraryStorage._databaseFileName, OfflineLibraryStorage._indexFileName]) {
      final source = File(_host._join(fromDirectory.path, fileName));

      if (!await source.exists()) {
        continue;
      }

      final target = File(_host._join(toDirectory.path, fileName));

      if (await target.exists()) {
        continue;
      }

      await source.copy(target.path);
    }

    await _copyDirectoryIfNeeded(
      fromDirectory: Directory(_host._join(fromDirectory.path, OfflineLibraryStorage._artDirName)),
      toDirectory: Directory(_host._join(toDirectory.path, OfflineLibraryStorage._artDirName)),
    );
  }

  Future<void> _copyServerDownloadDirectoriesIfNeeded({
    required Directory fromDirectory,
    required Directory toDirectory,
  }) async {
    if (fromDirectory.absolute.path == toDirectory.absolute.path || !(await fromDirectory.exists())) {
      return;
    }

    await toDirectory.create(recursive: true);

    await for (final entity in fromDirectory.list(recursive: false)) {
      if (entity is! Directory) {
        continue;
      }

      final name = entity.path.split(Platform.pathSeparator).last;

      if (!name.startsWith('server_')) {
        continue;
      }

      await _copyDirectoryIfNeeded(fromDirectory: entity, toDirectory: Directory(_host._join(toDirectory.path, name)));
    }
  }

  Future<void> _copyDirectoryIfNeeded({required Directory fromDirectory, required Directory toDirectory}) async {
    if (!await fromDirectory.exists()) {
      return;
    }

    await toDirectory.create(recursive: true);

    await for (final entity in fromDirectory.list(recursive: false)) {
      final name = entity.path.split(Platform.pathSeparator).last;

      if (name.isEmpty) {
        continue;
      }

      final targetPath = _host._join(toDirectory.path, name);

      if (entity is Directory) {
        await _copyDirectoryIfNeeded(fromDirectory: entity, toDirectory: Directory(targetPath));
      } else if (entity is File) {
        final target = File(targetPath);

        if (!await target.exists()) {
          await entity.copy(target.path);
        }
      }
    }
  }

  String? _normalizeConfiguredDirectory(String? value) {
    final trimmed = value?.trim();

    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }

    return Directory(trimmed).absolute.path;
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _OfflineStorageRelocatorFacade {
  _OfflineStorageRelocator get _ownerLocations;

  Future<OfflineStorageLocations> resolveStorageLocations() => _ownerLocations.resolveStorageLocations();

  Future<void> updateStorageLocations({
    Object? metadataDirectory = OfflineLibraryStorage._storageUnset,
    Object? downloadsDirectory = OfflineLibraryStorage._storageUnset,
  }) => _ownerLocations.updateStorageLocations(
    metadataDirectory: metadataDirectory,
    downloadsDirectory: downloadsDirectory,
  );

  Future<void> migrateManagedStoragePathsIfNeeded() => _ownerLocations.migrateManagedStoragePathsIfNeeded();
}
