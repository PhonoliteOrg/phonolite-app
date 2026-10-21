part of 'package:phonolite_app/infrastructure/downloads/client/offline_download_client.dart';

class _DownloadDataReset {
  final _OfflineDownloadActorCore _host;
  Future<void>? _loadFuture;
  Future<void>? _resetLocalDataFuture;
  bool _clearingUnfinishedDownloads = false;
  final Set<Future<dynamic>> _pendingStorageOperations = {};
  Timer? _localUserDataReloadTimer;

  _DownloadDataReset(this._host);

  Future<void> resetLocalData() {
    final existing = _resetLocalDataFuture;
    if (existing != null) {
      return _clearingUnfinishedDownloads ? existing.then((_) => _host.resetLocalData()) : existing;
    }

    final future = _resetLocalData();

    _resetLocalDataFuture = future.whenComplete(() {
      _resetLocalDataFuture = null;
    });

    return _resetLocalDataFuture!;
  }

  Future<void> clearUnfinishedDownloads() {
    final existing = _resetLocalDataFuture;
    if (existing != null) {
      return existing;
    }

    _clearingUnfinishedDownloads = true;

    void finishClearingUnfinishedDownloads() {
      _resetLocalDataFuture = null;
      _clearingUnfinishedDownloads = false;
    }

    _resetLocalDataFuture = _resetLocalData(unfinishedOnly: true).whenComplete(finishClearingUnfinishedDownloads);

    return _resetLocalDataFuture!;
  }

  Future<void> _resetLocalData({bool unfinishedOnly = false}) async {
    await _host._ensureLoaded();

    _host._resettingLocalData = true;
    _host._localDataRevision++;

    try {
      _localUserDataReloadTimer?.cancel();
      _localUserDataReloadTimer = null;

      _host._pendingArtworkHydration.clear();
      _host._pendingFileCleanupRequested = false;
      _host._topUpRequested = false;

      for (final download in _host._downloads) {
        if (unfinishedOnly && download.isDownloaded) {
          continue;
        }

        final key = _host._downloadKey(download);

        _host._removedDownloadKeys.add(key);
        _host._cancelRequested.add(key);
        _host._activeCancelPorts[key]?.send(null);
      }

      await _loadFuture;
      await _host._topUpFuture;
      await Future.wait(_host._active.values.toList(), eagerError: false);
      await _host._localUserDataReloadChain;
      await _host._pendingFileCleanupFuture;

      while (_pendingStorageOperations.isNotEmpty) {
        await Future.wait(_pendingStorageOperations.toList(), eagerError: false);
      }

      await _host._storage.close();

      if (unfinishedOnly) {
        await _host._storage.clearUnfinishedDownloads();
      } else {
        await _host._storage.resetLocalData();
      }

      _host._downloads = await _host._storage.readDownloads();
      _host._batches = await _host._storage.readDownloadBatches();
      _host._jobs = await _host._storage.readDownloadJobs();
      _host._localLiked = await _host._storage.readLocalLikedTracks();
      _host._localPlaylists = await _host._storage.readLocalPlaylists();

      if (!unfinishedOnly || !_host._localPlaylists.any((playlist) => playlist.id == _host._localPlaylistTracksId)) {
        _host._localPlaylistTracksId = null;
      }

      _host._localPlaylistTracks = _host._localPlaylistTracksId == null
          ? const <Track>[]
          : await _host._storage.readLocalPlaylistTracks(_host._localPlaylistTracksId!);
      _host._localDownloadedTracksCache = const <Track>[];

      final retainedJobs = _host._jobs.map((job) => job.jobId).toSet();

      _host._jobItemsByJobId.removeWhere((jobId, _) => !retainedJobs.contains(jobId));
      _host._jobSourcesByJobId.removeWhere((jobId, _) => !retainedJobs.contains(jobId));

      _host._albumArtPathById.clear();
      _host._artistArtPathByKey.clear();

      _host._pausedServerUrls.clear();
      _host._active.clear();
      _host._activeCancelPorts.clear();
      _host._lastScheduledQueueGroup = null;
      _host._topUpRequested = false;
      _host._queueAttemptSequence = 0;

      _host._rebuildDownloadIndexes();
      _host._emit();
      _host._emitBatches();
      _host._emitJobs();
      _host._emitLocalPlaylists();
      _host._emitLocalLiked();
      _host._emitLocalPlaylistTracks();
    } finally {
      _host._cancelRequested.clear();
      _host._removedDownloadKeys.clear();
      _host._artHydrationKeys.clear();
      _host._pendingArtworkHydration.clear();

      _host._resettingLocalData = false;
    }
  }

  bool _localDataCurrent(int revision) =>
      !_host._disposed && !_host._resettingLocalData && revision == _host._localDataRevision;

  Future<T> _storageOperation<T>(Future<T> Function() operation) async {
    final pending = operation();

    _pendingStorageOperations.add(pending);

    try {
      return await pending;
    } finally {
      _pendingStorageOperations.remove(pending);
    }
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _DownloadDataResetFacade {
  _DownloadDataReset get _ownerReset;

  Future<void>? get _loadFuture => _ownerReset._loadFuture;

  set _loadFuture(Future<void>? value) => _ownerReset._loadFuture = value;

  Future<void>? get _resetLocalDataFuture => _ownerReset._resetLocalDataFuture;

  Set<Future<dynamic>> get _pendingStorageOperations => _ownerReset._pendingStorageOperations;

  Timer? get _localUserDataReloadTimer => _ownerReset._localUserDataReloadTimer;

  set _localUserDataReloadTimer(Timer? value) => _ownerReset._localUserDataReloadTimer = value;

  Future<void> resetLocalData() => _ownerReset.resetLocalData();

  Future<void> clearUnfinishedDownloads() => _ownerReset.clearUnfinishedDownloads();

  bool _localDataCurrent(int revision) => _ownerReset._localDataCurrent(revision);

  Future<T> _storageOperation<T>(Future<T> Function() operation) => _ownerReset._storageOperation(operation);
}
