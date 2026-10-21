import 'package:flutter/foundation.dart' show immutable;

@immutable
class OfflineStorageLocations {
  final String metadataDirectory;
  final String downloadsDirectory;
  final bool metadataDirectoryIsDefault;
  final bool downloadsDirectoryIsDefault;

  const OfflineStorageLocations({
    required this.metadataDirectory,
    required this.downloadsDirectory,
    required this.metadataDirectoryIsDefault,
    required this.downloadsDirectoryIsDefault,
  });
}
