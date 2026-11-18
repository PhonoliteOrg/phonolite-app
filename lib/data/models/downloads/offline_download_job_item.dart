import 'package:flutter/foundation.dart' show immutable;

import 'package:phonolite_app/data/models/downloads/download_status.dart';
import 'package:phonolite_app/data/models/downloads/offline_track_metadata.dart';
import 'package:phonolite_app/data/models/library/track.dart';

const Object _offlineUnset = Object();

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
