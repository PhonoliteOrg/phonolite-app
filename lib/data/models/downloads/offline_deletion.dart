import 'package:flutter/foundation.dart' show immutable;

import 'package:phonolite_app/data/models/downloads/offline_track_download.dart';

enum OfflineDeletionScopeKind { track, album, artist }

@immutable
class OfflineDeletionScope {
  final OfflineDeletionScopeKind kind;
  final String? id;
  final String? label;
  final List<String> ids;

  const OfflineDeletionScope.track({this.id, this.label}) : ids = const [], kind = OfflineDeletionScopeKind.track;

  const OfflineDeletionScope.album({this.id, this.label}) : ids = const [], kind = OfflineDeletionScopeKind.album;

  const OfflineDeletionScope.artist({this.id, this.label, this.ids = const []})
    : kind = OfflineDeletionScopeKind.artist;
}

@immutable
class OfflineDeletionRequest {
  final OfflineDeletionScope scope;
  final List<OfflineTrackDownload> downloads;
  final List<String> downloadJobIds;

  const OfflineDeletionRequest({required this.scope, required this.downloads, this.downloadJobIds = const []});

  factory OfflineDeletionRequest.tracks(Iterable<OfflineTrackDownload> downloads) {
    return OfflineDeletionRequest(
      scope: const OfflineDeletionScope.track(),
      downloads: downloads.toList(growable: false),
    );
  }
}

@immutable
class OfflineDeletionResult {
  final OfflineDeletionScope scope;
  final int removedSourceCount;
  final int removedLocalTrackCount;
  final int removedMetadataFragmentCount;
  final int clearedJobMetadataCount;
  final int pendingFileDeleteCount;
  final int pendingArtworkDeleteCount;

  const OfflineDeletionResult({
    required this.scope,
    this.removedSourceCount = 0,
    this.removedLocalTrackCount = 0,
    this.removedMetadataFragmentCount = 0,
    this.clearedJobMetadataCount = 0,
    this.pendingFileDeleteCount = 0,
    this.pendingArtworkDeleteCount = 0,
  });

  OfflineDeletionResult copyWith({
    int? removedSourceCount,
    int? removedLocalTrackCount,
    int? removedMetadataFragmentCount,
    int? clearedJobMetadataCount,
    int? pendingFileDeleteCount,
    int? pendingArtworkDeleteCount,
  }) {
    return OfflineDeletionResult(
      scope: scope,
      removedSourceCount: removedSourceCount ?? this.removedSourceCount,
      removedLocalTrackCount: removedLocalTrackCount ?? this.removedLocalTrackCount,
      removedMetadataFragmentCount: removedMetadataFragmentCount ?? this.removedMetadataFragmentCount,
      clearedJobMetadataCount: clearedJobMetadataCount ?? this.clearedJobMetadataCount,
      pendingFileDeleteCount: pendingFileDeleteCount ?? this.pendingFileDeleteCount,
      pendingArtworkDeleteCount: pendingArtworkDeleteCount ?? this.pendingArtworkDeleteCount,
    );
  }
}
