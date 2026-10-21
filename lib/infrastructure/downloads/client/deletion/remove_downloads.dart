part of 'package:phonolite_app/infrastructure/downloads/client/offline_download_client.dart';

class _DownloadRemoval {
  final _OfflineDownloadActorCore _host;

  _DownloadRemoval(this._host);

  Future<void> removeTrack(String trackId) async {
    final download = _host.findForCurrentServer(trackId);
    if (download == null) {
      return;
    }

    await _host.removeDownload(download);
  }

  Future<void> removeDownload(OfflineTrackDownload download) async {
    await _host.removeDownloads(<OfflineTrackDownload>[download]);
  }

  Future<void> removeDownloads(
    Iterable<OfflineTrackDownload> downloads, {
    OfflineDeletionScope scope = const OfflineDeletionScope.track(),
  }) async {
    await _host._ensureLoaded();

    final byKey = <String, OfflineTrackDownload>{};

    for (final download in downloads) {
      byKey[_host._downloadKey(download)] = download;
    }

    final removedJobIds = _expandArtistRemoval(byKey, scope);

    if (byKey.isEmpty) {
      return;
    }

    final removeKeys = byKey.keys.toSet();
    final activeRemovals = [
      for (final key in removeKeys)
        if (_host._active[key] case final active?) active,
    ];
    final currentByKey = <String, OfflineTrackDownload>{};

    for (final download in _host._downloads) {
      final key = _host._downloadKey(download);

      if (removeKeys.contains(key) && download.status != OfflineDownloadStatus.removing) {
        currentByKey[key] = download;
      }
    }

    final removals = currentByKey.values.toList(growable: false);

    if (removals.isEmpty && removedJobIds.isEmpty) {
      return;
    }

    final batchIds = <String>{};
    final v2JobIds = <String>{};
    final removedTrackIdsByServer = <String, Set<String>>{};

    for (final download in removals) {
      removedTrackIdsByServer.putIfAbsent(download.serverBaseUrl, () => {}).add(_host._serverTrackId(download));
    }

    for (final job in _host._jobs) {
      if (removedJobIds.contains(job.jobId) &&
          job.serverBaseUrl == _host.connection.baseUrl &&
          _host._looksLikeV2DownloadJobId(job.jobId)) {
        v2JobIds.add(job.jobId);
      }

      final removedTrackIds = removedTrackIdsByServer[job.serverBaseUrl];

      if (removedTrackIds != null &&
          (_host._jobItemsByJobId[job.jobId] ?? const <OfflineDownloadJobItem>[]).any(
            (item) => removedTrackIds.contains(item.serverTrackId),
          )) {
        batchIds.add(job.jobId);
      }
    }

    final now = DateTime.now();

    for (final download in removals) {
      final key = _host._downloadKey(download);

      _host._removedDownloadKeys.add(key);
      _host._cancelRequested.add(key);
      _host._activeCancelPorts[key]?.send(null);

      final batchId = download.batchId;

      if (batchId != null) {
        batchIds.add(batchId);

        if (download.serverBaseUrl == _host.connection.baseUrl && _host._downloadBelongsToV2Job(download)) {
          v2JobIds.add(batchId);
        }
      }
    }

    // Stop discovery and staging before waiting for file/metadata deletion.
    // The database removes these plans together with the selected downloads.
    for (final jobId in removedJobIds) {
      _host._forgetRollingJob(jobId);
    }

    OfflineTrackDownload markForRemoval(OfflineTrackDownload download) {
      final key = _host._downloadKey(download);

      if (!currentByKey.containsKey(key)) {
        return download;
      }

      return download.copyWith(status: OfflineDownloadStatus.removing, updatedAt: now, error: null);
    }

    _host._downloads = _host._downloads.map(markForRemoval).toList(growable: false);
    _host._rebuildDownloadIndexes();
    _host._emit();

    await _host._storage.removeDownloadsScoped(
      OfflineDeletionRequest(scope: scope, downloads: removals, downloadJobIds: removedJobIds.toList(growable: false)),
    );

    // Release old workers and file handles before finishing deletion, so an
    // immediate new download cannot inherit their partial files or stop flags.
    await Future.wait(activeRemovals);
    await _host._cleanupPendingFileDeletes();

    _host._downloads = _host._downloads
        .where((download) => !removeKeys.contains(_host._downloadKey(download)))
        .toList(growable: false);
    _host._rebuildDownloadIndexes();
    _host._emit();

    await _host._loadLocalUserData();

    for (final batchId in batchIds) {
      if (removedJobIds.contains(batchId)) {
        continue;
      }

      if (_host._isRollingJob(batchId)) {
        final job = _host._jobById(batchId)!;

        await _host._markJobItems(
          batchId,
          removals.where((download) => download.serverBaseUrl == job.serverBaseUrl).map(_host._serverTrackId),
          OfflineDownloadStatus.canceled,
          materialized: true,
          clearPayload: true,
        );
        await _host._refreshJobCounts(batchId);
        await _host._deleteRollingJobIfAbandoned(batchId);
      } else {
        await _host._refreshBatchCounts(batchId);
      }
    }

    for (final batchId in v2JobIds) {
      await _host._retireServerDownloadJobIfUnused(batchId);
    }

    _host._schedule();

    unawaited(_host._cleanupPendingFileDeletes());
  }

