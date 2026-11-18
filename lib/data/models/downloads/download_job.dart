import 'package:flutter/foundation.dart' show immutable;

import 'package:phonolite_app/data/models/downloads/download_status.dart';

const Object _offlineUnset = Object();

@immutable
class OfflineDownloadJob {
  final String profile;
  final String? serverJobId;
  final String jobId;
  final String kind;
  final String serverBaseUrl;
  final OfflineDownloadStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int totalCount;
  final int discoveredCount;
  final int completedCount;
  final int failedCount;
  final int materializedCount;
  final int sourceCursor;
  final String? label;
  final String? sourceId;
  final String? error;

  const OfflineDownloadJob({
    this.profile = 'original',
    this.serverJobId,
    required this.jobId,
    required this.kind,
    required this.serverBaseUrl,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.totalCount = 0,
    this.discoveredCount = 0,
    this.completedCount = 0,
    this.failedCount = 0,
    this.materializedCount = 0,
    this.sourceCursor = 0,
    this.label,
    this.sourceId,
    this.error,
  });

  OfflineDownloadJob copyWith({
    String? profile,
    Object? serverJobId = _offlineUnset,
    OfflineDownloadStatus? status,
    DateTime? updatedAt,
    int? totalCount,
    int? discoveredCount,
    int? completedCount,
    int? failedCount,
    int? materializedCount,
    int? sourceCursor,
    Object? label = _offlineUnset,
    Object? sourceId = _offlineUnset,
    Object? error = _offlineUnset,
  }) {
    return OfflineDownloadJob(
      profile: profile ?? this.profile,
      serverJobId: identical(serverJobId, _offlineUnset) ? this.serverJobId : serverJobId as String?,
      jobId: jobId,
      kind: kind,
      serverBaseUrl: serverBaseUrl,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      totalCount: totalCount ?? this.totalCount,
      discoveredCount: discoveredCount ?? this.discoveredCount,
      completedCount: completedCount ?? this.completedCount,
      failedCount: failedCount ?? this.failedCount,
      materializedCount: materializedCount ?? this.materializedCount,
      sourceCursor: sourceCursor ?? this.sourceCursor,
      label: identical(label, _offlineUnset) ? this.label : label as String?,
      sourceId: identical(sourceId, _offlineUnset) ? this.sourceId : sourceId as String?,
      error: identical(error, _offlineUnset) ? this.error : error as String?,
    );
  }
}
