part of '../offline_download_client.dart';

class _DownloadStateStore {
  final _OfflineDownloadActorCore _host;
  final StreamController<List<OfflineTrackDownload>> _controller =
      StreamController<List<OfflineTrackDownload>>.broadcast();
  final StreamController<List<OfflineDownloadBatch>> _batchController =
      StreamController<List<OfflineDownloadBatch>>.broadcast();
  final StreamController<List<OfflineDownloadJob>> _jobController =
      StreamController<List<OfflineDownloadJob>>.broadcast();
  List<OfflineTrackDownload> _downloads = <OfflineTrackDownload>[];
  List<OfflineDownloadBatch> _batches = <OfflineDownloadBatch>[];
  OfflineDownloadIndex _downloadIndex = OfflineDownloadIndex(const []);
  List<Track> _localDownloadedTracksCache = const <Track>[];
  final Set<String> _removedDownloadKeys = <String>{};
  Timer? _downloadsEmitTimer;
  Timer? _batchesEmitTimer;
  Timer? _jobsEmitTimer;
  bool _disposed = false;

  _DownloadStateStore(this._host);

  OfflineTrackDownload? findForCurrentServer(String trackId) {
    return _host.find(_host.connection.baseUrl, trackId);
  }

  OfflineTrackDownload? find(String serverBaseUrl, String trackId) {
    return _downloadIndex.findServer(serverBaseUrl, trackId);
  }

  OfflineTrackDownload? findLocal(String localTrackId) {
    return _downloadIndex.findLocal(localTrackId);
  }

  List<Track> localDownloadedTracks() => _localDownloadedTracksCache;

  Future<bool> _replace(OfflineTrackDownload download, {required bool persist}) async {
    final dataRevision = _host._localDataRevision;

    if (!_host._localDataCurrent(dataRevision)) {
      return false;
    }

    final key = _host._downloadKey(download);

    if (_removedDownloadKeys.contains(key)) {
      await _host._recordPendingDownloadFiles(download);
      unawaited(_host._cleanupPendingFileDeletes());

      return false;
    }

    final prepared = download.localTrackId == null
        ? await _host._storageOperation(() => _host._storage.prepareDownload(download))
        : download;

    if (!_host._localDataCurrent(dataRevision)) {
      return false;
    }

    if (_removedDownloadKeys.contains(_host._downloadKey(prepared))) {
      await _host._recordPendingDownloadFiles(prepared);
      unawaited(_host._cleanupPendingFileDeletes());

      return false;
    }

    var replaced = false;
    var libraryChanged = _downloadPresentInLibrary(prepared);
    final next = <OfflineTrackDownload>[];

    for (final existing in _downloads) {
      final sameTrack =
          existing.serverBaseUrl == prepared.serverBaseUrl &&
          _host._serverTrackId(existing) == _host._serverTrackId(prepared);

      if (sameTrack) {
        next.add(prepared);
        replaced = true;
        libraryChanged = libraryChanged || _downloadPresentInLibrary(existing);
      } else {
        next.add(existing);
      }
    }

    if (!replaced) {
      next.add(prepared);
    }

    _downloads = next;
    _rebuildDownloadIndexes(rebuildLibrary: libraryChanged);
    _emit();

    if (persist) {
      await _host._storageOperation(() => _host._storage.upsertDownload(prepared));

      if (!_host._localDataCurrent(dataRevision)) {
        return false;
      }

      await _host._syncJobItemFromDownload(prepared);

      if (prepared.status != OfflineDownloadStatus.downloading && prepared.status != OfflineDownloadStatus.preparing) {
        _host._scheduleLocalUserDataReload();
      }

      final batchId = prepared.batchId;

      if (batchId != null && !_host._isRollingJob(batchId)) {
        await _refreshBatchCounts(batchId);
      }
    }

    return true;
  }

  void _clearObsoleteStopMarkersForQueue(OfflineTrackDownload download) {
    final key = _host._downloadKey(download);

    if (_host._active.containsKey(key)) {
      return;
    }

    _host._cancelRequested.remove(key);
    _removedDownloadKeys.remove(key);
  }

