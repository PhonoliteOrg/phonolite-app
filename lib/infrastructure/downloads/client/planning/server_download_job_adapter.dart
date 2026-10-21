part of 'package:phonolite_app/infrastructure/downloads/client/offline_download_client.dart';

class _ServerDownloadJobAdapter {
  final _OfflineDownloadActorCore _host;

  _ServerDownloadJobAdapter(this._host);

  Future<int?> _tryQueueV2DownloadJob({
    required DownloadJobScopeV2 scope,
    required String clientRequestId,
    required String kind,
    String? label,
    String? sourceId,
    List<Album> artistAlbums = const [],
    String? localIntentJobId,
  }) async {
    final dataRevision = _host._localDataRevision;

    bool requestCurrent() =>
        _host._localDataCurrent(dataRevision) && (localIntentJobId == null || _host._jobById(localIntentJobId) != null);

    try {
      final capabilities = await _host.connection.fetchCapabilities();

      if (!requestCurrent()) {
        return 0;
      }

      if (!capabilities.downloadJobsV2) {
        return null;
      }

      final clientId = await _host._storageOperation(_host._storage.readOrCreateClientId);

      if (!requestCurrent()) {
        return 0;
      }

      final attemptRequestId = _host._queueAttemptRequestId(clientRequestId);
      final serverJob = await _host.connection.createDownloadJob(
        clientId: clientId,
        clientRequestId: attemptRequestId,
        scope: scope,
      );

      if (!requestCurrent()) {
        return 0;
      }

      // Servers can reuse a job by collection even for a new request ID.
      // Rebuild locally rather than restoring that older job's failed items.
      if (serverJob.clientId != clientId || serverJob.clientRequestId != attemptRequestId) {
        AppLogger.status('Rebuilding a fresh download plan after the server returned an older job');

        return null;
      }

      final queued = await _ingestV2DownloadJob(
        serverJob,
        kind: kind,
        label: label,
        sourceId: sourceId,
        artistAlbums: artistAlbums,
      );

      return _host._localDataCurrent(dataRevision) ? queued : 0;
    } catch (err, stackTrace) {
      if (!requestCurrent()) {
        return 0;
      }

      AppLogger.warning('Falling back to legacy offline queue after v2 job failure: $err');
      developer.log('v2 download job queue failed', name: 'OfflineDownloadManager', error: err, stackTrace: stackTrace);

      return null;
    }
  }

  Future<int> _ingestV2DownloadJob(
    DownloadJobV2 serverJob, {
    required String kind,
    String? label,
    String? sourceId,
    List<Album> artistAlbums = const [],
  }) async {
    final jobId = serverJob.jobId.trim();

    if (jobId.isEmpty) {
      return 0;
    }

    final existingJob = _host._jobById(jobId);

    if (existingJob != null && _host._jobBlocksNewQueue(existingJob)) {
      return 0;
    }

    if (existingJob != null) {
      await _host._deleteRollingJob(jobId, removePendingDownloads: true);
    }

    final baseUrl = _host.connection.baseUrl;
    final now = DateTime.now();
    final job = OfflineDownloadJob(
      jobId: jobId,
      kind: kind,
      serverBaseUrl: baseUrl,
      status: _statusFromV2Job(serverJob.status, freshQueue: true),
      createdAt: serverJob.createdAt,
      updatedAt: now,
      totalCount: serverJob.totalCount,
      discoveredCount: serverJob.items.length,
      failedCount: serverJob.failedCount,
      label: label,
      sourceId: sourceId ?? _v2ScopeSourceId(serverJob.scope, kind),
    );

    OfflineDownloadJobItem materializeJobItem(DownloadJobItemV2 item) {
      final existing = _host.find(baseUrl, item.trackId);
      final available = existing != null && _host._downloadAvailable(existing);
      final OfflineDownloadStatus status;

      if (available) {
        status = OfflineDownloadStatus.downloaded;
      } else if (item.status == 'complete') {
        status = OfflineDownloadStatus.queued;
      } else {
        status = _statusFromV2JobItem(item, freshQueue: true);
      }

      return OfflineDownloadJobItem(
        jobId: jobId,
        position: item.position,
        serverTrackId: item.trackId,
        status: status,
        materialized: available,
        createdAt: serverJob.createdAt,
        updatedAt: now,
        track: item.offlineMetadata?.track.copyWith(
          id: item.trackId,
          serverBaseUrl: baseUrl,
          serverTrackId: item.trackId,
        ),
        offlineMetadata: item.offlineMetadata,
        error: item.error,
      );
    }

    final jobItems = serverJob.items.map(materializeJobItem).toList(growable: false);

    await _host._insertRollingJob(
      job,
      items: jobItems,
      sources: [
        for (var index = 0; index < artistAlbums.length; index++)
          OfflineDownloadJobSource(
            jobId: jobId,
            position: index,
            sourceId: artistAlbums[index].id,
            status: OfflineDownloadStatus.queued,
            createdAt: now,
            updatedAt: now,
            label: artistAlbums[index].title,
          ),
      ],
    );

    final downloads = <OfflineTrackDownload>[];

    for (final item in serverJob.items) {
      if (downloads.length >= _OfflineDownloadActorCore._rollingWindowSize) {
        break;
      }

      final freshPausedItem = item.status == 'paused' && item.offlineMetadata != null;

      if (!item.readyToDownload && !freshPausedItem) {
        continue;
      }

      final metadata = item.offlineMetadata!;
      final track = metadata.track.copyWith(id: item.trackId, serverBaseUrl: baseUrl, serverTrackId: item.trackId);
      final hydratedMetadata = metadata.copyWith(track: track);
      final existing = _host.find(baseUrl, item.trackId);

      if (_host._downloadQueuedOrAvailable(existing)) {
        continue;
      }

      downloads.add(
        existing?.copyWith(
              batchId: jobId,
              downloadUrl: item.downloadUrl,
              status: OfflineDownloadStatus.queued,
              updatedAt: now,
              filePath: null,
              bytesTotal: item.byteLength,
              etag: item.etag,
              expectedSha256: item.sha256,
              contentType: item.contentType,
              error: null,
              retryCount: existing.retryCount + 1,
              priority: serverJob.items.length - item.position,
              track: track,
              offlineMetadata: hydratedMetadata,
            ) ??
            OfflineTrackDownload(
              serverBaseUrl: baseUrl,
              batchId: jobId,
              downloadUrl: item.downloadUrl,
              track: track,
              offlineMetadata: hydratedMetadata,
              status: OfflineDownloadStatus.queued,
              createdAt: now,
              updatedAt: now,
              bytesTotal: item.byteLength,
              etag: item.etag,
              expectedSha256: item.sha256,
              contentType: item.contentType,
              priority: serverJob.items.length - item.position,
            ),
      );
    }

    if (downloads.isNotEmpty) {
      await _host._persistMaterializedDownloads(jobId, downloads);

      _host._scheduleQueuedDownloads();
    } else {
      await _host._refreshJobCounts(jobId);
    }

    return serverJob.totalCount > 0 ? serverJob.totalCount : downloads.length;
  }

