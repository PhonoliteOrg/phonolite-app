import 'package:flutter/foundation.dart' show immutable;

import 'package:phonolite_app/data/models/downloads/download_status.dart';
import 'package:phonolite_app/data/models/downloads/offline_track_metadata.dart';
import 'package:phonolite_app/data/models/library/track.dart';

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

@immutable
class OfflineDownloadJobItem {
  final String jobId;
  final int position;
  final String serverTrackId;
  final OfflineDownloadStatus status;
  final bool materialized;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Track? track;
  final OfflineTrackMetadata? offlineMetadata;
  final String? error;

  const OfflineDownloadJobItem({
    required this.jobId,
    required this.position,
    required this.serverTrackId,
    required this.status,
    required this.materialized,
    required this.createdAt,
    required this.updatedAt,
    this.track,
    this.offlineMetadata,
    this.error,
  });

  OfflineDownloadJobItem copyWith({
    OfflineDownloadStatus? status,
    bool? materialized,
    DateTime? updatedAt,
    Object? track = _offlineUnset,
    Object? offlineMetadata = _offlineUnset,
    Object? error = _offlineUnset,
  }) {
    return OfflineDownloadJobItem(
      jobId: jobId,
      position: position,
      serverTrackId: serverTrackId,
      status: status ?? this.status,
      materialized: materialized ?? this.materialized,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      track: identical(track, _offlineUnset) ? this.track : track as Track?,
      offlineMetadata: identical(offlineMetadata, _offlineUnset)
          ? this.offlineMetadata
          : offlineMetadata as OfflineTrackMetadata?,
      error: identical(error, _offlineUnset) ? this.error : error as String?,
    );
  }
}

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
