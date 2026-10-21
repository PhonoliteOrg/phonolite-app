part of 'package:phonolite_app/infrastructure/downloads/client/offline_download_client.dart';

class _LocalCollectionCommands {
  final _OfflineDownloadActorCore _host;
  final StreamController<List<Track>> _localLikedController = StreamController<List<Track>>.broadcast();
  final StreamController<List<Playlist>> _localPlaylistsController = StreamController<List<Playlist>>.broadcast();
  final StreamController<List<Track>> _localPlaylistTracksController = StreamController<List<Track>>.broadcast();
  List<Track> _localLiked = <Track>[];
  List<Playlist> _localPlaylists = <Playlist>[];
  List<Track> _localPlaylistTracks = <Track>[];
  String? _localPlaylistTracksId;
  Future<void> _localUserDataReloadChain = Future<void>.value();

  _LocalCollectionCommands(this._host);

  Future<void> loadLocalPlaylists() async {
    _localPlaylists = await _host._storage.readLocalPlaylists();

    _host._rebuildDownloadIndexes();
    _emitLocalPlaylists();
  }

  Future<void> loadLocalPlaylistTracks(String playlistId) async {
    _localPlaylistTracksId = playlistId;

    _localPlaylistTracks = await _host._storage.readLocalPlaylistTracks(playlistId);

    _emitLocalPlaylistTracks();
  }

  Future<void> loadLocalLikedTracks() async {
    _localLiked = await _host._storage.readLocalLikedTracks();

    _host._rebuildDownloadIndexes();
    _emitLocalLiked();
  }

  Future<void> setLocalLike(Track track, bool liked) async {
    final localId = _host._localTrackId(track);
    if (localId == null) {
      throw StateError('Track must be downloaded before saving local likes.');
    }

    await _host._storage.setLocalLike(localId, liked);

    await _loadLocalUserData();
  }

  Future<List<LocalLikeState>> readLocalLikeStates() {
    return _host._storage.readLocalLikeStates();
  }

  Future<Playlist> createLocalPlaylist(String name, {String? description}) async {
    final playlist = await _host._storage.createLocalPlaylist(name, description: description);

    await _host.loadLocalPlaylists();

    return playlist;
  }

  Future<Playlist> downloadPlaylist(OfflineDownloadPlaylistRequest request) async {
    final dataRevision = _host._localDataRevision;

    void requireCurrentData() {
      if (!_host._localDataCurrent(dataRevision)) {
        throw StateError('Playlist download canceled by local data reset.');
      }
    }

    await _host._ensureLoaded();
    requireCurrentData();

    final baseUrl = _host.connection.baseUrl;

    if (request.name.trim().isEmpty) {
      throw ArgumentError('Playlist name is required.');
    }

    final tracksById = {for (final track in request.tracks) track.id: track};
    final orderedTracks = [
      for (final id in request.playlist.trackIds)
        tracksById[id] ?? (throw StateError('Playlist track $id is unavailable.')),
    ];
    var imageEdit = request.imageEdit;
    final imageRef = request.playlist.imageRef?.trim();

    if (imageEdit.kind == PlaylistImageEditKind.keep && imageRef != null && imageRef.isNotEmpty) {
      final artwork = await _host.connection.fetchPlaylistCoverBytes(request.playlist.id, imageRef: imageRef);

      requireCurrentData();

      if (artwork == null) {
        throw StateError('Playlist artwork could not be downloaded.');
      }

      imageEdit = PlaylistImageEdit.replace(
        bytes: Uint8List.fromList(artwork.bytes),
        contentType: artwork.contentType ?? 'application/octet-stream',
      );
    }

    if (_host.connection.baseUrl != baseUrl) {
      throw StateError('The server changed while downloading the playlist.');
    }

    await _host.queueTracks(orderedTracks, label: request.name, kind: 'playlist', sourceId: request.playlist.id);
    requireCurrentData();

    // Persist order separately from the queue, which deduplicates track downloads.
    var localPlaylist = await _host._storageOperation(
      () => _host._storage.createLocalPlaylist(
        request.name,
        description: request.description,
        downloadServerBaseUrl: baseUrl,
        downloadTrackIds: orderedTracks.map((track) => track.id).toList(),
      ),
    );

    requireCurrentData();

    try {
      if (imageEdit.kind == PlaylistImageEditKind.replace) {
        localPlaylist =
            await _host._storageOperation(() => _host._storage.updateLocalPlaylistImage(localPlaylist.id, imageEdit)) ??
            localPlaylist;
      }

      requireCurrentData();

      await _loadLocalUserData();

      return localPlaylist;
    } catch (_) {
      if (!_host._localDataCurrent(dataRevision)) {
        rethrow;
      }

      await _host._storage.deleteLocalPlaylist(localPlaylist.id);
      await _loadLocalUserData();

      rethrow;
    }
  }

