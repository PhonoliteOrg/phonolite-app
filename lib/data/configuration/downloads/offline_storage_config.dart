import 'dart:io';

import 'package:phonolite_app/data/storage/offline/library/offline_library.dart';

class OfflineStorageConfig {
  final String? baseDirectory;
  final String? metadataDirectory;
  final String? downloadsDirectory;

  const OfflineStorageConfig({this.baseDirectory, this.metadataDirectory, this.downloadsDirectory});

  factory OfflineStorageConfig.fromStorage(OfflineLibraryStorage storage) {
    return OfflineStorageConfig(
      baseDirectory: storage.baseDirectory?.absolute.path,
      metadataDirectory: storage.metadataDirectory?.absolute.path,
      downloadsDirectory: storage.downloadsDirectory?.absolute.path,
    );
  }

  OfflineLibraryStorage createStorage() {
    return OfflineLibraryStorage(
      keepDatabaseOpen: true,
      baseDirectory: baseDirectory == null ? null : Directory(baseDirectory!),
      metadataDirectory: metadataDirectory == null ? null : Directory(metadataDirectory!),
      downloadsDirectory: downloadsDirectory == null ? null : Directory(downloadsDirectory!),
    );
  }
}
