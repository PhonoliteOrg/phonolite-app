part of '../app_controller.dart';

class _PlaylistCoordinator {
  final AppController _host;
  final _playlistsController = StreamController<List<Playlist>>.broadcast();
  final _playlistTracksController = StreamController<List<Track>>.broadcast();
  List<Playlist> _playlists = <Playlist>[];
  List<Track> _playlistTracks = <Track>[];
  final _playlistTrackRequests = RequestGeneration();
  final _playlistRequests = RequestGeneration();
  String? _currentPlaylistId;

  _PlaylistCoordinator(this._host);

  Stream<List<Playlist>> get playlistsStream => _playlistsController.stream;

  Stream<List<Track>> get playlistTracksStream => _playlistTracksController.stream;

  List<Playlist> get playlists => List.unmodifiable(_playlists);

  List<Track> get playlistTracks => List.unmodifiable(_playlistTracks);

  void _clearServerData() {
    _playlistTrackRequests.advance();
    _playlistRequests.advance();
    _playlists = [];
    _playlistTracks = [];
    _currentPlaylistId = null;
    _playlistsController.add(const []);
    _playlistTracksController.add(const []);
  }

  void _applyCollectionSnapshot(List<Playlist> playlists, String? openPlaylistId, List<Track> tracks) {
    _playlistRequests.advance();
    _playlists = List.of(playlists);
    _playlistsController.add(List.unmodifiable(_playlists));

    if (_currentPlaylistId != openPlaylistId || openPlaylistId == null) {
      return;
    }

    _playlistTrackRequests.advance();
    final matching = playlists.where((playlist) => playlist.id == openPlaylistId);

    if (matching.isEmpty) {
      _currentPlaylistId = null;
      _playlistTracks = [];
    } else {
      final byId = {
        for (final track in [..._playlistTracks, ...tracks]) track.id: track,
      };
      _playlistTracks = [
        for (final id in matching.first.trackIds)
          if (byId[id] case final track?) _host.connection.projectServerTrack(track),
      ];
    }

    _playlistTracksController.add(List.unmodifiable(_playlistTracks));
  }

