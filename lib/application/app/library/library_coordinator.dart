part of 'package:phonolite_app/application/app/app_controller.dart';

class _LibraryCoordinator {
  final AppController _host;
  final _artistsController = StreamController<List<Artist>>.broadcast();
  final _albumsController = StreamController<List<Album>>.broadcast();
  final _artistReleasesController = StreamController<ArtistReleases>.broadcast();
  final _tracksController = StreamController<List<Track>>.broadcast();
  final _searchController = StreamController<List<SearchResult>>.broadcast();
  final _artistUpdatesController = StreamController<Artist>.broadcast();
  final _albumUpdatesController = StreamController<Album>.broadcast();
  final _artistsLoadingController = StreamController<bool>.broadcast();
  final _albumsLoadingController = StreamController<bool>.broadcast();
  final _tracksLoadingController = StreamController<bool>.broadcast();
  final _searchLoadingController = StreamController<bool>.broadcast();
  late final _artistCatalog = _ArtistCatalogCoordinator(this, _host);
  List<Album> _albums = <Album>[];
  ArtistReleases _artistReleases = const ArtistReleases();
  String? _artistReleasesArtistId;
  List<Track> _tracks = <Track>[];
  List<SearchResult> _search = <SearchResult>[];
  bool _artistsLoading = false;
  final _artistReleasesRequests = RequestGeneration();
  bool _albumsLoading = false;
  bool _tracksLoading = false;
  bool _searchLoading = false;
  final _searchRequests = RequestGeneration();
  final _trackRequests = RequestGeneration();
  final _albumRequests = RequestGeneration();
  String? _lastArtistId;
  String? _lastAlbumId;
  late final MetadataEventListener _metadataEvents = MetadataEventListener(
    openStream: _host.connection.streamMetadataEvents,
    isSessionCurrent: (baseUrl, token) =>
        !_host._disposed &&
        _host._authState.isAuthorized &&
        _host.connection.baseUrl == baseUrl &&
        _host.connection.token == token,
    applyEvent: _applyMetadataEvent,
    onDiagnostic: AppLogger.debug,
    onSessionInvalidated: () => unawaited(_host._sessionCoordinator.requireSignIn()),
  );

  _LibraryCoordinator(this._host);

  List<Artist> get _artists => _artistCatalog.artists;

  set _artists(List<Artist> value) => _artistCatalog.artists = value;

  set _artistsOffset(int value) => _artistCatalog.offset = value;

  bool get _artistsHasMore => _artistCatalog.hasMore;

  set _artistsHasMore(bool value) => _artistCatalog.hasMore = value;

  void _clearPersonalizedData() {
    _trackRequests.advance();
    _albumRequests.advance();
    _searchRequests.advance();
    _tracks = [];
    _search = [];
    _lastAlbumId = null;
    _tracksController.add(const []);
    _searchController.add(const []);
    _setTracksLoading(false);
    _setAlbumsLoading(false);
    _setSearchLoading(false);
  }

  Stream<List<Artist>> get artistsStream => _artistsController.stream;

  Stream<List<Album>> get albumsStream => _albumsController.stream;

  Stream<ArtistReleases> get artistReleasesStream => _artistReleasesController.stream;

  Stream<List<Track>> get tracksStream => _tracksController.stream;

  Stream<List<SearchResult>> get searchStream => _searchController.stream;

  Stream<bool> get artistsLoadingStream => _artistsLoadingController.stream;

  Stream<bool> get albumsLoadingStream => _albumsLoadingController.stream;

  Stream<bool> get tracksLoadingStream => _tracksLoadingController.stream;

  Stream<bool> get searchLoadingStream => _searchLoadingController.stream;

  List<Artist> get artists => List.unmodifiable(_artists);

  List<Album> get albums => List.unmodifiable(_albums);

  ArtistReleases get artistReleases => _artistReleases;

  List<Track> get tracks => List.unmodifiable(_tracks);

  List<SearchResult> get searchResults => List.unmodifiable(_search);

  bool get artistsLoading => _artistsLoading;

  bool get hasMoreArtists => _artistsHasMore;

  bool get albumsLoading => _albumsLoading;

  bool get tracksLoading => _tracksLoading;

  bool get searchLoading => _searchLoading;

