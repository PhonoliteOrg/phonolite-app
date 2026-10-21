part of 'package:phonolite_app/application/app/app_controller.dart';

class _PlaylistCoordinator {
  final AppController _host;
  final _playlistsController = StreamController<List<Playlist>>.broadcast();
  final _playlistTracksController = StreamController<List<Track>>.broadcast();
  List<Playlist> _playlists = <Playlist>[];
  List<Track> _playlistTracks = <Track>[];
  final _playlistTrackRequests = RequestGeneration();
  String? _currentPlaylistId;

  _PlaylistCoordinator(this._host);

  Stream<List<Playlist>> get playlistsStream => _playlistsController.stream;

  Stream<List<Track>> get playlistTracksStream => _playlistTracksController.stream;

  List<Playlist> get playlists => List.unmodifiable(_playlists);

  List<Track> get playlistTracks => List.unmodifiable(_playlistTracks);

  Future<void> loadPlaylists() async {
    if (!_host._requireServer('loading playlists')) {
      return;
    }

    try {
      _playlists = await _host.connection.fetchPlaylists();
      _playlistsController.add(List.unmodifiable(_playlists));
    } on ApiException catch (err) {
      _host._handleApiError(err, context: 'playlists');
    } catch (err) {
      _host._pushMessage('Failed to load playlists: $err', level: LogLevel.warning);
    }
  }

  Future<void> loadLocalPlaylists() async {
    await _host._offlineDownloadManager.loadLocalPlaylists();
  }

  Future<void> loadPlaylistTracks(String playlistId) async {
    if (!_host._requireServer('loading playlist tracks')) {
      return;
    }

    final requestId = _playlistTrackRequests.advance();
    final changedPlaylist = _currentPlaylistId != playlistId;

    _currentPlaylistId = playlistId;

    if (changedPlaylist && _playlistTracks.isNotEmpty) {
      _playlistTracks = <Track>[];
      _playlistTracksController.add(List.unmodifiable(_playlistTracks));
    }

    try {
      final tracks = await _host.connection.fetchPlaylistTracks(playlistId);

      if (!_playlistTrackRequests.isCurrent(requestId) || _currentPlaylistId != playlistId) {
        return;
      }

      _playlistTracks = tracks;

      for (final track in _playlistTracks) {
        _host._cacheTrackAlbumId(track);
      }

      _playlistTracksController.add(List.unmodifiable(_playlistTracks));
    } on ApiException catch (err) {
      if (!_playlistTrackRequests.isCurrent(requestId) || _currentPlaylistId != playlistId) {
        return;
      }

      _host._handleApiError(err, context: 'playlist tracks');
    } catch (err) {
      if (!_playlistTrackRequests.isCurrent(requestId) || _currentPlaylistId != playlistId) {
        return;
      }

      _host._pushMessage('Failed to load playlist tracks: $err', level: LogLevel.warning);
    }
  }

  Future<void> loadLocalPlaylistTracks(String playlistId) async {
    await _host._offlineDownloadManager.loadLocalPlaylistTracks(playlistId);
  }

  Future<void> createPlaylist(
    String name, {
    String? description,
    PlaylistImageEdit imageEdit = const PlaylistImageEdit.keep(),
  }) async {
    if (!_host._requireServer('creating playlists')) {
      throw StateError('Connect to a server before creating playlists.');
    }

    try {
      var playlist = await _host.connection.createPlaylist(name, description: description);

      _playlists = [..._playlists, playlist];
      _playlistsController.add(List.unmodifiable(_playlists));

      playlist = await _applyServerPlaylistImageEdit(playlist, imageEdit);
      _replaceServerPlaylist(playlist);
    } on ApiException catch (err) {
      _host._handleApiError(err, context: 'create playlist');

      rethrow;
    } catch (err) {
      _host._pushMessage('Failed to create playlist: $err');

      rethrow;
    }
  }

  Future<void> createLocalPlaylist(
    String name, {
    String? description,
    PlaylistImageEdit imageEdit = const PlaylistImageEdit.keep(),
  }) async {
    try {
      final playlist = await _host._offlineDownloadManager.createLocalPlaylist(name, description: description);

      if (imageEdit.kind != PlaylistImageEditKind.keep) {
        await _host._offlineDownloadManager.updateLocalPlaylistImage(playlist.id, imageEdit);
      }
    } catch (err) {
      _host._pushMessage('Failed to create local playlist: $err');

      rethrow;
    }
  }

  Future<void> renamePlaylist(
    String playlistId,
    String name, {
    String? description,
    PlaylistImageEdit imageEdit = const PlaylistImageEdit.keep(),
  }) async {
    if (!_host._requireServer('renaming playlists')) {
      throw StateError('Connect to a server before renaming playlists.');
    }

    try {
      var updated = await _host.connection.renamePlaylist(playlistId, name, description: description);

      _replaceServerPlaylist(updated);

      updated = await _applyServerPlaylistImageEdit(updated, imageEdit);
      _replaceServerPlaylist(updated);
    } on ApiException catch (err) {
      _host._handleApiError(err, context: 'rename playlist');

      rethrow;
    } catch (err) {
      _host._pushMessage('Failed to rename playlist: $err');

      rethrow;
    }
  }

