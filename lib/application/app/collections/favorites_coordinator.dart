part of 'package:phonolite_app/application/app/app_controller.dart';

class _FavoritesCoordinator {
  final AppController _host;
  final _likedController = StreamController<List<Track>>.broadcast();
  List<Track> _liked = <Track>[];
  final _likedRequests = RequestGeneration();

  _FavoritesCoordinator(this._host);

  Stream<List<Track>> get likedStream => _likedController.stream;

  List<Track> get liked => List.unmodifiable(_liked);

  void _clearServerData() {
    _likedRequests.advance();
    _liked = [];
    _likedController.add(const []);
  }

  Future<void> loadLikedTracks() async {
    if (!_host._requireServer('loading liked tracks')) {
      return;
    }

    final revision = _host.connection.sessionRevision;
    final request = _likedRequests.advance();
    bool isCurrent() =>
        _host._sessionCoordinator._isServerSessionCurrent(revision) && _likedRequests.isCurrent(request);
    try {
      final tracks = await _host.connection.fetchLikedTracks();
      if (!isCurrent()) return;
      _liked = tracks;

      for (final track in _liked) {
        _host._cacheTrackAlbumId(track);
      }

      _likedController.add(List.unmodifiable(_liked));
    } on ApiException catch (err) {
      if (!isCurrent()) return;
      _host._handleApiError(err, context: 'liked tracks');
    } catch (err) {
      if (!isCurrent()) return;
      _host._pushMessage('Failed to load liked tracks: $err', level: LogLevel.warning);
    }
  }

  Future<void> loadLocalLikedTracks() async {
    await _host._offlineDownloadManager.loadLocalLikedTracks();
  }

  Future<void> toggleLike(Track track) async {
    if (_shouldUseLocalUserData(track)) {
      await _host.toggleLocalLike(track);

      return;
    }

    if (!_host._requireServer('updating likes')) {
      return;
    }

    final revision = _host.connection.sessionRevision;
    bool isCurrent() => _host._sessionCoordinator._isServerSessionCurrent(revision);
    try {
      final liked = !track.liked;
      final state = await _host.connection.setLikeState(track.id, liked);
      if (!isCurrent()) return;

      _updateLike(track.id, state?.liked ?? liked, knownTrack: track);
      await _host._pushNowPlayingUpdate(force: true);
    } on ApiException catch (err) {
      if (!isCurrent()) return;
      _host._handleApiError(err, context: 'like');
    } catch (err) {
      if (!isCurrent()) return;
      _host._pushMessage('Failed to update like: $err');
    }
  }

  Future<void> toggleLocalLike(Track track) async {
    final localId = _localTrackIdFor(track);

    if (localId == null) {
      _host._pushMessage('Download ${track.title} before saving it to local liked songs.', level: LogLevel.warning);

      return;
    }

    final currentlyLiked = track.liked || _host.localLiked.any((item) => item.localId == localId || item.id == localId);

    try {
      await _host._offlineDownloadManager.setLocalLike(track, !currentlyLiked);

      _updateLocalLike(localId, !currentlyLiked);
      await _host._pushNowPlayingUpdate(force: true);
    } catch (err) {
      _host._pushMessage('Failed to update local like: $err');
    }
  }

  void _updateLike(String trackId, bool liked, {Track? knownTrack}) {
    _host._tracks = _host._tracks.map((track) => track.id == trackId ? track.copyWith(liked: liked) : track).toList();
    _host._playlistTracks = _host._playlistTracks
        .map((track) => track.id == trackId ? track.copyWith(liked: liked) : track)
        .toList();
    _host._playQueue = _host._playQueue
        .map((track) => track.id == trackId ? track.copyWith(liked: liked) : track)
        .toList();

    final current = _host._playbackState.track;

    if (current != null && current.id == trackId) {
      _host._updatePlayback(track: current.copyWith(liked: liked));
    }

    if (liked) {
      final existing = _knownLikedTrack(trackId, knownTrack: knownTrack);

      if (existing != null) {
        _liked = [existing, ..._liked.where((track) => track.id != trackId && track.serverTrackId != trackId)];
      } else {
        AppLogger.debug('Skipped adding liked track $trackId because metadata is not loaded.');
      }
    } else {
      _liked = _liked.where((track) => track.id != trackId && track.serverTrackId != trackId).toList();
    }

    _host._tracksController.add(List.unmodifiable(_host._tracks));
    _host._playlistTracksController.add(List.unmodifiable(_host._playlistTracks));
    _likedController.add(List.unmodifiable(_liked));
  }

  Track? _knownLikedTrack(String trackId, {Track? knownTrack}) {
    Track? findIn(Iterable<Track> tracks) {
      for (final track in tracks) {
        if (track.id == trackId || track.serverTrackId == trackId) {
          return _asServerLikedTrack(trackId, track);
        }
      }

      return null;
    }

    if (knownTrack != null) {
      return _asServerLikedTrack(trackId, knownTrack);
    }

    return findIn(_host._tracks) ??
        findIn(_host._playlistTracks) ??
        findIn(_host._playQueue) ??
        (_host._playbackState.track != null ? findIn(<Track>[_host._playbackState.track!]) : null) ??
        findIn(_liked);
  }