  Future<void> _retireServerDownloadJobIfUnused(String jobId) async {
    if (!_looksLikeV2DownloadJobId(jobId) ||
        _downloads.any((download) => download.batchId == jobId) ||
        _host.connection.token == null ||
        _host.connection.token!.isEmpty) {
      return;
    }

    try {
      await _host.connection.applyDownloadJobAction(jobId: jobId, action: 'delete');
    } catch (err, stackTrace) {
      developer.log(
        'Failed to retire v2 download job after local removal',
        name: 'OfflineDownloadManager',
        error: err,
        stackTrace: stackTrace,
      );
    }
  }

  bool _looksLikeV2DownloadJobId(String jobId) {
    return RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(jobId);
  }

  bool _downloadBelongsToV2Job(OfflineTrackDownload download) {
    final batchId = download.batchId;

    if (batchId == null || !_looksLikeV2DownloadJobId(batchId)) {
      return false;
    }

    final segments = Uri.tryParse(download.downloadUrl?.trim() ?? '')?.pathSegments;

    return segments != null &&
        segments.length >= 4 &&
        segments[segments.length - 4] == 'download' &&
        segments[segments.length - 3] == 'tracks' &&
        segments.last == 'file';
  }

  void _replaceManyInMemory(List<OfflineTrackDownload> downloads) {
    if (downloads.isEmpty) {
      return;
    }

    for (final download in downloads) {
      _clearObsoleteStopMarkersForQueue(download);
    }

    final byKey = {for (final download in downloads) _host._downloadKey(download): download};
    final next = <OfflineTrackDownload>[];
    final inserted = <String>{};

    for (final existing in _downloads) {
      final key = _host._downloadKey(existing);
      final replacement = byKey[key];

      if (replacement == null) {
        next.add(existing);
      } else {
        next.add(replacement);
        inserted.add(key);
      }
    }

    for (final download in downloads) {
      final key = _host._downloadKey(download);

      if (!inserted.contains(key)) {
        next.add(download);
      }
    }

    _downloads = next;
    _rebuildDownloadIndexes();
    _emit();
  }

  Iterable<List<T>> _chunks<T>(List<T> items, int size) sync* {
    for (var start = 0; start < items.length; start += size) {
      final end = start + size > items.length ? items.length : start + size;

      yield items.sublist(start, end);
    }
  }

  Future<void> _upsertBatch(OfflineDownloadBatch batch) async {
    if (_host._resettingLocalData || _disposed) {
      return;
    }

    var replaced = false;
    final batches = <OfflineDownloadBatch>[];

    for (final existing in _batches) {
      if (existing.batchId == batch.batchId) {
        replaced = true;
        batches.add(batch);
      } else {
        batches.add(existing);
      }
    }

    _batches = batches;

    if (!replaced) {
      _batches = [batch, ..._batches];
    }

    _emitBatches();

    await _host._storageOperation(() => _host._storage.upsertDownloadBatch(batch));
  }

  Future<void> _refreshBatchCounts(String batchId) async {
    OfflineDownloadBatch? batch;

    for (final item in _batches) {
      if (item.batchId == batchId) {
        batch = item;
        break;
      }
    }

    if (batch == null) {
      return;
    }

    final items = _downloads.where((download) => download.batchId == batchId).toList(growable: false);
    final completed = items.where((item) => item.status == OfflineDownloadStatus.downloaded).length;
    final failed = items
        .where(
          (item) =>
              item.status == OfflineDownloadStatus.failed ||
              item.status == OfflineDownloadStatus.corrupt ||
              item.status == OfflineDownloadStatus.canceled,
        )
        .length;
    final active = items.any((item) => DownloadQueueRules.hasActiveWork(item.status));
    final queued = items.any((item) => item.status == OfflineDownloadStatus.queued);
    final paused = items.isNotEmpty && items.every((item) => item.status == OfflineDownloadStatus.paused);
    final OfflineDownloadStatus status;

    if (completed >= batch.totalCount && batch.totalCount > 0) {
      status = OfflineDownloadStatus.downloaded;
    } else if (active) {
      status = OfflineDownloadStatus.downloading;
    } else if (paused) {
      status = OfflineDownloadStatus.paused;
    } else if (failed > 0 && !queued) {
      status = OfflineDownloadStatus.failed;
    } else {
      status = OfflineDownloadStatus.queued;
    }

    final updated = batch.copyWith(
      status: status,
      updatedAt: DateTime.now(),
      completedCount: completed,
      failedCount: failed,
    );

    if (batch.status == updated.status &&
        batch.completedCount == updated.completedCount &&
        batch.failedCount == updated.failedCount) {
      return;
    }

    _batches = _batches.map((item) => item.batchId == batchId ? updated : item).toList(growable: false);
    _emitBatches();

    await _host._storage.upsertDownloadBatch(updated);
  }