  Future<void> renameLocalPlaylist(
    String playlistId,
    String name, {
    String? description,
    PlaylistImageEdit imageEdit = const PlaylistImageEdit.keep(),
  }) async {
    try {
      await _host._offlineDownloadManager.renameLocalPlaylist(playlistId, name, description: description);

      if (imageEdit.kind != PlaylistImageEditKind.keep) {
        await _host._offlineDownloadManager.updateLocalPlaylistImage(playlistId, imageEdit);
      }
    } catch (err) {
      _host._pushMessage('Failed to rename local playlist: $err');

      rethrow;
    }
  }

  Future<void> deletePlaylist(String playlistId) async {
    if (!_host._requireServer('deleting playlists')) {
      return;
    }

    try {
      await _host.connection.deletePlaylist(playlistId);

      _playlists = _playlists.where((playlist) => playlist.id != playlistId).toList();
      _playlistsController.add(List.unmodifiable(_playlists));

      if (_currentPlaylistId == playlistId) {
        _currentPlaylistId = null;
        _playlistTracks = <Track>[];
        _playlistTracksController.add(List.unmodifiable(_playlistTracks));
      }
    } on ApiException catch (err) {
      _host._handleApiError(err, context: 'delete playlist');
    } catch (err) {
      _host._pushMessage('Failed to delete playlist: $err');
    }
  }

  Future<void> deleteLocalPlaylist(String playlistId) async {
    try {
      await _host._offlineDownloadManager.deleteLocalPlaylist(playlistId);
    } catch (err) {
      _host._pushMessage('Failed to delete local playlist: $err');
    }
  }

  Future<void> updatePlaylistTracks(String playlistId, List<String> trackIds) async {
    if (!_host._requireServer('updating playlists')) {
      return;
    }

    try {
      final updated = await _host.connection.updatePlaylistTracks(playlistId, trackIds);

      _replaceServerPlaylist(updated);
    } on ApiException catch (err) {
      _host._handleApiError(err, context: 'update playlist');
    } catch (err) {
      _host._pushMessage('Failed to update playlist: $err');
    }
  }

  Future<void> addTrackToPlaylist(Playlist playlist, Track track) async {
    if (!_host._requireServer('updating playlists')) {
      return;
    }

    try {
      final resolved = _playlists.firstWhere((item) => item.id == playlist.id, orElse: () => playlist);

      if (resolved.trackIds.contains(track.id)) {
        _host._pushMessage('Track already in playlist: ${resolved.name}');

        return;
      }

      final updatedIds = [...resolved.trackIds, track.id];
      final updated = await _host.connection.updatePlaylistTracks(resolved.id, updatedIds);

      _replaceServerPlaylist(updated);

      if (_currentPlaylistId == resolved.id) {
        final exists = _playlistTracks.any((item) => item.id == track.id);

        if (!exists) {
          _playlistTracks = [..._playlistTracks, track];
          _playlistTracksController.add(List.unmodifiable(_playlistTracks));
        }
      }

      _host._pushMessage('Added to playlist: ${resolved.name}');
    } on ApiException catch (err) {
      _host._handleApiError(err, context: 'update playlist');
    } catch (err) {
      _host._pushMessage('Failed to update playlist: $err');
    }
  }

  Future<void> addTrackToLocalPlaylist(Playlist playlist, Track track) async {
    if (_host._localTrackIdFor(track) == null) {
      _host._pushMessage('Download ${track.title} before adding it to a local playlist.', level: LogLevel.warning);

      return;
    }

    try {
      final updated = await _host._offlineDownloadManager.addLocalTrackToPlaylist(playlist, track);

      if (updated != null) {
        _host._pushMessage('Added to local playlist: ${updated.name}');
      }
    } catch (err) {
      _host._pushMessage('Failed to update local playlist: $err');
    }
  }

  Future<void> removeTrackFromPlaylist(Playlist playlist, Track track) async {
    if (!_host._requireServer('updating playlists')) {
      return;
    }

    try {
      final resolved = _playlists.firstWhere((item) => item.id == playlist.id, orElse: () => playlist);

      if (!resolved.trackIds.contains(track.id)) {
        _host._pushMessage('Track not in playlist: ${resolved.name}');

        return;
      }

      final updatedIds = resolved.trackIds.where((id) => id != track.id).toList();
      final updated = await _host.connection.updatePlaylistTracks(resolved.id, updatedIds);

      _replaceServerPlaylist(updated);

      if (_currentPlaylistId == resolved.id) {
        _playlistTracks = _playlistTracks.where((item) => item.id != track.id).toList();
        _playlistTracksController.add(List.unmodifiable(_playlistTracks));
      }

      _host._pushMessage('Removed from playlist: ${resolved.name}');
    } on ApiException catch (err) {
      _host._handleApiError(err, context: 'update playlist');
    } catch (err) {
      _host._pushMessage('Failed to update playlist: $err');
    }
  }

