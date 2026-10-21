import 'package:phonolite_app/data/models/downloads/offline_track_metadata.dart';
import 'package:phonolite_app/data/structures/serialization/json_values.dart';

class DownloadBatchManifest {
  final int schemaVersion;
  final String batchId;
  final DateTime createdAt;
  final List<DownloadBatchItem> items;
  final List<DownloadBatchUnavailable> unavailable;

  DownloadBatchManifest({
    required this.schemaVersion,
    required this.batchId,
    required this.createdAt,
    required this.items,
    required this.unavailable,
  });

  factory DownloadBatchManifest.fromJson(Map<String, dynamic> json) {
    final items =
        (json['items'] as List?)
            ?.whereType<Map>()
            .map((item) => DownloadBatchItem.fromJson(Map<String, dynamic>.from(item)))
            .toList(growable: false) ??
        const <DownloadBatchItem>[];
    final unavailable =
        (json['unavailable'] as List?)
            ?.whereType<Map>()
            .map((item) => DownloadBatchUnavailable.fromJson(Map<String, dynamic>.from(item)))
            .toList(growable: false) ??
        const <DownloadBatchUnavailable>[];

    return DownloadBatchManifest(
      schemaVersion: (json['schema_version'] as num?)?.toInt() ?? 1,
      batchId: json['batch_id']?.toString() ?? '',
      createdAt: JsonValues.downloadDate(json['created_at']),
      items: items,
      unavailable: unavailable,
    );
  }
}

class DownloadBatchItem {
  final String trackId;
  final String downloadUrl;
  final OfflineTrackMetadata offlineMetadata;
  final int byteLength;
  final String contentType;
  final String etag;
  final String sha256;

  DownloadBatchItem({
    required this.trackId,
    required this.downloadUrl,
    required this.offlineMetadata,
    required this.byteLength,
    required this.contentType,
    required this.etag,
    required this.sha256,
  });

  factory DownloadBatchItem.fromJson(Map<String, dynamic> json) {
    return DownloadBatchItem(
      trackId: json['track_id']?.toString() ?? '',
      downloadUrl: json['download_url']?.toString() ?? '',
      offlineMetadata: OfflineTrackMetadata.fromJson(
        Map<String, dynamic>.from(json['offline_metadata'] as Map? ?? const {}),
      ),
      byteLength: (json['byte_length'] as num?)?.toInt() ?? 0,
      contentType: json['content_type']?.toString() ?? 'application/octet-stream',
      etag: json['etag']?.toString() ?? '',
      sha256: json['sha256']?.toString() ?? '',
    );
  }
}

class DownloadBatchUnavailable {
  final String trackId;
  final String reason;

  DownloadBatchUnavailable({required this.trackId, required this.reason});

  factory DownloadBatchUnavailable.fromJson(Map<String, dynamic> json) {
    return DownloadBatchUnavailable(
      trackId: json['track_id']?.toString() ?? '',
      reason: json['reason']?.toString() ?? 'unavailable',
    );
  }
}
