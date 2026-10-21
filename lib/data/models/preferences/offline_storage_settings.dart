import 'dart:io';

import 'package:flutter/foundation.dart';

const _offlineStorageUnset = Object();

@immutable
class OfflineStorageSettings {
  final String? metadataDirectory;
  final String? downloadsDirectory;

  const OfflineStorageSettings({this.metadataDirectory, this.downloadsDirectory});

  static OfflineStorageSettings fromJson(Map<String, dynamic> json) {
    return OfflineStorageSettings(
      metadataDirectory: _optionalPath(json['metadata_directory']),
      downloadsDirectory: _optionalPath(json['downloads_directory']),
    );
  }

  OfflineStorageSettings copyWith({
    Object? metadataDirectory = _offlineStorageUnset,
    Object? downloadsDirectory = _offlineStorageUnset,
  }) {
    return OfflineStorageSettings(
      metadataDirectory: identical(metadataDirectory, _offlineStorageUnset)
          ? this.metadataDirectory
          : metadataDirectory as String?,
      downloadsDirectory: identical(downloadsDirectory, _offlineStorageUnset)
          ? this.downloadsDirectory
          : downloadsDirectory as String?,
    );
  }

  Map<String, dynamic> toJson() => {'metadata_directory': metadataDirectory, 'downloads_directory': downloadsDirectory};

  static String? _optionalPath(Object? value) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty) {
      return null;
    }

    return Directory(text).absolute.path;
  }
}
