import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'app_log.dart';
import 'models.dart';
import 'offline_storage_settings.dart';

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
    : kind = OfflineDeletionScopeKind.track;

  const OfflineDeletionScope.album({this.id, this.label})
    : kind = OfflineDeletionScopeKind.album;

  const OfflineDeletionScope.artist({this.id, this.label})
    : kind = OfflineDeletionScopeKind.artist;

  final OfflineDeletionScopeKind kind;
  final String? id;
  final String? label;
}

@immutable
class OfflineDeletionRequest {
  const OfflineDeletionRequest({required this.scope, required this.downloads});

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

class _OfflineDeletionDraft {
  _OfflineDeletionDraft({required this.scope});

  final OfflineDeletionScope scope;
  final Set<String> pendingFileDeletes = <String>{};
  int removedSourceCount = 0;
  int removedLocalTrackCount = 0;
  int removedMetadataFragmentCount = 0;
  int clearedJobMetadataCount = 0;

  OfflineDeletionResult toResult({
    required int pendingFileDeleteCount,
    required int pendingArtworkDeleteCount,
  }) {
    return OfflineDeletionResult(
      scope: scope,
      removedSourceCount: removedSourceCount,
      removedLocalTrackCount: removedLocalTrackCount,
      removedMetadataFragmentCount: removedMetadataFragmentCount,
      clearedJobMetadataCount: clearedJobMetadataCount,
      pendingFileDeleteCount: pendingFileDeleteCount,
      pendingArtworkDeleteCount: pendingArtworkDeleteCount,
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
class ServerLikeSync {
  const ServerLikeSync({
    required this.localTrackId,
    required this.serverBaseUrl,
    required this.serverTrackId,
    required this.matchConfidence,
    required this.matchKind,
    required this.lastLocalLiked,
    required this.lastLocalUpdatedAt,
    required this.lastServerLiked,
    required this.lastServerUpdatedAt,
    required this.syncedAt,
  });

  final String localTrackId;
  final String serverBaseUrl;
  final String serverTrackId;
  final double matchConfidence;
  final String matchKind;
  final bool lastLocalLiked;
  final int lastLocalUpdatedAt;
  final bool lastServerLiked;
  final int lastServerUpdatedAt;
  final int syncedAt;
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

class OfflineLibraryStorage {
  const OfflineLibraryStorage({
    this.baseDirectory,
    this.metadataDirectory,
    this.downloadsDirectory,
    this.settingsStorage = const OfflineStorageSettingsStorage(),
  });

  final Directory? baseDirectory;
  final Directory? metadataDirectory;
  final Directory? downloadsDirectory;
  final OfflineStorageSettingsStorage settingsStorage;

  static const String _rootDirName = 'offline';
  static const String _tracksDirName = 'tracks';
  static const String _artDirName = 'art';
  static const String _albumArtDirName = 'albums';
  static const String _artistArtDirName = 'artists';
  static const String _indexFileName = 'offline_library.json';
  static const String _databaseFileName = 'phonolite_offline.sqlite';
  static const String _partialExtension = 'part';
  static const int _schemaVersion = 8;
  static const Object _storageUnset = Object();

  Future<OfflineStorageLocations> resolveStorageLocations() async {
    final defaultRoot = await _defaultOfflineRoot();
    final settings =
        baseDirectory == null &&
            metadataDirectory == null &&
            downloadsDirectory == null
        ? await settingsStorage.read()
        : const OfflineStorageSettings();
    final configuredMetadata =
        metadataDirectory?.absolute.path ?? settings.metadataDirectory;
    final configuredDownloads =
        downloadsDirectory?.absolute.path ?? settings.downloadsDirectory;
    final metadataPath = configuredMetadata ?? defaultRoot.path;
    final downloadsPath = configuredDownloads ?? defaultRoot.path;
    return OfflineStorageLocations(
      metadataDirectory: metadataPath,
      downloadsDirectory: downloadsPath,
      metadataDirectoryIsDefault: configuredMetadata == null,
      downloadsDirectoryIsDefault: configuredDownloads == null,
    );
  }

  Future<void> updateStorageLocations({
    Object? metadataDirectory = _storageUnset,
    Object? downloadsDirectory = _storageUnset,
  }) async {
    if (kIsWeb) {
      return;
    }
    final current = await settingsStorage.read();
    final currentLocations = await resolveStorageLocations();
    var next = current;
    if (metadataDirectory != _storageUnset) {
      next = next.copyWith(
        metadataDirectory: _normalizeConfiguredDirectory(
          metadataDirectory as String?,
        ),
      );
    }
    if (downloadsDirectory != _storageUnset) {
      next = next.copyWith(
        downloadsDirectory: _normalizeConfiguredDirectory(
          downloadsDirectory as String?,
        ),
      );
    }
    final defaultRoot = await _defaultOfflineRoot();
    final nextMetadataPath = next.metadataDirectory ?? defaultRoot.path;
    if (currentLocations.metadataDirectory != nextMetadataPath) {
      await _copyMetadataFilesIfNeeded(
        fromDirectory: Directory(currentLocations.metadataDirectory),
        toDirectory: Directory(nextMetadataPath),
      );
    }
    if (next.downloadsDirectory != null) {
      await Directory(next.downloadsDirectory!).create(recursive: true);
    }
    await settingsStorage.write(next);
  }

  Future<void> resetLocalData() async {
    if (kIsWeb) {
      return;
    }
    try {
      final locations = await resolveStorageLocations();
      final metadataDir = Directory(locations.metadataDirectory);
      final downloadsDir = Directory(locations.downloadsDirectory);
      await _deleteOfflineMetadataFiles(metadataDir);
      await _deleteOfflineDownloadFiles(downloadsDir);
    } catch (err) {
      AppLogger.warning('Failed to reset offline storage: $err');
      rethrow;
    }
  }

  Future<List<OfflineTrackDownload>> readDownloads() async {
    if (kIsWeb) {
      return const [];
    }
    Database? db;
    try {
      db = await _openDatabase();
      return _readDownloads(db);
    } catch (err) {
      AppLogger.warning('Failed to read offline library: $err');
      return const [];
    } finally {
      db?.dispose();
    }
  }

  Future<String> readOrCreateClientId() async {
    if (kIsWeb) {
      return 'web';
    }
    final db = await _openDatabase();
    try {
      final rows = db.select(
        'SELECT value FROM client_identity WHERE key = ? LIMIT 1',
        ['client_id'],
      );
      if (rows.isNotEmpty) {
        final existing = rows.first['value']?.toString().trim();
        if (existing != null && existing.isNotEmpty) {
          return existing;
        }
      }
      final clientId = _generateClientId();
      db.execute(
        'INSERT OR REPLACE INTO client_identity (key, value, updated_at) VALUES (?, ?, ?)',
        ['client_id', clientId, DateTime.now().millisecondsSinceEpoch],
      );
      return clientId;
    } finally {
      db.dispose();
    }
  }

  Future<List<OfflineDownloadBatch>> readDownloadBatches() async {
    if (kIsWeb) {
      return const [];
    }
    Database? db;
    try {
      db = await _openDatabase();
      return _readDownloadBatches(db);
    } catch (err) {
      AppLogger.warning('Failed to read offline download batches: $err');
      return const [];
    } finally {
      db?.dispose();
    }
  }

  Future<List<OfflineDownloadJob>> readDownloadJobs() async {
    if (kIsWeb) {
      return const [];
    }
    Database? db;
    try {
      db = await _openDatabase();
      return _readDownloadJobs(db);
    } catch (err) {
      AppLogger.warning('Failed to read offline download jobs: $err');
      return const [];
    } finally {
      db?.dispose();
    }
  }

  Future<List<OfflineDownloadJobItem>> readDownloadJobItems(
    String jobId,
  ) async {
    if (kIsWeb) {
      return const [];
    }
    Database? db;
    try {
      db = await _openDatabase();
      return _readDownloadJobItems(db, jobId);
    } catch (err) {
      AppLogger.warning('Failed to read offline download job items: $err');
      return const [];
    } finally {
      db?.dispose();
    }
  }

  Future<List<OfflineDownloadJobItem>> readDownloadJobItemsLean(
    String jobId,
  ) async {
    if (kIsWeb) {
      return const [];
    }
    Database? db;
    try {
      developer.Timeline.startSync('offline.sqlite.readJobItemsLean');
      db = await _openDatabase();
      return _readDownloadJobItems(db, jobId, includeTrackJson: false);
    } catch (err) {
      AppLogger.warning('Failed to read offline download job items: $err');
      return const [];
    } finally {
      developer.Timeline.finishSync();
      db?.dispose();
    }
  }

  Future<List<OfflineDownloadJobItem>> readDownloadJobItemsForTracks(
    String jobId,
    Iterable<String> serverTrackIds,
  ) async {
    if (kIsWeb) {
      return const [];
    }
    final ids = serverTrackIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    if (ids.isEmpty) {
      return const [];
    }
    Database? db;
    try {
      developer.Timeline.startSync('offline.sqlite.readJobItemsWindow');
      db = await _openDatabase();
      return _readDownloadJobItemsForTracks(db, jobId, ids);
    } catch (err) {
      AppLogger.warning(
        'Failed to read offline download job item window: $err',
      );
      return const [];
    } finally {
      developer.Timeline.finishSync();
      db?.dispose();
    }
  }

  Future<List<OfflineDownloadJobSource>> readDownloadJobSources(
    String jobId,
  ) async {
    if (kIsWeb) {
      return const [];
    }
    Database? db;
    try {
      db = await _openDatabase();
      return _readDownloadJobSources(db, jobId);
    } catch (err) {
      AppLogger.warning('Failed to read offline download job sources: $err');
      return const [];
    } finally {
      db?.dispose();
    }
  }

  Future<void> upsertDownloadBatch(OfflineDownloadBatch batch) async {
    if (kIsWeb) {
      return;
    }
    Database? db;
    try {
      db = await _openDatabase();
      _upsertDownloadBatch(db, batch);
    } catch (err) {
      AppLogger.warning('Failed to persist offline download batch: $err');
    } finally {
      db?.dispose();
    }
  }

  Future<void> upsertDownloadJob(OfflineDownloadJob job) async {
    if (kIsWeb) {
      return;
    }
    Database? db;
    try {
      db = await _openDatabase();
      _upsertDownloadJob(db, job);
    } catch (err) {
      AppLogger.warning('Failed to persist offline download job: $err');
    } finally {
      db?.dispose();
    }
  }

  Future<void> upsertDownloadJobs(List<OfflineDownloadJob> jobs) async {
    if (kIsWeb || jobs.isEmpty) {
      return;
    }
    Database? db;
    try {
      db = await _openDatabase();
      _transaction(db, () {
        for (final job in jobs) {
          _upsertDownloadJob(db!, job);
        }
      });
    } catch (err) {
      AppLogger.warning('Failed to persist offline download jobs: $err');
    } finally {
      db?.dispose();
    }
  }

  Future<void> upsertDownloadJobItems(
    List<OfflineDownloadJobItem> items,
  ) async {
    if (kIsWeb || items.isEmpty) {
      return;
    }
    Database? db;
    try {
      db = await _openDatabase();
      _transaction(db, () {
        for (final item in items) {
          _upsertDownloadJobItem(db!, item);
        }
      });
    } catch (err) {
      AppLogger.warning('Failed to persist offline download job items: $err');
    } finally {
      db?.dispose();
    }
  }

  Future<void> upsertDownloadJobSources(
    List<OfflineDownloadJobSource> sources,
  ) async {
    if (kIsWeb || sources.isEmpty) {
      return;
    }
    Database? db;
    try {
      db = await _openDatabase();
      _transaction(db, () {
        for (final source in sources) {
          _upsertDownloadJobSource(db!, source);
        }
      });
    } catch (err) {
      AppLogger.warning('Failed to persist offline download job sources: $err');
    } finally {
      db?.dispose();
    }
  }

  Future<void> deleteDownloadBatch(String batchId) async {
    if (kIsWeb) {
      return;
    }
    Database? db;
    try {
      db = await _openDatabase();
      db.execute('DELETE FROM download_batches WHERE batch_id = ?', [batchId]);
    } catch (err) {
      AppLogger.warning('Failed to delete offline download batch: $err');
    } finally {
      db?.dispose();
    }
  }

  Future<void> deleteDownloadJob(String jobId) async {
    if (kIsWeb) {
      return;
    }
    final trimmed = jobId.trim();
    if (trimmed.isEmpty) {
      return;
    }
    Database? db;
    try {
      final database = await _openDatabase();
      db = database;
      _transaction(database, () {
        database.execute('DELETE FROM download_job_items WHERE job_id = ?', [
          trimmed,
        ]);
        database.execute('DELETE FROM download_job_sources WHERE job_id = ?', [
          trimmed,
        ]);
        database.execute('DELETE FROM download_jobs WHERE job_id = ?', [
          trimmed,
        ]);
        database.execute('DELETE FROM download_batches WHERE batch_id = ?', [
          trimmed,
        ]);
      });
    } catch (err) {
      AppLogger.warning('Failed to delete offline download job: $err');
    } finally {
      db?.dispose();
    }
  }

  Future<void> recordPendingFileDeletes(Iterable<String?> paths) async {
    if (kIsWeb) {
      return;
    }
    final deleteRoots = await _managedDeleteRootPaths();
    final pendingPaths = paths
        .map((path) => _managedPendingDeletePath(path, deleteRoots))
        .whereType<String>()
        .toSet()
        .toList(growable: false);
    if (pendingPaths.isEmpty) {
      return;
    }
    Database? db;
    try {
      db = await _openDatabase();
      _transaction(db, () {
        _recordPendingFileDeletes(
          db!,
          pendingPaths,
          DateTime.now().millisecondsSinceEpoch,
        );
      });
    } catch (err) {
      AppLogger.warning('Failed to record pending file deletes: $err');
    } finally {
      db?.dispose();
    }
  }

  Future<bool> isManagedDeletePath(String path) async {
    if (kIsWeb) {
      return false;
    }
    final deleteRoots = await _managedDeleteRootPaths();
    return _managedPendingDeletePath(path, deleteRoots) != null;
  }

  Future<List<String>> readPendingFileDeletes() async {
    if (kIsWeb) {
      return const [];
    }
    Database? db;
    try {
      db = await _openDatabase();
      return db
          .select(
            'SELECT path FROM pending_file_deletes ORDER BY created_at, path',
          )
          .map((row) => _readString(row, 'path'))
          .where((path) => path.trim().isNotEmpty)
          .toList(growable: false);
    } catch (err) {
      AppLogger.warning('Failed to read pending file deletes: $err');
      return const [];
    } finally {
      db?.dispose();
    }
  }

  Future<void> clearPendingFileDeletes(Iterable<String> paths) async {
    if (kIsWeb) {
      return;
    }
    final pendingPaths = paths
        .map(_pendingDeletePath)
        .whereType<String>()
        .toSet()
        .toList(growable: false);
    if (pendingPaths.isEmpty) {
      return;
    }
    Database? db;
    try {
      db = await _openDatabase();
      _transaction(db, () {
        for (final path in pendingPaths) {
          db!.execute('DELETE FROM pending_file_deletes WHERE path = ?', [
            path,
          ]);
        }
      });
    } catch (err) {
      AppLogger.warning('Failed to clear pending file deletes: $err');
    } finally {
      db?.dispose();
    }
  }

  Future<void> removeDownloads(Iterable<OfflineTrackDownload> downloads) async {
    await removeDownloadsScoped(OfflineDeletionRequest.tracks(downloads));
  }

  Future<OfflineDeletionResult> removeDownloadsScoped(
    OfflineDeletionRequest request,
  ) async {
    if (kIsWeb) {
      return OfflineDeletionResult(scope: request.scope);
    }
    final byKey = <String, OfflineTrackDownload>{};
    for (final download in request.downloads) {
      byKey[_sourceKey(download.serverBaseUrl, _serverTrackId(download))] =
          download;
    }
    final removals = byKey.values.toList(growable: false);
    if (removals.isEmpty) {
      return OfflineDeletionResult(scope: request.scope);
    }

    Database? db;
    try {
      final deleteRoots = await _managedDeleteRootPaths();
      db = await _openDatabase();
      late _OfflineDeletionDraft draft;
      _transaction(db, () {
        draft = _removeDownloadsInTransaction(
          db!,
          request.scope,
          removals,
          deleteRoots,
        );
      });
      final artworkDeletes = await _unusedArtworkFiles(db, deleteRoots);
      final pendingDeletes = <String>{
        ...draft.pendingFileDeletes,
        ...artworkDeletes,
      };
      if (pendingDeletes.isNotEmpty) {
        _transaction(db, () {
          _recordPendingFileDeletes(
            db!,
            pendingDeletes,
            DateTime.now().millisecondsSinceEpoch,
            deleteRoots: deleteRoots,
          );
        });
      }
      return draft.toResult(
        pendingFileDeleteCount: pendingDeletes.length,
        pendingArtworkDeleteCount: artworkDeletes.length,
      );
    } catch (err) {
      AppLogger.warning('Failed to remove offline downloads: $err');
      return OfflineDeletionResult(scope: request.scope);
    } finally {
      db?.dispose();
    }
  }

  _OfflineDeletionDraft _removeDownloadsInTransaction(
    Database db,
    OfflineDeletionScope scope,
    List<OfflineTrackDownload> removals,
    List<String> deleteRoots,
  ) {
    final draft = _OfflineDeletionDraft(scope: scope);
    final localTrackIds = <String>{};
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final download in removals) {
      final serverTrackId = _serverTrackId(download);
      final rows = db.select(
        '''
        SELECT
          s.local_track_id,
          s.file_path,
          s.partial_path,
          t.album_art_path,
          t.artist_art_path,
          t.artist_banner_path
        FROM source_tracks s
        LEFT JOIN tracks t ON t.id = s.local_track_id
        WHERE s.server_base_url = ? AND s.server_track_id = ?
      ''',
        [download.serverBaseUrl, serverTrackId],
      );
      for (final row in rows) {
        localTrackIds.add(_readString(row, 'local_track_id'));
        _addPendingDeletePath(
          draft.pendingFileDeletes,
          _readNullableString(row, 'file_path'),
          deleteRoots,
        );
        _addPendingDeletePath(
          draft.pendingFileDeletes,
          _readNullableString(row, 'partial_path'),
          deleteRoots,
        );
      }
      _addPendingDeletePath(
        draft.pendingFileDeletes,
        download.filePath,
        deleteRoots,
      );
      _addPendingDeletePath(
        draft.pendingFileDeletes,
        download.partialPath,
        deleteRoots,
      );

      draft.removedMetadataFragmentCount += db
          .select(
            '''
            SELECT 1
            FROM offline_metadata_fragments
            WHERE server_base_url = ? AND server_track_id = ?
          ''',
            [download.serverBaseUrl, serverTrackId],
          )
          .length;

      db.execute(
        'DELETE FROM source_tracks WHERE server_base_url = ? AND server_track_id = ?',
        [download.serverBaseUrl, serverTrackId],
      );
      db.execute(
        'DELETE FROM download_items WHERE server_base_url = ? AND server_track_id = ?',
        [download.serverBaseUrl, serverTrackId],
      );
      db.execute(
        'DELETE FROM offline_metadata_fragments WHERE server_base_url = ? AND server_track_id = ?',
        [download.serverBaseUrl, serverTrackId],
      );
      final jobRows = db.select(
        '''
        SELECT i.job_id
        FROM download_job_items i
        JOIN download_jobs j ON j.job_id = i.job_id
        WHERE j.server_base_url = ?
          AND i.server_track_id = ?
          AND (i.track_json IS NOT NULL OR i.metadata_json IS NOT NULL)
      ''',
        [download.serverBaseUrl, serverTrackId],
      );
      draft.clearedJobMetadataCount += jobRows.length;
      db.execute(
        '''
        UPDATE download_job_items
        SET track_json = NULL,
            metadata_json = NULL,
            updated_at = ?
        WHERE server_track_id = ?
          AND job_id IN (
            SELECT job_id FROM download_jobs WHERE server_base_url = ?
          )
      ''',
        [now, serverTrackId, download.serverBaseUrl],
      );
      draft.removedSourceCount += rows.isEmpty ? 0 : rows.length;
    }

    for (final localTrackId in localTrackIds) {
      final rows = db.select(
        '''
        SELECT id
        FROM tracks t
        WHERE t.id = ?
          AND NOT EXISTS (
            SELECT 1
            FROM source_tracks s
            WHERE s.local_track_id = t.id
          )
      ''',
        [localTrackId],
      );
      if (rows.isEmpty) {
        continue;
      }
      db.execute('DELETE FROM tracks WHERE id = ?', [localTrackId]);
      draft.removedLocalTrackCount += 1;
    }

    _pruneUnavailableLocalUserData(db);
    return draft;
  }

  Future<void> writeDownloads(List<OfflineTrackDownload> downloads) async {
    if (kIsWeb) {
      return;
    }
    Database? db;
    try {
      db = await _openDatabase();
      _transaction(db, () {
        final existing = db!.select(
          'SELECT server_base_url, server_track_id FROM source_tracks',
        );
        final nextKeys = downloads
            .map(
              (item) => _sourceKey(
                item.serverBaseUrl,
                item.track.serverTrackId ?? item.track.id,
              ),
            )
            .toSet();
        for (final row in existing) {
          final key = _sourceKey(
            _readString(row, 'server_base_url'),
            _readString(row, 'server_track_id'),
          );
          if (!nextKeys.contains(key)) {
            db.execute(
              'DELETE FROM source_tracks WHERE server_base_url = ? AND server_track_id = ?',
              [
                _readString(row, 'server_base_url'),
                _readString(row, 'server_track_id'),
              ],
            );
            db.execute(
              'DELETE FROM download_items WHERE server_base_url = ? AND server_track_id = ?',
              [
                _readString(row, 'server_base_url'),
                _readString(row, 'server_track_id'),
              ],
            );
            db.execute(
              'DELETE FROM offline_metadata_fragments WHERE server_base_url = ? AND server_track_id = ?',
              [
                _readString(row, 'server_base_url'),
                _readString(row, 'server_track_id'),
              ],
            );
          }
        }
        for (final download in downloads) {
          _upsertDownload(db, download);
        }
        _pruneUnavailableLocalUserData(db);
      });
    } catch (err) {
      AppLogger.warning('Failed to persist offline library: $err');
    } finally {
      db?.dispose();
    }
  }

  Future<OfflineTrackDownload> prepareDownload(
    OfflineTrackDownload download,
  ) async {
    if (kIsWeb) {
      return download;
    }
    Database? db;
    try {
      db = await _openDatabase();
      final localTrackId = _resolveLocalTrackId(db, download.track);
      return _withLocalTrack(download, localTrackId);
    } catch (err) {
      AppLogger.warning('Failed to prepare offline metadata: $err');
      return download;
    } finally {
      db?.dispose();
    }
  }

  Future<List<OfflineTrackDownload>> prepareDownloads(
    List<OfflineTrackDownload> downloads,
  ) async {
    if (kIsWeb || downloads.isEmpty) {
      return downloads;
    }
    Database? db;
    try {
      db = await _openDatabase();
      return downloads
          .map((download) {
            final localTrackId = _resolveLocalTrackId(db!, download.track);
            return _withLocalTrack(download, localTrackId);
          })
          .toList(growable: false);
    } catch (err) {
      AppLogger.warning('Failed to prepare offline metadata batch: $err');
      return downloads;
    } finally {
      db?.dispose();
    }
  }

  Future<void> upsertDownload(OfflineTrackDownload download) async {
    if (kIsWeb) {
      return;
    }
    Database? db;
    try {
      db = await _openDatabase();
      _transaction(db, () {
        _upsertDownload(db!, download);
        _pruneUnavailableLocalUserData(db);
      });
    } catch (err) {
      AppLogger.warning('Failed to upsert offline download: $err');
    } finally {
      db?.dispose();
    }
  }

  Future<void> updateTrackArtPaths(
    String localTrackId, {
    String? albumArtPath,
    String? artistArtPath,
    String? artistBannerPath,
  }) async {
    if (kIsWeb) {
      return;
    }
    if (albumArtPath == null &&
        artistArtPath == null &&
        artistBannerPath == null) {
      return;
    }
    Database? db;
    try {
      db = await _openDatabase();
      db.execute(
        '''
        UPDATE tracks
        SET album_art_path = COALESCE(?, album_art_path),
            artist_art_path = COALESCE(?, artist_art_path),
            artist_banner_path = COALESCE(?, artist_banner_path),
            updated_at = ?
        WHERE id = ?
      ''',
        [
          albumArtPath,
          artistArtPath,
          artistBannerPath,
          DateTime.now().millisecondsSinceEpoch,
          localTrackId,
        ],
      );
    } catch (err) {
      AppLogger.warning('Failed to update offline artwork metadata: $err');
    } finally {
      db?.dispose();
    }
  }

  Future<void> upsertDownloads(List<OfflineTrackDownload> downloads) async {
    if (kIsWeb || downloads.isEmpty) {
      return;
    }
    Database? db;
    try {
      db = await _openDatabase();
      _transaction(db, () {
        for (final download in downloads) {
          _upsertDownload(db!, download);
        }
        _pruneUnavailableLocalUserData(db!);
      });
    } catch (err) {
      AppLogger.warning('Failed to upsert offline downloads: $err');
    } finally {
      db?.dispose();
    }
  }

  Future<List<Track>> readLocalDownloadedTracks() async {
    if (kIsWeb) {
      return const [];
    }
    Database? db;
    try {
      db = await _openDatabase();
      return _readLocalTracks(db, whereDownloaded: true);
    } catch (err) {
      AppLogger.warning('Failed to read local downloaded tracks: $err');
      return const [];
    } finally {
      db?.dispose();
    }
  }

  Future<List<Track>> readLocalLikedTracks() async {
    if (kIsWeb) {
      return const [];
    }
    Database? db;
    try {
      db = await _openDatabase();
      final rows = db.select(
        '''
        SELECT t.*, s.server_base_url, s.server_track_id
        FROM tracks t
        JOIN local_likes l ON l.local_track_id = t.id
        LEFT JOIN source_tracks s ON s.local_track_id = t.id
          AND s.status = ?
          AND s.file_path IS NOT NULL
        WHERE EXISTS (
          SELECT 1 FROM source_tracks ds
          WHERE ds.local_track_id = t.id
            AND ds.status = ?
            AND ds.file_path IS NOT NULL
        )
        GROUP BY t.id
        ORDER BY l.created_at DESC, t.artist, t.album, t.disc_no, t.track_no, t.title
      ''',
        [
          OfflineDownloadStatus.downloaded.name,
          OfflineDownloadStatus.downloaded.name,
        ],
      );
      return rows
          .map(
            (row) => _trackFromRow(
              row,
              liked: true,
              inPlaylists: _trackInLocalPlaylists(db!, _readString(row, 'id')),
            ),
          )
          .toList(growable: false);
    } catch (err) {
      AppLogger.warning('Failed to read local liked tracks: $err');
      return const [];
    } finally {
      db?.dispose();
    }
  }

  Future<List<LocalLikeState>> readLocalLikeStates() async {
    if (kIsWeb) {
      return const [];
    }
    Database? db;
    try {
      db = await _openDatabase();
      final rows = db.select(
        '''
        SELECT s.local_track_id, s.liked, s.updated_at
        FROM local_like_states s
        WHERE EXISTS (
          SELECT 1 FROM source_tracks ds
          WHERE ds.local_track_id = s.local_track_id
            AND ds.status = ?
            AND ds.file_path IS NOT NULL
        )
      ''',
        [OfflineDownloadStatus.downloaded.name],
      );
      return rows
          .map(
            (row) => LocalLikeState(
              localTrackId: _readString(row, 'local_track_id'),
              liked: _readBool(row, 'liked'),
              updatedAt: _readInt(row, 'updated_at'),
            ),
          )
          .toList(growable: false);
    } catch (err) {
      AppLogger.warning('Failed to read local like states: $err');
      return const [];
    } finally {
      db?.dispose();
    }
  }

  Future<List<ServerLikeSync>> readServerLikeSyncs(String serverBaseUrl) async {
    if (kIsWeb) {
      return const [];
    }
    Database? db;
    try {
      db = await _openDatabase();
      final rows = db.select(
        '''
        SELECT *
        FROM server_like_syncs
        WHERE server_base_url = ?
      ''',
        [serverBaseUrl],
      );
      return rows.map(_serverLikeSyncFromRow).toList(growable: false);
    } catch (err) {
      AppLogger.warning('Failed to read server like syncs: $err');
      return const [];
    } finally {
      db?.dispose();
    }
  }

  Future<void> upsertServerLikeSyncs(List<ServerLikeSync> syncs) async {
    if (kIsWeb || syncs.isEmpty) {
      return;
    }
    Database? db;
    try {
      db = await _openDatabase();
      _transaction(db, () {
        for (final sync in syncs) {
          db!.execute(
            '''
            INSERT INTO server_like_syncs (
              local_track_id,
              server_base_url,
              server_track_id,
              match_confidence,
              match_kind,
              last_local_liked,
              last_local_updated_at,
              last_server_liked,
              last_server_updated_at,
              synced_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(local_track_id, server_base_url) DO UPDATE SET
              server_track_id = excluded.server_track_id,
              match_confidence = excluded.match_confidence,
              match_kind = excluded.match_kind,
              last_local_liked = excluded.last_local_liked,
              last_local_updated_at = excluded.last_local_updated_at,
              last_server_liked = excluded.last_server_liked,
              last_server_updated_at = excluded.last_server_updated_at,
              synced_at = excluded.synced_at
          ''',
            [
              sync.localTrackId,
              sync.serverBaseUrl,
              sync.serverTrackId,
              sync.matchConfidence,
              sync.matchKind,
              sync.lastLocalLiked ? 1 : 0,
              sync.lastLocalUpdatedAt,
              sync.lastServerLiked ? 1 : 0,
              sync.lastServerUpdatedAt,
              sync.syncedAt,
            ],
          );
        }
      });
    } finally {
      db?.dispose();
    }
  }

  Future<List<OfflineMetadataRepairRequest>> readMetadataRepairRequests(
    String serverBaseUrl, {
    int limit = 32,
  }) async {
    if (kIsWeb) {
      return const [];
    }
    Database? db;
    try {
      db = await _openDatabase();
      final rows = db.select(
        '''
        SELECT s.server_base_url, s.server_track_id
        FROM source_tracks s
        LEFT JOIN offline_metadata_fragments f
          ON f.server_base_url = s.server_base_url
         AND f.server_track_id = s.server_track_id
        WHERE s.server_base_url = ?
          AND s.status = ?
          AND s.file_path IS NOT NULL
          AND (
            f.schema_version IS NULL
            OR f.schema_version < ?
            OR f.track_json IS NULL
            OR f.album_json IS NULL
            OR f.artist_json IS NULL
            OR trim(f.track_json) = ''
            OR trim(f.album_json) = ''
            OR trim(f.artist_json) = ''
            OR json_valid(f.track_json) = 0
            OR json_valid(f.album_json) = 0
            OR json_valid(f.artist_json) = 0
          )
        ORDER BY s.updated_at DESC
        LIMIT ?
      ''',
        [
          serverBaseUrl,
          OfflineDownloadStatus.downloaded.name,
          OfflineTrackMetadata.currentSchemaVersion,
          limit,
        ],
      );
      return rows
          .map(
            (row) => OfflineMetadataRepairRequest(
              serverBaseUrl: _readString(row, 'server_base_url'),
              serverTrackId: _readString(row, 'server_track_id'),
            ),
          )
          .toList(growable: false);
    } catch (err) {
      AppLogger.warning('Failed to read offline metadata repair queue: $err');
      return const [];
    } finally {
      db?.dispose();
    }
  }

  Future<void> upsertOfflineMetadataFragment(
    String serverBaseUrl,
    String serverTrackId,
    OfflineTrackMetadata metadata,
  ) async {
    if (kIsWeb) {
      return;
    }
    Database? db;
    try {
      db = await _openDatabase();
      final rows = db.select(
        '''
        SELECT local_track_id
        FROM source_tracks
        WHERE server_base_url = ?
          AND server_track_id = ?
        LIMIT 1
      ''',
        [serverBaseUrl, serverTrackId],
      );
      if (rows.isEmpty) {
        return;
      }
      final localTrackId = _readString(rows.first, 'local_track_id');
      final track = metadata.track.copyWith(
        id: serverTrackId,
        localId: localTrackId,
        serverBaseUrl: serverBaseUrl,
        serverTrackId: serverTrackId,
      );
      _transaction(db, () {
        _upsertTrack(db!, localTrackId, track);
        _upsertOfflineMetadataFragmentRaw(
          db,
          serverBaseUrl: serverBaseUrl,
          serverTrackId: serverTrackId,
          localTrackId: localTrackId,
          metadata: metadata.copyWith(track: track),
        );
      });
    } finally {
      db?.dispose();
    }
  }

  Future<List<Playlist>> readLocalPlaylists() async {
    if (kIsWeb) {
      return const [];
    }
    Database? db;
    try {
      db = await _openDatabase();
      return _readLocalPlaylists(db);
    } catch (err) {
      AppLogger.warning('Failed to read local playlists: $err');
      return const [];
    } finally {
      db?.dispose();
    }
  }

  Future<List<Track>> readLocalPlaylistTracks(String playlistId) async {
    if (kIsWeb) {
      return const [];
    }
    Database? db;
    try {
      db = await _openDatabase();
      final rows = db.select(
        '''
        SELECT t.*, s.server_base_url, s.server_track_id
        FROM local_playlist_tracks pt
        JOIN tracks t ON t.id = pt.local_track_id
        LEFT JOIN source_tracks s ON s.local_track_id = t.id
          AND s.status = ?
          AND s.file_path IS NOT NULL
        WHERE pt.playlist_id = ?
          AND EXISTS (
            SELECT 1 FROM source_tracks ds
            WHERE ds.local_track_id = t.id
              AND ds.status = ?
              AND ds.file_path IS NOT NULL
          )
        GROUP BY t.id
        ORDER BY pt.position, pt.rowid
      ''',
        [
          OfflineDownloadStatus.downloaded.name,
          playlistId,
          OfflineDownloadStatus.downloaded.name,
        ],
      );
      return rows
          .map(
            (row) => _trackFromRow(
              row,
              liked: _trackIsLocallyLiked(db!, _readString(row, 'id')),
              inPlaylists: true,
            ),
          )
          .toList(growable: false);
    } catch (err) {
      AppLogger.warning('Failed to read local playlist tracks: $err');
      return const [];
    } finally {
      db?.dispose();
    }
  }

  Future<Playlist> createLocalPlaylist(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('name is required');
    }
    Database? db;
    try {
      db = await _openDatabase();
      final now = DateTime.now().millisecondsSinceEpoch;
      final id = _stableId('playlist|$trimmed|$now');
      _transaction(db, () {
        db!.execute(
          'INSERT INTO local_playlists (id, name, created_at, updated_at) VALUES (?, ?, ?, ?)',
          [id, trimmed, now, now],
        );
      });
      return Playlist(id: id, name: trimmed, trackIds: const []);
    } finally {
      db?.dispose();
    }
  }

  Future<Playlist?> renameLocalPlaylist(String playlistId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('name is required');
    }
    Database? db;
    try {
      db = await _openDatabase();
      final now = DateTime.now().millisecondsSinceEpoch;
      _transaction(db, () {
        db!.execute(
          'UPDATE local_playlists SET name = ?, updated_at = ? WHERE id = ?',
          [trimmed, now, playlistId],
        );
      });
      final playlists = _readLocalPlaylists(db);
      for (final playlist in playlists) {
        if (playlist.id == playlistId) {
          return playlist;
        }
      }
      return null;
    } finally {
      db?.dispose();
    }
  }

  Future<void> deleteLocalPlaylist(String playlistId) async {
    Database? db;
    try {
      db = await _openDatabase();
      _transaction(db, () {
        db!.execute('DELETE FROM local_playlist_tracks WHERE playlist_id = ?', [
          playlistId,
        ]);
        db.execute('DELETE FROM local_playlists WHERE id = ?', [playlistId]);
      });
    } finally {
      db?.dispose();
    }
  }

  Future<void> setLocalLike(String localTrackId, bool liked) async {
    Database? db;
    try {
      db = await _openDatabase();
      _requireDownloadedLocalTrack(db, localTrackId);
      final now = DateTime.now().millisecondsSinceEpoch;
      _transaction(db, () {
        _writeLocalLikeState(db!, localTrackId, liked, now);
      });
    } finally {
      db?.dispose();
    }
  }

  Future<void> applySyncedLocalLikeState(
    String localTrackId,
    bool liked,
    int updatedAt,
  ) async {
    Database? db;
    try {
      db = await _openDatabase();
      _requireDownloadedLocalTrack(db, localTrackId);
      _transaction(db, () {
        _writeLocalLikeState(db!, localTrackId, liked, updatedAt);
      });
    } finally {
      db?.dispose();
    }
  }

  Future<Playlist?> addLocalTrackToPlaylist(
    String playlistId,
    String localTrackId,
  ) async {
    Database? db;
    try {
      db = await _openDatabase();
      _requireDownloadedLocalTrack(db, localTrackId);
      final count =
          db.select(
                'SELECT COUNT(*) AS count FROM local_playlist_tracks WHERE playlist_id = ?',
                [playlistId],
              ).first['count']
              as int;
      _transaction(db, () {
        db!.execute(
          'INSERT OR IGNORE INTO local_playlist_tracks (playlist_id, local_track_id, position) VALUES (?, ?, ?)',
          [playlistId, localTrackId, count],
        );
        db.execute('UPDATE local_playlists SET updated_at = ? WHERE id = ?', [
          DateTime.now().millisecondsSinceEpoch,
          playlistId,
        ]);
      });
      return _readLocalPlaylists(
        db,
      ).where((item) => item.id == playlistId).firstOrNull;
    } finally {
      db?.dispose();
    }
  }

  Future<Playlist?> removeLocalTrackFromPlaylist(
    String playlistId,
    String localTrackId,
  ) async {
    Database? db;
    try {
      db = await _openDatabase();
      _transaction(db, () {
        db!.execute(
          'DELETE FROM local_playlist_tracks WHERE playlist_id = ? AND local_track_id = ?',
          [playlistId, localTrackId],
        );
        db.execute('UPDATE local_playlists SET updated_at = ? WHERE id = ?', [
          DateTime.now().millisecondsSinceEpoch,
          playlistId,
        ]);
      });
      return _readLocalPlaylists(
        db,
      ).where((item) => item.id == playlistId).firstOrNull;
    } finally {
      db?.dispose();
    }
  }

  Future<File> trackFile({
    required String serverBaseUrl,
    required String trackId,
    String extension = 'audio',
  }) async {
    final dir = await _trackDirectory(serverBaseUrl, createDir: true);
    final safeExtension = _safePathToken(extension).replaceAll('.', '');
    return File(_join(dir.path, '${_safePathToken(trackId)}.$safeExtension'));
  }

  Future<File> partialTrackFile({
    required String serverBaseUrl,
    required String trackId,
  }) async {
    final dir = await _trackDirectory(serverBaseUrl, createDir: true);
    return File(
      _join(dir.path, '${_safePathToken(trackId)}.$_partialExtension'),
    );
  }

  Future<File> albumArtFile({
    required String albumId,
    required String extension,
  }) async {
    final dir = await _artDirectory(_albumArtDirName, createDir: true);
    final safeExtension = _safePathToken(extension).replaceAll('.', '');
    return File(_join(dir.path, '${_safePathToken(albumId)}.$safeExtension'));
  }

  Future<File> artistArtFile({
    required String artistId,
    required String kind,
    required String extension,
  }) async {
    final dir = await _artDirectory(_artistArtDirName, createDir: true);
    final safeExtension = _safePathToken(extension).replaceAll('.', '');
    final safeName = '${_safePathToken(artistId)}_${_safePathToken(kind)}';
    return File(_join(dir.path, '$safeName.$safeExtension'));
  }

  Future<Directory> offlineRoot({bool createDir = false}) async {
    return metadataRoot(createDir: createDir);
  }

  Future<Directory> metadataRoot({bool createDir = false}) async {
    final locations = await resolveStorageLocations();
    final dir = Directory(locations.metadataDirectory);
    if (createDir) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _indexFile({bool createDir = false}) async {
    final dir = await offlineRoot(createDir: createDir);
    return File(_join(dir.path, _indexFileName));
  }

  Future<File> _databaseFile({bool createDir = false}) async {
    final dir = await metadataRoot(createDir: createDir);
    return File(_join(dir.path, _databaseFileName));
  }

  Future<void> _deleteOfflineMetadataFiles(Directory metadataDir) async {
    for (final fileName in [
      _databaseFileName,
      '$_databaseFileName-wal',
      '$_databaseFileName-shm',
      '$_databaseFileName-journal',
      _indexFileName,
    ]) {
      await _deleteFileIfExists(File(_join(metadataDir.path, fileName)));
    }
    await _deleteDirectoryIfExists(
      Directory(_join(metadataDir.path, _artDirName)),
    );
  }

  Future<void> _deleteOfflineDownloadFiles(Directory downloadsDir) async {
    if (!await downloadsDir.exists()) {
      return;
    }
    await for (final entity in downloadsDir.list(recursive: false)) {
      if (entity is! Directory) {
        continue;
      }
      final name = entity.path.split(Platform.pathSeparator).last;
      if (name.startsWith('server_')) {
        await entity.delete(recursive: true);
      }
    }
  }

  Future<void> _deleteFileIfExists(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> _deleteDirectoryIfExists(Directory directory) async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Future<Database> _openDatabase() async {
    final file = await _databaseFile(createDir: true);
    final db = sqlite3.open(file.path);
    db.execute('PRAGMA busy_timeout = 5000');
    final hadMetadataTable = _metadataTableExists(db);
    final previousSchemaVersion = hadMetadataTable
        ? _readStoredSchemaVersion(db)
        : _schemaVersion;
    final gcAlreadyRan = hadMetadataTable && _metadataFlag(db, 'orphan_gc_v7');
    _initSchema(db);
    await _migrateJsonIndexIfNeeded(db);
    if (hadMetadataTable &&
        (previousSchemaVersion < _schemaVersion || !gcAlreadyRan)) {
      await _runStartupGarbageCollection(db);
      db.execute('INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?)', [
        'orphan_gc_v7',
        '1',
      ]);
    } else if (!hadMetadataTable) {
      db.execute('INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?)', [
        'orphan_gc_v7',
        '1',
      ]);
    }
    return db;
  }

  bool _metadataTableExists(Database db) {
    try {
      return db.select('''
            SELECT 1
            FROM sqlite_master
            WHERE type = 'table'
              AND name = 'metadata'
            LIMIT 1
          ''').isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  int _readStoredSchemaVersion(Database db) {
    try {
      final rows = db.select('SELECT value FROM metadata WHERE key = ?', [
        'schema_version',
      ]);
      if (rows.isEmpty) {
        return 0;
      }
      return int.tryParse(_readString(rows.first, 'value')) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  bool _metadataFlag(Database db, String key) {
    try {
      final rows = db.select('SELECT value FROM metadata WHERE key = ?', [key]);
      if (rows.isEmpty) {
        return false;
      }
      return _readString(rows.first, 'value') == '1';
    } catch (_) {
      return false;
    }
  }

  Future<void> _runStartupGarbageCollection(Database db) async {
    final deleteRoots = await _managedDeleteRootPaths();
    final pendingDeletes = <String>{};
    _transaction(db, () {
      final orphanRows = db.select('''
        SELECT album_art_path, artist_art_path, artist_banner_path
        FROM tracks t
        WHERE NOT EXISTS (
          SELECT 1
          FROM source_tracks s
          WHERE s.local_track_id = t.id
        )
      ''');
      for (final row in orphanRows) {
        _addPendingDeletePath(
          pendingDeletes,
          _readNullableString(row, 'album_art_path'),
          deleteRoots,
        );
        _addPendingDeletePath(
          pendingDeletes,
          _readNullableString(row, 'artist_art_path'),
          deleteRoots,
        );
        _addPendingDeletePath(
          pendingDeletes,
          _readNullableString(row, 'artist_banner_path'),
          deleteRoots,
        );
      }
      db.execute('''
        DELETE FROM tracks
        WHERE NOT EXISTS (
          SELECT 1
          FROM source_tracks s
          WHERE s.local_track_id = tracks.id
        )
      ''');
      db.execute('''
        DELETE FROM offline_metadata_fragments
        WHERE NOT EXISTS (
          SELECT 1
          FROM source_tracks s
          WHERE s.server_base_url = offline_metadata_fragments.server_base_url
            AND s.server_track_id = offline_metadata_fragments.server_track_id
        )
      ''');
      db.execute(
        '''
        UPDATE download_job_items
        SET track_json = NULL,
            metadata_json = NULL,
            updated_at = ?
        WHERE materialized = 1
          AND (track_json IS NOT NULL OR metadata_json IS NOT NULL)
          AND NOT EXISTS (
            SELECT 1
            FROM download_jobs j
            JOIN source_tracks s
              ON s.server_base_url = j.server_base_url
             AND s.server_track_id = download_job_items.server_track_id
            WHERE j.job_id = download_job_items.job_id
          )
      ''',
        [DateTime.now().millisecondsSinceEpoch],
      );
      _pruneUnavailableLocalUserData(db);
    });
    pendingDeletes.addAll(await _unusedArtworkFiles(db, deleteRoots));
    if (pendingDeletes.isNotEmpty) {
      _transaction(db, () {
        _recordPendingFileDeletes(
          db,
          pendingDeletes,
          DateTime.now().millisecondsSinceEpoch,
          deleteRoots: deleteRoots,
        );
      });
    }
  }

  void _initSchema(Database db) {
    db.execute('PRAGMA foreign_keys = ON');
    db.execute('''
      CREATE TABLE IF NOT EXISTS metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS client_identity (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS tracks (
        id TEXT PRIMARY KEY,
        match_key TEXT NOT NULL,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        artist_id TEXT,
        album TEXT NOT NULL,
        album_id TEXT,
        album_art_path TEXT,
        artist_art_path TEXT,
        artist_banner_path TEXT,
        genres_json TEXT NOT NULL DEFAULT '[]',
        duration_ms INTEGER NOT NULL,
        track_no INTEGER,
        disc_no INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tracks_match_key ON tracks(match_key)',
    );
    _ensureColumn(db, 'tracks', 'album_art_path', 'TEXT');
    _ensureColumn(db, 'tracks', 'artist_art_path', 'TEXT');
    _ensureColumn(db, 'tracks', 'artist_banner_path', 'TEXT');
    _ensureColumn(db, 'tracks', 'genres_json', "TEXT NOT NULL DEFAULT '[]'");
    db.execute('''
      CREATE TABLE IF NOT EXISTS source_tracks (
        server_base_url TEXT NOT NULL,
        server_track_id TEXT NOT NULL,
        local_track_id TEXT NOT NULL,
        batch_id TEXT,
        download_url TEXT,
        status TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        file_path TEXT,
        partial_path TEXT,
        bytes_downloaded INTEGER NOT NULL DEFAULT 0,
        bytes_total INTEGER,
        etag TEXT,
        expected_sha256 TEXT,
        content_type TEXT,
        error TEXT,
        retry_count INTEGER NOT NULL DEFAULT 0,
        priority INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (server_base_url, server_track_id),
        FOREIGN KEY (local_track_id) REFERENCES tracks(id) ON DELETE CASCADE
      )
    ''');
    _ensureColumn(db, 'source_tracks', 'batch_id', 'TEXT');
    _ensureColumn(db, 'source_tracks', 'download_url', 'TEXT');
    _ensureColumn(db, 'source_tracks', 'expected_sha256', 'TEXT');
    _ensureColumn(
      db,
      'source_tracks',
      'retry_count',
      'INTEGER NOT NULL DEFAULT 0',
    );
    _ensureColumn(
      db,
      'source_tracks',
      'priority',
      'INTEGER NOT NULL DEFAULT 0',
    );
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_source_tracks_local ON source_tracks(local_track_id)',
    );
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_source_tracks_batch ON source_tracks(batch_id)',
    );
    db.execute('''
      CREATE TABLE IF NOT EXISTS offline_metadata_fragments (
        server_base_url TEXT NOT NULL,
        server_track_id TEXT NOT NULL,
        local_track_id TEXT NOT NULL,
        schema_version INTEGER NOT NULL,
        track_json TEXT NOT NULL,
        album_json TEXT NOT NULL,
        artist_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (server_base_url, server_track_id),
        FOREIGN KEY (local_track_id) REFERENCES tracks(id) ON DELETE CASCADE
      )
    ''');
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_offline_metadata_local ON offline_metadata_fragments(local_track_id)',
    );
    db.execute('''
      CREATE TABLE IF NOT EXISTS download_batches (
        batch_id TEXT PRIMARY KEY,
        server_base_url TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        total_count INTEGER NOT NULL DEFAULT 0,
        completed_count INTEGER NOT NULL DEFAULT 0,
        failed_count INTEGER NOT NULL DEFAULT 0,
        label TEXT
      )
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS download_items (
        server_base_url TEXT NOT NULL,
        server_track_id TEXT NOT NULL,
        batch_id TEXT,
        local_track_id TEXT,
        status TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        file_path TEXT,
        partial_path TEXT,
        bytes_downloaded INTEGER NOT NULL DEFAULT 0,
        bytes_total INTEGER,
        etag TEXT,
        expected_sha256 TEXT,
        content_type TEXT,
        error TEXT,
        retry_count INTEGER NOT NULL DEFAULT 0,
        priority INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (server_base_url, server_track_id)
      )
    ''');
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_download_items_batch ON download_items(batch_id)',
    );
    db.execute('''
      CREATE TABLE IF NOT EXISTS download_jobs (
        job_id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        server_base_url TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        total_count INTEGER NOT NULL DEFAULT 0,
        discovered_count INTEGER NOT NULL DEFAULT 0,
        completed_count INTEGER NOT NULL DEFAULT 0,
        failed_count INTEGER NOT NULL DEFAULT 0,
        materialized_count INTEGER NOT NULL DEFAULT 0,
        source_cursor INTEGER NOT NULL DEFAULT 0,
        label TEXT,
        error TEXT
      )
    ''');
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_download_jobs_server ON download_jobs(server_base_url, status)',
    );
    db.execute('''
      CREATE TABLE IF NOT EXISTS download_job_items (
        job_id TEXT NOT NULL,
        position INTEGER NOT NULL,
        server_track_id TEXT NOT NULL,
        status TEXT NOT NULL,
        materialized INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        track_json TEXT,
        metadata_json TEXT,
        error TEXT,
        PRIMARY KEY (job_id, server_track_id),
        FOREIGN KEY (job_id) REFERENCES download_jobs(job_id) ON DELETE CASCADE
      )
    ''');
    _ensureColumn(db, 'download_job_items', 'metadata_json', 'TEXT');
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_download_job_items_next ON download_job_items(job_id, materialized, position)',
    );
    db.execute('''
      CREATE TABLE IF NOT EXISTS download_job_sources (
        job_id TEXT NOT NULL,
        position INTEGER NOT NULL,
        source_id TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        label TEXT,
        error TEXT,
        PRIMARY KEY (job_id, source_id),
        FOREIGN KEY (job_id) REFERENCES download_jobs(job_id) ON DELETE CASCADE
      )
    ''');
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_download_job_sources_next ON download_job_sources(job_id, status, position)',
    );
    db.execute('''
      CREATE TABLE IF NOT EXISTS metadata_snapshots (
        server_base_url TEXT NOT NULL,
        kind TEXT NOT NULL,
        item_id TEXT NOT NULL,
        schema_version INTEGER NOT NULL,
        snapshot_json TEXT NOT NULL,
        server_revision INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (server_base_url, kind, item_id)
      )
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS file_artifacts (
        server_base_url TEXT NOT NULL,
        server_track_id TEXT NOT NULL,
        file_path TEXT NOT NULL,
        partial_path TEXT,
        byte_length INTEGER,
        etag TEXT,
        sha256 TEXT,
        status TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (server_base_url, server_track_id)
      )
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS artwork_artifacts (
        server_base_url TEXT NOT NULL,
        kind TEXT NOT NULL,
        item_id TEXT NOT NULL,
        variant TEXT NOT NULL,
        file_path TEXT NOT NULL,
        content_type TEXT,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (server_base_url, kind, item_id, variant)
      )
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS sync_cursors (
        server_base_url TEXT NOT NULL,
        stream TEXT NOT NULL,
        cursor TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (server_base_url, stream)
      )
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS repair_queue (
        id TEXT PRIMARY KEY,
        server_base_url TEXT NOT NULL,
        kind TEXT NOT NULL,
        item_id TEXT NOT NULL,
        status TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        next_attempt_at INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS pending_file_deletes (
        path TEXT PRIMARY KEY,
        created_at INTEGER NOT NULL
      )
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS local_likes (
        local_track_id TEXT PRIMARY KEY,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (local_track_id) REFERENCES tracks(id) ON DELETE CASCADE
      )
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS local_like_states (
        local_track_id TEXT PRIMARY KEY,
        liked INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (local_track_id) REFERENCES tracks(id) ON DELETE CASCADE
      )
    ''');
    db.execute('''
      INSERT OR IGNORE INTO local_like_states (
        local_track_id,
        liked,
        updated_at
      )
      SELECT local_track_id, 1, created_at FROM local_likes
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS server_like_syncs (
        local_track_id TEXT NOT NULL,
        server_base_url TEXT NOT NULL,
        server_track_id TEXT NOT NULL,
        match_confidence REAL NOT NULL,
        match_kind TEXT NOT NULL,
        last_local_liked INTEGER NOT NULL,
        last_local_updated_at INTEGER NOT NULL,
        last_server_liked INTEGER NOT NULL,
        last_server_updated_at INTEGER NOT NULL,
        synced_at INTEGER NOT NULL,
        PRIMARY KEY (local_track_id, server_base_url),
        FOREIGN KEY (local_track_id) REFERENCES tracks(id) ON DELETE CASCADE
      )
    ''');
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_server_like_syncs_server ON server_like_syncs(server_base_url)',
    );
    db.execute('''
      CREATE TABLE IF NOT EXISTS local_playlists (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS local_playlist_tracks (
        playlist_id TEXT NOT NULL,
        local_track_id TEXT NOT NULL,
        position INTEGER NOT NULL,
        PRIMARY KEY (playlist_id, local_track_id),
        FOREIGN KEY (playlist_id) REFERENCES local_playlists(id) ON DELETE CASCADE,
        FOREIGN KEY (local_track_id) REFERENCES tracks(id) ON DELETE CASCADE
      )
    ''');
    db.execute('INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?)', [
      'schema_version',
      _schemaVersion.toString(),
    ]);
  }

  Future<void> _migrateJsonIndexIfNeeded(Database db) async {
    final migrated = db.select('SELECT value FROM metadata WHERE key = ?', [
      'json_migrated',
    ]);
    if (migrated.isNotEmpty) {
      return;
    }
    final file = await _indexFile();
    if (!await file.exists()) {
      db.execute('INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?)', [
        'json_migrated',
        '1',
      ]);
      return;
    }
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      final items = decoded is Map ? decoded['downloads'] : decoded;
      if (items is List) {
        _transaction(db, () {
          for (final item in items.whereType<Map>()) {
            final download = OfflineTrackDownload.fromJson(
              Map<String, dynamic>.from(item),
            );
            if (download != null) {
              _upsertDownload(db, download);
            }
          }
          db.execute(
            'INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?)',
            ['json_migrated', '1'],
          );
        });
      }
    } catch (err) {
      AppLogger.warning('Failed to migrate offline JSON index: $err');
      db.execute('INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?)', [
        'json_migrated',
        '1',
      ]);
    }
  }

  List<OfflineTrackDownload> _readDownloads(Database db) {
    final rows = db.select('''
      SELECT
        s.*,
        t.title,
        t.artist,
        t.artist_id,
        t.album,
        t.album_id,
        t.album_art_path,
        t.artist_art_path,
        t.artist_banner_path,
        t.genres_json,
        t.duration_ms,
        t.track_no,
        t.disc_no,
        f.schema_version AS offline_schema_version,
        f.track_json AS offline_track_json,
        f.album_json AS offline_album_json,
        f.artist_json AS offline_artist_json,
        EXISTS(SELECT 1 FROM local_likes l WHERE l.local_track_id = t.id) AS local_liked,
        EXISTS(SELECT 1 FROM local_playlist_tracks pt WHERE pt.local_track_id = t.id) AS local_in_playlists
      FROM source_tracks s
      JOIN tracks t ON t.id = s.local_track_id
      LEFT JOIN offline_metadata_fragments f
        ON f.server_base_url = s.server_base_url
       AND f.server_track_id = s.server_track_id
      ORDER BY s.updated_at DESC
    ''');
    return rows.map(_downloadFromRow).toList(growable: false);
  }

  List<OfflineDownloadBatch> _readDownloadBatches(Database db) {
    final rows = db.select(
      'SELECT * FROM download_batches ORDER BY updated_at DESC',
    );
    return rows
        .map(
          (row) => OfflineDownloadBatch(
            batchId: _readString(row, 'batch_id'),
            serverBaseUrl: _readString(row, 'server_base_url'),
            status: _parseStatus(_readString(row, 'status')),
            createdAt: _dateFromMs(_readInt(row, 'created_at')),
            updatedAt: _dateFromMs(_readInt(row, 'updated_at')),
            totalCount: _readInt(row, 'total_count'),
            completedCount: _readInt(row, 'completed_count'),
            failedCount: _readInt(row, 'failed_count'),
            label: _readNullableString(row, 'label'),
          ),
        )
        .toList(growable: false);
  }

  List<OfflineDownloadJob> _readDownloadJobs(Database db) {
    final rows = db.select(
      'SELECT * FROM download_jobs ORDER BY updated_at DESC',
    );
    return rows.map(_downloadJobFromRow).toList(growable: false);
  }

  List<OfflineDownloadJobItem> _readDownloadJobItems(
    Database db,
    String jobId, {
    bool includeTrackJson = true,
  }) {
    final rows = db.select(
      includeTrackJson
          ? 'SELECT * FROM download_job_items WHERE job_id = ? ORDER BY position'
          : '''
            SELECT
              job_id,
              position,
              server_track_id,
              status,
              materialized,
              created_at,
              updated_at,
              NULL AS track_json,
              NULL AS metadata_json,
              error
            FROM download_job_items
            WHERE job_id = ?
            ORDER BY position
          ''',
      [jobId],
    );
    return rows.map(_downloadJobItemFromRow).toList(growable: false);
  }

  List<OfflineDownloadJobItem> _readDownloadJobItemsForTracks(
    Database db,
    String jobId,
    List<String> serverTrackIds,
  ) {
    if (serverTrackIds.isEmpty) {
      return const [];
    }
    final placeholders = List.filled(serverTrackIds.length, '?').join(',');
    final rows = db.select(
      '''
      SELECT *
      FROM download_job_items
      WHERE job_id = ?
        AND server_track_id IN ($placeholders)
      ORDER BY position
      ''',
      <Object?>[jobId, ...serverTrackIds],
    );
    return rows.map(_downloadJobItemFromRow).toList(growable: false);
  }

  List<OfflineDownloadJobSource> _readDownloadJobSources(
    Database db,
    String jobId,
  ) {
    final rows = db.select(
      'SELECT * FROM download_job_sources WHERE job_id = ? ORDER BY position',
      [jobId],
    );
    return rows.map(_downloadJobSourceFromRow).toList(growable: false);
  }

  List<Track> _readLocalTracks(Database db, {required bool whereDownloaded}) {
    final downloaded = OfflineDownloadStatus.downloaded.name;
    final rows = db.select(
      '''
      SELECT
        t.*,
        s.server_base_url,
        s.server_track_id,
        (
          SELECT f.schema_version
          FROM offline_metadata_fragments f
          JOIN source_tracks fs
            ON fs.server_base_url = f.server_base_url
           AND fs.server_track_id = f.server_track_id
          WHERE f.local_track_id = t.id
            AND fs.status = ?
            AND fs.file_path IS NOT NULL
          ORDER BY fs.updated_at DESC
          LIMIT 1
        ) AS offline_schema_version,
        (
          SELECT f.track_json
          FROM offline_metadata_fragments f
          JOIN source_tracks fs
            ON fs.server_base_url = f.server_base_url
           AND fs.server_track_id = f.server_track_id
          WHERE f.local_track_id = t.id
            AND fs.status = ?
            AND fs.file_path IS NOT NULL
          ORDER BY fs.updated_at DESC
          LIMIT 1
        ) AS offline_track_json,
        (
          SELECT f.album_json
          FROM offline_metadata_fragments f
          JOIN source_tracks fs
            ON fs.server_base_url = f.server_base_url
           AND fs.server_track_id = f.server_track_id
          WHERE f.local_track_id = t.id
            AND fs.status = ?
            AND fs.file_path IS NOT NULL
          ORDER BY fs.updated_at DESC
          LIMIT 1
        ) AS offline_album_json,
        (
          SELECT f.artist_json
          FROM offline_metadata_fragments f
          JOIN source_tracks fs
            ON fs.server_base_url = f.server_base_url
           AND fs.server_track_id = f.server_track_id
          WHERE f.local_track_id = t.id
            AND fs.status = ?
            AND fs.file_path IS NOT NULL
          ORDER BY fs.updated_at DESC
          LIMIT 1
        ) AS offline_artist_json
      FROM tracks t
      LEFT JOIN source_tracks s ON s.local_track_id = t.id
        AND s.status = ?
        AND s.file_path IS NOT NULL
      ${whereDownloaded ? '''
      WHERE EXISTS (
        SELECT 1 FROM source_tracks ds
        WHERE ds.local_track_id = t.id
          AND ds.status = ?
          AND ds.file_path IS NOT NULL
      )
      ''' : ''}
      GROUP BY t.id
      ORDER BY t.artist, t.album, t.disc_no, t.track_no, t.title
    ''',
      whereDownloaded
          ? [
              downloaded,
              downloaded,
              downloaded,
              downloaded,
              downloaded,
              downloaded,
            ]
          : [downloaded, downloaded, downloaded, downloaded, downloaded],
    );
    return rows
        .map((row) {
          final localId = _readString(row, 'id');
          return _trackFromRow(
            row,
            liked: _trackIsLocallyLiked(db, localId),
            inPlaylists: _trackInLocalPlaylists(db, localId),
          );
        })
        .toList(growable: false);
  }

  List<Playlist> _readLocalPlaylists(Database db) {
    final playlistRows = db.select(
      'SELECT id, name FROM local_playlists ORDER BY updated_at DESC, name',
    );
    final playlists = <Playlist>[];
    for (final row in playlistRows) {
      final playlistId = _readString(row, 'id');
      final trackRows = db.select(
        'SELECT local_track_id FROM local_playlist_tracks WHERE playlist_id = ? ORDER BY position, rowid',
        [playlistId],
      );
      playlists.add(
        Playlist(
          id: playlistId,
          name: _readString(row, 'name'),
          trackIds: trackRows
              .map((item) => _readString(item, 'local_track_id'))
              .toList(growable: false),
        ),
      );
    }
    return playlists;
  }

  OfflineTrackDownload _downloadFromRow(Row row) {
    final localTrackId = _readString(row, 'local_track_id');
    final serverBaseUrl = _readString(row, 'server_base_url');
    final serverTrackId = _readString(row, 'server_track_id');
    final fallbackTrack = Track(
      id: serverTrackId,
      title: _readString(row, 'title'),
      artist: _readString(row, 'artist'),
      artistId: _readNullableString(row, 'artist_id'),
      album: _readString(row, 'album'),
      albumId: _readNullableString(row, 'album_id'),
      localId: localTrackId,
      serverBaseUrl: serverBaseUrl,
      serverTrackId: serverTrackId,
      albumArtPath: _readNullableString(row, 'album_art_path'),
      artistArtPath: _readNullableString(row, 'artist_art_path'),
      artistBannerPath: _readNullableString(row, 'artist_banner_path'),
      genres: _genresFromRow(row),
      durationMs: _readInt(row, 'duration_ms'),
      liked: _readBool(row, 'local_liked'),
      inPlaylists: _readBool(row, 'local_in_playlists'),
      trackNo: _readNullableInt(row, 'track_no'),
      discNo: _readNullableInt(row, 'disc_no'),
    );
    final offlineMetadata = _offlineMetadataFromRow(row);
    final track = _trackWithOfflineMetadata(
      fallbackTrack,
      offlineMetadata,
      id: serverTrackId,
      localId: localTrackId,
      serverBaseUrl: serverBaseUrl,
      serverTrackId: serverTrackId,
      liked: _readBool(row, 'local_liked'),
      inPlaylists: _readBool(row, 'local_in_playlists'),
    );
    return OfflineTrackDownload(
      serverBaseUrl: serverBaseUrl,
      batchId: _readNullableString(row, 'batch_id'),
      localTrackId: localTrackId,
      track: track,
      offlineMetadata: offlineMetadata?.copyWith(track: track),
      status: _parseStatus(_readString(row, 'status')),
      createdAt: _dateFromMs(_readInt(row, 'created_at')),
      updatedAt: _dateFromMs(_readInt(row, 'updated_at')),
      downloadUrl: _readNullableString(row, 'download_url'),
      filePath: _readNullableString(row, 'file_path'),
      partialPath: _readNullableString(row, 'partial_path'),
      bytesDownloaded: _readInt(row, 'bytes_downloaded'),
      bytesTotal: _readNullableInt(row, 'bytes_total'),
      etag: _readNullableString(row, 'etag'),
      expectedSha256: _readNullableString(row, 'expected_sha256'),
      contentType: _readNullableString(row, 'content_type'),
      error: _readNullableString(row, 'error'),
      retryCount: _readInt(row, 'retry_count'),
      priority: _readInt(row, 'priority'),
    );
  }

  OfflineDownloadJob _downloadJobFromRow(Row row) {
    return OfflineDownloadJob(
      jobId: _readString(row, 'job_id'),
      kind: _readString(row, 'kind'),
      serverBaseUrl: _readString(row, 'server_base_url'),
      status: _parseStatus(_readString(row, 'status')),
      createdAt: _dateFromMs(_readInt(row, 'created_at')),
      updatedAt: _dateFromMs(_readInt(row, 'updated_at')),
      totalCount: _readInt(row, 'total_count'),
      discoveredCount: _readInt(row, 'discovered_count'),
      completedCount: _readInt(row, 'completed_count'),
      failedCount: _readInt(row, 'failed_count'),
      materializedCount: _readInt(row, 'materialized_count'),
      sourceCursor: _readInt(row, 'source_cursor'),
      label: _readNullableString(row, 'label'),
      error: _readNullableString(row, 'error'),
    );
  }

  OfflineDownloadJobItem _downloadJobItemFromRow(Row row) {
    Track? track;
    OfflineTrackMetadata? offlineMetadata;
    final rawMetadata = _readNullableString(row, 'metadata_json');
    if (rawMetadata != null && rawMetadata.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawMetadata);
        if (decoded is Map) {
          offlineMetadata = OfflineTrackMetadata.fromJson(
            Map<String, dynamic>.from(decoded),
          );
          track = offlineMetadata.track;
        }
      } catch (_) {}
    }
    final rawTrack = _readNullableString(row, 'track_json');
    if (track == null && rawTrack != null && rawTrack.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawTrack);
        if (decoded is Map) {
          track = Track.fromJson(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {}
    }
    return OfflineDownloadJobItem(
      jobId: _readString(row, 'job_id'),
      position: _readInt(row, 'position'),
      serverTrackId: _readString(row, 'server_track_id'),
      status: _parseStatus(_readString(row, 'status')),
      materialized: _readBool(row, 'materialized'),
      createdAt: _dateFromMs(_readInt(row, 'created_at')),
      updatedAt: _dateFromMs(_readInt(row, 'updated_at')),
      track: track,
      offlineMetadata: offlineMetadata,
      error: _readNullableString(row, 'error'),
    );
  }

  OfflineDownloadJobSource _downloadJobSourceFromRow(Row row) {
    return OfflineDownloadJobSource(
      jobId: _readString(row, 'job_id'),
      position: _readInt(row, 'position'),
      sourceId: _readString(row, 'source_id'),
      status: _parseStatus(_readString(row, 'status')),
      createdAt: _dateFromMs(_readInt(row, 'created_at')),
      updatedAt: _dateFromMs(_readInt(row, 'updated_at')),
      label: _readNullableString(row, 'label'),
      error: _readNullableString(row, 'error'),
    );
  }

  ServerLikeSync _serverLikeSyncFromRow(Row row) {
    return ServerLikeSync(
      localTrackId: _readString(row, 'local_track_id'),
      serverBaseUrl: _readString(row, 'server_base_url'),
      serverTrackId: _readString(row, 'server_track_id'),
      matchConfidence: _readDouble(row, 'match_confidence'),
      matchKind: _readString(row, 'match_kind'),
      lastLocalLiked: _readBool(row, 'last_local_liked'),
      lastLocalUpdatedAt: _readInt(row, 'last_local_updated_at'),
      lastServerLiked: _readBool(row, 'last_server_liked'),
      lastServerUpdatedAt: _readInt(row, 'last_server_updated_at'),
      syncedAt: _readInt(row, 'synced_at'),
    );
  }

  List<String> _genresFromRow(Row row) {
    final raw = _tryReadNullableString(row, 'genres_json');
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
      }
    } catch (_) {}
    return const [];
  }

  Track _trackFromRow(
    Row row, {
    required bool liked,
    required bool inPlaylists,
  }) {
    final localId = _readString(row, 'id');
    final serverBaseUrl = _readNullableString(row, 'server_base_url');
    final serverTrackId = _readNullableString(row, 'server_track_id');
    final fallbackTrack = Track(
      id: localId,
      title: _readString(row, 'title'),
      artist: _readString(row, 'artist'),
      artistId: _readNullableString(row, 'artist_id'),
      album: _readString(row, 'album'),
      albumId: _readNullableString(row, 'album_id'),
      localId: localId,
      serverBaseUrl: serverBaseUrl,
      serverTrackId: serverTrackId,
      albumArtPath: _readNullableString(row, 'album_art_path'),
      artistArtPath: _readNullableString(row, 'artist_art_path'),
      artistBannerPath: _readNullableString(row, 'artist_banner_path'),
      genres: _genresFromRow(row),
      durationMs: _readInt(row, 'duration_ms'),
      liked: liked,
      inPlaylists: inPlaylists,
      trackNo: _readNullableInt(row, 'track_no'),
      discNo: _readNullableInt(row, 'disc_no'),
    );
    return _trackWithOfflineMetadata(
      fallbackTrack,
      _offlineMetadataFromRow(row),
      id: localId,
      localId: localId,
      serverBaseUrl: serverBaseUrl,
      serverTrackId: serverTrackId,
      liked: liked,
      inPlaylists: inPlaylists,
    );
  }

  OfflineTrackMetadata? _offlineMetadataFromRow(Row row) {
    final trackJson = _tryReadNullableString(row, 'offline_track_json');
    final albumJson = _tryReadNullableString(row, 'offline_album_json');
    final artistJson = _tryReadNullableString(row, 'offline_artist_json');
    if (trackJson == null || albumJson == null || artistJson == null) {
      return null;
    }
    try {
      final rawTrack = jsonDecode(trackJson);
      final rawAlbum = jsonDecode(albumJson);
      final rawArtist = jsonDecode(artistJson);
      if (rawTrack is! Map || rawAlbum is! Map || rawArtist is! Map) {
        return null;
      }
      return OfflineTrackMetadata(
        schemaVersion: _tryReadNullableInt(row, 'offline_schema_version') ?? 1,
        track: Track.fromJson(Map<String, dynamic>.from(rawTrack)),
        album: Album.fromJson(Map<String, dynamic>.from(rawAlbum)),
        artist: Artist.fromJson(Map<String, dynamic>.from(rawArtist)),
      );
    } catch (_) {
      return null;
    }
  }

  Track _trackWithOfflineMetadata(
    Track fallback,
    OfflineTrackMetadata? metadata, {
    required String id,
    required String? localId,
    required String? serverBaseUrl,
    required String? serverTrackId,
    required bool liked,
    required bool inPlaylists,
  }) {
    final source = metadata?.track ?? fallback;
    return source.copyWith(
      id: id,
      artist: source.artist.trim().isEmpty ? fallback.artist : source.artist,
      artistId: source.artistId ?? fallback.artistId,
      album: source.album.trim().isEmpty ? fallback.album : source.album,
      albumId: source.albumId ?? fallback.albumId,
      localId: localId,
      serverBaseUrl: serverBaseUrl,
      serverTrackId: serverTrackId,
      albumArtPath: fallback.albumArtPath ?? source.albumArtPath,
      artistArtPath: fallback.artistArtPath ?? source.artistArtPath,
      artistBannerPath: fallback.artistBannerPath ?? source.artistBannerPath,
      durationMs: source.durationMs > 0
          ? source.durationMs
          : fallback.durationMs,
      genres: source.genres.isEmpty ? fallback.genres : source.genres,
      liked: liked,
      inPlaylists: inPlaylists,
      trackNo: source.trackNo ?? fallback.trackNo,
      discNo: source.discNo ?? fallback.discNo,
      offlineAlbum: metadata?.album ?? fallback.offlineAlbum,
      offlineArtist: metadata?.artist ?? fallback.offlineArtist,
    );
  }

  OfflineTrackDownload _withLocalTrack(
    OfflineTrackDownload download,
    String localTrackId,
  ) {
    final serverTrackId = download.track.serverTrackId ?? download.track.id;
    final track = download.track.copyWith(
      localId: localTrackId,
      serverBaseUrl: download.serverBaseUrl,
      serverTrackId: serverTrackId,
      offlineAlbum:
          download.offlineMetadata?.album ?? download.track.offlineAlbum,
      offlineArtist:
          download.offlineMetadata?.artist ?? download.track.offlineArtist,
    );
    return download.copyWith(
      localTrackId: localTrackId,
      track: track,
      offlineMetadata: download.offlineMetadata?.copyWith(track: track),
    );
  }

  void _upsertDownload(Database db, OfflineTrackDownload download) {
    final localTrackId = download.localTrackId?.trim().isNotEmpty == true
        ? download.localTrackId!
        : _resolveLocalTrackId(db, download.track);
    final normalized = _withLocalTrack(download, localTrackId);
    _upsertTrack(db, localTrackId, normalized.track);
    _upsertOfflineMetadataFragment(db, normalized, localTrackId);
    db.execute(
      '''
      INSERT INTO source_tracks (
        server_base_url,
        server_track_id,
        local_track_id,
        batch_id,
        download_url,
        status,
        created_at,
        updated_at,
        file_path,
        partial_path,
        bytes_downloaded,
        bytes_total,
        etag,
        expected_sha256,
        content_type,
        error,
        retry_count,
        priority
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(server_base_url, server_track_id) DO UPDATE SET
        local_track_id = excluded.local_track_id,
        batch_id = excluded.batch_id,
        download_url = excluded.download_url,
        status = excluded.status,
        updated_at = excluded.updated_at,
        file_path = excluded.file_path,
        partial_path = excluded.partial_path,
        bytes_downloaded = excluded.bytes_downloaded,
        bytes_total = excluded.bytes_total,
        etag = excluded.etag,
        expected_sha256 = excluded.expected_sha256,
        content_type = excluded.content_type,
        error = excluded.error,
        retry_count = excluded.retry_count,
        priority = excluded.priority
    ''',
      [
        normalized.serverBaseUrl,
        normalized.track.serverTrackId ?? normalized.track.id,
        localTrackId,
        normalized.batchId,
        normalized.downloadUrl,
        normalized.status.name,
        normalized.createdAt.millisecondsSinceEpoch,
        normalized.updatedAt.millisecondsSinceEpoch,
        normalized.filePath,
        normalized.partialPath,
        normalized.bytesDownloaded,
        normalized.bytesTotal,
        normalized.etag,
        normalized.expectedSha256,
        normalized.contentType,
        normalized.error,
        normalized.retryCount,
        normalized.priority,
      ],
    );
    db.execute(
      '''
      INSERT INTO download_items (
        server_base_url,
        server_track_id,
        batch_id,
        local_track_id,
        status,
        created_at,
        updated_at,
        file_path,
        partial_path,
        bytes_downloaded,
        bytes_total,
        etag,
        expected_sha256,
        content_type,
        error,
        retry_count,
        priority
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(server_base_url, server_track_id) DO UPDATE SET
        batch_id = excluded.batch_id,
        local_track_id = excluded.local_track_id,
        status = excluded.status,
        updated_at = excluded.updated_at,
        file_path = excluded.file_path,
        partial_path = excluded.partial_path,
        bytes_downloaded = excluded.bytes_downloaded,
        bytes_total = excluded.bytes_total,
        etag = excluded.etag,
        expected_sha256 = excluded.expected_sha256,
        content_type = excluded.content_type,
        error = excluded.error,
        retry_count = excluded.retry_count,
        priority = excluded.priority
    ''',
      [
        normalized.serverBaseUrl,
        normalized.track.serverTrackId ?? normalized.track.id,
        normalized.batchId,
        localTrackId,
        normalized.status.name,
        normalized.createdAt.millisecondsSinceEpoch,
        normalized.updatedAt.millisecondsSinceEpoch,
        normalized.filePath,
        normalized.partialPath,
        normalized.bytesDownloaded,
        normalized.bytesTotal,
        normalized.etag,
        normalized.expectedSha256,
        normalized.contentType,
        normalized.error,
        normalized.retryCount,
        normalized.priority,
      ],
    );
  }

  void _upsertOfflineMetadataFragment(
    Database db,
    OfflineTrackDownload download,
    String localTrackId,
  ) {
    final metadata = download.offlineMetadata;
    if (metadata == null) {
      return;
    }
    final serverTrackId = _serverTrackId(download);
    final track = metadata.track.copyWith(
      id: serverTrackId,
      localId: localTrackId,
      serverBaseUrl: download.serverBaseUrl,
      serverTrackId: serverTrackId,
      albumArtPath: download.track.albumArtPath ?? metadata.track.albumArtPath,
      artistArtPath:
          download.track.artistArtPath ?? metadata.track.artistArtPath,
      artistBannerPath:
          download.track.artistBannerPath ?? metadata.track.artistBannerPath,
      liked: download.track.liked,
      inPlaylists: download.track.inPlaylists,
    );
    final normalized = metadata.copyWith(track: track);
    _upsertOfflineMetadataFragmentRaw(
      db,
      serverBaseUrl: download.serverBaseUrl,
      serverTrackId: serverTrackId,
      localTrackId: localTrackId,
      metadata: normalized,
    );
  }

  void _upsertOfflineMetadataFragmentRaw(
    Database db, {
    required String serverBaseUrl,
    required String serverTrackId,
    required String localTrackId,
    required OfflineTrackMetadata metadata,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      '''
      INSERT INTO offline_metadata_fragments (
        server_base_url,
        server_track_id,
        local_track_id,
        schema_version,
        track_json,
        album_json,
        artist_json,
        created_at,
        updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(server_base_url, server_track_id) DO UPDATE SET
        local_track_id = excluded.local_track_id,
        schema_version = excluded.schema_version,
        track_json = excluded.track_json,
        album_json = excluded.album_json,
        artist_json = excluded.artist_json,
        updated_at = excluded.updated_at
    ''',
      [
        serverBaseUrl,
        serverTrackId,
        localTrackId,
        metadata.schemaVersion,
        jsonEncode(metadata.track.toJson()),
        jsonEncode(metadata.album.toJson()),
        jsonEncode(metadata.artist.toJson()),
        now,
        now,
      ],
    );
  }

  void _upsertDownloadBatch(Database db, OfflineDownloadBatch batch) {
    db.execute(
      '''
      INSERT INTO download_batches (
        batch_id,
        server_base_url,
        status,
        created_at,
        updated_at,
        total_count,
        completed_count,
        failed_count,
        label
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(batch_id) DO UPDATE SET
        server_base_url = excluded.server_base_url,
        status = excluded.status,
        updated_at = excluded.updated_at,
        total_count = excluded.total_count,
        completed_count = excluded.completed_count,
        failed_count = excluded.failed_count,
        label = excluded.label
    ''',
      [
        batch.batchId,
        batch.serverBaseUrl,
        batch.status.name,
        batch.createdAt.millisecondsSinceEpoch,
        batch.updatedAt.millisecondsSinceEpoch,
        batch.totalCount,
        batch.completedCount,
        batch.failedCount,
        batch.label,
      ],
    );
  }

  void _upsertDownloadJob(Database db, OfflineDownloadJob job) {
    db.execute(
      '''
      INSERT INTO download_jobs (
        job_id,
        kind,
        server_base_url,
        status,
        created_at,
        updated_at,
        total_count,
        discovered_count,
        completed_count,
        failed_count,
        materialized_count,
        source_cursor,
        label,
        error
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(job_id) DO UPDATE SET
        kind = excluded.kind,
        server_base_url = excluded.server_base_url,
        status = excluded.status,
        updated_at = excluded.updated_at,
        total_count = excluded.total_count,
        discovered_count = excluded.discovered_count,
        completed_count = excluded.completed_count,
        failed_count = excluded.failed_count,
        materialized_count = excluded.materialized_count,
        source_cursor = excluded.source_cursor,
        label = excluded.label,
        error = excluded.error
    ''',
      [
        job.jobId,
        job.kind,
        job.serverBaseUrl,
        job.status.name,
        job.createdAt.millisecondsSinceEpoch,
        job.updatedAt.millisecondsSinceEpoch,
        job.totalCount,
        job.discoveredCount,
        job.completedCount,
        job.failedCount,
        job.materializedCount,
        job.sourceCursor,
        job.label,
        job.error,
      ],
    );
  }

  void _upsertDownloadJobItem(Database db, OfflineDownloadJobItem item) {
    final track = item.track;
    db.execute(
      '''
      INSERT INTO download_job_items (
        job_id,
        position,
        server_track_id,
        status,
        materialized,
        created_at,
        updated_at,
        track_json,
        metadata_json,
        error
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(job_id, server_track_id) DO UPDATE SET
        position = excluded.position,
        status = excluded.status,
        materialized = excluded.materialized,
        updated_at = excluded.updated_at,
        track_json = COALESCE(excluded.track_json, track_json),
        metadata_json = COALESCE(excluded.metadata_json, metadata_json),
        error = excluded.error
    ''',
      [
        item.jobId,
        item.position,
        item.serverTrackId,
        item.status.name,
        item.materialized ? 1 : 0,
        item.createdAt.millisecondsSinceEpoch,
        item.updatedAt.millisecondsSinceEpoch,
        track == null
            ? null
            : jsonEncode(OfflineTrackDownload._trackToJson(track)),
        item.offlineMetadata == null
            ? null
            : jsonEncode(item.offlineMetadata!.toJson()),
        item.error,
      ],
    );
  }

  void _upsertDownloadJobSource(Database db, OfflineDownloadJobSource source) {
    db.execute(
      '''
      INSERT INTO download_job_sources (
        job_id,
        position,
        source_id,
        status,
        created_at,
        updated_at,
        label,
        error
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(job_id, source_id) DO UPDATE SET
        position = excluded.position,
        status = excluded.status,
        updated_at = excluded.updated_at,
        label = excluded.label,
        error = excluded.error
    ''',
      [
        source.jobId,
        source.position,
        source.sourceId,
        source.status.name,
        source.createdAt.millisecondsSinceEpoch,
        source.updatedAt.millisecondsSinceEpoch,
        source.label,
        source.error,
      ],
    );
  }

  String _resolveLocalTrackId(Database db, Track track) {
    final matchKey = _metadataMatchKey(track);
    final rows = db.select(
      'SELECT id, duration_ms FROM tracks WHERE match_key = ?',
      [matchKey],
    );
    for (final row in rows) {
      final duration = _readInt(row, 'duration_ms');
      if ((duration - track.durationMs).abs() <= 2000) {
        final id = _readString(row, 'id');
        _upsertTrack(db, id, track);
        return id;
      }
    }
    var id = _stableId('$matchKey|${track.durationMs}');
    var suffix = 1;
    while (db.select('SELECT id FROM tracks WHERE id = ?', [id]).isNotEmpty) {
      id = _stableId('$matchKey|${track.durationMs}|$suffix');
      suffix += 1;
    }
    _upsertTrack(db, id, track);
    return id;
  }

  void _upsertTrack(Database db, String localTrackId, Track track) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final matchKey = _metadataMatchKey(track);
    db.execute(
      '''
      INSERT INTO tracks (
        id,
        match_key,
        title,
        artist,
        artist_id,
        album,
        album_id,
        album_art_path,
        artist_art_path,
        artist_banner_path,
        genres_json,
        duration_ms,
        track_no,
        disc_no,
        created_at,
        updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        match_key = excluded.match_key,
        title = excluded.title,
        artist = excluded.artist,
        artist_id = excluded.artist_id,
        album = excluded.album,
        album_id = excluded.album_id,
        album_art_path = COALESCE(excluded.album_art_path, album_art_path),
        artist_art_path = COALESCE(excluded.artist_art_path, artist_art_path),
        artist_banner_path = COALESCE(
          excluded.artist_banner_path,
          artist_banner_path
        ),
        genres_json = excluded.genres_json,
        duration_ms = excluded.duration_ms,
        track_no = excluded.track_no,
        disc_no = excluded.disc_no,
        updated_at = excluded.updated_at
    ''',
      [
        localTrackId,
        matchKey,
        track.title,
        track.artist,
        track.artistId,
        track.album,
        track.albumId,
        track.albumArtPath,
        track.artistArtPath,
        track.artistBannerPath,
        jsonEncode(track.genres),
        track.durationMs,
        track.trackNo,
        track.discNo,
        now,
        now,
      ],
    );
  }

  void _requireDownloadedLocalTrack(Database db, String localTrackId) {
    final rows = db.select(
      '''
      SELECT file_path FROM source_tracks
      WHERE local_track_id = ?
        AND status = ?
        AND file_path IS NOT NULL
    ''',
      [localTrackId, OfflineDownloadStatus.downloaded.name],
    );
    for (final row in rows) {
      final filePath = _readNullableString(row, 'file_path');
      if (filePath != null && File(filePath).existsSync()) {
        return;
      }
    }
    throw StateError('Track must be downloaded before saving local user data.');
  }

  void _pruneUnavailableLocalUserData(Database db) {
    db.execute(
      '''
      DELETE FROM local_likes
      WHERE NOT EXISTS (
        SELECT 1 FROM source_tracks s
        WHERE s.local_track_id = local_likes.local_track_id
          AND s.status = ?
          AND s.file_path IS NOT NULL
      )
    ''',
      [OfflineDownloadStatus.downloaded.name],
    );
    db.execute(
      '''
      DELETE FROM local_like_states
      WHERE NOT EXISTS (
        SELECT 1 FROM source_tracks s
        WHERE s.local_track_id = local_like_states.local_track_id
          AND s.status = ?
          AND s.file_path IS NOT NULL
      )
    ''',
      [OfflineDownloadStatus.downloaded.name],
    );
    db.execute(
      '''
      DELETE FROM server_like_syncs
      WHERE NOT EXISTS (
        SELECT 1 FROM source_tracks s
        WHERE s.local_track_id = server_like_syncs.local_track_id
          AND s.status = ?
          AND s.file_path IS NOT NULL
      )
    ''',
      [OfflineDownloadStatus.downloaded.name],
    );
    db.execute(
      '''
      DELETE FROM local_playlist_tracks
      WHERE NOT EXISTS (
        SELECT 1 FROM source_tracks s
        WHERE s.local_track_id = local_playlist_tracks.local_track_id
          AND s.status = ?
          AND s.file_path IS NOT NULL
      )
    ''',
      [OfflineDownloadStatus.downloaded.name],
    );
  }

  bool _trackIsLocallyLiked(Database db, String localTrackId) {
    return db.select(
      'SELECT 1 FROM local_likes WHERE local_track_id = ? LIMIT 1',
      [localTrackId],
    ).isNotEmpty;
  }

  void _writeLocalLikeState(
    Database db,
    String localTrackId,
    bool liked,
    int updatedAt,
  ) {
    db.execute(
      '''
      INSERT OR REPLACE INTO local_like_states (
        local_track_id,
        liked,
        updated_at
      ) VALUES (?, ?, ?)
    ''',
      [localTrackId, liked ? 1 : 0, updatedAt],
    );
    if (liked) {
      db.execute(
        'INSERT OR REPLACE INTO local_likes (local_track_id, created_at) VALUES (?, ?)',
        [localTrackId, updatedAt],
      );
    } else {
      db.execute('DELETE FROM local_likes WHERE local_track_id = ?', [
        localTrackId,
      ]);
    }
  }

  bool _trackInLocalPlaylists(Database db, String localTrackId) {
    return db.select(
      'SELECT 1 FROM local_playlist_tracks WHERE local_track_id = ? LIMIT 1',
      [localTrackId],
    ).isNotEmpty;
  }

  void _transaction(Database db, void Function() body) {
    db.execute('BEGIN IMMEDIATE');
    try {
      body();
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  void _ensureColumn(
    Database db,
    String tableName,
    String columnName,
    String definition,
  ) {
    final columns = db.select('PRAGMA table_info($tableName)');
    final exists = columns.any((row) => _readString(row, 'name') == columnName);
    if (!exists) {
      db.execute('ALTER TABLE $tableName ADD COLUMN $columnName $definition');
    }
  }

  Future<Directory> _trackDirectory(
    String serverBaseUrl, {
    bool createDir = false,
  }) async {
    final root = await downloadsRoot(createDir: createDir);
    final serverDir = Directory(
      _join(root.path, 'server_${_serverKey(serverBaseUrl)}'),
    );
    final tracksDir = Directory(_join(serverDir.path, _tracksDirName));
    if (createDir) {
      await tracksDir.create(recursive: true);
    }
    return tracksDir;
  }

  Future<Directory> _artDirectory(
    String childDirectory, {
    bool createDir = false,
  }) async {
    final root = await metadataRoot(createDir: createDir);
    final dir = Directory(_join(_join(root.path, _artDirName), childDirectory));
    if (createDir) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> downloadsRoot({bool createDir = false}) async {
    final locations = await resolveStorageLocations();
    final dir = Directory(locations.downloadsDirectory);
    if (createDir) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> _defaultOfflineRoot() async {
    final base = await _resolveBaseDirectory();
    return Directory(_join(base.path, _rootDirName));
  }

  Future<Directory> _resolveBaseDirectory() async {
    final override = baseDirectory;
    if (override != null) {
      return override;
    }
    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData != null && localAppData.trim().isNotEmpty) {
        return Directory(_join(localAppData, 'Phonolite'));
      }
    }
    final supportDir = await getApplicationSupportDirectory();
    return Directory(_join(supportDir.path, 'Phonolite'));
  }

  Future<void> _copyMetadataFilesIfNeeded({
    required Directory fromDirectory,
    required Directory toDirectory,
  }) async {
    if (fromDirectory.absolute.path == toDirectory.absolute.path) {
      return;
    }
    await toDirectory.create(recursive: true);
    for (final fileName in [_databaseFileName, _indexFileName]) {
      final source = File(_join(fromDirectory.path, fileName));
      if (!await source.exists()) {
        continue;
      }
      final target = File(_join(toDirectory.path, fileName));
      if (await target.exists()) {
        continue;
      }
      await source.copy(target.path);
    }
    await _copyDirectoryIfNeeded(
      fromDirectory: Directory(_join(fromDirectory.path, _artDirName)),
      toDirectory: Directory(_join(toDirectory.path, _artDirName)),
    );
  }

  Future<void> _copyDirectoryIfNeeded({
    required Directory fromDirectory,
    required Directory toDirectory,
  }) async {
    if (!await fromDirectory.exists()) {
      return;
    }
    await toDirectory.create(recursive: true);
    await for (final entity in fromDirectory.list(recursive: false)) {
      final name = entity.path.split(Platform.pathSeparator).last;
      if (name.isEmpty) {
        continue;
      }
      final targetPath = _join(toDirectory.path, name);
      if (entity is Directory) {
        await _copyDirectoryIfNeeded(
          fromDirectory: entity,
          toDirectory: Directory(targetPath),
        );
      } else if (entity is File) {
        final target = File(targetPath);
        if (!await target.exists()) {
          await entity.copy(target.path);
        }
      }
    }
  }

  String? _normalizeConfiguredDirectory(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return Directory(trimmed).absolute.path;
  }

  static String extensionFromContentType(String? contentType) {
    final value = contentType?.split(';').first.trim().toLowerCase() ?? '';
    switch (value) {
      case 'audio/mpeg':
      case 'audio/mp3':
        return 'mp3';
      case 'audio/mp4':
      case 'audio/x-m4a':
        return 'm4a';
      case 'audio/flac':
      case 'audio/x-flac':
        return 'flac';
      case 'audio/ogg':
      case 'application/ogg':
        return 'ogg';
      case 'audio/opus':
        return 'opus';
      case 'audio/aac':
        return 'aac';
      case 'audio/wav':
      case 'audio/x-wav':
        return 'wav';
      default:
        return 'audio';
    }
  }

  static String extensionFromImageContentType(String? contentType) {
    final value = contentType?.split(';').first.trim().toLowerCase() ?? '';
    switch (value) {
      case 'image/jpeg':
      case 'image/jpg':
        return 'jpg';
      case 'image/png':
        return 'png';
      case 'image/webp':
        return 'webp';
      case 'image/gif':
        return 'gif';
      default:
        return 'img';
    }
  }

  static String? extensionFromContentDisposition(String? contentDisposition) {
    final value = contentDisposition?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    final match = RegExp(
      "filename\\*?=(?:UTF-8'')?\"?([^\";]+)\"?",
      caseSensitive: false,
    ).firstMatch(value);
    final filename = match?.group(1)?.trim();
    if (filename == null || filename.isEmpty || !filename.contains('.')) {
      return null;
    }
    final extension = filename.split('.').last.trim().toLowerCase();
    if (extension.isEmpty) {
      return null;
    }
    return _safePathToken(Uri.decodeComponent(extension)).replaceAll('.', '');
  }

  static OfflineDownloadStatus _parseStatus(String value) {
    for (final status in OfflineDownloadStatus.values) {
      if (status.name == value) {
        return status;
      }
    }
    return OfflineDownloadStatus.queued;
  }

  static DateTime _dateFromMs(int value) {
    if (value <= 0) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(value);
  }

  static String _sourceKey(String serverBaseUrl, String trackId) {
    return '$serverBaseUrl\n$trackId';
  }

  static String _serverTrackId(OfflineTrackDownload download) {
    return download.track.serverTrackId ?? download.track.id;
  }

  Future<List<String>> _managedDeleteRootPaths() async {
    final roots = <String>[
      (await downloadsRoot()).absolute.path,
      _join((await metadataRoot()).absolute.path, _artDirName),
    ];
    return roots.map(_normalizedRootPath).toList(growable: false);
  }

  Future<List<String>> _unusedArtworkFiles(
    Database db,
    List<String> deleteRoots,
  ) async {
    final root = await metadataRoot();
    final artRoot = Directory(_join(root.path, _artDirName));
    if (!await artRoot.exists()) {
      return const <String>[];
    }
    final paths = <String>{};
    await for (final entity in artRoot.list(recursive: true)) {
      if (entity is! File) {
        continue;
      }
      final path = _managedPendingDeletePath(entity.path, deleteRoots);
      if (path == null) {
        continue;
      }
      if (!_artworkPathHasSourceBackedReference(db, path)) {
        paths.add(path);
      }
    }
    return paths.toList(growable: false);
  }

  bool _artworkPathHasSourceBackedReference(Database db, String path) {
    return db
        .select(
          '''
          SELECT 1
          FROM tracks t
          JOIN source_tracks s ON s.local_track_id = t.id
          WHERE t.album_art_path = ?
             OR t.artist_art_path = ?
             OR t.artist_banner_path = ?
          LIMIT 1
        ''',
          [path, path, path],
        )
        .isNotEmpty;
  }

  static String? _pendingDeletePath(String? path) {
    final text = path?.trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    return File(text).absolute.path;
  }

  static String? _managedPendingDeletePath(
    String? path,
    List<String> deleteRoots,
  ) {
    final normalized = _pendingDeletePath(path);
    if (normalized == null) {
      return null;
    }
    return _pathIsUnderAnyRoot(normalized, deleteRoots) ? normalized : null;
  }

  static void _addPendingDeletePath(
    Set<String> target,
    String? path,
    List<String> deleteRoots,
  ) {
    final normalized = _managedPendingDeletePath(path, deleteRoots);
    if (normalized != null) {
      target.add(normalized);
    }
  }

  static String _normalizedRootPath(String path) {
    final absolute = Directory(path).absolute.path;
    final separator = Platform.pathSeparator;
    final normalized = absolute.endsWith(separator)
        ? absolute
        : '$absolute$separator';
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  static bool _pathIsUnderAnyRoot(String path, List<String> roots) {
    final separator = Platform.pathSeparator;
    final absolute = File(path).absolute.path;
    final normalizedPath = Platform.isWindows
        ? absolute.toLowerCase()
        : absolute;
    for (final root in roots) {
      final rootWithoutSeparator = root.endsWith(separator)
          ? root.substring(0, root.length - separator.length)
          : root;
      if (normalizedPath == rootWithoutSeparator ||
          normalizedPath.startsWith(root)) {
        return true;
      }
    }
    return false;
  }

  void _recordPendingFileDeletes(
    Database db,
    Iterable<String> paths,
    int createdAt, {
    List<String>? deleteRoots,
  }) {
    final roots = deleteRoots;
    for (final path in paths) {
      final normalized = roots == null
          ? _pendingDeletePath(path)
          : _managedPendingDeletePath(path, roots);
      if (normalized == null) {
        continue;
      }
      db.execute(
        '''
        INSERT INTO pending_file_deletes (path, created_at)
        VALUES (?, ?)
        ON CONFLICT(path) DO NOTHING
      ''',
        [normalized, createdAt],
      );
    }
  }

  static String _metadataMatchKey(Track track) {
    return [
      _normalizeMetadataText(track.artist),
      _normalizeMetadataText(track.album),
      _normalizeMetadataText(track.title),
    ].join('|');
  }

  static String _normalizeMetadataText(String value) {
    final out = StringBuffer();
    var lastSpace = false;
    for (final codeUnit in value.trim().toLowerCase().codeUnits) {
      final isAlphaNumeric =
          (codeUnit >= 48 && codeUnit <= 57) ||
          (codeUnit >= 97 && codeUnit <= 122);
      if (isAlphaNumeric) {
        out.writeCharCode(codeUnit);
        lastSpace = false;
      } else if (!lastSpace) {
        out.write(' ');
        lastSpace = true;
      }
    }
    return out.toString().trim();
  }

  static String _stableId(String value) {
    final encoded = base64Url.encode(utf8.encode(value)).replaceAll('=', '');
    return 'lt_$encoded';
  }

  static String _serverKey(String baseUrl) {
    final encoded = base64Url.encode(utf8.encode(baseUrl.trim()));
    return encoded.replaceAll('=', '');
  }

  static String _safePathToken(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 'item';
    }
    final out = StringBuffer();
    for (final codeUnit in trimmed.codeUnits) {
      final ch = String.fromCharCode(codeUnit);
      final safe =
          (codeUnit >= 48 && codeUnit <= 57) ||
          (codeUnit >= 65 && codeUnit <= 90) ||
          (codeUnit >= 97 && codeUnit <= 122) ||
          ch == '-' ||
          ch == '_' ||
          ch == '.';
      out.write(safe ? ch : '_');
    }
    final text = out.toString();
    return text.isEmpty ? 'item' : text;
  }

  static String _readString(Row row, String key) {
    return row[key]?.toString() ?? '';
  }

  static String? _readNullableString(Row row, String key) {
    final value = row[key];
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    return text;
  }

  static String? _tryReadNullableString(Row row, String key) {
    try {
      return _readNullableString(row, key);
    } catch (_) {
      return null;
    }
  }

  static int _readInt(Row row, String key) {
    final value = row[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int? _readNullableInt(Row row, String key) {
    final value = row[key];
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value.toString());
  }

  static int? _tryReadNullableInt(Row row, String key) {
    try {
      return _readNullableInt(row, key);
    } catch (_) {
      return null;
    }
  }

  static double _readDouble(Row row, String key) {
    final value = row[key];
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static bool _readBool(Row row, String key) {
    final value = row[key];
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    return value?.toString() == 'true';
  }

  String _join(String left, String right) {
    if (left.isEmpty) {
      return right;
    }
    final separator = Platform.pathSeparator;
    if (left.endsWith(separator)) {
      return '$left$right';
    }
    return '$left$separator$right';
  }

  String _generateClientId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final suffix = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return 'client-${DateTime.now().millisecondsSinceEpoch}-$suffix';
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) {
      return null;
    }
    return iterator.current;
  }
}
