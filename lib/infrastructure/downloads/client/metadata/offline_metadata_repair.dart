part of 'package:phonolite_app/infrastructure/downloads/client/offline_download_client.dart';

class _OfflineMetadataRepair {
  final _OfflineDownloadActorCore _host;
  Future<void>? _metadataRepairFuture;

  _OfflineMetadataRepair(this._host);

  Future<void> repairOfflineMetadataFragments() async {
    await _host._ensureLoaded();

    await _repairOfflineMetadataFragments();
  }

  Future<void> refreshOfflineMetadataForAlbum(String albumId) async {
    await _host._ensureLoaded();

    final id = albumId.trim();

    if (id.isEmpty) {
      return;
    }

    await _refreshOfflineMetadataWhere(
      (download) =>
          _host._nonEmpty(download.track.albumId) == id || _host._nonEmpty(download.offlineMetadata?.album.id) == id,
    );
  }

  Future<void> refreshOfflineMetadataForArtist(String artistId) async {
    await _host._ensureLoaded();

    final id = artistId.trim();

    if (id.isEmpty) {
      return;
    }

    await _refreshOfflineMetadataWhere(
      (download) =>
          _host._nonEmpty(download.track.artistId) == id ||
          download.track.credits.any((credit) => credit.artistId == id) ||
          (download.offlineMetadata?.album.credits.any((credit) => credit.artistId == id) ?? false) ||
          _host._nonEmpty(download.offlineMetadata?.artist.id) == id,
    );
  }

  Future<void> _repairOfflineMetadataFragments() {
    final existing = _metadataRepairFuture;
    if (existing != null) {
      return existing;
    }

    final future = _runOfflineMetadataRepair();

    _metadataRepairFuture = future.whenComplete(() {
      _metadataRepairFuture = null;
    });

    return _metadataRepairFuture!;
  }

  Future<void> _runOfflineMetadataRepair() async {
    final dataRevision = _host._localDataRevision;

    if (_host._disposed || _host._resettingLocalData) {
      return;
    }

    final token = _host.connection.token;

    if (token == null || token.trim().isEmpty) {
      return;
    }

    final sessionRevision = _host.connection.sessionRevision;
    final attemptedKeys = <String>{};
    final repairedKeys = <String>{};

    while (attemptedKeys.length < _OfflineDownloadActorCore._metadataRepairMaxPerRun &&
        _host._localDataCurrent(dataRevision) &&
        _host.connection.sessionRevision == sessionRevision) {
      final remaining = _OfflineDownloadActorCore._metadataRepairMaxPerRun - attemptedKeys.length;
      final requests =
          (await _host._storageOperation(
                () => _host._storage.readMetadataRepairRequests(
                  _host.connection.baseUrl,
                  limit: remaining < _OfflineDownloadActorCore._metadataRepairBatchSize
                      ? remaining
                      : _OfflineDownloadActorCore._metadataRepairBatchSize,
                ),
              ))
              .where(
                (request) => !attemptedKeys.contains(_host._lookupKey(request.serverBaseUrl, request.serverTrackId)),
              )
              .toList(growable: false);

      if (!_host._localDataCurrent(dataRevision) || requests.isEmpty) {
        break;
      }

      for (final request in requests) {
        attemptedKeys.add(_host._lookupKey(request.serverBaseUrl, request.serverTrackId));
      }

      final repaired = await _repairOfflineMetadataRequests(requests);

      if (repaired.isEmpty) {
        break;
      }

      repairedKeys.addAll(repaired);
    }

    if (repairedKeys.isEmpty || !_host._localDataCurrent(dataRevision)) {
      return;
    }

    await _reloadAfterOfflineMetadataRepair(repairedKeys);
  }

  Future<void> _refreshOfflineMetadataWhere(bool Function(OfflineTrackDownload download) matches) async {
    final dataRevision = _host._localDataRevision;

    if (_host._disposed || _host._resettingLocalData) {
      return;
    }

    final token = _host.connection.token;

    if (token == null || token.trim().isEmpty) {
      return;
    }

    final requests = <OfflineMetadataRepairRequest>[];
    final seen = <String>{};

    for (final download in _host._downloads) {
      if (download.serverBaseUrl != _host.connection.baseUrl ||
          !_host._downloadAvailable(download) ||
          !matches(download)) {
        continue;
      }

      final serverTrackId = _host._serverTrackId(download).trim();

      if (serverTrackId.isEmpty) {
        continue;
      }

      final key = _host._lookupKey(download.serverBaseUrl, serverTrackId);

      if (!seen.add(key)) {
        continue;
      }

      requests.add(OfflineMetadataRepairRequest(serverBaseUrl: download.serverBaseUrl, serverTrackId: serverTrackId));
    }

    if (requests.isEmpty) {
      return;
    }

    final repairedKeys = await _repairOfflineMetadataRequests(requests);

    if (repairedKeys.isEmpty || !_host._localDataCurrent(dataRevision)) {
      return;
    }

    await _reloadAfterOfflineMetadataRepair(repairedKeys);
  }

