import 'package:phonolite_app/data/models/downloads/offline_track_metadata.dart';
import 'package:phonolite_app/data/structures/serialization/json_values.dart';

class DownloadJobScopeV2 {
  final String kind;
  final String? id;
  final List<String> trackIds;

  DownloadJobScopeV2({required this.kind, this.id, this.trackIds = const []});

  Map<String, dynamic> toJson() => {
    'kind': kind,
    if (id != null && id!.trim().isNotEmpty) 'id': id,
    if (trackIds.isNotEmpty) 'track_ids': trackIds,
  };
}

class DownloadJobV2 {
  final String jobId;
  final String profile;
  final String clientId;
  final String clientRequestId;
  final DownloadJobScopeV2 scope;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int totalCount;
  final int readyCount;
  final int completedCount;
  final int failedCount;
  final int eventCursor;
  final List<DownloadJobItemV2> items;

  DownloadJobV2({
    required this.jobId,
    this.profile = 'original',
    required this.clientId,
    required this.clientRequestId,
    required this.scope,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.totalCount,
    required this.readyCount,
    required this.completedCount,
    required this.failedCount,
    required this.eventCursor,
    required this.items,
  });

  factory DownloadJobV2.fromJson(Map<String, dynamic> json) {
    final rawScope = json['scope'];
    final scopeJson = rawScope is Map ? Map<String, dynamic>.from(rawScope) : const <String, dynamic>{};

    return DownloadJobV2(
      jobId: json['job_id']?.toString() ?? '',
      profile: json['profile']?.toString() ?? 'original',
      clientId: json['client_id']?.toString() ?? '',
      clientRequestId: json['client_request_id']?.toString() ?? '',
      scope: DownloadJobScopeV2(
        kind: scopeJson['kind']?.toString() ?? '',
        id: scopeJson['id']?.toString(),
        trackIds:
            (scopeJson['track_ids'] as List?)?.map((item) => item.toString()).toList(growable: false) ??
            const <String>[],
      ),
      status: json['status']?.toString() ?? 'queued',
      createdAt: JsonValues.downloadDate(json['created_at']),
      updatedAt: JsonValues.downloadDate(json['updated_at']),
      totalCount: _parseV2Int(json['total_count']),
      readyCount: _parseV2Int(json['ready_count']),
      completedCount: _parseV2Int(json['completed_count']),
      failedCount: _parseV2Int(json['failed_count']),
      eventCursor: _parseV2Int(json['event_cursor']),
      items:
          (json['items'] as List?)
              ?.whereType<Map>()
              .map((item) => DownloadJobItemV2.fromJson(Map<String, dynamic>.from(item)))
              .toList(growable: false) ??
          const <DownloadJobItemV2>[],
    );
  }
}

class DownloadJobItemV2 {
  final String profile;
  final String? renditionId;
  final int position;
  final String trackId;
  final String status;
  final String? downloadUrl;
  final OfflineTrackMetadata? offlineMetadata;
  final int? byteLength;
  final String? contentType;
  final String? etag;
  final String? sha256;
  final String? error;

  DownloadJobItemV2({
    this.profile = 'original',
    this.renditionId,
    required this.position,
    required this.trackId,
    required this.status,
    this.downloadUrl,
    this.offlineMetadata,
    this.byteLength,
    this.contentType,
    this.etag,
    this.sha256,
    this.error,
  });

  factory DownloadJobItemV2.fromJson(Map<String, dynamic> json) {
    final rawMetadata = json['offline_metadata'];

    return DownloadJobItemV2(
      profile: json['profile']?.toString() ?? 'original',
      renditionId: JsonValues.nonEmptyString(json['rendition_id']),
      position: _parseV2Int(json['position']),
      trackId: json['track_id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'queued',
      downloadUrl: JsonValues.nonEmptyString(json['download_url']),
      offlineMetadata: rawMetadata is Map
          ? OfflineTrackMetadata.fromJson(Map<String, dynamic>.from(rawMetadata))
          : null,
      byteLength: _parseNullableV2Int(json['byte_length']),
      contentType: JsonValues.nonEmptyString(json['content_type']),
      etag: JsonValues.nonEmptyString(json['etag']),
      sha256: JsonValues.nonEmptyString(json['sha256']),
      error: JsonValues.nonEmptyString(json['error']),
    );
  }

  bool get readyToDownload => status == 'ready_to_download' && offlineMetadata != null;
}

int _parseV2Int(Object? value) {
  if (value is num) {
    return value.toInt();
  }

  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _parseNullableV2Int(Object? value) {
  if (value == null) {
    return null;
  }

  if (value is num) {
    return value.toInt();
  }

  return int.tryParse(value.toString());
}
