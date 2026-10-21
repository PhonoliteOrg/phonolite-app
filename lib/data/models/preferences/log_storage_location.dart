import 'package:flutter/foundation.dart' show immutable;

@immutable
class LogStorageLocation {
  final String directory;
  final bool isDefault;

  const LogStorageLocation({required this.directory, required this.isDefault});

  @override
  bool operator ==(Object other) =>
      other is LogStorageLocation &&
      runtimeType == other.runtimeType &&
      directory == other.directory &&
      isDefault == other.isDefault;

  @override
  int get hashCode => Object.hash(runtimeType, directory, isDefault);
}
