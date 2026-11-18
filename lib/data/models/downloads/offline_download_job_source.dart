import 'package:flutter/foundation.dart' show immutable;

import 'package:phonolite_app/data/models/downloads/download_status.dart';

const Object _offlineUnset = Object();

@immutable
class OfflineDownloadJobSource {
  final String jobId;
  final int position;
  final String sourceId;
  final OfflineDownloadStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? label;
  final String? error;

  const OfflineDownloadJobSource({
    required this.jobId,
    required this.position,
    required this.sourceId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.label,
    this.error,
  });

  OfflineDownloadJobSource copyWith({
    OfflineDownloadStatus? status,
    DateTime? updatedAt,
    Object? label = _offlineUnset,
    Object? error = _offlineUnset,
  }) {
    return OfflineDownloadJobSource(
      jobId: jobId,
      position: position,
      sourceId: sourceId,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      label: identical(label, _offlineUnset) ? this.label : label as String?,
      error: identical(error, _offlineUnset) ? this.error : error as String?,
    );
  }
}