  Track _asServerLikedTrack(String trackId, Track track) {
    return track.copyWith(
      id: trackId,
      localId: null,
      serverBaseUrl: track.serverBaseUrl ?? _host.connection.baseUrl,
      serverTrackId: track.serverTrackId ?? trackId,
      liked: true,
    );
  }

  void _updateLocalLike(String localTrackId, bool liked) {
    _host._playQueue = _host._playQueue
        .map(
          (track) => (track.localId == localTrackId || track.id == localTrackId) ? track.copyWith(liked: liked) : track,
        )
        .toList();

    if (!liked) {
      _pruneTrackFromLocalLikedQueue(localTrackId);
    }

    final current = _host._playbackState.track;

    if (current != null && (current.localId == localTrackId || current.id == localTrackId)) {
      _host._updatePlayback(track: current.copyWith(liked: liked));
    }
  }

  void _pruneTrackFromLocalLikedQueue(String localTrackId) {
    if (_host._playbackState.queueSource != PlaybackQueueSource.offline ||
        _host._offlineQueueSource != OfflineQueueSource.localLiked ||
        _host._playQueue.isEmpty) {
      return;
    }

    final oldQueue = _host._playQueue;
    final current = _host._playbackState.track;
    final currentIndex = current == null
        ? -1
        : oldQueue.indexWhere((track) => _host._sameTrackIdentity(track, current));
    final effectiveIndex = currentIndex >= 0 ? currentIndex : _host._playIndex.clamp(0, oldQueue.length - 1).toInt();
    var removedBeforeEffectiveIndex = 0;
    final nextQueue = <Track>[];

    for (var i = 0; i < oldQueue.length; i += 1) {
      final track = oldQueue[i];

      if (_trackMatchesLocalId(track, localTrackId)) {
        if (i < effectiveIndex) {
          removedBeforeEffectiveIndex += 1;
        }

        continue;
      }

      nextQueue.add(track);
    }

    if (nextQueue.length == oldQueue.length) {
      return;
    }

    _host._playQueue = nextQueue;

    if (_host._playQueue.isEmpty) {
      _host._playIndex = 0;

      return;
    }

    final currentWasRemoved = current != null && _trackMatchesLocalId(current, localTrackId);

    if (currentWasRemoved) {
      _host._playIndex = min(effectiveIndex, _host._playQueue.length) - 1;

      return;
    }

    _host._playIndex = (effectiveIndex - removedBeforeEffectiveIndex).clamp(0, _host._playQueue.length - 1).toInt();
  }

  bool _trackMatchesLocalId(Track track, String localTrackId) {
    return track.id == localTrackId || track.localId == localTrackId;
  }

  bool _localTrackIsLiked(String trackId) {
    return _host.localLiked.any(
      (track) => track.id == trackId || track.localId == trackId || track.serverTrackId == trackId,
    );
  }

  bool _shouldUseLocalUserData(Track track) {
    if (_host._playbackState.isLocalPlayback &&
        _host._playbackState.track != null &&
        (_host._playbackState.track!.id == track.id || _host._playbackState.track!.localId == track.localId)) {
      return true;
    }

    final localId = _localTrackIdFor(track);
    if (localId == null) {
      return false;
    }

    return track.id == localId || track.localId == localId;
  }

  String? _localTrackIdFor(Track track) {
    final localId = track.localId;

    if (localId != null && localId.isNotEmpty) {
      return localId;
    }

    final download = _host.availableOfflineDownloadForTrack(track.id);

    return download?.localTrackId ?? download?.track.localId;
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _FavoritesFacade {
  _FavoritesCoordinator get _favoritesCoordinator;

  StreamController<List<Track>> get _likedController => _favoritesCoordinator._likedController;

  List<Track> get _liked => _favoritesCoordinator._liked;

  set _liked(List<Track> value) => _favoritesCoordinator._liked = value;

  Stream<List<Track>> get likedStream => _favoritesCoordinator.likedStream;

  List<Track> get liked => _favoritesCoordinator.liked;

  Future<void> loadLikedTracks() => _favoritesCoordinator.loadLikedTracks();

  Future<void> loadLocalLikedTracks() => _favoritesCoordinator.loadLocalLikedTracks();

  Future<void> toggleLike(Track track) => _favoritesCoordinator.toggleLike(track);

  Future<void> toggleLocalLike(Track track) => _favoritesCoordinator.toggleLocalLike(track);

  bool _localTrackIsLiked(String trackId) => _favoritesCoordinator._localTrackIsLiked(trackId);

  String? _localTrackIdFor(Track track) => _favoritesCoordinator._localTrackIdFor(track);
}