  Stream<Artist> watchArtist(String artistId) =>
      _artistUpdatesController.stream.where((artist) => artist.id == artistId);

  Stream<Album> watchAlbum(String albumId) => _albumUpdatesController.stream.where((album) => album.id == albumId);

  Future<void> loadArtists({bool refresh = false}) => _artistCatalog.load(refresh: refresh);

  Future<void> loadMoreArtists() => _artistCatalog.loadMore();

  Future<void> loadAllArtists() => _artistCatalog.loadAll();

  Future<void> loadArtistReleases(String artistId) async {
    if (!_host._requireServer('loading artist releases')) {
      return;
    }

    final epoch = _artistReleasesRequests.advance();
    final sessionRevision = _host.connection.sessionRevision;

    _lastArtistId = artistId;
    _artistReleasesArtistId = artistId;
    _artistReleases = const ArtistReleases();
    _albums = [];
    _artistReleasesController.add(_artistReleases);
    _albumsController.add(const []);
    _setAlbumsLoading(true);

    try {
      final fetched = await _host.connection.fetchArtistReleases(artistId);

      if (_host._disposed ||
          !_artistReleasesRequests.isCurrent(epoch) ||
          sessionRevision != _host.connection.sessionRevision) {
        return;
      }

      _artistReleases = ArtistReleases(
        albums: _sortAlbumsByReleaseYear(fetched.albums),
        collabAlbums: fetched.collabAlbums,
        appearsOn: fetched.appearsOn,
        otherCredits: fetched.otherCredits,
      );
      _albums = _artistReleases.albums;

      for (final album in [
        ..._albums,
        ...fetched.collabAlbums.map((entry) => entry.album),
        ...fetched.appearsOn.map((entry) => entry.album),
        ...fetched.otherCredits.map((entry) => entry.album),
      ]) {
        _host._cacheAlbumId(album: album);
      }

      _albumsController.add(List.unmodifiable(_albums));
      _artistReleasesController.add(_artistReleases);

      final artistIndex = _artists.indexWhere((artist) => artist.id == artistId);

      if (artistIndex >= 0) {
        final updated = _artists[artistIndex].copyWith(
          albumCount: _artistReleases.albums.length,
          collabAlbumCount: _artistReleases.collabAlbums.length,
          appearanceCount: _artistReleases.appearsOn.length,
          otherCreditCount: _artistReleases.otherCredits.length,
          releaseCount: _artistReleases.releaseCount,
        );
        final artists = [..._artists];

        artists[artistIndex] = updated;
        _artists = artists;
        _artistsController.add(List.unmodifiable(_artists));
        _artistUpdatesController.add(updated);
      }
    } on ApiException catch (err) {
      if (_host._disposed ||
          !_artistReleasesRequests.isCurrent(epoch) ||
          sessionRevision != _host.connection.sessionRevision) {
        return;
      }

      _host._handleApiError(err, context: 'artist releases');
    } catch (err) {
      if (_host._disposed ||
          !_artistReleasesRequests.isCurrent(epoch) ||
          sessionRevision != _host.connection.sessionRevision) {
        return;
      }

      _host._pushMessage('Failed to load artist releases: $err', level: LogLevel.warning);
    } finally {
      if (_artistReleasesRequests.isCurrent(epoch)) {
        _setAlbumsLoading(false);
      }
    }
  }

  Future<void> loadAlbums(String artistId) async {
    if (!_host._requireServer('loading albums')) {
      return;
    }

    final revision = _host.connection.sessionRevision;
    final request = _albumRequests.advance();
    bool isCurrent() =>
        _host._sessionCoordinator._isServerSessionCurrent(revision) && _albumRequests.isCurrent(request);
    _setAlbumsLoading(true);

    try {
      _lastArtistId = artistId;
      _albums = <Album>[];
      _albumsController.add(List.unmodifiable(_albums));

      final albums = await _host.connection.fetchAlbums(artistId);
      if (!isCurrent()) return;
      _albums = _sortAlbumsByReleaseYear(albums);

      for (final album in _albums) {
        _host._cacheAlbumId(album: album);
      }

      _albumsController.add(List.unmodifiable(_albums));
    } on ApiException catch (err) {
      if (!isCurrent()) return;
      _host._handleApiError(err, context: 'albums');
    } catch (err) {
      if (!isCurrent()) return;
      _host._pushMessage('Failed to load albums: $err', level: LogLevel.warning);
    } finally {
      if (isCurrent()) _setAlbumsLoading(false);
    }
  }

