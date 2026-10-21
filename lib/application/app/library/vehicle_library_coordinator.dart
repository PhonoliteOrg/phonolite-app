part of 'package:phonolite_app/application/app/app_controller.dart';

class _VehicleLibraryCoordinator {
  final AppController _host;
  final _carPlayStateDebounce = DebouncedAction();
  StreamSubscription<OfflineLibrarySnapshot>? _carPlayOfflineLibrarySubscription;
  StreamSubscription<List<Track>>? _carPlayLocalLikedSubscription;
  StreamSubscription<List<Playlist>>? _carPlayLocalPlaylistsSubscription;

  _VehicleLibraryCoordinator(this._host);

  void _configureCarPlay() {
    if (!_host._vehicleSurface.isSupported) {
      return;
    }

    Future<VehicleResponse?> handleVehicleRequest(VehicleRequest request) async {
      if (_host._disposed) {
        return null;
      }

      return switch (request.operation) {
        VehicleOperation.getState => _carPlayGetState(),
        VehicleOperation.getHomeActions => _carPlayGetLegacyHomeActions(),
        VehicleOperation.getAuthorization => VehicleAuthorizationState(
          authorized: _host._authState.isAuthorized,
          hasSession: _host._authState.hasSession,
          status: _host._authState.status,
        ),
        VehicleOperation.getArtists => _carPlayGetArtists(request.scope),
        VehicleOperation.getAlbums => _carPlayGetAlbums(request.scope, request.artistId ?? ''),
        VehicleOperation.getPlaylists => _carPlayGetPlaylists(request.scope),
        VehicleOperation.getLibraryStatus => _carPlayGetLibraryStatus(request.scope),
        VehicleOperation.playAlbum => _carPlayPlayAlbum(request.scope, request.albumId ?? ''),
        VehicleOperation.playPlaylist => _carPlayPlayPlaylist(request.scope, request.playlistId ?? ''),
        VehicleOperation.playLiked => _carPlayPlayLiked(request.scope),
        VehicleOperation.startShuffle => _carPlayStartShuffle(
          request.scope,
          request.shuffleKind,
          artistId: request.artistId,
          albumId: request.albumId,
          playlistId: request.playlistId,
        ),
        VehicleOperation.unknown => null,
      };
    }

    _host._vehicleSurface.setRequestHandler(handleVehicleRequest);
    _notifyCarPlayState();
  }

  void _notifyCarPlayAuthState(bool authorized) {
    _notifyCarPlayState();
  }

  void _scheduleCarPlayStateUpdate() {
    if (_host._disposed) {
      return;
    }

    if (!_host._vehicleSurface.isSupported) {
      return;
    }

    _carPlayStateDebounce.schedule(const Duration(milliseconds: 250), _notifyCarPlayState);
  }

  void _notifyCarPlayState() {
    if (_host._disposed) {
      return;
    }

    if (!_host._vehicleSurface.isSupported) {
      return;
    }

    final payload = _carPlayStatePayload();

    _host._vehicleSurface.notifySourceState(payload).catchError((_) {});
    _host._vehicleSurface.notifyAuthorization(payload.serverAvailable).catchError((_) {});
  }

  VehicleCommandResult _carPlayOk() => const VehicleCommandResult.ok();

  VehicleCommandResult _carPlayError(VehicleFailure failure) => VehicleCommandResult.failure(failure);

  VehicleCommandResult? _carPlayServerAvailabilityError() {
    if (_host._authState.isAuthorized) {
      return null;
    }

    return _carPlayError(
      _host._authState.status == SessionStatus.serverUnavailable
          ? VehicleFailure.serverUnavailable
          : VehicleFailure.unauthorized,
    );
  }

  VehicleItems _carPlayList(List<VehicleItem> items) => VehicleItems(items);

  Future<VehicleResponse> _carPlayGetState() async {
    if (_host._authState.status == SessionStatus.serverUnavailable) {
      unawaited(_host._triggerImmediateServerReconnect(reason: 'vehicle state request'));
    }

    await _host._offlineDownloadManager.load();

    return _carPlayStatePayload();
  }

  VehicleSourceState _carPlayStatePayload() {
    final serverAvailable = _host._authState.isAuthorized;
    final localAvailable = _host.offlineTracks.isNotEmpty;

    return VehicleSourceState(serverAvailable: serverAvailable, localAvailable: localAvailable);
  }