  Future<void> loadPlaylists() async {
    if (!_host._requireServer('loading playlists')) {
      return;
    }

    if (_host._collectionCoordinator.hasSnapshot) {
      _host._collectionCoordinator.refresh();

      return;
    }

    final revision = _host.connection.sessionRevision;
    final request = _playlistRequests.advance();
    bool isCurrent() =>
        _host._sessionCoordinator._isServerSessionCurrent(revision) && _playlistRequests.isCurrent(request);
    try {
      final playlists = await _host.connection.fetchPlaylists();
      if (!isCurrent()) return;
      _playlists = playlists;
      _playlistsController.add(List.unmodifiable(_playlists));
    } on ApiException catch (err) {
      if (!isCurrent()) return;
      _host._handleApiError(err, context: 'playlists');
    } catch (err) {
      if (!isCurrent()) return;
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

    final revision = _host.connection.sessionRevision;
    bool isCurrent() => _host._sessionCoordinator._isServerSessionCurrent(revision);
    final requestId = _playlistTrackRequests.advance();
    final changedPlaylist = _currentPlaylistId != playlistId;

    _currentPlaylistId = playlistId;

    if (changedPlaylist && _playlistTracks.isNotEmpty) {
      _playlistTracks = <Track>[];
      _playlistTracksController.add(List.unmodifiable(_playlistTracks));
    }

    try {
      final tracks = await _host.connection.fetchPlaylistTracks(playlistId);

      if (!isCurrent() || !_playlistTrackRequests.isCurrent(requestId) || _currentPlaylistId != playlistId) {
        return;
      }

      _playlistTracks = tracks;

      for (final track in _playlistTracks) {
        _host._cacheTrackAlbumId(track);
      }

      _playlistTracksController.add(List.unmodifiable(_playlistTracks));
    } on ApiException catch (err) {
      if (!isCurrent() || !_playlistTrackRequests.isCurrent(requestId) || _currentPlaylistId != playlistId) {
        return;
      }

      _host._handleApiError(err, context: 'playlist tracks');
    } catch (err) {
      if (!isCurrent() || !_playlistTrackRequests.isCurrent(requestId) || _currentPlaylistId != playlistId) {
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

    final revision = _host.connection.sessionRevision;
    bool isCurrent() => _host._sessionCoordinator._isServerSessionCurrent(revision);
    final finishMutation = _host._collectionCoordinator.beginMutation();

    try {
      var playlist = await _host.connection.createPlaylist(name, description: description);
      if (!isCurrent()) return;

      _playlists = [..._playlists, playlist];
      _host.connection.recordServerPlaylist(playlist);
      _playlistsController.add(List.unmodifiable(_playlists));

      playlist = await _applyServerPlaylistImageEdit(playlist, imageEdit);
      if (!isCurrent()) return;
      _replaceServerPlaylist(playlist);
    } on ApiException catch (err) {
      if (!isCurrent()) return;
      _host._handleApiError(err, context: 'create playlist');

      rethrow;
    } catch (err) {
      if (!isCurrent()) return;
      _host._pushMessage('Failed to create playlist: $err');

      rethrow;
    } finally {
      finishMutation();
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

    final revision = _host.connection.sessionRevision;
    bool isCurrent() => _host._sessionCoordinator._isServerSessionCurrent(revision);
    final finishMutation = _host._collectionCoordinator.beginMutation();

    try {
      var updated = await _host.connection.renamePlaylist(playlistId, name, description: description);
      if (!isCurrent()) return;

      _replaceServerPlaylist(updated);

      updated = await _applyServerPlaylistImageEdit(updated, imageEdit);
      if (!isCurrent()) return;
      _replaceServerPlaylist(updated);
    } on ApiException catch (err) {
      if (!isCurrent()) return;
      _host._handleApiError(err, context: 'rename playlist');

      rethrow;
    } catch (err) {
      if (!isCurrent()) return;
      _host._pushMessage('Failed to rename playlist: $err');

      rethrow;
    } finally {
      finishMutation();
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

    final revision = _host.connection.sessionRevision;
    bool isCurrent() => _host._sessionCoordinator._isServerSessionCurrent(revision);
    final finishMutation = _host._collectionCoordinator.beginMutation();

    try {
      await _host.connection.deletePlaylist(playlistId);
      if (!isCurrent()) return;

      _host.connection.recordServerPlaylistDeleted(playlistId);
      _playlistRequests.advance();
      _playlists = _playlists.where((playlist) => playlist.id != playlistId).toList();
      _playlistsController.add(List.unmodifiable(_playlists));
      _host._collectionCoordinator.publishMembership();

      if (_currentPlaylistId == playlistId) {
        _currentPlaylistId = null;
        _playlistTracks = <Track>[];
        _playlistTracksController.add(List.unmodifiable(_playlistTracks));
      }
    } on ApiException catch (err) {
      if (!isCurrent()) return;
      _host._handleApiError(err, context: 'delete playlist');
    } catch (err) {
      if (!isCurrent()) return;
      _host._pushMessage('Failed to delete playlist: $err');
    } finally {
      finishMutation();
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

    final revision = _host.connection.sessionRevision;
    bool isCurrent() => _host._sessionCoordinator._isServerSessionCurrent(revision);
    final finishMutation = _host._collectionCoordinator.beginMutation();

    try {
      final matching = _playlists.where((playlist) => playlist.id == playlistId);
      final expectedRevision = matching.isEmpty ? null : matching.first.revision;
      final updated = expectedRevision == null
          ? await _host.connection.updatePlaylistTracks(playlistId, trackIds)
          : await _host.connection.replacePlaylistTracks(playlistId, trackIds, expectedRevision: expectedRevision);
      if (!isCurrent()) return;

      _replaceServerPlaylist(updated);
    } on ApiException catch (err) {
      if (!isCurrent()) return;
      if (err.statusCode == 409 || err.statusCode == 428) {
        _host._collectionCoordinator.refresh();
        _host._pushMessage('The playlist changed on another device. Reload it before saving this order.');

        return;
      }

      _host._handleApiError(err, context: 'update playlist');
    } catch (err) {
      if (!isCurrent()) return;
      _host._pushMessage('Failed to update playlist: $err');
    } finally {
      finishMutation();
    }
  }

  Future<void> addTrackToPlaylist(Playlist playlist, Track track) async {
    if (!_host._requireServer('updating playlists')) {
      return;
    }

    final revision = _host.connection.sessionRevision;
    bool isCurrent() => _host._sessionCoordinator._isServerSessionCurrent(revision);
    final finishMutation = _host._collectionCoordinator.beginMutation();

    try {
      final resolved = _playlists.firstWhere((item) => item.id == playlist.id, orElse: () => playlist);

      if (resolved.revision == null && resolved.trackIds.contains(track.id)) {
        _host._pushMessage('Track already in playlist: ${resolved.name}');

        return;
      }

      final updated = resolved.revision != null
          ? await _host.connection.addPlaylistTracks(resolved.id, [track.id])
          : await _host.connection.updatePlaylistTracks(resolved.id, [...resolved.trackIds, track.id]);
      if (!isCurrent()) return;

      final accepted = _replaceServerPlaylist(updated);

      if (accepted && _currentPlaylistId == resolved.id) {
        final exists = _playlistTracks.any((item) => item.id == track.id);

        if (!exists) {
          _playlistTracks = [..._playlistTracks, _host.connection.projectServerTrack(track)];
          _playlistTracksController.add(List.unmodifiable(_playlistTracks));
        }
      }

      _host._pushMessage('Added to playlist: ${resolved.name}');
    } on ApiException catch (err) {
      if (!isCurrent()) return;
      _host._handleApiError(err, context: 'update playlist');
    } catch (err) {
      if (!isCurrent()) return;
      _host._pushMessage('Failed to update playlist: $err');
    } finally {
      finishMutation();
    }
  }

  Future<void> addTrackToLocalPlaylist(Playlist playlist, Track track) async {
    try {
      final source = _host.localPlaylistSourceForTrack(track);

      if (source != null) {
        await _host._offlineDownloadManager.addSourceToLocalPlaylist(playlist.id, track, source);

        return;
      }

      final updated = await _host._offlineDownloadManager.addLocalTrackToPlaylist(playlist, track);

      if (updated != null) {
        _host._pushMessage('Added to local playlist: ${updated.name}');
      }
    } catch (err) {
      _host._pushMessage('Failed to update local playlist: $err');

      rethrow;
    }
  }

  Future<void> removeTrackFromPlaylist(Playlist playlist, Track track) async {
    if (!_host._requireServer('updating playlists')) {
      return;
    }

    final revision = _host.connection.sessionRevision;
    bool isCurrent() => _host._sessionCoordinator._isServerSessionCurrent(revision);
    final finishMutation = _host._collectionCoordinator.beginMutation();

    try {
      final resolved = _playlists.firstWhere((item) => item.id == playlist.id, orElse: () => playlist);

      if (resolved.revision == null && !resolved.trackIds.contains(track.id)) {
        _host._pushMessage('Track not in playlist: ${resolved.name}');

        return;
      }

      final updated = resolved.revision != null
          ? await _host.connection.removePlaylistTracks(resolved.id, [track.id])
          : await _host.connection.updatePlaylistTracks(
              resolved.id,
              resolved.trackIds.where((id) => id != track.id).toList(),
            );
      if (!isCurrent()) return;

      final accepted = _replaceServerPlaylist(updated);

      if (accepted && _currentPlaylistId == resolved.id) {
        _playlistTracks = _playlistTracks.where((item) => item.id != track.id).toList();
        _playlistTracksController.add(List.unmodifiable(_playlistTracks));
      }

      _host._pushMessage('Removed from playlist: ${resolved.name}');
    } on ApiException catch (err) {
      if (!isCurrent()) return;
      _host._handleApiError(err, context: 'update playlist');
    } catch (err) {
      if (!isCurrent()) return;
      _host._pushMessage('Failed to update playlist: $err');
    } finally {
      finishMutation();
    }
  }

  Future<void> removeTrackFromLocalPlaylist(Playlist playlist, Track track) async {
    try {
      final source = _host.localPlaylistSourceForTrack(track);
      final captured = source == null
          ? track
          : track.copyWith(serverBaseUrl: source.serverBaseUrl, serverTrackId: source.serverTrackId);
      final updated = await _host._offlineDownloadManager.removeLocalTrackFromPlaylist(playlist, captured);

      if (updated != null) {
        _host._pushMessage('Removed from local playlist: ${updated.name}');
      }
    } catch (err) {
      _host._pushMessage('Failed to update local playlist: $err');

      rethrow;
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

  bool _replaceServerPlaylist(Playlist updated) {
    final existing = _playlists.where((playlist) => playlist.id == updated.id);
    final currentRevision = existing.isEmpty ? null : existing.first.revision;

    if (existing.isEmpty) {
      return false;
    }

    if (updated.revision != null && currentRevision != null && updated.revision! < currentRevision) {
      return false;
    }

    _playlistRequests.advance();
    _host.connection.recordServerPlaylist(updated);
    _playlists = [for (final playlist in _playlists) playlist.id == updated.id ? updated : playlist];
    _playlistsController.add(List.unmodifiable(_playlists));
    _host._collectionCoordinator.publishMembership();

    return true;
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _PlaylistFacade {
  _PlaylistCoordinator get _playlistsCoordinator;

  List<LocalPlaylistEntry> get localPlaylistEntries =>
      _playlistsCoordinator._host._offlineDownloadManager.localPlaylistEntries;

  Stream<List<LocalPlaylistEntry>> get localPlaylistEntriesStream =>
      _playlistsCoordinator._host._offlineDownloadManager.localPlaylistEntriesStream;

  Future<void> loadLocalPlaylistEntries(String playlistId) =>
      _playlistsCoordinator._host._offlineDownloadManager.loadLocalPlaylistTracks(playlistId);

  SourceTrackRef? localPlaylistSourceForTrack(Track track) =>
      _playlistsCoordinator._host._playlistSources.sourceForTrack(track);

  Future<String?> resolveLocalPlaylistTrackId(Track track) =>
      _playlistsCoordinator._host._playlistSources.resolveLocalTrackId(track);

  Future<Track?> resolveServerTrackForCurrentServer(Track track) =>
      _playlistsCoordinator._host._playlistSources.resolveServerTrack(track);

  bool localPlaylistContainsTrack(Playlist playlist, Track track) =>
      _playlistsCoordinator._host._playlistSources.contains(playlist, track);

  OfflineTrackDownload? offlineDownloadForLocalPlaylistEntry(LocalPlaylistEntry entry) =>
      _playlistsCoordinator._host._playlistSources.downloadForEntry(entry);

  Future<void> retryLocalPlaylistEntry(LocalPlaylistEntry entry) =>
      _playlistsCoordinator._host._offlineDownloadManager.retryLocalPlaylistEntry(entry);

  Future<void> resumeLocalPlaylistEntry(LocalPlaylistEntry entry) =>
      _playlistsCoordinator._host._offlineDownloadManager.resumeLocalPlaylistEntry(entry);

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