  Future<void> loadTracks(String albumId) async {
    if (!_host._requireServer('loading tracks')) {
      return;
    }

    final revision = _host.connection.sessionRevision;
    final request = _trackRequests.advance();
    bool isCurrent() =>
        _host._sessionCoordinator._isServerSessionCurrent(revision) && _trackRequests.isCurrent(request);
    _setTracksLoading(true);

    try {
      _lastAlbumId = albumId;
      _tracks = <Track>[];
      _tracksController.add(List.unmodifiable(_tracks));

      final tracks = await _host.connection.fetchTracks(albumId);
      if (!isCurrent()) return;
      _tracks = tracks;

      for (final track in _tracks) {
        _host._cacheTrackAlbumId(track, fallbackAlbumId: albumId);
      }

      _tracksController.add(List.unmodifiable(_tracks));
    } on ApiException catch (err) {
      if (!isCurrent()) return;
      _host._handleApiError(err, context: 'tracks');
    } catch (err) {
      if (!isCurrent()) return;
      _host._pushMessage('Failed to load tracks: $err', level: LogLevel.warning);
    } finally {
      if (isCurrent()) _setTracksLoading(false);
    }
  }

  Future<void> search(String query, {String filter = 'all'}) async {
    final trimmed = query.trim();
    final requestId = _searchRequests.advance();
    final revision = _host.connection.sessionRevision;
    bool isCurrent() =>
        _host._sessionCoordinator._isServerSessionCurrent(revision) && _searchRequests.isCurrent(requestId);

    if (!_host._authState.isAuthorized) {
      _search = <SearchResult>[];
      _searchController.add(List.unmodifiable(_search));
      _setSearchLoading(false);

      return;
    }

    if (trimmed.isEmpty) {
      _search = <SearchResult>[];
      _searchController.add(List.unmodifiable(_search));
      _setSearchLoading(false);

      return;
    }

    _setSearchLoading(true);

    try {
      final results = await _host.connection.search(trimmed, filter: filter);

      if (!isCurrent()) {
        return;
      }

      _search = results;
      _searchController.add(List.unmodifiable(_search));
    } on ApiException catch (err) {
      if (!isCurrent()) {
        return;
      }

      _host._handleApiError(err, context: 'search');
    } catch (err) {
      if (!isCurrent()) {
        return;
      }

      _host._pushMessage('Search failed: $err');
    } finally {
      if (isCurrent()) {
        _setSearchLoading(false);
      }
    }
  }

  Future<void> selectSearchResult(SearchResult result) async {
    if (!_host._requireServer('opening search results')) {
      return;
    }

    switch (result.kind) {
      case 'artist':
        await _host.loadAlbums(result.id);
        break;
      case 'album':
        final album = await _host.connection.fetchAlbumById(result.id);

        await _host.loadAlbums(album.artistId);
        await _host.loadTracks(album.id);
        break;
      case 'track':
        final track = await _host.connection.fetchTrackById(result.id);

        if (track.albumId == null) {
          _host._pushMessage('Track is missing album info');

          return;
        }

        final album = await _host.connection.fetchAlbumById(track.albumId!);

        await _host.loadAlbums(album.artistId);
        await _host.loadTracks(album.id);
        await _host.queueAlbum(album.id, startTrackId: track.id);
        break;
      default:
        break;
    }
  }

  void _setArtistsLoading(bool value) {
    if (_artistsLoading == value) {
      return;
    }

    _artistsLoading = value;
    if (!_host._disposed && !_artistsLoadingController.isClosed) {
      _artistsLoadingController.add(value);
    }
  }

  void _setAlbumsLoading(bool value) {
    if (_albumsLoading == value) {
      return;
    }

    _albumsLoading = value;
    _albumsLoadingController.add(value);
  }

  void _setTracksLoading(bool value) {
    if (_tracksLoading == value) {
      return;
    }

    _tracksLoading = value;
    _tracksLoadingController.add(value);
  }

  void _setSearchLoading(bool value) {
    if (_searchLoading == value) {
      return;
    }

    _searchLoading = value;
    _searchLoadingController.add(value);
  }

