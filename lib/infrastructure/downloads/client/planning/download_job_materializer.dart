part of 'package:phonolite_app/infrastructure/downloads/client/offline_download_client.dart';

class _DownloadJobMaterializer {
  final _OfflineDownloadActorCore _host;

  _DownloadJobMaterializer(this._host);

  Future<void> _materializeJobItems(OfflineDownloadJob job, List<OfflineDownloadJobItem> items) async {
    items = await _hydrateMaterializationWindow(job.jobId, items);

    if (!_canMaterializeJob(job.jobId)) {
      return;
    }

    final ids = items.map((item) => item.serverTrackId).toList(growable: false);

    if (ids.isEmpty) {
      return;
    }

    if ((_host.connection.token == null || _host.connection.token!.isEmpty) &&
        items.any((item) => item.offlineMetadata == null)) {
      // Keep the unstaged request intact until the restored session can fetch
      // its metadata. Loading before sign-in must not consume or fail it.
      return;
    }

    if (_host.connection.token != null && _host.connection.token!.isNotEmpty) {
      try {
        final manifest = await _host.connection.createDownloadBatch(ids, clientBatchId: job.jobId);

        if (!_canMaterializeJob(job.jobId)) {
          return;
        }

        await _materializeManifestItems(job, manifest.items);

        if (manifest.unavailable.isNotEmpty) {
          await _markJobItems(
            job.jobId,
            manifest.unavailable.map((item) => item.trackId),
            OfflineDownloadStatus.failed,
            error: 'unavailable',
          );
        }

        return;
      } catch (err) {
        AppLogger.warning('Falling back to direct rolling queue for ${job.label ?? job.jobId}: $err');
      }
    }

    if (!_canMaterializeJob(job.jobId)) {
      return;
    }

    final downloads = <OfflineTrackDownload>[];
    final now = DateTime.now();

    for (var index = 0; index < items.length; index += 1) {
      final item = items[index];
      final track = item.track;

      if (track == null) {
        await _markJobItems(
          job.jobId,
          <String>[item.serverTrackId],
          OfflineDownloadStatus.failed,
          error: 'missing offline metadata',
        );
        continue;
      }

      downloads.add(
        OfflineTrackDownload(
          serverBaseUrl: job.serverBaseUrl,
          batchId: job.jobId,
          track: track.copyWith(
            id: item.serverTrackId,
            serverBaseUrl: job.serverBaseUrl,
            serverTrackId: item.serverTrackId,
          ),
          offlineMetadata: item.offlineMetadata?.copyWith(
            track: item.offlineMetadata!.track.copyWith(
              id: item.serverTrackId,
              serverBaseUrl: job.serverBaseUrl,
              serverTrackId: item.serverTrackId,
            ),
          ),
          status: OfflineDownloadStatus.queued,
          createdAt: now,
          updatedAt: now,
          priority: items.length - index,
        ),
      );
    }

    await _persistMaterializedDownloads(job.jobId, downloads);
  }

  Future<List<OfflineDownloadJobItem>> _hydrateMaterializationWindow(
    String jobId,
    List<OfflineDownloadJobItem> items,
  ) async {
    final missingIds = items
        .where((item) => item.track == null || item.offlineMetadata == null)
        .map((item) => item.serverTrackId)
        .toList(growable: false);

    if (missingIds.isEmpty) {
      return items;
    }

    final hydratedItems = await _host._storage.readDownloadJobItemsForTracks(jobId, missingIds);
    final tracksById = <String, Track>{
      for (final item in hydratedItems)
        if (item.track != null) item.serverTrackId: item.track!,
    };
    final metadataById = <String, OfflineTrackMetadata>{
      for (final item in hydratedItems)
        if (item.offlineMetadata != null) item.serverTrackId: item.offlineMetadata!,
    };

    if (tracksById.isEmpty && metadataById.isEmpty) {
      return items;
    }

    final merged = [
      for (final item in items)
        (item.track == null || item.offlineMetadata == null) &&
                (tracksById.containsKey(item.serverTrackId) || metadataById.containsKey(item.serverTrackId))
            ? _mergeHydratedJobItem(item, tracksById, metadataById)
            : item,
    ];
    final allItems = List<OfflineDownloadJobItem>.from(
      _host._jobItemsByJobId[jobId] ?? const <OfflineDownloadJobItem>[],
    );

    for (var index = 0; index < allItems.length; index += 1) {
      final track = tracksById[allItems[index].serverTrackId];
      final metadata = metadataById[allItems[index].serverTrackId];

      if (track != null || metadata != null) {
        allItems[index] = _mergeHydratedJobItem(allItems[index], tracksById, metadataById);
      }
    }

    _host._jobItemsByJobId[jobId] = allItems;

    return merged;
  }