  Future<Set<String>> _repairOfflineMetadataRequests(List<OfflineMetadataRepairRequest> requests) async {
    final serverBaseUrl = _host.connection.baseUrl;
    final sessionRevision = _host.connection.sessionRevision;
    final dataRevision = _host._localDataRevision;

    bool shouldPersist() =>
        _host._localDataCurrent(dataRevision) && _host.connection.sessionRevision == sessionRevision;

    final repairedKeys = <String>{};

    for (var index = 0; index < requests.length; index += _OfflineDownloadActorCore._maxParallelMetadataRepairs) {
      if (!shouldPersist()) {
        break;
      }

      final chunk = requests
          .skip(index)
          .take(_OfflineDownloadActorCore._maxParallelMetadataRepairs)
          .where((request) => request.serverBaseUrl == serverBaseUrl)
          .toList(growable: false);

      Future<MapEntry<String, OfflineTrackMetadata>?> repairMetadata(OfflineMetadataRepairRequest request) async {
        final metadata = await _fetchOfflineMetadataForRepair(request, dataRevision);

        return metadata == null ? null : MapEntry(request.serverTrackId, metadata);
      }

      final results = await Future.wait(chunk.map(repairMetadata));

      if (!shouldPersist()) {
        break;
      }

      final metadataByTrackId = Map<String, OfflineTrackMetadata>.fromEntries(
        results.whereType<MapEntry<String, OfflineTrackMetadata>>(),
      );

      try {
        final persisted = await _host._storageOperation(
          () => _host._storage.upsertOfflineMetadataFragments(
            serverBaseUrl,
            metadataByTrackId,
            shouldPersist: shouldPersist,
          ),
        );

        repairedKeys.addAll(persisted.map((trackId) => _host._lookupKey(serverBaseUrl, trackId)));
      } catch (err) {
        AppLogger.debug('Failed to persist offline metadata repair chunk: $err');
      }
    }

    return repairedKeys;
  }

  Future<void> _reloadAfterOfflineMetadataRepair(Set<String> repairedKeys) async {
    final dataRevision = _host._localDataRevision;

    if (!_host._localDataCurrent(dataRevision)) {
      return;
    }

    final downloads = await _host._storageOperation(_host._storage.readDownloads);

    if (!_host._localDataCurrent(dataRevision)) {
      return;
    }

    _host._downloads = downloads;
    _host._rebuildDownloadIndexes();

    await _host._loadLocalUserData();

    for (final download in _host._downloads) {
      if (repairedKeys.contains(_host._downloadKey(download)) && _host._downloadAvailable(download)) {
        _host._queueArtworkHydration(download);
      }
    }

    _host._emit();
  }

  Future<OfflineTrackMetadata?> _fetchOfflineMetadataForRepair(
    OfflineMetadataRepairRequest request,
    int dataRevision,
  ) async {
    try {
      return await _host.connection.fetchOfflineMetadata(request.serverTrackId);
    } catch (err) {
      if (!_host._localDataCurrent(dataRevision)) {
        return null;
      }

      AppLogger.debug('Failed to repair offline metadata for ${request.serverTrackId}: $err');

      return null;
    }
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _OfflineMetadataRepairFacade {
  _OfflineMetadataRepair get _ownerMetadata;

  Future<void> repairOfflineMetadataFragments() => _ownerMetadata.repairOfflineMetadataFragments();

  Future<void> refreshOfflineMetadataForAlbum(String albumId) => _ownerMetadata.refreshOfflineMetadataForAlbum(albumId);

  Future<void> refreshOfflineMetadataForArtist(String artistId) =>
      _ownerMetadata.refreshOfflineMetadataForArtist(artistId);

  Future<void> _repairOfflineMetadataFragments() => _ownerMetadata._repairOfflineMetadataFragments();
}