  void _startMetadataEventListener() {
    final token = _host.connection.token;

    if (token == null || token.isEmpty) {
      return;
    }

    _metadataEvents.start(baseUrl: _host.connection.baseUrl, token: token);
  }

  Future<void> _stopMetadataEventListener() => _metadataEvents.stop();

  Future<void> _applyMetadataEvent(MetadataUpdateEvent event) async {
    // A read started before this update may still contain the old metadata.
    _host.connection.invalidateMetadataReads();
    _host._albumIdByKey.clear();
    _host._metadataReadRevision++;

    switch (event.kind) {
      case 'resync':
        _artistCatalog.details.reset();
        _artistCatalog.browse.reconcile();
        break;
      case 'artist':
        await _refreshMetadataArtist(event.artistId ?? event.id);
        break;
      case 'album':
        await _refreshMetadataAlbum(event.albumId ?? event.id);
        break;
      case 'album_artists':
        final shouldReloadAlbums = _metadataEventMayAffectCurrentArtist(event);

        await _refreshMetadataAlbum(event.albumId ?? event.id, reloadCurrentArtistAlbums: shouldReloadAlbums);
        await _host.loadArtists(refresh: true);
        break;
    }
  }

  Future<void> _refreshMetadataArtist(String artistId) async {
    if (artistId.trim().isEmpty) {
      return;
    }

    final details = _artistCatalog.details;
    _artistCatalog.offlineRepairs.schedule(artistId);
    final needsDetail =
        details.contains(artistId) || _artistReleasesArtistId == artistId || _loadedTracksUseArtist(artistId);
    details.invalidate(artistId);
    _artistCatalog.browse.invalidateArtist(artistId);

    if (!needsDetail) {
      return;
    }

    final sessionRevision = _host.connection.sessionRevision;

    try {
      final updated = await details.load(artistId, refresh: true);

      if (_host._disposed || !_host._authState.isAuthorized || _host.connection.sessionRevision != sessionRevision) {
        return;
      }

      _artistCatalog.updateArtist(updated);
      _artistUpdatesController.add(updated);

      if (updated.name.trim().isNotEmpty) {
        _updateLoadedTrackMetadata((track) => _trackWithUpdatedArtistCredit(track, updated));
      }

      if (_artistReleasesArtistId == artistId) {
        await _host.loadArtistReleases(artistId);
      }
    } catch (error) {
      AppLogger.debug('Failed to refresh artist metadata for $artistId (${error.runtimeType})');
    }
  }

  bool _loadedTracksUseArtist(String artistId) {
    bool includes(Track track) => track.credits.any((credit) => credit.artistId == artistId);

    return [_tracks, _host._playlistTracks, _host._liked, _host._playQueue].any((tracks) => tracks.any(includes)) ||
        (_host._playbackState.track != null && includes(_host._playbackState.track!));
  }

  Track _trackWithUpdatedArtistCredit(Track track, Artist artist) {
    if (!track.credits.any((credit) => credit.artistId == artist.id)) {
      return track;
    }

    final credits = [
      for (final credit in track.credits)
        if (credit.artistId == artist.id)
          ArtistCredit(
            artistId: credit.artistId,
            name: artist.name,
            creditedName: credit.creditedName,
            role: credit.role,
            joinPhrase: credit.joinPhrase,
          )
        else
          credit,
    ];
    final performers = credits.where((credit) => credit.isPerformingArtist).toList();
    final display = StringBuffer();

    for (var i = 0; i < performers.length; i++) {
      display.write(performers[i].displayName);

      if (i < performers.length - 1) {
        display.write(performers[i].joinPhrase.isEmpty ? ', ' : performers[i].joinPhrase);
      }
    }

    return track.copyWith(
      artist: performers.isEmpty ? track.artist : display.toString(),
      artistIds: performers.map((credit) => credit.artistId).toList(),
      artistNames: performers.map((credit) => credit.name).toList(),
      artistCredits: credits,
    );
  }