  void _emit() {
    if (_disposed || _controller.isClosed) {
      return;
    }

    if (_downloadsEmitTimer != null) {
      return;
    }

    void publishDownloads() {
      _downloadsEmitTimer = null;

      if (_disposed || _controller.isClosed) {
        return;
      }

      _controller.add(List.unmodifiable(_downloads));
    }

    _downloadsEmitTimer = Timer(_OfflineDownloadActorCore._stateEmitCoalesceDelay, publishDownloads);
  }

  void _emitBatches() {
    if (_disposed || _batchController.isClosed) {
      return;
    }

    if (_batchesEmitTimer != null) {
      return;
    }

    void publishBatches() {
      _batchesEmitTimer = null;

      if (_disposed || _batchController.isClosed) {
        return;
      }

      _batchController.add(List.unmodifiable(_batches));
    }

    _batchesEmitTimer = Timer(_OfflineDownloadActorCore._stateEmitCoalesceDelay, publishBatches);
  }

  void _emitJobs() {
    if (_disposed || _jobController.isClosed) {
      return;
    }

    if (_jobsEmitTimer != null) {
      return;
    }

    void publishJobs() {
      _jobsEmitTimer = null;

      if (_disposed || _jobController.isClosed) {
        return;
      }

      _jobController.add(List.unmodifiable(_host._jobs));
    }

    _jobsEmitTimer = Timer(_OfflineDownloadActorCore._stateEmitCoalesceDelay, publishJobs);
  }

  void _rebuildDownloadIndexes({bool rebuildLibrary = true}) {
    _downloadIndex = OfflineDownloadIndex(_downloads);
    // Transfer progress still needs fresh lookup records, but cannot change the
    // completed library. Reuse that projection until a visible record changes.
    if (rebuildLibrary) {
      _localDownloadedTracksCache = _computeLocalDownloadedTracks();
    }
  }

  List<Track> _computeLocalDownloadedTracks() {
    final likedLocalIds = {
      for (final track in _host._localLiked)
        if (track.localId != null) track.localId!,
    };
    final playlistTrackIds = <String>{};

    for (final playlist in _host._localPlaylists) {
      playlistTrackIds.addAll(playlist.trackIds);
    }

    final byLocalId = <String, Track>{};
    final newestByLocalId = <String, DateTime>{};

    for (final download in _downloads.where(_downloadPresentInLibrary)) {
      final localId = download.localTrackId ?? download.track.localId;

      if (localId == null || localId.isEmpty) {
        continue;
      }

      final previousUpdatedAt = newestByLocalId[localId];

      if (previousUpdatedAt != null && previousUpdatedAt.isAfter(download.updatedAt)) {
        continue;
      }

      newestByLocalId[localId] = download.updatedAt;
      byLocalId[localId] = download.track.copyWith(
        id: localId,
        localId: localId,
        serverBaseUrl: download.serverBaseUrl,
        serverTrackId: download.track.serverTrackId ?? download.track.id,
        liked: likedLocalIds.contains(localId),
        inPlaylists: playlistTrackIds.contains(localId),
      );
    }

    final tracks = byLocalId.values.toList();

    int compareLocalTracks(Track a, Track b) {
      final artist = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());

      if (artist != 0) {
        return artist;
      }

      final album = a.album.toLowerCase().compareTo(b.album.toLowerCase());

      if (album != 0) {
        return album;
      }

      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    }

    tracks.sort(compareLocalTracks);