  Future<VehicleResponse> _carPlayGetArtists(ActionScope scope) async {
    if (scope == ActionScope.local) {
      await _host._offlineDownloadManager.load();

      final groups = _host.offlineLibrarySnapshot.artistGroups;
      final items = groups
          .map(
            (group) => VehicleItem(
              id: group.id,
              title: group.name,
              subtitle:
                  '${group.soloAlbums.length} albums'
                  '${group.collabAlbums.isEmpty ? '' : ' · ${group.collabAlbums.length} collab albums'}',
              artworkPath: group.coverPath,
            ),
          )
          .toList();

      return _carPlayList(items);
    }

    final serverError = _carPlayServerAvailabilityError();
    if (serverError != null) {
      return serverError;
    }

    if (_host._artists.isEmpty && !_host._artistsLoading) {
      await _host.loadArtists();
    }

    final items = _host._artists
        .map(
          (artist) => VehicleItem(
            id: artist.id,
            title: artist.name,
            subtitle:
                '${artist.releaseCount} albums'
                '${artist.collabAlbumCount == 0 ? '' : ' · ${artist.collabAlbumCount} collab albums'}',
            artworkUrl: (artist.logoRef?.trim().isNotEmpty ?? false)
                ? _host.connection.buildArtistCoverUrl(artist.id, kind: 'logo', ref: artist.logoRef)
                : null,
            token: _host.connection.token ?? '',
            serverPin: _host.connection.trust?.spki,
          ),
        )
        .toList();

    return _carPlayList(items);
  }

  Future<VehicleResponse> _carPlayGetLegacyHomeActions() async {
    if (!_host._authState.isAuthorized) {
      final unavailable = _host._authState.status == SessionStatus.serverUnavailable;

      return _carPlayList([
        VehicleItem.action(
          action: VehicleHomeAction.libraryShuffle,
          title: 'Start Library Shuffle',
          subtitle: unavailable ? 'Server unavailable' : 'Connect to a server',
          enabled: false,
        ),
        VehicleItem.action(
          action: VehicleHomeAction.likedShuffle,
          title: 'Start Liked Shuffle',
          subtitle: unavailable ? 'Server unavailable' : 'Connect to a server',
          enabled: false,
        ),
        VehicleItem.action(
          action: VehicleHomeAction.customShuffle,
          title: 'Start Custom Shuffle',
          subtitle: unavailable ? 'Server unavailable' : 'Connect to a server',
          enabled: false,
        ),
      ]);
    }

    final actions = <VehicleItem>[
      VehicleItem.action(
        action: VehicleHomeAction.libraryShuffle,
        title: 'Start Library Shuffle',
        subtitle: 'Shuffle all tracks',
        enabled: true,
      ),
    ];

    var liked = _host._liked;

    if (liked.isEmpty) {
      try {
        liked = await _host.connection.fetchLikedTracks();
      } catch (_) {
        liked = const <Track>[];
      }
    }

    actions.add(
      VehicleItem.action(
        action: VehicleHomeAction.likedShuffle,
        title: 'Start Liked Shuffle',
        subtitle: liked.isNotEmpty ? 'Shuffle liked songs' : 'No liked songs yet',
        enabled: liked.isNotEmpty,
      ),
    );

    await _host._ensureCustomShuffleSettingsLoaded();

    final customReady =
        _host._customShuffleSettings.artistIds.isNotEmpty || _host._customShuffleSettings.genres.isNotEmpty;

    actions.add(
      VehicleItem.action(
        action: VehicleHomeAction.customShuffle,
        title: 'Start Custom Shuffle',
        subtitle: customReady ? 'Shuffle with your rules' : 'Set up custom shuffle',
        enabled: customReady,
      ),
    );

    return _carPlayList(actions);
  }

  Future<VehicleResponse> _carPlayGetAlbums(ActionScope scope, String artistId) async {
    if (scope == ActionScope.local) {
      await _host._offlineDownloadManager.load();

      final group = _carPlayLocalArtistGroup(artistId);
      if (group == null) {
        return _carPlayError(VehicleFailure.missingArtist);
      }

      final items = group.albums
          .map(
            (album) => VehicleItem(
              id: album.id,
              title: album.title,
              subtitle: album.metadata?.year != null
                  ? album.metadata!.year.toString()
                  : '${album.tracks.length} tracks',
              artworkPath: album.coverPath,
            ),
          )
          .toList();

      return _carPlayList(items);
    }

    final serverError = _carPlayServerAvailabilityError();
    if (serverError != null) {
      return serverError;
    }

    if (artistId.isEmpty) {
      return _carPlayError(VehicleFailure.missingArtist);
    }

    await _host.loadAlbums(artistId);

    final token = _host.connection.token ?? '';
    final items = _host._albums
        .map(
          (album) => VehicleItem(
            id: album.id,
            title: album.title,
            subtitle: album.year != null ? album.year.toString() : '${album.trackCount} tracks',
            artworkUrl: _host.connection.buildAlbumCoverUrl(album.id),
            token: token,
            serverPin: _host.connection.trust?.spki,
          ),
        )
        .toList();

    return _carPlayList(items);
  }