  Future<void> _refreshMetadataAlbum(String albumId, {bool reloadCurrentArtistAlbums = false}) async {
    if (albumId.trim().isEmpty) {
      return;
    }

    final sessionRevision = _host.connection.sessionRevision;

    try {
      final fetched = await _host.connection.fetchAlbumById(albumId);

      if (_host._disposed || !_host._authState.isAuthorized || _host.connection.sessionRevision != sessionRevision) {
        return;
      }

      var updated = await _albumWithDisplayArtist(fetched);

      if (_host._disposed || !_host._authState.isAuthorized || _host.connection.sessionRevision != sessionRevision) {
        return;
      }

      final index = _albums.indexWhere((album) => album.id == updated.id);

      if (index >= 0) {
        updated = _albumWithListFallbacks(updated, existing: _albums[index]);
        final next = [..._albums];

        next[index] = updated;
        _albums = _sortAlbumsByReleaseYear(next);
        _host._cacheAlbumId(album: updated);
        _albumsController.add(List.unmodifiable(_albums));
      }

      _albumUpdatesController.add(updated);

      unawaited(_host._offlineDownloadManager.refreshOfflineMetadataForAlbum(albumId));
      await _refreshLoadedTracksForAlbum(albumId, sessionRevision);

      if (_host._disposed || !_host._authState.isAuthorized || _host.connection.sessionRevision != sessionRevision) {
        return;
      }

      final artistId = _lastArtistId;

      if ((reloadCurrentArtistAlbums ||
              _artistReleases.collabAlbums.any((entry) => entry.album.id == albumId) ||
              _artistReleases.appearsOn.any((entry) => entry.album.id == albumId) ||
              _artistReleases.otherCredits.any((entry) => entry.album.id == albumId) ||
              _albums.any((album) => album.id == albumId)) &&
          artistId != null &&
          artistId.trim().isNotEmpty) {
        if (_artistReleasesArtistId == artistId) {
          await _host.loadArtistReleases(artistId);
        } else {
          await _host.loadAlbums(artistId);
        }
      }
    } catch (err) {
      AppLogger.debug('Failed to refresh album metadata for $albumId: $err');
    }
  }

  Future<void> _refreshLoadedTracksForAlbum(String albumId, int sessionRevision) async {
    final remotePlayback =
        !_host._playbackState.isLocalPlayback && _host._playbackState.queueSource != PlaybackQueueSource.offline;
    final loaded = <Track>[
      ..._tracks,
      ..._host._playlistTracks,
      ..._host._liked,
      if (remotePlayback) ..._host._playQueue,
      if (remotePlayback && _host._playbackState.track != null) _host._playbackState.track!,
    ];

    if (_lastAlbumId != albumId && !loaded.any((track) => track.albumId == albumId)) {
      return;
    }

    final metadataRevision = _host._metadataReadRevision;
    final fetched = await _host.connection.fetchTracks(albumId);

    if (_host._disposed ||
        !_host._authState.isAuthorized ||
        _host.connection.sessionRevision != sessionRevision ||
        metadataRevision != _host._metadataReadRevision) {
      return;
    }

    final byId = {for (final track in fetched) track.id: track};

    Track refreshMetadata(Track track) {
      final updated = byId[track.id];
      if (updated == null) {
        return track;
      }

      // The track response carries its tagged performer, which can differ from
      // the album's primary artist. Keep current user and playback state.
      return track.copyWith(
        title: updated.title,
        artist: updated.artist,
        artistId: updated.artistId,
        artistIds: updated.artistIds,
        artistNames: updated.artistNames,
        artistCredits: updated.artistCredits,
        album: updated.album,
        albumId: updated.albumId ?? albumId,
        genres: updated.genres,
        listeningGenres: updated.listeningGenres,
        durationMs: updated.durationMs,
        trackNo: updated.trackNo,
        discNo: updated.discNo,
      );
    }

    _updateLoadedTrackMetadata(refreshMetadata);
  }

  void _updateLoadedTrackMetadata(Track Function(Track) update) {
    List<Track> apply(List<Track> tracks) => tracks.map(update).toList();

    _tracks = apply(_tracks);
    _host._playlistTracks = apply(_host._playlistTracks);
    _host._liked = apply(_host._liked);
    _tracksController.add(List.unmodifiable(_tracks));
    _host._playlistTracksController.add(List.unmodifiable(_host._playlistTracks));
    _host._likedController.add(List.unmodifiable(_host._liked));

    if (_host._playbackState.isLocalPlayback || _host._playbackState.queueSource == PlaybackQueueSource.offline) {
      return;
    }

    _host._playQueue = apply(_host._playQueue);

    final current = _host._playbackState.track;
    if (current == null) {
      return;
    }

    final updated = update(current);

    if (!identical(current, updated)) {
      _host._bumpNowPlayingEpoch();
      _host._updatePlayback(track: updated);
    }
  }