  Future<void> clearFailedAndCorrupt() async {
    final removable = _host._downloads
        .where(
          (download) =>
              download.status == OfflineDownloadStatus.failed ||
              download.status == OfflineDownloadStatus.corrupt ||
              download.status == OfflineDownloadStatus.canceled,
        )
        .toList(growable: false);

    await _host.removeDownloads(removable);

    final failedJobs = _host._jobs
        .where(
          (job) =>
              job.status == OfflineDownloadStatus.failed ||
              job.status == OfflineDownloadStatus.corrupt ||
              job.status == OfflineDownloadStatus.canceled,
        )
        .toList(growable: false);

    for (final job in failedJobs) {
      await _host._deleteRollingJob(job.jobId, removePendingDownloads: true);
    }
  }

  Set<String> _expandArtistRemoval(Map<String, OfflineTrackDownload> downloads, OfflineDeletionScope scope) {
    if (scope.kind != OfflineDeletionScopeKind.artist) {
      return const {};
    }

    final artistIds = {...scope.ids, if (_host._nonEmpty(scope.id) != null) scope.id!};

    if (artistIds.isEmpty) {
      return const {};
    }

    final servers = downloads.values.map((item) => item.serverBaseUrl).toSet();
    final artistNames = <String>{};
    final albumIdsByServer = <String, Set<String>>{};

    for (final download in downloads.values) {
      final track = download.track;
      final album = download.offlineMetadata?.album ?? track.offlineAlbum;

      albumIdsByServer.putIfAbsent(download.serverBaseUrl, () => {}).addAll([
        if (_host._nonEmpty(album?.id) != null) album!.id,
        if (_host._nonEmpty(track.albumId) != null) track.albumId!,
      ]);

      for (final credit in [...track.credits, ...?album?.credits]) {
        if (artistIds.contains(credit.artistId)) {
          artistNames.add(credit.name.trim().toLowerCase());
        }
      }
    }

    if (artistIds.length == 1 && _host._nonEmpty(scope.label) != null) {
      artistNames.add(scope.label!.trim().toLowerCase());
    }

    final removedJobIds = <String>{};

    for (final job in _host._jobs) {
      if (!servers.contains(job.serverBaseUrl) || job.kind != 'artist') {
        continue;
      }

      final matches = _host._nonEmpty(job.sourceId) != null
          ? artistIds.contains(job.sourceId)
          : artistNames.contains(_host._normalizedJobLabel(job.label));

      if (!matches) {
        continue;
      }

      removedJobIds.add(job.jobId);
      albumIdsByServer
          .putIfAbsent(job.serverBaseUrl, () => {})
          .addAll(
            (_host._jobSourcesByJobId[job.jobId] ?? const <OfflineDownloadJobSource>[]).map(
              (source) => source.sourceId,
            ),
          );
    }

    for (final job in _host._jobs) {
      if (job.kind == 'album' && (albumIdsByServer[job.serverBaseUrl]?.contains(job.sourceId) ?? false)) {
        removedJobIds.add(job.jobId);
      }
    }

    for (final download in _host._downloads) {
      if (!servers.contains(download.serverBaseUrl)) {
        continue;
      }

      final track = download.track;
      final album = download.offlineMetadata?.album ?? track.offlineAlbum;
      final belongsToArtist =
          track.credits.any((credit) => credit.isPerformingArtist && artistIds.contains(credit.artistId)) ||
          (album?.credits.any((credit) => credit.isAlbumArtist && artistIds.contains(credit.artistId)) ?? false);

      if (belongsToArtist || removedJobIds.contains(download.batchId)) {
        downloads[_host._downloadKey(download)] = download;
      }
    }

    return removedJobIds;
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _DownloadRemovalFacade {
  _DownloadRemoval get _ownerDeletion;

  Future<void> removeTrack(String trackId) => _ownerDeletion.removeTrack(trackId);

  Future<void> removeDownload(OfflineTrackDownload download) => _ownerDeletion.removeDownload(download);

  Future<void> removeDownloads(
    Iterable<OfflineTrackDownload> downloads, {
    OfflineDeletionScope scope = const OfflineDeletionScope.track(),
  }) => _ownerDeletion.removeDownloads(downloads, scope: scope);

  Future<void> clearFailedAndCorrupt() => _ownerDeletion.clearFailedAndCorrupt();
}