  Future<VehicleResponse> _carPlayGetPlaylists(ActionScope scope) async {
    if (scope == ActionScope.local) {
      await _host.loadLocalPlaylists();

      final items = _host.localPlaylists
          .map(
            (playlist) =>
                VehicleItem(id: playlist.id, title: playlist.name, subtitle: '${playlist.trackIds.length} tracks'),
          )
          .toList();

      return _carPlayList(items);
    }

    final serverError = _carPlayServerAvailabilityError();
    if (serverError != null) {
      return serverError;
    }

    if (_host._playlists.isEmpty) {
      await _host.loadPlaylists();
    }

    final items = _host._playlists
        .map(
          (playlist) =>
              VehicleItem(id: playlist.id, title: playlist.name, subtitle: '${playlist.trackIds.length} tracks'),
        )
        .toList();

    return _carPlayList(items);
  }

  Future<VehicleResponse> _carPlayGetLibraryStatus(ActionScope scope) async {
    if (scope == ActionScope.local) {
      if (_host.localLiked.isEmpty) {
        await _host.loadLocalLikedTracks();
      }

      return VehicleLibraryStatus(likedAvailable: _host.localLiked.isNotEmpty);
    }

    final serverError = _carPlayServerAvailabilityError();
    if (serverError != null) {
      return VehicleLibraryStatus(likedAvailable: false, failure: serverError.failure);
    }

    final liked = await _carPlayServerLikedTracks();

    return VehicleLibraryStatus(likedAvailable: liked.isNotEmpty);
  }

  Future<VehicleResponse> _carPlayPlayAlbum(ActionScope scope, String albumId) async {
    if (albumId.isEmpty) {
      return _carPlayError(VehicleFailure.missingAlbum);
    }

    if (scope == ActionScope.local) {
      await _host._offlineDownloadManager.load();

      final album = _carPlayLocalAlbumGroup(albumId);

      if (album == null || album.tracks.isEmpty) {
        return _carPlayError(VehicleFailure.missingAlbum);
      }

      _host.updateShuffleMode(ShuffleMode.off, scope: ActionScope.local);
      await _host.playOfflineTrack(album.tracks.first.id, tracks: album.tracks);

      return _carPlayOk();
    }

    final serverError = _carPlayServerAvailabilityError();
    if (serverError != null) {
      return serverError;
    }

    _host.updateShuffleMode(ShuffleMode.off, scope: ActionScope.server);
    await _host.queueAlbum(albumId);

    return _carPlayOk();
  }

  Future<VehicleResponse> _carPlayPlayPlaylist(ActionScope scope, String playlistId) async {
    if (playlistId.isEmpty) {
      return _carPlayError(VehicleFailure.missingPlaylist);
    }

    if (scope == ActionScope.local) {
      _host.updateShuffleMode(ShuffleMode.off, scope: ActionScope.local);
      await _host.playLocalPlaylistFromTop(playlistId);

      return _carPlayOk();
    }

    final serverError = _carPlayServerAvailabilityError();
    if (serverError != null) {
      return serverError;
    }

    _host.updateShuffleMode(ShuffleMode.off, scope: ActionScope.server);
    await _host.queuePlaylist(playlistId);

    return _carPlayOk();
  }

  Future<VehicleResponse> _carPlayPlayLiked(ActionScope scope) async {
    if (scope == ActionScope.local) {
      if (_host.localLiked.isEmpty) {
        await _host.loadLocalLikedTracks();
      }

      if (_host.localLiked.isEmpty) {
        return _carPlayError(VehicleFailure.likedEmpty);
      }

      _host.updateShuffleMode(ShuffleMode.off, scope: ActionScope.local);
      await _host.playLocalLikedTrack(_host.localLiked.first.id);

      return _carPlayOk();
    }

    final serverError = _carPlayServerAvailabilityError();
    if (serverError != null) {
      return serverError;
    }

    _host.updateShuffleMode(ShuffleMode.off, scope: ActionScope.server);
    await _host.queueLiked();

    return _carPlayOk();
  }