  OfflineDownloadJobItem _mergeHydratedJobItem(
    OfflineDownloadJobItem item,
    Map<String, Track> tracksById,
    Map<String, OfflineTrackMetadata> metadataById,
  ) {
    var updated = item;
    final track = tracksById[item.serverTrackId];

    if (track != null) {
      updated = updated.copyWith(track: track);
    }

    if (metadataById.containsKey(item.serverTrackId)) {
      updated = updated.copyWith(offlineMetadata: metadataById[item.serverTrackId]);
    }

    return updated;
  }

  Future<void> _materializeManifestItems(OfflineDownloadJob job, List<DownloadBatchItem> manifestItems) async {
    final now = DateTime.now();
    final downloads = <OfflineTrackDownload>[];

    for (var index = 0; index < manifestItems.length; index += 1) {
      final item = manifestItems[index];
      final track = item.offlineMetadata.track.copyWith(
        id: item.trackId,
        serverBaseUrl: job.serverBaseUrl,
        serverTrackId: item.trackId,
      );
      final offlineMetadata = item.offlineMetadata.copyWith(track: track);

      downloads.add(
        OfflineTrackDownload(
          serverBaseUrl: job.serverBaseUrl,
          batchId: job.jobId,
          downloadUrl: item.downloadUrl,
          track: track,
          offlineMetadata: offlineMetadata,
          status: OfflineDownloadStatus.queued,
          createdAt: now,
          updatedAt: now,
          bytesTotal: item.byteLength > 0 ? item.byteLength : null,
          etag: item.etag.isEmpty ? null : item.etag,
          expectedSha256: item.sha256.isEmpty ? null : item.sha256,
          contentType: item.contentType,
          priority: manifestItems.length - index,
        ),
      );
    }

    await _persistMaterializedDownloads(job.jobId, downloads);
  }

  Future<void> _persistMaterializedDownloads(String jobId, List<OfflineTrackDownload> downloads) async {
    if (downloads.isEmpty || !_canMaterializeJob(jobId)) {
      return;
    }

    final prepared = await _host._storage.prepareDownloads(downloads);

    if (!_canMaterializeJob(jobId)) {
      return;
    }

    for (final download in prepared) {
      _host._clearObsoleteStopMarkersForQueue(download);
    }

    _host._replaceManyInMemory(prepared);

    await _host._storage.upsertDownloads(prepared);

    await _markJobItems(
      jobId,
      prepared.map(_host._serverTrackId),
      OfflineDownloadStatus.queued,
      materialized: true,
      tracksById: {for (final download in prepared) _host._serverTrackId(download): download.track},
      metadataById: {
        for (final download in prepared)
          if (download.offlineMetadata != null) _host._serverTrackId(download): download.offlineMetadata!,
      },
    );

    await _host._refreshJobCounts(jobId);
  }

  bool _canMaterializeJob(String jobId) {
    final job = _host._jobById(jobId);

    return !_host._disposed &&
        !_host._resettingLocalData &&
        job != null &&
        job.status != OfflineDownloadStatus.paused &&
        job.status != OfflineDownloadStatus.canceled &&
        job.status != OfflineDownloadStatus.removing &&
        !_host._pausedServerUrls.contains(job.serverBaseUrl);
  }

