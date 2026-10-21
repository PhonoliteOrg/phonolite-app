import 'package:flutter/foundation.dart' show immutable;

import 'package:phonolite_app/data/models/downloads/download_status.dart';
import 'package:phonolite_app/data/models/downloads/offline_track_metadata.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/structures/serialization/json_values.dart';

const Object _offlineUnset = Object();

@immutable
class OfflineTrackDownload {
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
      batchId: JsonValues.nonEmptyString(json['batchId']),
      localTrackId: JsonValues.nonEmptyString(json['localTrackId']),
      track: track,
      offlineMetadata: rawMetadata is Map
          ? OfflineTrackMetadata.fromJson(Map<String, dynamic>.from(rawMetadata))
          : null,
      status: _parseStatus(json['status']),
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
      downloadUrl: JsonValues.nonEmptyString(json['downloadUrl']),
      filePath: JsonValues.nonEmptyString(json['filePath']),
      partialPath: JsonValues.nonEmptyString(json['partialPath']),
      bytesDownloaded: _parseInt(json['bytesDownloaded']),
      bytesTotal: _parseNullableInt(json['bytesTotal']),
      etag: JsonValues.nonEmptyString(json['etag']),
      expectedSha256: JsonValues.nonEmptyString(json['expectedSha256']),
      contentType: JsonValues.nonEmptyString(json['contentType']),
      error: JsonValues.nonEmptyString(json['error']),
      retryCount: _parseInt(json['retryCount']),
      priority: _parseInt(json['priority']),
    );
  }

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
      batchId: identical(batchId, _offlineUnset) ? this.batchId : batchId as String?,
      localTrackId: identical(localTrackId, _offlineUnset) ? this.localTrackId : localTrackId as String?,
      track: track ?? this.track,
      offlineMetadata: identical(offlineMetadata, _offlineUnset)
          ? this.offlineMetadata
          : offlineMetadata as OfflineTrackMetadata?,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      downloadUrl: identical(downloadUrl, _offlineUnset) ? this.downloadUrl : downloadUrl as String?,
      filePath: identical(filePath, _offlineUnset) ? this.filePath : filePath as String?,
      partialPath: identical(partialPath, _offlineUnset) ? this.partialPath : partialPath as String?,
      bytesDownloaded: bytesDownloaded ?? this.bytesDownloaded,
      bytesTotal: identical(bytesTotal, _offlineUnset) ? this.bytesTotal : bytesTotal as int?,
      etag: identical(etag, _offlineUnset) ? this.etag : etag as String?,
      expectedSha256: identical(expectedSha256, _offlineUnset) ? this.expectedSha256 : expectedSha256 as String?,
      contentType: identical(contentType, _offlineUnset) ? this.contentType : contentType as String?,
      error: identical(error, _offlineUnset) ? this.error : error as String?,
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

  static Map<String, dynamic> _trackToJson(Track track) => track.toJson();
}