  Future<Playlist?> renameLocalPlaylist(String playlistId, String name, {String? description}) async {
    final playlist = await _host._storage.renameLocalPlaylist(playlistId, name, description: description);

    await _host.loadLocalPlaylists();

    return playlist;
  }

  Future<Playlist?> updateLocalPlaylistImage(String playlistId, PlaylistImageEdit imageEdit) async {
    final playlist = await _host._storage.updateLocalPlaylistImage(playlistId, imageEdit);

    await _host.loadLocalPlaylists();

    return playlist;
  }

  Future<void> deleteLocalPlaylist(String playlistId) async {
    await _host._storage.deleteLocalPlaylist(playlistId);

    await _host.loadLocalPlaylists();

    if (_localPlaylistTracksId == playlistId) {
      _localPlaylistTracksId = null;
      _localPlaylistTracks = <Track>[];
      _emitLocalPlaylistTracks();
    }
  }

  Future<Playlist?> addLocalTrackToPlaylist(Playlist playlist, Track track) async {
    final localId = _host._localTrackId(track);
    if (localId == null) {
      throw StateError('Track must be downloaded before saving local playlists.');
    }

    final updated = await _host._storage.addLocalTrackToPlaylist(playlist.id, localId);

    await _loadLocalUserData();

    return updated;
  }

  Future<Playlist?> removeLocalTrackFromPlaylist(Playlist playlist, Track track) async {
    final localId = _host._localTrackId(track);
    if (localId == null) {
      return playlist;
    }

    final updated = await _host._storage.removeLocalTrackFromPlaylist(playlist.id, localId);

    await _loadLocalUserData();

    return updated;
  }

  Future<void> _loadLocalUserData() async {
    final dataRevision = _host._localDataRevision;

    if (!_host._localDataCurrent(dataRevision)) {
      return;
    }

    final playlists = await _host._storage.readLocalPlaylists();
    final liked = await _host._storage.readLocalLikedTracks();

    if (!_host._localDataCurrent(dataRevision)) {
      return;
    }

    _localPlaylists = playlists;
    _localLiked = liked;

    final playlistId = _localPlaylistTracksId;

    if (playlistId != null && _localPlaylists.any((playlist) => playlist.id == playlistId)) {
      _localPlaylistTracks = await _host._storage.readLocalPlaylistTracks(playlistId);
    } else if (playlistId != null) {
      _localPlaylistTracksId = null;
      _localPlaylistTracks = <Track>[];
    }

    _host._rebuildDownloadIndexes();
    _emitLocalPlaylists();
    _emitLocalLiked();
    _emitLocalPlaylistTracks();
  }

  void _scheduleLocalUserDataReload() {
    final dataRevision = _host._localDataRevision;

    if (!_host._localDataCurrent(dataRevision)) {
      return;
    }

    _host._localUserDataReloadTimer?.cancel();

    void enqueueReload() {
      Future<void> reloadIfCurrent(void _) async {
        if (!_host._localDataCurrent(dataRevision)) {
          return;
        }

        try {
          await _loadLocalUserData();
        } catch (err) {
          AppLogger.warning('Failed to refresh local offline data: $err');
        }
      }

      _localUserDataReloadChain = _localUserDataReloadChain.then(reloadIfCurrent);
      unawaited(_localUserDataReloadChain);
    }

    _host._localUserDataReloadTimer = Timer(_OfflineDownloadActorCore._localUserDataReloadDelay, enqueueReload);
  }