  Future<void> _markJobItems(
    String jobId,
    Iterable<String> serverTrackIds,
    OfflineDownloadStatus status, {
    bool? materialized,
    Map<String, Track> tracksById = const <String, Track>{},
    Map<String, OfflineTrackMetadata> metadataById = const <String, OfflineTrackMetadata>{},
    bool clearPayload = false,
    String? error,
  }) async {
    final ids = serverTrackIds.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet();

    if (ids.isEmpty) {
      return;
    }

    final now = DateTime.now();
    final items = List<OfflineDownloadJobItem>.from(_host._jobItemsByJobId[jobId] ?? const <OfflineDownloadJobItem>[]);
    final changed = <OfflineDownloadJobItem>[];

    for (var index = 0; index < items.length; index += 1) {
      final item = items[index];

      if (!ids.contains(item.serverTrackId)) {
        continue;
      }

      var updated = item.copyWith(status: status, materialized: materialized, updatedAt: now, error: error);

      if (clearPayload) {
        updated = updated.copyWith(track: null, offlineMetadata: null);
      } else if (tracksById.containsKey(item.serverTrackId)) {
        updated = updated.copyWith(track: tracksById[item.serverTrackId]);
      }

      if (metadataById.containsKey(item.serverTrackId)) {
        updated = updated.copyWith(offlineMetadata: metadataById[item.serverTrackId]);
      }

      items[index] = updated;
      changed.add(updated);
    }

    if (changed.isEmpty) {
      return;
    }

    _host._jobItemsByJobId[jobId] = items;

    await _host._storage.upsertDownloadJobItems(changed);
  }

  Future<void> _syncJobItemFromDownload(OfflineTrackDownload download) async {
    final jobId = download.batchId;

    if (jobId == null || !_host._jobs.any((job) => job.jobId == jobId)) {
      return;
    }

    await _markJobItems(
      jobId,
      <String>[_host._serverTrackId(download)],
      download.status,
      materialized: true,
      tracksById: {_host._serverTrackId(download): download.track},
      metadataById: download.offlineMetadata == null
          ? const <String, OfflineTrackMetadata>{}
          : {_host._serverTrackId(download): download.offlineMetadata!},
      error: download.error,
    );

    await _host._refreshJobCounts(jobId);

    if (_host._terminalStatus(download.status)) {
      _host._scheduleTopUp();
    }
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _DownloadJobMaterializerFacade {
  _DownloadJobMaterializer get _ownerMaterialize;

  Future<void> _materializeJobItems(OfflineDownloadJob job, List<OfflineDownloadJobItem> items) =>
      _ownerMaterialize._materializeJobItems(job, items);

  Future<void> _materializeManifestItems(OfflineDownloadJob job, List<DownloadBatchItem> manifestItems) =>
      _ownerMaterialize._materializeManifestItems(job, manifestItems);

  Future<void> _persistMaterializedDownloads(String jobId, List<OfflineTrackDownload> downloads) =>
      _ownerMaterialize._persistMaterializedDownloads(jobId, downloads);

  Future<void> _markJobItems(
    String jobId,
    Iterable<String> serverTrackIds,
    OfflineDownloadStatus status, {
    bool? materialized,
    Map<String, Track> tracksById = const <String, Track>{},
    Map<String, OfflineTrackMetadata> metadataById = const <String, OfflineTrackMetadata>{},
    bool clearPayload = false,
    String? error,
  }) => _ownerMaterialize._markJobItems(
    jobId,
    serverTrackIds,
    status,
    materialized: materialized,
    tracksById: tracksById,
    metadataById: metadataById,
    clearPayload: clearPayload,
    error: error,
  );

  Future<void> _syncJobItemFromDownload(OfflineTrackDownload download) =>
      _ownerMaterialize._syncJobItemFromDownload(download);
}