  OfflineDownloadStatus _statusFromV2Job(String status, {bool freshQueue = false}) {
    switch (status) {
      case 'downloading':
        return OfflineDownloadStatus.downloading;
      case 'paused':
        return freshQueue ? OfflineDownloadStatus.queued : OfflineDownloadStatus.paused;
      case 'complete':
        return OfflineDownloadStatus.downloaded;
      case 'failed':
      case 'metadata_failed':
        return OfflineDownloadStatus.failed;
      case 'canceled':
        return OfflineDownloadStatus.canceled;
      case 'removing':
        return OfflineDownloadStatus.removing;
      case 'resolving_metadata':
      case 'ready_to_download':
      case 'queued':
      default:
        return OfflineDownloadStatus.queued;
    }
  }

  String? _v2ScopeSourceId(DownloadJobScopeV2 scope, String kind) {
    if (kind != 'artist' && kind != 'album') {
      return null;
    }

    final id = scope.id?.trim();

    return id == null || id.isEmpty ? null : id;
  }

  OfflineDownloadStatus _statusFromV2JobItem(DownloadJobItemV2 item, {bool freshQueue = false}) {
    switch (item.status) {
      case 'downloading':
        return OfflineDownloadStatus.downloading;
      case 'paused':
        return freshQueue ? OfflineDownloadStatus.queued : OfflineDownloadStatus.paused;
      case 'complete':
        return OfflineDownloadStatus.downloaded;
      case 'failed':
      case 'metadata_failed':
        return OfflineDownloadStatus.failed;
      case 'canceled':
        return OfflineDownloadStatus.canceled;
      case 'removing':
        return OfflineDownloadStatus.removing;
      case 'verifying':
        return OfflineDownloadStatus.validating;
      case 'ready_to_download':
        return item.readyToDownload ? OfflineDownloadStatus.queued : OfflineDownloadStatus.failed;
      case 'resolving_metadata':
      case 'queued':
      default:
        return OfflineDownloadStatus.queued;
    }
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _ServerDownloadJobAdapterFacade {
  _ServerDownloadJobAdapter get _ownerV2;

  Future<int?> _tryQueueV2DownloadJob({
    required DownloadJobScopeV2 scope,
    required String clientRequestId,
    required String kind,
    String? label,
    String? sourceId,
    List<Album> artistAlbums = const [],
    String? localIntentJobId,
  }) => _ownerV2._tryQueueV2DownloadJob(
    scope: scope,
    clientRequestId: clientRequestId,
    kind: kind,
    label: label,
    sourceId: sourceId,
    artistAlbums: artistAlbums,
    localIntentJobId: localIntentJobId,
  );
}