  void _emitLocalLiked() {
    if (_host._disposed || _localLikedController.isClosed) {
      return;
    }

    _localLikedController.add(List.unmodifiable(_localLiked));
  }

  void _emitLocalPlaylists() {
    if (_host._disposed || _localPlaylistsController.isClosed) {
      return;
    }

    _localPlaylistsController.add(List.unmodifiable(_localPlaylists));
  }

  void _emitLocalPlaylistTracks() {
    if (_host._disposed || _localPlaylistTracksController.isClosed) {
      return;
    }

    _localPlaylistTracksController.add(List.unmodifiable(_localPlaylistTracks));
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _LocalCollectionCommandsFacade {
  _LocalCollectionCommands get _ownerCollections;

  StreamController<List<Track>> get _localLikedController => _ownerCollections._localLikedController;

  StreamController<List<Playlist>> get _localPlaylistsController => _ownerCollections._localPlaylistsController;

  StreamController<List<Track>> get _localPlaylistTracksController => _ownerCollections._localPlaylistTracksController;

  List<Track> get _localLiked => _ownerCollections._localLiked;

  set _localLiked(List<Track> value) => _ownerCollections._localLiked = value;

  List<Playlist> get _localPlaylists => _ownerCollections._localPlaylists;

  set _localPlaylists(List<Playlist> value) => _ownerCollections._localPlaylists = value;

  List<Track> get _localPlaylistTracks => _ownerCollections._localPlaylistTracks;

  set _localPlaylistTracks(List<Track> value) => _ownerCollections._localPlaylistTracks = value;

  String? get _localPlaylistTracksId => _ownerCollections._localPlaylistTracksId;

  set _localPlaylistTracksId(String? value) => _ownerCollections._localPlaylistTracksId = value;

  Future<void> get _localUserDataReloadChain => _ownerCollections._localUserDataReloadChain;

  Future<void> loadLocalPlaylists() => _ownerCollections.loadLocalPlaylists();

  Future<void> loadLocalPlaylistTracks(String playlistId) => _ownerCollections.loadLocalPlaylistTracks(playlistId);

  Future<void> loadLocalLikedTracks() => _ownerCollections.loadLocalLikedTracks();

  Future<void> setLocalLike(Track track, bool liked) => _ownerCollections.setLocalLike(track, liked);

  Future<List<LocalLikeState>> readLocalLikeStates() => _ownerCollections.readLocalLikeStates();

  Future<Playlist> createLocalPlaylist(String name, {String? description}) =>
      _ownerCollections.createLocalPlaylist(name, description: description);

  Future<Playlist> downloadPlaylist(OfflineDownloadPlaylistRequest request) =>
      _ownerCollections.downloadPlaylist(request);

  Future<Playlist?> renameLocalPlaylist(String playlistId, String name, {String? description}) =>
      _ownerCollections.renameLocalPlaylist(playlistId, name, description: description);

  Future<Playlist?> updateLocalPlaylistImage(String playlistId, PlaylistImageEdit imageEdit) =>
      _ownerCollections.updateLocalPlaylistImage(playlistId, imageEdit);

  Future<void> deleteLocalPlaylist(String playlistId) => _ownerCollections.deleteLocalPlaylist(playlistId);

  Future<Playlist?> addLocalTrackToPlaylist(Playlist playlist, Track track) =>
      _ownerCollections.addLocalTrackToPlaylist(playlist, track);

  Future<Playlist?> removeLocalTrackFromPlaylist(Playlist playlist, Track track) =>
      _ownerCollections.removeLocalTrackFromPlaylist(playlist, track);

  Future<void> _loadLocalUserData() => _ownerCollections._loadLocalUserData();

  void _scheduleLocalUserDataReload() => _ownerCollections._scheduleLocalUserDataReload();

  void _emitLocalLiked() => _ownerCollections._emitLocalLiked();

  void _emitLocalPlaylists() => _ownerCollections._emitLocalPlaylists();

  void _emitLocalPlaylistTracks() => _ownerCollections._emitLocalPlaylistTracks();
}
