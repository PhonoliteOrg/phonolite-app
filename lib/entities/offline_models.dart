import 'package:flutter/foundation.dart' show immutable;

import 'models.dart';

enum OfflineDownloadStatus {
  queued,
  preparing,
  downloading,
  paused,
  validating,
  downloaded,
  removing,
  failed,
  corrupt,
  canceled,
}

const Object _offlineUnset = Object();

enum OfflineDeletionScopeKind { track, album, artist }

@immutable
class OfflineDeletionScope {
  const OfflineDeletionScope.track({this.id, this.label})
    : ids = const [],
      kind = OfflineDeletionScopeKind.track;

  const OfflineDeletionScope.album({this.id, this.label})
    : ids = const [],
      kind = OfflineDeletionScopeKind.album;

  const OfflineDeletionScope.artist({this.id, this.label, this.ids = const []})
    : kind = OfflineDeletionScopeKind.artist;

  final OfflineDeletionScopeKind kind;
  final String? id;
  final String? label;
  final List<String> ids;
}

@immutable
class OfflineDeletionRequest {
  const OfflineDeletionRequest({
    required this.scope,
    required this.downloads,
    this.downloadJobIds = const [],
  });

  factory OfflineDeletionRequest.tracks(
    Iterable<OfflineTrackDownload> downloads,
  ) {
    return OfflineDeletionRequest(
      scope: const OfflineDeletionScope.track(),
      downloads: downloads.toList(growable: false),
    );
  }

  final OfflineDeletionScope scope;
  final List<OfflineTrackDownload> downloads;
  final List<String> downloadJobIds;
}

@immutable
class OfflineDeletionResult {
  const OfflineDeletionResult({
    required this.scope,
    this.removedSourceCount = 0,
    this.removedLocalTrackCount = 0,
    this.removedMetadataFragmentCount = 0,
    this.clearedJobMetadataCount = 0,
    this.pendingFileDeleteCount = 0,
    this.pendingArtworkDeleteCount = 0,
  });

  final OfflineDeletionScope scope;
  final int removedSourceCount;
  final int removedLocalTrackCount;
  final int removedMetadataFragmentCount;
  final int clearedJobMetadataCount;
  final int pendingFileDeleteCount;
  final int pendingArtworkDeleteCount;

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
      removedLocalTrackCount:
          removedLocalTrackCount ?? this.removedLocalTrackCount,
      removedMetadataFragmentCount:
          removedMetadataFragmentCount ?? this.removedMetadataFragmentCount,
      clearedJobMetadataCount:
          clearedJobMetadataCount ?? this.clearedJobMetadataCount,
      pendingFileDeleteCount:
          pendingFileDeleteCount ?? this.pendingFileDeleteCount,
      pendingArtworkDeleteCount:
          pendingArtworkDeleteCount ?? this.pendingArtworkDeleteCount,
    );
  }
}

@immutable
class OfflineDownloadBatch {
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

  final String batchId;
  final String serverBaseUrl;
  final OfflineDownloadStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int totalCount;
  final int completedCount;
  final int failedCount;
  final String? label;

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
      label: label == _offlineUnset ? this.label : label as String?,
    );
  }
}

@immutable
class OfflineDownloadJob {
  const OfflineDownloadJob({
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

  OfflineDownloadJob copyWith({
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
      label: label == _offlineUnset ? this.label : label as String?,
      sourceId: sourceId == _offlineUnset ? this.sourceId : sourceId as String?,
      error: error == _offlineUnset ? this.error : error as String?,
    );
  }
}

@immutable
class OfflineDownloadJobItem {
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
      track: track == _offlineUnset ? this.track : track as Track?,
      offlineMetadata: offlineMetadata == _offlineUnset
          ? this.offlineMetadata
          : offlineMetadata as OfflineTrackMetadata?,
      error: error == _offlineUnset ? this.error : error as String?,
    );
  }
}

@immutable
class OfflineDownloadJobSource {
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

  final String jobId;
  final int position;
  final String sourceId;
  final OfflineDownloadStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? label;
  final String? error;

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
      label: label == _offlineUnset ? this.label : label as String?,
      error: error == _offlineUnset ? this.error : error as String?,
    );
  }
}

@immutable
class LocalLikeState {
  const LocalLikeState({
    required this.localTrackId,
    required this.liked,
    required this.updatedAt,
  });

  final String localTrackId;
  final bool liked;
  final int updatedAt;
}

@immutable
class OfflineMetadataRepairRequest {
  const OfflineMetadataRepairRequest({
    required this.serverBaseUrl,
    required this.serverTrackId,
  });

  final String serverBaseUrl;
  final String serverTrackId;
}

@immutable
class OfflineTrackDownload {
  const OfflineTrackDownload({
    required this.serverBaseUrl,
    required this.track,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.offlineMetadata,
    this.batchId,
    this.localTrackId,
    this.downloadUrl,
    this.filePath,
    this.partialPath,
    this.bytesDownloaded = 0,
    this.bytesTotal,
    this.etag,
    this.expectedSha256,
    this.contentType,
    this.error,
    this.retryCount = 0,
    this.priority = 0,
  });

  final String serverBaseUrl;
  final String? batchId;
  final String? localTrackId;
  final Track track;
  final OfflineTrackMetadata? offlineMetadata;
  final OfflineDownloadStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? downloadUrl;
  final String? filePath;
  final String? partialPath;
  final int bytesDownloaded;
  final int? bytesTotal;
  final String? etag;
  final String? expectedSha256;
  final String? contentType;
  final String? error;
  final int retryCount;
  final int priority;