  Future<VehicleResponse> _carPlayStartShuffle(
    ActionScope scope,
    VehicleShuffleKind kind, {
    String? artistId,
    String? albumId,
    String? playlistId,
  }) async {
    if (scope == ActionScope.local) {
      if (kind == VehicleShuffleKind.custom) {
        await _host._ensureCustomShuffleSettingsLoaded();

        if (_host._customShuffleSettings.localArtistIds.isEmpty && _host._customShuffleSettings.localGenres.isEmpty) {
          return _carPlayError(VehicleFailure.customEmpty);
        }
      }

      final mode = switch (kind) {
        VehicleShuffleKind.artist => ShuffleMode.artist,
        VehicleShuffleKind.album => ShuffleMode.album,
        VehicleShuffleKind.playlist => ShuffleMode.currentPlaylist,
        VehicleShuffleKind.custom => ShuffleMode.custom,
        VehicleShuffleKind.liked => ShuffleMode.liked,
        VehicleShuffleKind.library => ShuffleMode.all,
      };

      _host.updateShuffleMode(mode, scope: ActionScope.local);
      await _host.queueLocalShuffle(playlistId: playlistId, artistId: artistId, albumId: albumId, play: true);

      return _carPlayOk();
    }

    final serverError = _carPlayServerAvailabilityError();
    if (serverError != null) {
      return serverError;
    }

    if (kind == VehicleShuffleKind.custom) {
      await _host._ensureCustomShuffleSettingsLoaded();

      if (_host._customShuffleSettings.artistIds.isEmpty && _host._customShuffleSettings.genres.isEmpty) {
        return _carPlayError(VehicleFailure.customEmpty);
      }

      _host.updateShuffleMode(ShuffleMode.custom, scope: ActionScope.server);
      await _host.queueShuffle(scope: 'library', play: true);

      return _carPlayOk();
    }

    if (kind == VehicleShuffleKind.liked) {
      _host.updateShuffleMode(ShuffleMode.liked, scope: ActionScope.server);
      await _host.queueShuffle(scope: 'liked', play: true);

      return _carPlayOk();
    }

    _host.updateShuffleMode(ShuffleMode.all, scope: ActionScope.server);
    await _host.queueShuffle(scope: 'library', play: true);

    return _carPlayOk();
  }

  Future<List<Track>> _carPlayServerLikedTracks() async {
    if (!_host._authState.isAuthorized) {
      return const <Track>[];
    }

    if (_host._liked.isNotEmpty) {
      return _host._liked;
    }

    try {
      return await _host.connection.fetchLikedTracks();
    } catch (_) {
      return const <Track>[];
    }
  }

  OfflineArtistGroup? _carPlayLocalArtistGroup(String artistId) {
    return _host._localLibrary.artist(artistId);
  }

  OfflineAlbumGroup? _carPlayLocalAlbumGroup(String albumId) {
    return _host._localLibrary.album(albumId);
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _VehicleLibraryFacade {
  _VehicleLibraryCoordinator get _vehicleCoordinator;

  DebouncedAction get _carPlayStateDebounce => _vehicleCoordinator._carPlayStateDebounce;

  StreamSubscription<OfflineLibrarySnapshot>? get _carPlayOfflineLibrarySubscription =>
      _vehicleCoordinator._carPlayOfflineLibrarySubscription;

  set _carPlayOfflineLibrarySubscription(StreamSubscription<OfflineLibrarySnapshot>? value) =>
      _vehicleCoordinator._carPlayOfflineLibrarySubscription = value;

  StreamSubscription<List<Track>>? get _carPlayLocalLikedSubscription =>
      _vehicleCoordinator._carPlayLocalLikedSubscription;

  set _carPlayLocalLikedSubscription(StreamSubscription<List<Track>>? value) =>
      _vehicleCoordinator._carPlayLocalLikedSubscription = value;

  StreamSubscription<List<Playlist>>? get _carPlayLocalPlaylistsSubscription =>
      _vehicleCoordinator._carPlayLocalPlaylistsSubscription;

  set _carPlayLocalPlaylistsSubscription(StreamSubscription<List<Playlist>>? value) =>
      _vehicleCoordinator._carPlayLocalPlaylistsSubscription = value;

  void _configureCarPlay() => _vehicleCoordinator._configureCarPlay();

  void _notifyCarPlayAuthState(bool authorized) => _vehicleCoordinator._notifyCarPlayAuthState(authorized);

  void _scheduleCarPlayStateUpdate() => _vehicleCoordinator._scheduleCarPlayStateUpdate();
}