  Future<Album> _albumWithDisplayArtist(Album album) async {
    if (album.artist.trim().isNotEmpty) {
      return album;
    }

    final loaded = _loadedAlbum(album.id);
    final loadedArtist = loaded?.artist.trim();

    if (loaded?.artistId == album.artistId && loadedArtist != null && loadedArtist.isNotEmpty) {
      return album.copyWith(artist: loadedArtist);
    }

    if (album.artistId.trim().isEmpty) {
      return album;
    }

    try {
      final artist = await _host.connection.fetchArtistById(album.artistId);

      if (artist.name.trim().isNotEmpty) {
        return album.copyWith(artist: artist.name);
      }
    } catch (_) {}

    return album;
  }

  Album? _loadedAlbum(String albumId) {
    for (final album in _albums) {
      if (album.id == albumId) {
        return album;
      }
    }

    return null;
  }

  Album _albumWithListFallbacks(Album album, {required Album existing}) {
    if (album.trackCount != 0 || existing.trackCount <= 0) {
      return album;
    }

    return album.copyWith(trackCount: existing.trackCount);
  }

  List<Album> _sortAlbumsByReleaseYear(Iterable<Album> albums) {
    final sorted = albums.toList(growable: false);

    sorted.sort(_compareAlbumsByReleaseYear);

    return sorted;
  }

  int _compareAlbumsByReleaseYear(Album a, Album b) {
    final aYear = a.year;
    final bYear = b.year;

    if (aYear != null && bYear != null) {
      final year = aYear.compareTo(bYear);

      if (year != 0) {
        return year;
      }
    } else if (aYear != null) {
      return -1;
    } else if (bYear != null) {
      return 1;
    }

    final title = a.title.toLowerCase().compareTo(b.title.toLowerCase());

    if (title != 0) {
      return title;
    }

    return a.id.compareTo(b.id);
  }