  bool get isDownloaded => status == OfflineDownloadStatus.downloaded;

  bool get isRemoving => status == OfflineDownloadStatus.removing;

  double? get progress {
    final total = bytesTotal;
    if (total == null || total <= 0) {
      return null;
    }
    return (bytesDownloaded / total).clamp(0.0, 1.0);
  }

  OfflineTrackDownload copyWith({
    OfflineDownloadStatus? status,
    DateTime? updatedAt,
    Object? batchId = _offlineUnset,
    Object? localTrackId = _offlineUnset,
    Object? downloadUrl = _offlineUnset,
    Object? filePath = _offlineUnset,
    Object? partialPath = _offlineUnset,
    int? bytesDownloaded,
    Object? bytesTotal = _offlineUnset,
    Object? etag = _offlineUnset,
    Object? expectedSha256 = _offlineUnset,
    Object? contentType = _offlineUnset,
    Object? error = _offlineUnset,
    Object? offlineMetadata = _offlineUnset,
    int? retryCount,
    int? priority,
    Track? track,
  }) {
    return OfflineTrackDownload(
      serverBaseUrl: serverBaseUrl,
      batchId: batchId == _offlineUnset ? this.batchId : batchId as String?,
      localTrackId: localTrackId == _offlineUnset
          ? this.localTrackId
          : localTrackId as String?,
      track: track ?? this.track,
      offlineMetadata: offlineMetadata == _offlineUnset
          ? this.offlineMetadata
          : offlineMetadata as OfflineTrackMetadata?,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      downloadUrl: downloadUrl == _offlineUnset
          ? this.downloadUrl
          : downloadUrl as String?,
      filePath: filePath == _offlineUnset ? this.filePath : filePath as String?,
      partialPath: partialPath == _offlineUnset
          ? this.partialPath
          : partialPath as String?,
      bytesDownloaded: bytesDownloaded ?? this.bytesDownloaded,
      bytesTotal: bytesTotal == _offlineUnset
          ? this.bytesTotal
          : bytesTotal as int?,
      etag: etag == _offlineUnset ? this.etag : etag as String?,
      expectedSha256: expectedSha256 == _offlineUnset
          ? this.expectedSha256
          : expectedSha256 as String?,
      contentType: contentType == _offlineUnset
          ? this.contentType
          : contentType as String?,
      error: error == _offlineUnset ? this.error : error as String?,
      retryCount: retryCount ?? this.retryCount,
      priority: priority ?? this.priority,
    );
  }

  Map<String, dynamic> toJson() => {
    'serverBaseUrl': serverBaseUrl,
    'batchId': batchId,
    'localTrackId': localTrackId,
    'downloadUrl': downloadUrl,
    'track': _trackToJson(track),
    'offlineMetadata': offlineMetadata?.toJson(),
    'status': status.name,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'filePath': filePath,
    'partialPath': partialPath,
    'bytesDownloaded': bytesDownloaded,
    'bytesTotal': bytesTotal,
    'etag': etag,
    'expectedSha256': expectedSha256,
    'contentType': contentType,
    'error': error,
    'retryCount': retryCount,
    'priority': priority,
  };

  static OfflineTrackDownload? fromJson(Map<String, dynamic> json) {
    final serverBaseUrl = json['serverBaseUrl']?.toString() ?? '';
    final rawTrack = json['track'];
    if (serverBaseUrl.trim().isEmpty || rawTrack is! Map) {
      return null;
    }
    final track = Track.fromJson(Map<String, dynamic>.from(rawTrack));
    final rawMetadata = json['offlineMetadata'] ?? json['offline_metadata'];
    return OfflineTrackDownload(
      serverBaseUrl: serverBaseUrl,
      batchId: _optionalString(json['batchId']),
      localTrackId: _optionalString(json['localTrackId']),
      track: track,
      offlineMetadata: rawMetadata is Map
          ? OfflineTrackMetadata.fromJson(
              Map<String, dynamic>.from(rawMetadata),
            )
          : null,
      status: _parseStatus(json['status']),
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
      downloadUrl: _optionalString(json['downloadUrl']),
      filePath: _optionalString(json['filePath']),
      partialPath: _optionalString(json['partialPath']),
      bytesDownloaded: _parseInt(json['bytesDownloaded']),
      bytesTotal: _parseNullableInt(json['bytesTotal']),
      etag: _optionalString(json['etag']),
      expectedSha256: _optionalString(json['expectedSha256']),
      contentType: _optionalString(json['contentType']),
      error: _optionalString(json['error']),
      retryCount: _parseInt(json['retryCount']),
      priority: _parseInt(json['priority']),
    );
  }

  static OfflineDownloadStatus _parseStatus(Object? value) {
    final text = value?.toString();
    for (final status in OfflineDownloadStatus.values) {
      if (status.name == text) {
        return status;
      }
    }
    return OfflineDownloadStatus.queued;
  }

  static DateTime _parseDate(Object? value) {
    final ms = _parseInt(value);
    if (ms <= 0) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static int _parseInt(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int? _parseNullableInt(Object? value) {
    if (value == null) {
      return null;
    }
    final parsed = _parseInt(value);
    return parsed <= 0 ? null : parsed;
  }

  static String? _optionalString(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    return text;
  }

  static Map<String, dynamic> _trackToJson(Track track) => track.toJson();
}