    return List.unmodifiable(tracks);
  }

  String? _localTrackId(Track track) {
    final localId = track.localId;

    if (localId != null && localId.isNotEmpty) {
      return localId;
    }

    final byLocal = _downloads.where((download) => download.localTrackId == track.id).firstOrNull;

    if (byLocal?.localTrackId != null) {
      return byLocal!.localTrackId;
    }

    final serverTrackId = track.serverTrackId ?? track.id;
    final serverBaseUrl = track.serverBaseUrl ?? _host.connection.baseUrl;

    for (final download in _downloads) {
      if (download.serverBaseUrl == serverBaseUrl &&
          (download.track.id == serverTrackId || download.track.serverTrackId == serverTrackId)) {
        return download.localTrackId;
      }
    }

    return null;
  }

  bool _downloadAvailable(OfflineTrackDownload download) {
    final filePath = download.filePath;

    if (!download.isDownloaded || filePath == null || filePath.isEmpty) {
      return false;
    }

    return true;
  }

  bool _downloadPresentInLibrary(OfflineTrackDownload download) {
    final filePath = download.filePath;

    if (filePath == null || filePath.isEmpty) {
      return false;
    }

    if (download.status != OfflineDownloadStatus.downloaded && download.status != OfflineDownloadStatus.removing) {
      return false;
    }

    return true;
  }

  bool _downloadQueuedOrAvailable(OfflineTrackDownload? download) {
    if (download == null) {
      return false;
    }

    switch (download.status) {
      case OfflineDownloadStatus.queued:
      case OfflineDownloadStatus.preparing:
      case OfflineDownloadStatus.downloading:
      case OfflineDownloadStatus.validating:
      case OfflineDownloadStatus.removing:
        return true;
      case OfflineDownloadStatus.downloaded:
        return _downloadAvailable(download);
      case OfflineDownloadStatus.paused:
      case OfflineDownloadStatus.failed:
      case OfflineDownloadStatus.corrupt:
      case OfflineDownloadStatus.canceled:
        return false;
    }
  }

  bool _canPause(OfflineDownloadStatus status) => DownloadQueueRules.canPauseDownloadStatus(status);

  bool _activeDownloadStatus(OfflineDownloadStatus status) {
    return switch (status) {
      OfflineDownloadStatus.preparing || OfflineDownloadStatus.downloading || OfflineDownloadStatus.validating => true,
      OfflineDownloadStatus.queued ||
      OfflineDownloadStatus.paused ||
      OfflineDownloadStatus.downloaded ||
      OfflineDownloadStatus.removing ||
      OfflineDownloadStatus.failed ||
      OfflineDownloadStatus.corrupt ||
      OfflineDownloadStatus.canceled => false,
    };
  }

  bool _canResume(OfflineDownloadStatus status) {
    return switch (status) {
      OfflineDownloadStatus.paused ||
      OfflineDownloadStatus.failed ||
      OfflineDownloadStatus.corrupt ||
      OfflineDownloadStatus.canceled => true,
      OfflineDownloadStatus.queued ||
      OfflineDownloadStatus.preparing ||
      OfflineDownloadStatus.downloading ||
      OfflineDownloadStatus.validating ||
      OfflineDownloadStatus.downloaded ||
      OfflineDownloadStatus.removing => false,
    };
  }

  bool _sameDownloadList(List<OfflineTrackDownload> left, List<OfflineTrackDownload> right) {
    if (left.length != right.length) {
      return false;
    }

    for (var i = 0; i < left.length; i += 1) {
      final a = left[i];
      final b = right[i];

      if (a.status != b.status ||
          a.filePath != b.filePath ||
          a.error != b.error ||
          a.profile != b.profile ||
          a.renditionId != b.renditionId) {
        return false;
      }
    }

    return true;
  }

  bool _sameJobList(List<OfflineDownloadJob> left, List<OfflineDownloadJob> right) {
    if (left.length != right.length) {
      return false;
    }

    for (var i = 0; i < left.length; i += 1) {
      final a = left[i];
      final b = right[i];

      if (a.profile != b.profile ||
          a.serverJobId != b.serverJobId ||
          a.jobId != b.jobId ||
          a.status != b.status ||
          a.completedCount != b.completedCount ||
          a.failedCount != b.failedCount ||
          a.materializedCount != b.materializedCount ||
          a.sourceId != b.sourceId) {
        return false;
      }
    }

    return true;
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _DownloadStateStoreFacade {
  _DownloadStateStore get _ownerState;

  StreamController<List<OfflineTrackDownload>> get _controller => _ownerState._controller;

  StreamController<List<OfflineDownloadBatch>> get _batchController => _ownerState._batchController;

  StreamController<List<OfflineDownloadJob>> get _jobController => _ownerState._jobController;

  List<OfflineTrackDownload> get _downloads => _ownerState._downloads;

  set _downloads(List<OfflineTrackDownload> value) => _ownerState._downloads = value;

  List<OfflineDownloadBatch> get _batches => _ownerState._batches;

  set _batches(List<OfflineDownloadBatch> value) => _ownerState._batches = value;

  set _localDownloadedTracksCache(List<Track> value) => _ownerState._localDownloadedTracksCache = value;

  Set<String> get _removedDownloadKeys => _ownerState._removedDownloadKeys;

  Timer? get _downloadsEmitTimer => _ownerState._downloadsEmitTimer;

  set _downloadsEmitTimer(Timer? value) => _ownerState._downloadsEmitTimer = value;

  Timer? get _batchesEmitTimer => _ownerState._batchesEmitTimer;

  set _batchesEmitTimer(Timer? value) => _ownerState._batchesEmitTimer = value;

  Timer? get _jobsEmitTimer => _ownerState._jobsEmitTimer;

  set _jobsEmitTimer(Timer? value) => _ownerState._jobsEmitTimer = value;

  bool get _disposed => _ownerState._disposed;

  set _disposed(bool value) => _ownerState._disposed = value;

  OfflineTrackDownload? findForCurrentServer(String trackId) => _ownerState.findForCurrentServer(trackId);

  OfflineTrackDownload? find(String serverBaseUrl, String trackId) => _ownerState.find(serverBaseUrl, trackId);

  OfflineTrackDownload? findLocal(String localTrackId) => _ownerState.findLocal(localTrackId);

  List<Track> localDownloadedTracks() => _ownerState.localDownloadedTracks();

  Future<bool> _replace(OfflineTrackDownload download, {required bool persist}) =>
      _ownerState._replace(download, persist: persist);

  void _clearObsoleteStopMarkersForQueue(OfflineTrackDownload download) =>
      _ownerState._clearObsoleteStopMarkersForQueue(download);

  Future<void> _retireServerDownloadJobIfUnused(String jobId) => _ownerState._retireServerDownloadJobIfUnused(jobId);

  bool _looksLikeV2DownloadJobId(String jobId) => _ownerState._looksLikeV2DownloadJobId(jobId);

  bool _downloadBelongsToV2Job(OfflineTrackDownload download) => _ownerState._downloadBelongsToV2Job(download);

  void _replaceManyInMemory(List<OfflineTrackDownload> downloads) => _ownerState._replaceManyInMemory(downloads);

  Iterable<List<T>> _chunks<T>(List<T> items, int size) => _ownerState._chunks(items, size);

  Future<void> _upsertBatch(OfflineDownloadBatch batch) => _ownerState._upsertBatch(batch);

  Future<void> _refreshBatchCounts(String batchId) => _ownerState._refreshBatchCounts(batchId);

  void _emit() => _ownerState._emit();

  void _emitBatches() => _ownerState._emitBatches();

  void _emitJobs() => _ownerState._emitJobs();

  void _rebuildDownloadIndexes({bool rebuildLibrary = true}) =>
      _ownerState._rebuildDownloadIndexes(rebuildLibrary: rebuildLibrary);

  String? _localTrackId(Track track) => _ownerState._localTrackId(track);

  bool _downloadAvailable(OfflineTrackDownload download) => _ownerState._downloadAvailable(download);

  bool _downloadQueuedOrAvailable(OfflineTrackDownload? download) => _ownerState._downloadQueuedOrAvailable(download);

  bool _canPause(OfflineDownloadStatus status) => _ownerState._canPause(status);

  bool _activeDownloadStatus(OfflineDownloadStatus status) => _ownerState._activeDownloadStatus(status);

  bool _canResume(OfflineDownloadStatus status) => _ownerState._canResume(status);

  bool _sameDownloadList(List<OfflineTrackDownload> left, List<OfflineTrackDownload> right) =>
      _ownerState._sameDownloadList(left, right);

  bool _sameJobList(List<OfflineDownloadJob> left, List<OfflineDownloadJob> right) =>
      _ownerState._sameJobList(left, right);
}