  bool _metadataEventMayAffectCurrentArtist(MetadataUpdateEvent event) {
    final artistId = _lastArtistId;

    if (artistId == null || artistId.trim().isEmpty) {
      return false;
    }

    if (event.artistId == artistId) {
      return true;
    }

    final albumId = event.albumId ?? event.id;

    return _albums.any((album) => album.id == albumId || album.artistId == artistId);
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _LibraryFacade {
  _LibraryCoordinator get _libraryCoordinator;

  StreamController<List<Artist>> get _artistsController => _libraryCoordinator._artistsController;

  StreamController<List<Album>> get _albumsController => _libraryCoordinator._albumsController;

  StreamController<ArtistReleases> get _artistReleasesController => _libraryCoordinator._artistReleasesController;

  StreamController<List<Track>> get _tracksController => _libraryCoordinator._tracksController;

  StreamController<List<SearchResult>> get _searchController => _libraryCoordinator._searchController;

  StreamController<Artist> get _artistUpdatesController => _libraryCoordinator._artistUpdatesController;

  StreamController<Album> get _albumUpdatesController => _libraryCoordinator._albumUpdatesController;

  StreamController<bool> get _artistsLoadingController => _libraryCoordinator._artistsLoadingController;

  StreamController<bool> get _albumsLoadingController => _libraryCoordinator._albumsLoadingController;

  StreamController<bool> get _tracksLoadingController => _libraryCoordinator._tracksLoadingController;

  StreamController<bool> get _searchLoadingController => _libraryCoordinator._searchLoadingController;

  List<Artist> get _artists => _libraryCoordinator._artists;

  set _artists(List<Artist> value) => _libraryCoordinator._artists = value;

  List<Album> get _albums => _libraryCoordinator._albums;

  set _albums(List<Album> value) => _libraryCoordinator._albums = value;

  ArtistReleases get _artistReleases => _libraryCoordinator._artistReleases;

  set _artistReleases(ArtistReleases value) => _libraryCoordinator._artistReleases = value;

  set _artistReleasesArtistId(String? value) => _libraryCoordinator._artistReleasesArtistId = value;

  List<Track> get _tracks => _libraryCoordinator._tracks;

  set _tracks(List<Track> value) => _libraryCoordinator._tracks = value;

  bool get _artistsLoading => _libraryCoordinator._artistsLoading;

  set _artistsOffset(int value) => _libraryCoordinator._artistsOffset = value;

  set _artistsHasMore(bool value) => _libraryCoordinator._artistsHasMore = value;

  String? get _lastArtistId => _libraryCoordinator._lastArtistId;

  set _lastArtistId(String? value) => _libraryCoordinator._lastArtistId = value;

  String? get _lastAlbumId => _libraryCoordinator._lastAlbumId;

  Stream<List<Artist>> get artistsStream => _libraryCoordinator.artistsStream;

  Stream<List<Album>> get albumsStream => _libraryCoordinator.albumsStream;

  Stream<ArtistReleases> get artistReleasesStream => _libraryCoordinator.artistReleasesStream;

  Stream<List<Track>> get tracksStream => _libraryCoordinator.tracksStream;

  Stream<List<SearchResult>> get searchStream => _libraryCoordinator.searchStream;

  Stream<bool> get artistsLoadingStream => _libraryCoordinator.artistsLoadingStream;

  Stream<bool> get albumsLoadingStream => _libraryCoordinator.albumsLoadingStream;

  Stream<bool> get tracksLoadingStream => _libraryCoordinator.tracksLoadingStream;

  Stream<bool> get searchLoadingStream => _libraryCoordinator.searchLoadingStream;

  List<Artist> get artists => _libraryCoordinator.artists;

  List<Album> get albums => _libraryCoordinator.albums;

  ArtistReleases get artistReleases => _libraryCoordinator.artistReleases;

  List<Track> get tracks => _libraryCoordinator.tracks;

  List<SearchResult> get searchResults => _libraryCoordinator.searchResults;

  bool get artistsLoading => _libraryCoordinator.artistsLoading;

  bool get hasMoreArtists => _libraryCoordinator.hasMoreArtists;

  bool get albumsLoading => _libraryCoordinator.albumsLoading;

  bool get tracksLoading => _libraryCoordinator.tracksLoading;

  bool get searchLoading => _libraryCoordinator.searchLoading;

  Stream<Artist> watchArtist(String artistId) => _libraryCoordinator.watchArtist(artistId);

  Stream<Album> watchAlbum(String albumId) => _libraryCoordinator.watchAlbum(albumId);

  Future<void> loadArtists({bool refresh = false}) => _libraryCoordinator.loadArtists(refresh: refresh);

  Future<void> loadMoreArtists() => _libraryCoordinator.loadMoreArtists();

  Future<void> loadAllArtists() => _libraryCoordinator.loadAllArtists();

  Future<void> loadArtistReleases(String artistId) => _libraryCoordinator.loadArtistReleases(artistId);

  Future<void> loadAlbums(String artistId) => _libraryCoordinator.loadAlbums(artistId);

  Future<void> loadTracks(String albumId) => _libraryCoordinator.loadTracks(albumId);

  Future<void> search(String query, {String filter = 'all'}) => _libraryCoordinator.search(query, filter: filter);

  Future<void> selectSearchResult(SearchResult result) => _libraryCoordinator.selectSearchResult(result);

  ArtistBrowseSnapshot get artistBrowseSnapshot => _libraryCoordinator._artistCatalog.browse.current;

  Stream<ArtistBrowseSnapshot> get artistBrowseStream => _libraryCoordinator._artistCatalog.browse.changes;

  Future<void> loadArtistBrowsePage(int index) => _libraryCoordinator._artistCatalog.loadIndex(index);

  Future<Artist> fetchArtistMetadata(String id, {bool refresh = false}) =>
      _libraryCoordinator._artistCatalog.details.load(id, refresh: refresh);

  void resetLibraryMemoryResources() => _libraryCoordinator._artistCatalog.reset();

  Future<void> closeLibraryMemoryResources() => _libraryCoordinator._artistCatalog.close();

  void _invalidateArtistPages() => resetLibraryMemoryResources();

  void _invalidateArtistReleases() => _libraryCoordinator._artistReleasesRequests.advance();

  void _startMetadataEventListener() => _libraryCoordinator._startMetadataEventListener();

  Future<void> _stopMetadataEventListener() => _libraryCoordinator._stopMetadataEventListener();
}
