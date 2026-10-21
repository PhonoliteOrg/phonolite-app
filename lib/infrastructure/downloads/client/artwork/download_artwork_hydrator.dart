part of 'package:phonolite_app/infrastructure/downloads/client/offline_download_client.dart';

class _DownloadArtworkHydrator {
  final _OfflineDownloadActorCore _host;
  final Set<String> _artHydrationKeys = <String>{};
  final Map<String, OfflineTrackDownload> _pendingArtworkHydration = <String, OfflineTrackDownload>{};
  final Map<String, String?> _albumArtPathById = <String, String?>{};
  final Map<String, String?> _artistArtPathByKey = <String, String?>{};
  bool _artHydrationRunning = false;

  _DownloadArtworkHydrator(this._host);

  void _queueArtworkHydration(OfflineTrackDownload download) {
    final localTrackId = download.localTrackId ?? download.track.localId;

    if (localTrackId == null || localTrackId.isEmpty) {
      return;
    }

    final key = '${download.serverBaseUrl}|$localTrackId';

    _pendingArtworkHydration[key] = download;

    if (!_artHydrationRunning) {
      unawaited(_drainArtworkHydrationQueue());
    }
  }

  Future<void> _drainArtworkHydrationQueue() async {
    if (_artHydrationRunning) {
      return;
    }

    _artHydrationRunning = true;
    final dataRevision = _host._localDataRevision;
    final albumArtById = <String, String?>{};
    final artistLogoById = <String, String?>{};
    final artistBannerById = <String, String?>{};

    try {
      while (_pendingArtworkHydration.isNotEmpty && _host._localDataCurrent(dataRevision)) {
        final key = _pendingArtworkHydration.keys.first;
        final download = _pendingArtworkHydration.remove(key);
        if (download == null) {
          continue;
        }

        await Future<void>.delayed(_OfflineDownloadActorCore._artworkHydrationDelay);

        if (!_host._localDataCurrent(dataRevision)) {
          break;
        }

        await _hydrateArtworkForDownload(
          download,
          albumArtById: albumArtById,
          artistLogoById: artistLogoById,
          artistBannerById: artistBannerById,
        );
      }
    } finally {
      _artHydrationRunning = false;

      if (_pendingArtworkHydration.isNotEmpty && !_host._disposed && !_host._resettingLocalData) {
        unawaited(_drainArtworkHydrationQueue());
      }
    }
  }

  Future<void> _hydrateArtworkForDownload(
    OfflineTrackDownload download, {
    Map<String, String?>? albumArtById,
    Map<String, String?>? artistLogoById,
    Map<String, String?>? artistBannerById,
  }) async {
    final dataRevision = _host._localDataRevision;
    final localTrackId = download.localTrackId ?? download.track.localId;

    if (localTrackId == null || localTrackId.isEmpty) {
      return;
    }

    final key = '${download.serverBaseUrl}|$localTrackId';

    if (!_artHydrationKeys.add(key)) {
      return;
    }

    try {
      if (_host._disposed ||
          _host._resettingLocalData ||
          _host.connection.baseUrl != download.serverBaseUrl ||
          _host.connection.token == null ||
          _host.connection.token!.isEmpty) {
        return;
      }

      final paths = await _fetchAndStoreArtwork(
        download.track,
        dataRevision: dataRevision,
        albumArtById: albumArtById ?? <String, String?>{},
        artistLogoById: artistLogoById ?? <String, String?>{},
        artistBannerById: artistBannerById ?? <String, String?>{},
      );

      if (paths.isEmpty) {
        return;
      }

      if (!_host._localDataCurrent(dataRevision)) {
        return;
      }

      await _host._storageOperation(
        () => _host._storage.updateTrackArtPaths(
          localTrackId,
          albumArtPath: paths.albumArtPath,
          artistArtPath: paths.artistArtPath,
          artistBannerPath: paths.artistBannerPath,
          artworkSource: download.track,
        ),
      );

      if (!_host._localDataCurrent(dataRevision)) {
        return;
      }

      _applyArtworkPaths(localTrackId, paths, download.track);
      _host._scheduleLocalUserDataReload();
    } catch (err) {
      if (!_host._localDataCurrent(dataRevision)) {
        return;
      }

      AppLogger.warning('Failed to cache offline artwork for ${download.track.title}: $err');
    } finally {
      _artHydrationKeys.remove(key);
    }
  }

  Future<DownloadArtworkPaths> _fetchAndStoreArtwork(
    Track track, {
    required int dataRevision,
    required Map<String, String?> albumArtById,
    required Map<String, String?> artistLogoById,
    required Map<String, String?> artistBannerById,
  }) async {
    final albumArtPath =
        _existingArtworkPath(track.albumArtPath) ?? await _fetchAlbumArt(track.albumId, albumArtById, dataRevision);

    if (!_host._localDataCurrent(dataRevision)) {
      return const DownloadArtworkPaths();
    }

    final artistArtPath =
        _existingArtworkPath(track.artistArtPath) ??
        await _fetchArtistArt(track.artistId, 'logo', artistLogoById, dataRevision);

    if (!_host._localDataCurrent(dataRevision)) {
      return const DownloadArtworkPaths();
    }

    final artistBannerPath =
        _existingArtworkPath(track.artistBannerPath) ??
        await _fetchArtistArt(track.artistId, 'banner', artistBannerById, dataRevision);

    return DownloadArtworkPaths(
      albumArtPath: albumArtPath,
      artistArtPath: artistArtPath,
      artistBannerPath: artistBannerPath,
    );
  }

