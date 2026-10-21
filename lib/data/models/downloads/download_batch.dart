import 'package:flutter/foundation.dart' show immutable;

import 'package:phonolite_app/data/models/downloads/download_status.dart';

const Object _offlineUnset = Object();

@immutable
class OfflineDownloadBatch {
  final String batchId;
  final String serverBaseUrl;
  final OfflineDownloadStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int totalCount;
  final int completedCount;
  final int failedCount;
  final String? label;

  const OfflineDownloadBatch({
    required this.batchId,
    required this.serverBaseUrl,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.totalCount,
    this.completedCount = 0,
    this.failedCount = 0,
    this.label,
  });

  OfflineDownloadBatch copyWith({
    OfflineDownloadStatus? status,
    DateTime? updatedAt,
    int? totalCount,
    int? completedCount,
    int? failedCount,
    Object? label = _offlineUnset,
  }) {
    return OfflineDownloadBatch(
      batchId: batchId,
      serverBaseUrl: serverBaseUrl,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      totalCount: totalCount ?? this.totalCount,
      completedCount: completedCount ?? this.completedCount,
      failedCount: failedCount ?? this.failedCount,
      label: identical(label, _offlineUnset) ? this.label : label as String?,
    );
  }
}