  Future<void> removeTrackFromLocalPlaylist(Playlist playlist, Track track) async {
    try {
      final updated = await _host._offlineDownloadManager.removeLocalTrackFromPlaylist(playlist, track);

      if (updated != null) {
        _host._pushMessage('Removed from local playlist: ${updated.name}');
      }
    } catch (err) {
      _host._pushMessage('Failed to update local playlist: $err');
    }
  }

  Future<Playlist> _applyServerPlaylistImageEdit(Playlist playlist, PlaylistImageEdit imageEdit) {
    return switch (imageEdit.kind) {
      PlaylistImageEditKind.keep => Future.value(playlist),
      PlaylistImageEditKind.clear =>
        playlist.imageRef == null ? Future.value(playlist) : _host.connection.deletePlaylistCover(playlist.id),
      PlaylistImageEditKind.replace => _host.connection.uploadPlaylistCover(
        playlist.id,
        imageEdit.bytes ?? const <int>[],
        imageEdit.contentType ?? 'application/octet-stream',
      ),
    };
  }

  void _replaceServerPlaylist(Playlist updated) {
    _playlists = _playlists.map((playlist) => playlist.id == updated.id ? updated : playlist).toList();
    _playlistsController.add(List.unmodifiable(_playlists));
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _PlaylistFacade {
  _PlaylistCoordinator get _playlistsCoordinator;

  StreamController<List<Playlist>> get _playlistsController => _playlistsCoordinator._playlistsController;

  StreamController<List<Track>> get _playlistTracksController => _playlistsCoordinator._playlistTracksController;

  List<Playlist> get _playlists => _playlistsCoordinator._playlists;

  List<Track> get _playlistTracks => _playlistsCoordinator._playlistTracks;

  set _playlistTracks(List<Track> value) => _playlistsCoordinator._playlistTracks = value;

  String? get _currentPlaylistId => _playlistsCoordinator._currentPlaylistId;

  Stream<List<Playlist>> get playlistsStream => _playlistsCoordinator.playlistsStream;

  Stream<List<Track>> get playlistTracksStream => _playlistsCoordinator.playlistTracksStream;

  List<Playlist> get playlists => _playlistsCoordinator.playlists;

  List<Track> get playlistTracks => _playlistsCoordinator.playlistTracks;

  Future<void> loadPlaylists() => _playlistsCoordinator.loadPlaylists();

  Future<void> loadLocalPlaylists() => _playlistsCoordinator.loadLocalPlaylists();

  Future<void> loadPlaylistTracks(String playlistId) => _playlistsCoordinator.loadPlaylistTracks(playlistId);

  Future<void> loadLocalPlaylistTracks(String playlistId) => _playlistsCoordinator.loadLocalPlaylistTracks(playlistId);

  Future<void> createPlaylist(
    String name, {
    String? description,
    PlaylistImageEdit imageEdit = const PlaylistImageEdit.keep(),
  }) => _playlistsCoordinator.createPlaylist(name, description: description, imageEdit: imageEdit);

  Future<void> createLocalPlaylist(
    String name, {
    String? description,
    PlaylistImageEdit imageEdit = const PlaylistImageEdit.keep(),
  }) => _playlistsCoordinator.createLocalPlaylist(name, description: description, imageEdit: imageEdit);

  Future<void> renamePlaylist(
    String playlistId,
    String name, {
    String? description,
    PlaylistImageEdit imageEdit = const PlaylistImageEdit.keep(),
  }) => _playlistsCoordinator.renamePlaylist(playlistId, name, description: description, imageEdit: imageEdit);

  Future<void> renameLocalPlaylist(
    String playlistId,
    String name, {
    String? description,
    PlaylistImageEdit imageEdit = const PlaylistImageEdit.keep(),
  }) => _playlistsCoordinator.renameLocalPlaylist(playlistId, name, description: description, imageEdit: imageEdit);

  Future<void> deletePlaylist(String playlistId) => _playlistsCoordinator.deletePlaylist(playlistId);

  Future<void> deleteLocalPlaylist(String playlistId) => _playlistsCoordinator.deleteLocalPlaylist(playlistId);

  Future<void> updatePlaylistTracks(String playlistId, List<String> trackIds) =>
      _playlistsCoordinator.updatePlaylistTracks(playlistId, trackIds);

  Future<void> addTrackToPlaylist(Playlist playlist, Track track) =>
      _playlistsCoordinator.addTrackToPlaylist(playlist, track);

  Future<void> addTrackToLocalPlaylist(Playlist playlist, Track track) =>
      _playlistsCoordinator.addTrackToLocalPlaylist(playlist, track);

  Future<void> removeTrackFromPlaylist(Playlist playlist, Track track) =>
      _playlistsCoordinator.removeTrackFromPlaylist(playlist, track);

  Future<void> removeTrackFromLocalPlaylist(Playlist playlist, Track track) =>
      _playlistsCoordinator.removeTrackFromLocalPlaylist(playlist, track);
}