  Future<String?> _fetchAlbumArt(String? albumId, Map<String, String?> albumArtById, int dataRevision) async {
    if (!_host._localDataCurrent(dataRevision)) {
      return null;
    }

    final id = albumId?.trim();

    if (id == null || id.isEmpty) {
      return null;
    }

    if (albumArtById.containsKey(id)) {
      return albumArtById[id];
    }

    if (_albumArtPathById.containsKey(id)) {
      final path = _albumArtPathById[id];

      albumArtById[id] = path;

      return path;
    }

    final artwork = await _host.connection.fetchAlbumCoverBytes(id);

    if (!_host._localDataCurrent(dataRevision)) {
      return null;
    }

    final path = artwork == null ? null : await _host._storageOperation(() => _storeAlbumArtwork(id, artwork));

    if (!_host._localDataCurrent(dataRevision)) {
      return null;
    }

    _albumArtPathById[id] = path;
    albumArtById[id] = path;

    return path;
  }

  Future<String?> _fetchArtistArt(
    String? artistId,
    String kind,
    Map<String, String?> artistArtById,
    int dataRevision,
  ) async {
    if (!_host._localDataCurrent(dataRevision)) {
      return null;
    }

    final id = artistId?.trim();

    if (id == null || id.isEmpty) {
      return null;
    }

    final key = '$id|$kind';

    if (artistArtById.containsKey(key)) {
      return artistArtById[key];
    }

    if (_artistArtPathByKey.containsKey(key)) {
      final path = _artistArtPathByKey[key];

      artistArtById[key] = path;

      return path;
    }

    final artwork = await _host.connection.fetchArtistCoverBytes(id, kind: kind);

    if (!_host._localDataCurrent(dataRevision)) {
      return null;
    }

    final path = artwork == null ? null : await _host._storageOperation(() => _storeArtistArtwork(id, kind, artwork));

    if (!_host._localDataCurrent(dataRevision)) {
      return null;
    }

    _artistArtPathByKey[key] = path;
    artistArtById[key] = path;

    return path;
  }

  Future<String> _storeAlbumArtwork(String albumId, ServerArtwork artwork) async {
    final file = await _host._storage.albumArtFile(
      albumId: albumId,
      extension: OfflineLibraryStorage.extensionFromImageContentType(artwork.contentType),
    );

    await file.writeAsBytes(artwork.bytes, flush: true);

    return file.path;
  }

  Future<String> _storeArtistArtwork(String artistId, String kind, ServerArtwork artwork) async {
    final file = await _host._storage.artistArtFile(
      artistId: artistId,
      kind: kind,
      extension: OfflineLibraryStorage.extensionFromImageContentType(artwork.contentType),
    );

    await file.writeAsBytes(artwork.bytes, flush: true);

    return file.path;
  }

  String? _existingArtworkPath(String? path) {
    final trimmed = path?.trim();

    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }

    return File(trimmed).existsSync() ? trimmed : null;
  }

  void _applyArtworkPaths(String localTrackId, DownloadArtworkPaths paths, Track artworkSource) {
    var changed = false;
    final downloads = <OfflineTrackDownload>[];

    for (final download in _host._downloads) {
      final id = download.localTrackId ?? download.track.localId;

      if (id != localTrackId) {
        downloads.add(download);
        continue;
      }

      changed = true;
      downloads.add(download.copyWith(track: _trackWithArtwork(download.track, paths, artworkSource)));
    }

    _host._downloads = downloads.toList(growable: false);

    if (changed) {
      _host._rebuildDownloadIndexes();
      _host._emit();
    }
  }

  Track _trackWithArtwork(Track track, DownloadArtworkPaths paths, Track artworkSource) {
    final sameArtist = track.artistArtworkIdentity == artworkSource.artistArtworkIdentity;

    return track.copyWith(
      albumArtPath: paths.albumArtPath ?? track.albumArtPath,
      artistArtPath: (sameArtist ? paths.artistArtPath : null) ?? track.artistArtPath,
      artistBannerPath: (sameArtist ? paths.artistBannerPath : null) ?? track.artistBannerPath,
    );
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _DownloadArtworkHydratorFacade {
  _DownloadArtworkHydrator get _ownerArtwork;

  Set<String> get _artHydrationKeys => _ownerArtwork._artHydrationKeys;

  Map<String, OfflineTrackDownload> get _pendingArtworkHydration => _ownerArtwork._pendingArtworkHydration;

  Map<String, String?> get _albumArtPathById => _ownerArtwork._albumArtPathById;

  Map<String, String?> get _artistArtPathByKey => _ownerArtwork._artistArtPathByKey;

  void _queueArtworkHydration(OfflineTrackDownload download) => _ownerArtwork._queueArtworkHydration(download);
}
