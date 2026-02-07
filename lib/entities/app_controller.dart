import 'dart:async';

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'auth_state.dart';
import 'models.dart';
import 'server_connection.dart';
import 'audio_engine.dart';

enum ShuffleMode { off, all, artist, album, custom }

enum RepeatMode { off, one }

enum StreamMode { auto, high, medium, low }

class _ShuffleContext {
  const _ShuffleContext({
    required this.scope,
    this.playlistId,
    this.artistId,
    this.albumId,
  });

  final String scope;
  final String? playlistId;
  final String? artistId;
  final String? albumId;
}

class PlaybackState {
  PlaybackState({
    required this.track,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.bufferRatio,
    required this.volume,
    required this.shuffleMode,
    required this.repeatMode,
    required this.streamMode,
    required this.bitrateKbps,
    required this.streamConnected,
    required this.streamRttMs,
  });

  final Track? track;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final double bufferRatio;
  final double volume;
  final ShuffleMode shuffleMode;
  final RepeatMode repeatMode;
  final StreamMode streamMode;
  final double? bitrateKbps;
  final bool streamConnected;
  final int? streamRttMs;

  PlaybackState copyWith({
    Track? track,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    double? bufferRatio,
    double? volume,
    ShuffleMode? shuffleMode,
    RepeatMode? repeatMode,
    StreamMode? streamMode,
    double? bitrateKbps,
    bool? streamConnected,
    int? streamRttMs,
  }) {
    return PlaybackState(
      track: track ?? this.track,
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      bufferRatio: bufferRatio ?? this.bufferRatio,
      volume: volume ?? this.volume,
      shuffleMode: shuffleMode ?? this.shuffleMode,
      repeatMode: repeatMode ?? this.repeatMode,
      streamMode: streamMode ?? this.streamMode,
      bitrateKbps: bitrateKbps ?? this.bitrateKbps,
      streamConnected: streamConnected ?? this.streamConnected,
      streamRttMs: streamRttMs ?? this.streamRttMs,
    );
  }
}

class AppController {
  AppController({required this.connection}) {
    _playbackState = PlaybackState(
      track: null,
      isPlaying: false,
      position: Duration.zero,
      duration: Duration.zero,
      bufferRatio: 0.0,
      volume: 1.0,
      shuffleMode: ShuffleMode.off,
      repeatMode: RepeatMode.off,
      streamMode: StreamMode.auto,
      bitrateKbps: null,
      streamConnected: false,
      streamRttMs: null,
    );
    _authState = AuthState(
      isAuthorized: false,
      baseUrl: connection.baseUrl,
    );
    _audioEngine = AudioEngine(
      onMessage: _pushMessage,
      onStats: (position, bufferedAhead, bitrateKbps) {
        final duration = _playbackState.duration;
        final clamped = duration == Duration.zero
            ? position
            : position > duration
                ? duration
                : position;
        final bufferedTotal = clamped + bufferedAhead;
        final bufferRatio = duration == Duration.zero
            ? 0.0
            : (bufferedTotal.inMilliseconds / duration.inMilliseconds)
                .clamp(0.0, 1.0);
        _updatePlayback(
          position: clamped,
          bufferRatio: bufferRatio,
          bitrateKbps: bitrateKbps,
        );
        _sendStreamControlUpdate(clamped, bufferedAhead);
        _maybeAutoAdvance(clamped, bufferedAhead);
      },
      onStreamInfo: (sessionId, bitrateKbps) {
        if (bitrateKbps != null) {
          _updatePlayback(bitrateKbps: bitrateKbps);
        }
        _openStreamControl(sessionId);
      },
      onComplete: _handleTrackFinished,
    );
  }

  final ServerConnection connection;
  late final AudioEngine _audioEngine;

  final _artistsController = StreamController<List<Artist>>.broadcast();
  final _albumsController = StreamController<List<Album>>.broadcast();
  final _tracksController = StreamController<List<Track>>.broadcast();
  final _playlistsController = StreamController<List<Playlist>>.broadcast();
  final _playlistTracksController = StreamController<List<Track>>.broadcast();
  final _likedController = StreamController<List<Track>>.broadcast();
  final _statsController = StreamController<StatsResponse?>.broadcast();
  final _searchController = StreamController<List<SearchResult>>.broadcast();
  final _messageController = StreamController<List<String>>.broadcast();
  final _playbackController = StreamController<PlaybackState>.broadcast();
  final _authController = StreamController<AuthState>.broadcast();
  final _artistsLoadingController = StreamController<bool>.broadcast();
  final _albumsLoadingController = StreamController<bool>.broadcast();
  final _tracksLoadingController = StreamController<bool>.broadcast();
  final _searchLoadingController = StreamController<bool>.broadcast();

  List<Artist> _artists = <Artist>[];
  List<Album> _albums = <Album>[];
  List<Track> _tracks = <Track>[];
  List<Playlist> _playlists = <Playlist>[];
  List<Track> _playlistTracks = <Track>[];
  List<Track> _liked = <Track>[];
  List<SearchResult> _search = <SearchResult>[];
  List<String> _messages = <String>[];
  StatsResponse? _stats;
  late PlaybackState _playbackState;
  late AuthState _authState;
  List<OutputDevice> _outputDevices = <OutputDevice>[];
  int _outputDeviceId = kDefaultOutputDeviceId;
  String? _outputDeviceName;
  bool _artistsLoading = false;
  bool _albumsLoading = false;
  bool _tracksLoading = false;
  bool _searchLoading = false;
  List<Track> _playQueue = <Track>[];
  int _playIndex = 0;
  final Random _shuffleRandom = Random();
  bool _autoAdvanceInFlight = false;
  DateTime? _suppressAutoAdvanceUntil;
  ShuffleMode _queueShuffleMode = ShuffleMode.off;
  String? _queueShuffleScope;
  String? _queueShufflePlaylistId;
  String? _queueShuffleArtistId;
  String? _queueShuffleAlbumId;
  String? _lastArtistId;
  String? _lastAlbumId;
  String? _currentPlaylistId;
  final Map<String, String> _albumIdByKey = <String, String>{};
  WebSocket? _streamControlSocket;
  String? _streamControlSessionId;
  DateTime? _lastPingAt;
  int? _lastPingSentMs;
  int? _lastRttMs;

  Stream<List<Artist>> get artistsStream => _artistsController.stream;
  Stream<List<Album>> get albumsStream => _albumsController.stream;
  Stream<List<Track>> get tracksStream => _tracksController.stream;
  Stream<List<Playlist>> get playlistsStream => _playlistsController.stream;
  Stream<List<Track>> get playlistTracksStream => _playlistTracksController.stream;
  Stream<List<Track>> get likedStream => _likedController.stream;
  Stream<StatsResponse?> get statsStream => _statsController.stream;
  Stream<List<SearchResult>> get searchStream => _searchController.stream;
  Stream<List<String>> get messageStream => _messageController.stream;
  Stream<PlaybackState> get playbackStream => _playbackController.stream;
  Stream<AuthState> get authStream => _authController.stream;
  Stream<bool> get artistsLoadingStream => _artistsLoadingController.stream;
  Stream<bool> get albumsLoadingStream => _albumsLoadingController.stream;
  Stream<bool> get tracksLoadingStream => _tracksLoadingController.stream;
  Stream<bool> get searchLoadingStream => _searchLoadingController.stream;

  List<Artist> get artists => _artists;
  List<Album> get albums => _albums;
  List<Track> get tracks => _tracks;
  List<Playlist> get playlists => _playlists;
  List<Track> get playlistTracks => _playlistTracks;
  List<Track> get liked => _liked;
  List<SearchResult> get searchResults => _search;
  List<String> get messages => _messages;
  StatsResponse? get stats => _stats;
  PlaybackState get playbackState => _playbackState;
  AuthState get authState => _authState;
  bool get artistsLoading => _artistsLoading;
  bool get albumsLoading => _albumsLoading;
  bool get tracksLoading => _tracksLoading;
  bool get searchLoading => _searchLoading;
  List<OutputDevice> get outputDevices => _outputDevices;
  int get outputDeviceId => _outputDeviceId;
  String? get outputDeviceName => _outputDeviceName;

  void dispose() {
    _artistsController.close();
    _albumsController.close();
    _tracksController.close();
    _playlistsController.close();
    _playlistTracksController.close();
    _likedController.close();
    _statsController.close();
    _searchController.close();
    _messageController.close();
    _playbackController.close();
    _authController.close();
    _artistsLoadingController.close();
    _albumsLoadingController.close();
    _tracksLoadingController.close();
    _searchLoadingController.close();
    _audioEngine.dispose();
    _closeStreamControl();
  }

  Future<void> loginWithPassword({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    try {
      connection.setBaseUrl(baseUrl);
      await connection.login(username: username, password: password);
      _setAuthorized(true, error: null);
      await _loadPlaybackSettings();
    } on ApiException catch (err) {
      final message = '${_formatApiError(err)} (POST ${connection.baseUrl}/auth/login)';
      _setAuthorized(false, error: message);
      _pushMessage('Login failed: $message');
    } catch (err) {
      _setAuthorized(false, error: err.toString());
      _pushMessage('Login failed: $err');
    }
  }

  void loginWithToken({required String baseUrl, required String token}) {
    connection.setBaseUrl(baseUrl);
    connection.setToken(token);
    _setAuthorized(true, error: null);
    () async {
      await _loadPlaybackSettings();
    }();
  }

  Future<bool> probeServer(String input) async {
    try {
      final resolved = await connection.resolveBaseUrl(input);
      connection.setBaseUrl(resolved);
      _setAuthorized(false, error: null);
      return true;
    } catch (err) {
      final message = err.toString();
      _setAuthorized(false, error: message);
      _pushMessage('Server connection failed: $message');
      return false;
    }
  }

  void logout() {
    connection.setToken(null);
    _setAuthorized(false, error: null);
    _audioEngine.stop();
    _playQueue = <Track>[];
    _playIndex = 0;
    _autoAdvanceInFlight = false;
  }

  Future<void> loadArtists() async {
    _setArtistsLoading(true);
    try {
      _artists = await connection.fetchArtists();
      _artistsController.add(_artists);
    } on ApiException catch (err) {
      _handleApiError(err, context: 'artists');
    } catch (err) {
      _pushMessage('Failed to load artists: $err');
    } finally {
      _setArtistsLoading(false);
    }
  }

  Future<void> loadAlbums(String artistId) async {
    _setAlbumsLoading(true);
    try {
      _lastArtistId = artistId;
      _albums = <Album>[];
      _albumsController.add(_albums);
      _albums = await connection.fetchAlbums(artistId);
      for (final album in _albums) {
        _cacheAlbumId(album: album);
      }
      _albumsController.add(_albums);
    } on ApiException catch (err) {
      _handleApiError(err, context: 'albums');
    } catch (err) {
      _pushMessage('Failed to load albums: $err');
    } finally {
      _setAlbumsLoading(false);
    }
  }

  Future<void> loadTracks(String albumId) async {
    _setTracksLoading(true);
    try {
      _lastAlbumId = albumId;
      _tracks = <Track>[];
      _tracksController.add(_tracks);
      _tracks = await connection.fetchTracks(albumId);
      for (final track in _tracks) {
        _cacheTrackAlbumId(track, fallbackAlbumId: albumId);
      }
      _tracksController.add(_tracks);
    } on ApiException catch (err) {
      _handleApiError(err, context: 'tracks');
    } catch (err) {
      _pushMessage('Failed to load tracks: $err');
    } finally {
      _setTracksLoading(false);
    }
  }

  Future<void> loadPlaylists() async {
    try {
      _playlists = await connection.fetchPlaylists();
      _playlistsController.add(_playlists);
    } on ApiException catch (err) {
      _handleApiError(err, context: 'playlists');
    } catch (err) {
      _pushMessage('Failed to load playlists: $err');
    }
  }

  Future<void> loadPlaylistTracks(String playlistId) async {
    try {
      _currentPlaylistId = playlistId;
      _playlistTracks = await connection.fetchPlaylistTracks(playlistId);
      for (final track in _playlistTracks) {
        _cacheTrackAlbumId(track);
      }
      _playlistTracksController.add(_playlistTracks);
    } on ApiException catch (err) {
      _handleApiError(err, context: 'playlist tracks');
    } catch (err) {
      _pushMessage('Failed to load playlist tracks: $err');
    }
  }

  Future<void> loadLikedTracks() async {
    try {
      _liked = await connection.fetchLikedTracks();
      for (final track in _liked) {
        _cacheTrackAlbumId(track);
      }
      _likedController.add(_liked);
    } on ApiException catch (err) {
      _handleApiError(err, context: 'liked tracks');
    } catch (err) {
      _pushMessage('Failed to load liked tracks: $err');
    }
  }

  Future<void> playLikedTrack(String trackId) async {
    Track? full;
    try {
      full = await connection.fetchTrackById(trackId);
    } catch (err) {
      _pushMessage('Track details lookup failed: $err');
    }
    var albumId = full?.albumId;
    if ((albumId == null || albumId.isEmpty) && full != null) {
      albumId = await _resolveAlbumIdBySearch(
        artist: full.artist,
        album: full.album,
      );
    }
    if (albumId != null && albumId.isNotEmpty) {
      await queueAlbum(albumId, startTrackId: trackId);
      return;
    }
    await queueLiked(startTrackId: trackId);
  }

  Future<void> loadStats({int? year, int? month}) async {
    try {
      _stats = await connection.fetchStats(year: year, month: month);
      _statsController.add(_stats);
    } on ApiException catch (err) {
      _handleApiError(err, context: 'stats');
      _statsController.add(null);
    } catch (err) {
      _pushMessage('Failed to load stats: $err');
      _statsController.add(null);
    }
  }

  Future<void> search(String query, {String filter = 'all'}) async {
    _setSearchLoading(true);
    try {
      _search = await connection.search(query, filter: filter);
      _searchController.add(_search);
    } on ApiException catch (err) {
      _handleApiError(err, context: 'search');
    } catch (err) {
      _pushMessage('Search failed: $err');
    } finally {
      _setSearchLoading(false);
    }
  }

  Future<void> selectSearchResult(SearchResult result) async {
    switch (result.kind) {
      case 'artist':
        await loadAlbums(result.id);
        break;
      case 'album':
        final album = await connection.fetchAlbumById(result.id);
        await loadAlbums(album.artistId);
        await loadTracks(album.id);
        break;
      case 'track':
        final track = await connection.fetchTrackById(result.id);
        if (track.albumId == null) {
          _pushMessage('Track is missing album info');
          return;
        }
        final album = await connection.fetchAlbumById(track.albumId!);
        await loadAlbums(album.artistId);
        await loadTracks(album.id);
        await queueAlbum(album.id, startTrackId: track.id);
        break;
      default:
        break;
    }
  }

  Future<void> toggleLike(Track track) async {
    try {
      if (track.liked) {
        await connection.unlikeTrack(track.id);
        _updateLike(track.id, false);
      } else {
        await connection.likeTrack(track.id);
        _updateLike(track.id, true);
      }
    } on ApiException catch (err) {
      _handleApiError(err, context: 'like');
    } catch (err) {
      _pushMessage('Failed to update like: $err');
    }
  }

  Future<void> createPlaylist(String name) async {
    try {
      final playlist = await connection.createPlaylist(name);
      _playlists = [..._playlists, playlist];
      _playlistsController.add(_playlists);
    } on ApiException catch (err) {
      _handleApiError(err, context: 'create playlist');
    } catch (err) {
      _pushMessage('Failed to create playlist: $err');
    }
  }

  Future<void> renamePlaylist(String playlistId, String name) async {
    try {
      final updated = await connection.renamePlaylist(playlistId, name);
      _playlists = _playlists
          .map((playlist) => playlist.id == updated.id ? updated : playlist)
          .toList();
      _playlistsController.add(_playlists);
    } on ApiException catch (err) {
      _handleApiError(err, context: 'rename playlist');
    } catch (err) {
      _pushMessage('Failed to rename playlist: $err');
    }
  }

  Future<void> deletePlaylist(String playlistId) async {
    try {
      await connection.deletePlaylist(playlistId);
      _playlists = _playlists.where((playlist) => playlist.id != playlistId).toList();
      _playlistsController.add(_playlists);
      if (_currentPlaylistId == playlistId) {
        _currentPlaylistId = null;
        _playlistTracks = <Track>[];
        _playlistTracksController.add(_playlistTracks);
      }
    } on ApiException catch (err) {
      _handleApiError(err, context: 'delete playlist');
    } catch (err) {
      _pushMessage('Failed to delete playlist: $err');
    }
  }

  Future<void> updatePlaylistTracks(String playlistId, List<String> trackIds) async {
    try {
      final updated = await connection.updatePlaylistTracks(playlistId, trackIds);
      _playlists = _playlists
          .map((playlist) => playlist.id == updated.id ? updated : playlist)
          .toList();
      _playlistsController.add(_playlists);
    } on ApiException catch (err) {
      _handleApiError(err, context: 'update playlist');
    } catch (err) {
      _pushMessage('Failed to update playlist: $err');
    }
  }

  Future<void> addTrackToPlaylist(Playlist playlist, Track track) async {
    try {
      if (playlist.trackIds.contains(track.id)) {
        _pushMessage('Track already in playlist: ${playlist.name}');
        return;
      }
      final updatedIds = [...playlist.trackIds, track.id];
      final updated = await connection.updatePlaylistTracks(
        playlist.id,
        updatedIds,
      );
      _playlists = _playlists
          .map((item) => item.id == updated.id ? updated : item)
          .toList();
      _playlistsController.add(_playlists);
      if (_currentPlaylistId == playlist.id) {
        final exists = _playlistTracks.any((item) => item.id == track.id);
        if (!exists) {
          _playlistTracks = [..._playlistTracks, track];
          _playlistTracksController.add(_playlistTracks);
        }
      }
      _pushMessage('Added to playlist: ${playlist.name}');
    } on ApiException catch (err) {
      _handleApiError(err, context: 'update playlist');
    } catch (err) {
      _pushMessage('Failed to update playlist: $err');
    }
  }

  Future<void> queueAlbum(String albumId, {String? startTrackId}) async {
    try {
      if (_playbackState.shuffleMode != ShuffleMode.off) {
        String? artistId;
        String? albumShuffleId;
        if (_playbackState.shuffleMode == ShuffleMode.album) {
          albumShuffleId = albumId;
        } else if (_playbackState.shuffleMode == ShuffleMode.artist) {
          final album = await connection.fetchAlbumById(albumId);
          artistId = album.artistId;
        }
        await queueShuffle(
          scope: 'library',
          artistId: artistId,
          albumId: albumShuffleId,
          startTrackId: startTrackId,
        );
        return;
      }
      _pushMessage('Queue album: $albumId${startTrackId == null ? '' : ' (start $startTrackId)'}');
      final tracks = await connection.fetchTracks(albumId);
      if (tracks.isEmpty) {
        _pushMessage('No tracks found for album');
        return;
      }
      final normalized = tracks
          .map(
            (track) => (track.albumId == null || track.albumId!.isEmpty)
                ? Track(
                    id: track.id,
                    title: track.title,
                    artist: track.artist,
                    album: track.album,
                    durationMs: track.durationMs,
                    liked: track.liked,
                    inPlaylists: track.inPlaylists,
                    albumId: albumId,
                    trackNo: track.trackNo,
                    discNo: track.discNo,
                  )
                : track,
          )
          .toList();
      _setQueue(normalized, startTrackId: startTrackId);
      await _playCurrent();
    } on ApiException catch (err) {
      _handleApiError(err, context: 'queue album');
    } catch (err) {
      _pushMessage('Failed to queue album: $err');
    }
  }

  Future<void> queuePlaylist(String playlistId, {String? startTrackId}) async {
    try {
      if (_playbackState.shuffleMode != ShuffleMode.off) {
        if ((_playbackState.shuffleMode == ShuffleMode.album ||
                _playbackState.shuffleMode == ShuffleMode.artist) &&
            startTrackId != null) {
          final context = await _resolveAlbumArtistForTrack(startTrackId);
          await queueShuffle(
            scope: 'library',
            artistId: context.artistId,
            albumId: context.albumId,
            startTrackId: startTrackId,
          );
        } else {
          await queueShuffle(
            scope: 'playlist',
            playlistId: playlistId,
            startTrackId: startTrackId,
          );
        }
        return;
      }
      _pushMessage('Queue playlist: $playlistId${startTrackId == null ? '' : ' (start $startTrackId)'}');
      final tracks = await connection.fetchPlaylistTracks(playlistId);
      if (tracks.isEmpty) {
        _pushMessage('No tracks found for playlist');
        return;
      }
      var normalized = _normalizeQueueTracks(tracks);
      if (startTrackId != null) {
        normalized = await _hydrateQueueStartTrack(normalized, startTrackId);
      }
      _setQueue(normalized, startTrackId: startTrackId);
      await _playCurrent();
    } on ApiException catch (err) {
      _handleApiError(err, context: 'queue playlist');
    } catch (err) {
      _pushMessage('Failed to queue playlist: $err');
    }
  }

  Future<void> queueLiked({String? startTrackId}) async {
    try {
      if (_playbackState.shuffleMode != ShuffleMode.off) {
        if ((_playbackState.shuffleMode == ShuffleMode.album ||
                _playbackState.shuffleMode == ShuffleMode.artist) &&
            startTrackId != null) {
          final context = await _resolveAlbumArtistForTrack(startTrackId);
          await queueShuffle(
            scope: 'library',
            artistId: context.artistId,
            albumId: context.albumId,
            startTrackId: startTrackId,
          );
        } else {
          await queueShuffle(scope: 'liked', startTrackId: startTrackId);
        }
        return;
      }
      _pushMessage('Queue liked${startTrackId == null ? '' : ' (start $startTrackId)'}');
      final tracks = await connection.fetchLikedTracks();
      if (tracks.isEmpty) {
        _pushMessage('No liked tracks found');
        return;
      }
      var normalized = _normalizeQueueTracks(tracks);
      if (startTrackId != null) {
        normalized = await _hydrateQueueStartTrack(normalized, startTrackId);
      }
      _setQueue(normalized, startTrackId: startTrackId);
      await _playCurrent();
    } on ApiException catch (err) {
      _handleApiError(err, context: 'queue liked');
    } catch (err) {
      _pushMessage('Failed to queue liked: $err');
    }
  }

  Future<void> queueShuffle({
    required String scope,
    String? playlistId,
    String? artistId,
    String? albumId,
    bool play = true,
    String? startTrackId,
  }) async {
    try {
      if (_playbackState.shuffleMode == ShuffleMode.off) {
        _pushMessage('Shuffle is off');
        return;
      }

      if (scope == 'playlist') {
        if (playlistId == null) {
          _pushMessage('No playlist selected for shuffle');
          return;
        }
        final tracks = await connection.fetchPlaylistTracks(playlistId);
        if (tracks.isEmpty) {
          _pushMessage('No tracks found for playlist');
          return;
        }
        _rememberShuffleContext(
          scope: scope,
          playlistId: playlistId,
          artistId: artistId,
          albumId: albumId,
        );
        var normalized = _normalizeQueueTracks(_shuffleTracks(tracks));
        if (startTrackId != null) {
          normalized = await _hydrateQueueStartTrack(normalized, startTrackId);
        }
        _setQueue(normalized, startTrackId: startTrackId);
        if (play) {
          await _playCurrent();
        }
        return;
      }

      if (scope == 'liked') {
        final tracks = await connection.fetchLikedTracks();
        if (tracks.isEmpty) {
          _pushMessage('No liked tracks found');
          return;
        }
        _rememberShuffleContext(
          scope: scope,
          playlistId: playlistId,
          artistId: artistId,
          albumId: albumId,
        );
        var normalized = _normalizeQueueTracks(_shuffleTracks(tracks));
        if (startTrackId != null) {
          normalized = await _hydrateQueueStartTrack(normalized, startTrackId);
        }
        _setQueue(normalized, startTrackId: startTrackId);
        if (play) {
          await _playCurrent();
        }
        return;
      }

      if (_playbackState.shuffleMode == ShuffleMode.artist && artistId == null) {
        _pushMessage('Select an artist to shuffle');
        return;
      }
      if (_playbackState.shuffleMode == ShuffleMode.album && albumId == null) {
        _pushMessage('Select an album to shuffle');
        return;
      }

      final mode = _shuffleQueryMode(_playbackState.shuffleMode);
      final tracks = await connection.fetchShuffleTracks(
        mode: mode,
        artistId: artistId,
        albumId: albumId,
      );
      if (tracks.isEmpty) {
        _pushMessage('No tracks found for shuffle');
        return;
      }
      _rememberShuffleContext(
        scope: scope,
        playlistId: playlistId,
        artistId: artistId,
        albumId: albumId,
      );
      _setQueue(_shuffleTracks(tracks), startTrackId: startTrackId);
      if (play) {
        await _playCurrent();
      }
    } on ApiException catch (err) {
      _handleApiError(err, context: 'queue shuffle');
    } catch (err) {
      _pushMessage('Failed to queue shuffle: $err');
    }
  }

  Future<void> nextTrack() async {
    try {
      if (_playbackState.shuffleMode != ShuffleMode.off) {
        final ensured = await _ensureShuffleQueue(play: false);
        if (!ensured && _playQueue.isEmpty) {
          _pushMessage('No shuffle queue available');
          return;
        }
      } else if (_playQueue.isEmpty ||
          (_queueShuffleMode != ShuffleMode.off &&
              _queueShuffleMode != _playbackState.shuffleMode)) {
        final ensured = await _ensureAlbumQueueFromCurrent();
        if (!ensured && _playQueue.isEmpty) {
          _pushMessage('No album queue available');
          return;
        }
      }
      if (_playQueue.isEmpty) {
        _pushMessage('No queue to advance');
        return;
      }
      _playIndex = (_playIndex + 1) % _playQueue.length;
      await _playCurrent();
    } on ApiException catch (err) {
      _handleApiError(err, context: 'next track');
    } catch (err) {
      _pushMessage('Failed to move to next track: $err');
    }
  }

  Future<void> prevTrack() async {
    try {
      if (_playbackState.shuffleMode != ShuffleMode.off) {
        final ensured = await _ensureShuffleQueue(play: false);
        if (!ensured && _playQueue.isEmpty) {
          _pushMessage('No shuffle queue available');
          return;
        }
      } else if (_playQueue.isEmpty ||
          (_queueShuffleMode != ShuffleMode.off &&
              _queueShuffleMode != _playbackState.shuffleMode)) {
        final ensured = await _ensureAlbumQueueFromCurrent();
        if (!ensured && _playQueue.isEmpty) {
          _pushMessage('No album queue available');
          return;
        }
      }
      if (_playQueue.isEmpty) {
        _pushMessage('No queue to rewind');
        return;
      }
      _playIndex = (_playIndex - 1) < 0 ? _playQueue.length - 1 : _playIndex - 1;
      await _playCurrent();
    } on ApiException catch (err) {
      _handleApiError(err, context: 'previous track');
    } catch (err) {
      _pushMessage('Failed to move to previous track: $err');
    }
  }

  Future<void> stop() async {
    try {
      _updatePlayback(isPlaying: false, position: Duration.zero, bufferRatio: 0.0);
      _audioEngine.stop();
      _autoAdvanceInFlight = false;
      _closeStreamControl();
    } on ApiException catch (err) {
      _handleApiError(err, context: 'stop');
    } catch (err) {
      _pushMessage('Failed to stop: $err');
    }
  }

  Future<void> pause(bool paused) async {
    try {
      if (!paused && _playbackState.track == null) {
        if (_playbackState.shuffleMode != ShuffleMode.off) {
          final started = await _ensureShuffleQueue(play: true);
          if (!started) {
            _updatePlayback(isPlaying: false);
          }
        } else {
          _pushMessage('No track selected');
          _updatePlayback(isPlaying: false);
        }
        return;
      }

      _updatePlayback(isPlaying: !paused);
      if (paused) {
        _audioEngine.pause();
      } else if (_playbackState.track != null) {
        _audioEngine.resume();
        if (!_audioEngine.hasActivePlayer) {
          _startPlayback(_playbackState.track!, startOffset: _playbackState.position);
        }
      }
    } on ApiException catch (err) {
      _handleApiError(err, context: 'pause');
    } catch (err) {
      _pushMessage('Failed to pause: $err');
    }
  }

  void updateShuffleMode(ShuffleMode mode) {
    _updatePlayback(shuffleMode: mode);
    _pushMessage('Shuffle: ${mode.name}');
    if (mode != ShuffleMode.off) {
      _queueShuffleMode = ShuffleMode.off;
      _queueShuffleScope = null;
      _queueShuffleArtistId = null;
      _queueShuffleAlbumId = null;
      _queueShufflePlaylistId = null;
    }
  }

  void toggleRepeatMode() {
    final next = _playbackState.repeatMode == RepeatMode.off
        ? RepeatMode.one
        : RepeatMode.off;
    _updatePlayback(repeatMode: next);
    _pushMessage('Repeat: ${next.name}');
    () async {
      await _persistPlaybackSettings(next);
    }();
  }

  void updateStreamMode(StreamMode mode) {
    _updatePlayback(streamMode: mode);
    _pushMessage('Stream: ${mode.name}');
    final track = _playbackState.track;
    if (track != null && _playbackState.isPlaying) {
      _startPlayback(track, startOffset: _playbackState.position);
    }
  }

  void setVolume(double value) {
    final clamped = value.clamp(0.0, 1.0);
    _audioEngine.setVolume(clamped);
    _updatePlayback(volume: clamped);
  }

  Future<List<OutputDevice>> listOutputDevices({bool refresh = false}) async {
    if (_outputDevices.isNotEmpty && !refresh) {
      return _outputDevices;
    }
    _outputDevices = await _audioEngine.listOutputDevices();
    final current = _outputDevices.firstWhere(
      (device) => device.id == _outputDeviceId,
      orElse: () => OutputDevice(id: kDefaultOutputDeviceId, name: 'System Default'),
    );
    _outputDeviceId = current.id;
    _outputDeviceName = current.name;
    return _outputDevices;
  }

  Future<void> selectOutputDevice(OutputDevice device) async {
    if (_outputDeviceId == device.id) {
      return;
    }
    final wasPlaying = _playbackState.isPlaying;
    _outputDeviceId = device.id;
    _outputDeviceName = device.name;
    _audioEngine.setOutputDevice(device.id);
    _pushMessage('Output device: ${device.name}');
    final track = _playbackState.track;
    if (track == null) {
      return;
    }
    if (_audioEngine.hasActivePlayer || wasPlaying) {
      _startPlayback(track, startOffset: _playbackState.position);
      if (!wasPlaying) {
        Future<void>.delayed(const Duration(milliseconds: 120), () {
          _audioEngine.pause();
          _updatePlayback(isPlaying: false);
        });
      }
    }
  }

  Future<void> seekTo(Duration position) async {
    final track = _playbackState.track;
    if (track == null) {
      return;
    }
    _suppressAutoAdvanceUntil = DateTime.now().add(const Duration(seconds: 2));
    final duration = _playbackState.duration;
    final clamped = duration == Duration.zero
        ? position
        : position > duration
            ? duration
            : position < Duration.zero
                ? Duration.zero
                : position;
    _updatePlayback(position: clamped, isPlaying: true, bufferRatio: 0.0);
    _startPlayback(track, startOffset: clamped);
  }

  void _updateLike(String trackId, bool liked) {
    _tracks = _tracks
        .map((track) => track.id == trackId ? track.copyWith(liked: liked) : track)
        .toList();
    _playlistTracks = _playlistTracks
        .map((track) => track.id == trackId ? track.copyWith(liked: liked) : track)
        .toList();
    final current = _playbackState.track;
    if (current != null && current.id == trackId) {
      _updatePlayback(track: current.copyWith(liked: liked));
    }
    if (liked) {
      final existing = _tracks.firstWhere(
        (track) => track.id == trackId,
        orElse: () => _playlistTracks.firstWhere(
          (track) => track.id == trackId,
          orElse: () => _liked.firstWhere(
            (track) => track.id == trackId,
            orElse: () {
              if (current != null && current.id == trackId) {
                return current.copyWith(liked: true);
              }
              return Track(
                id: trackId,
                title: 'Unknown track',
                artist: '',
                album: '',
                durationMs: 0,
                liked: true,
                inPlaylists: false,
              );
            },
          ),
        ),
      );
      _liked = [..._liked.where((track) => track.id != trackId), existing];
    } else {
      _liked = _liked.where((track) => track.id != trackId).toList();
    }

    _tracksController.add(_tracks);
    _playlistTracksController.add(_playlistTracks);
    _likedController.add(_liked);
  }

  void _setQueue(List<Track> tracks, {String? startTrackId}) {
    _playQueue = tracks;
    if (startTrackId != null) {
      final idx = tracks.indexWhere((track) => track.id == startTrackId);
      _playIndex = idx >= 0 ? idx : 0;
    } else {
      _playIndex = 0;
    }
    _autoAdvanceInFlight = false;
  }

  void _rememberShuffleContext({
    required String scope,
    String? playlistId,
    String? artistId,
    String? albumId,
  }) {
    _queueShuffleMode = _playbackState.shuffleMode;
    _queueShuffleScope = scope;
    _queueShufflePlaylistId = playlistId;
    _queueShuffleArtistId = artistId;
    _queueShuffleAlbumId = albumId;
  }

  Future<_ShuffleContext?> _resolveShuffleContext() async {
    if (_queueShuffleScope != null &&
        _queueShuffleScope!.isNotEmpty &&
        _queueShuffleMode == _playbackState.shuffleMode) {
      return _ShuffleContext(
        scope: _queueShuffleScope!,
        playlistId: _queueShufflePlaylistId,
        artistId: _queueShuffleArtistId,
        albumId: _queueShuffleAlbumId,
      );
    }

    if (_playbackState.shuffleMode == ShuffleMode.album) {
      var albumId = _playbackState.track?.albumId ?? _lastAlbumId;
      if (albumId == null || albumId.isEmpty) {
        final current = _playbackState.track;
        if (current != null) {
          try {
            final full = await connection.fetchTrackById(current.id);
            albumId = full.albumId;
          } catch (_) {}
        }
      }
      if (albumId == null || albumId.isEmpty) {
        _pushMessage('Shuffle album will apply after a track starts.');
        return null;
      }
      return _ShuffleContext(scope: 'library', albumId: albumId);
    }

    if (_playbackState.shuffleMode == ShuffleMode.artist) {
      String? artistId;
      final current = _playbackState.track;
      if (current != null) {
        var albumId = current.albumId;
        if (albumId == null || albumId.isEmpty) {
          try {
            final full = await connection.fetchTrackById(current.id);
            albumId = full.albumId;
          } catch (_) {}
        }
        if (albumId != null && albumId.isNotEmpty) {
          try {
            final album = await connection.fetchAlbumById(albumId);
            artistId = album.artistId;
          } catch (err) {
            _pushMessage('Failed to resolve artist for shuffle: $err');
          }
        }
      }
      artistId ??= _lastArtistId;
      if (artistId == null || artistId.isEmpty) {
        _pushMessage('Shuffle artist will apply after a track starts.');
        return null;
      }
      return _ShuffleContext(scope: 'library', artistId: artistId);
    }

    return const _ShuffleContext(scope: 'library');
  }

  Future<bool> _ensureShuffleQueue({bool play = true}) async {
    if (_playbackState.shuffleMode == ShuffleMode.off) {
      return false;
    }
    if (_playQueue.isNotEmpty &&
        _queueShuffleMode == _playbackState.shuffleMode &&
        _queueShuffleScope != null) {
      return true;
    }
    final context = await _resolveShuffleContext();
    if (context == null) {
      return false;
    }
    final startTrackId = play ? null : _playbackState.track?.id;
    await queueShuffle(
      scope: context.scope,
      playlistId: context.playlistId,
      artistId: context.artistId,
      albumId: context.albumId,
      play: play,
      startTrackId: startTrackId,
    );
    return _playQueue.isNotEmpty;
  }

  Future<bool> _ensureAlbumQueueFromCurrent() async {
    final current = _playbackState.track;
    if (current == null) {
      return false;
    }
    String? albumId = current.albumId;
    if (albumId == null || albumId.isEmpty) {
      try {
        final full = await connection.fetchTrackById(current.id);
        albumId = full.albumId;
      } catch (err) {
        _pushMessage('Failed to resolve album for track: $err');
      }
    }
    if (albumId == null || albumId.isEmpty) {
      _pushMessage('Track is missing album info');
      return false;
    }
    final tracks = await connection.fetchTracks(albumId);
    if (tracks.isEmpty) {
      _pushMessage('No tracks found for album');
      return false;
    }
    _setQueue(tracks, startTrackId: current.id);
    _queueShuffleMode = ShuffleMode.off;
    _queueShuffleScope = null;
    return true;
  }

  Future<({String? artistId, String? albumId})> _resolveAlbumArtistForTrack(
    String trackId,
  ) async {
    String? albumId;
    String? artistId;
    try {
      final full = await connection.fetchTrackById(trackId);
      albumId = full.albumId;
      if (albumId != null && albumId.isNotEmpty) {
        final album = await connection.fetchAlbumById(albumId);
        artistId = album.artistId;
      }
    } catch (err) {
      _pushMessage('Failed to resolve shuffle context: $err');
    }
    return (artistId: artistId, albumId: albumId);
  }

  Future<void> _playCurrent() async {
    if (_playQueue.isEmpty) {
      return;
    }
    _autoAdvanceInFlight = false;
    final queued = _playQueue[_playIndex];
    final track = _needsTrackHydration(queued)
        ? await _hydrateTrackForPlayback(queued)
        : queued;
    _playQueue =
        _playQueue.map((item) => item.id == track.id ? track : item).toList();
    _pushMessage(
      'Now playing: id=${track.id} artist="${track.artist}" album="${track.album}" albumId="${track.albumId ?? ''}"',
    );
    _updatePlayback(
      track: track,
      isPlaying: true,
      position: Duration.zero,
      duration: Duration(milliseconds: track.durationMs),
      bufferRatio: 0.0,
    );
    _startPlayback(track);
  }

  Future<Track> _hydrateTrackForPlayback(Track track) async {
    Track full = track;
    try {
      full = await connection.fetchTrackById(track.id);
      _pushMessage(
        'Track details response: id=${full.id} artist="${full.artist}" album="${full.album}" albumId="${full.albumId ?? ''}"',
      );
    } catch (err) {
      _pushMessage('Track details lookup failed: $err');
    }

    var resolvedAlbumId = full.albumId ?? track.albumId;
    if ((resolvedAlbumId == null || resolvedAlbumId.isEmpty) &&
        full.artist.isNotEmpty &&
        full.album.isNotEmpty) {
      final key = _albumKey(full.artist, full.album);
      resolvedAlbumId = _albumIdByKey[key];
      if (resolvedAlbumId == null || resolvedAlbumId.isEmpty) {
        resolvedAlbumId = await _resolveAlbumIdBySearch(
          artist: full.artist,
          album: full.album,
        );
        if (resolvedAlbumId != null && resolvedAlbumId.isNotEmpty) {
          _albumIdByKey[key] = resolvedAlbumId;
        }
      }
      if (resolvedAlbumId != null && resolvedAlbumId.isNotEmpty) {
        full = Track(
          id: full.id,
          title: full.title,
          artist: full.artist,
          album: full.album,
          durationMs: full.durationMs,
          liked: full.liked,
          inPlaylists: full.inPlaylists,
          albumId: resolvedAlbumId,
          trackNo: full.trackNo,
          discNo: full.discNo,
        );
      }
    }
    if ((full.artist.isEmpty ||
            full.album.isEmpty ||
            resolvedAlbumId == null ||
            resolvedAlbumId.isEmpty) &&
        resolvedAlbumId != null &&
        resolvedAlbumId.isNotEmpty) {
      try {
        final album = await connection.fetchAlbumById(resolvedAlbumId);
        full = _mergeTrackWithAlbum(full, album);
        if (full.artist.isEmpty && album.artistId.isNotEmpty) {
          final artist = await connection.fetchArtistById(album.artistId);
          full = _mergeTrackWithArtist(full, artist);
        }
      } catch (err) {
        _pushMessage('Album/artist lookup failed: $err');
      }
    }

    if (full.albumId == null || full.albumId!.isEmpty) {
      final albumId = resolvedAlbumId;
      if (albumId != null && albumId.isNotEmpty) {
        full = Track(
          id: full.id,
          title: full.title,
          artist: full.artist,
          album: full.album,
          durationMs: full.durationMs,
          liked: full.liked,
          inPlaylists: full.inPlaylists,
          albumId: albumId,
          trackNo: full.trackNo,
          discNo: full.discNo,
        );
      }
    }

    return full;
  }

  bool _needsTrackHydration(Track track) {
    return track.artist.isEmpty ||
        track.album.isEmpty ||
        track.albumId == null ||
        track.albumId!.isEmpty;
  }

  String _albumKey(String artist, String album) {
    return '${artist.trim().toLowerCase()}|${album.trim().toLowerCase()}';
  }

  void _cacheAlbumId({required Album album}) {
    final key = _albumKey(album.artist, album.title);
    if (key == '|') {
      return;
    }
    _albumIdByKey[key] = album.id;
  }

  void _cacheTrackAlbumId(Track track, {String? fallbackAlbumId}) {
    final albumId = track.albumId ?? fallbackAlbumId;
    if (albumId == null || albumId.isEmpty) {
      return;
    }
    final key = _albumKey(track.artist, track.album);
    if (key == '|') {
      return;
    }
    _albumIdByKey[key] = albumId;
  }

  String _normalizeLookup(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
  }

  Future<String?> _resolveAlbumIdBySearch({
    required String artist,
    required String album,
  }) async {
    final normalizedAlbum = _normalizeLookup(album);
    if (normalizedAlbum.isEmpty) {
      return null;
    }
    final normalizedArtist = _normalizeLookup(artist);
    final query = [artist, album].where((part) => part.trim().isNotEmpty).join(' ');
    if (query.isEmpty) {
      return null;
    }
    try {
      final results = await connection.search(query, filter: 'album');
      if (results.isEmpty) {
        return null;
      }
      SearchResult? match;
      for (final result in results) {
        final title = _normalizeLookup(result.title);
        if (title != normalizedAlbum) {
          continue;
        }
        if (normalizedArtist.isEmpty || result.subtitle == null) {
          match = result;
          break;
        }
        final subtitle = _normalizeLookup(result.subtitle ?? '');
        if (subtitle == normalizedArtist || subtitle.contains(normalizedArtist)) {
          match = result;
          break;
        }
      }
      if (match != null) {
        return match.id;
      }
      if (normalizedArtist.isNotEmpty) {
        for (final result in results) {
          final title = _normalizeLookup(result.title);
          if (!title.contains(normalizedAlbum)) {
            continue;
          }
          final subtitle = _normalizeLookup(result.subtitle ?? '');
          if (subtitle.contains(normalizedArtist)) {
            return result.id;
          }
        }
      }
    } catch (err) {
      _pushMessage('Album search fallback failed: $err');
    }
    return null;
  }

  List<Track> _normalizeQueueTracks(List<Track> tracks) {
    return tracks
        .map((track) {
          if (track.albumId != null && track.albumId!.isNotEmpty) {
            return track;
          }
          final key = _albumKey(track.artist, track.album);
          final albumId = _albumIdByKey[key];
          if (albumId == null || albumId.isEmpty) {
            return track;
          }
          return Track(
            id: track.id,
            title: track.title,
            artist: track.artist,
            album: track.album,
            durationMs: track.durationMs,
            liked: track.liked,
            inPlaylists: track.inPlaylists,
            albumId: albumId,
            trackNo: track.trackNo,
            discNo: track.discNo,
          );
        })
        .toList();
  }

  Future<List<Track>> _hydrateQueueStartTrack(
    List<Track> tracks,
    String startTrackId,
  ) async {
    final index = tracks.indexWhere((track) => track.id == startTrackId);
    if (index < 0) {
      return tracks;
    }
    final target = tracks[index];
    final hydrated = await _hydrateTrackForPlayback(target);
    if (hydrated.id != target.id) {
      return tracks;
    }
    final updated = [...tracks];
    updated[index] = hydrated;
    return updated;
  }

  Future<void> _ensureTrackDetails(Track track) async {
    if (track.artist.isNotEmpty &&
        track.album.isNotEmpty &&
        track.albumId != null &&
        track.albumId!.isNotEmpty) {
      return;
    }
    _pushMessage('Track details lookup: id=${track.id}');
    Track full = track;
    try {
      full = await connection.fetchTrackById(track.id);
      _pushMessage(
        'Track details response: id=${full.id} artist="${full.artist}" album="${full.album}" albumId="${full.albumId ?? ''}"',
      );
    } catch (err) {
      _pushMessage('Track details lookup failed: $err');
    }

    if (full.artist.isEmpty || full.album.isEmpty) {
      final albumId = full.albumId ?? track.albumId;
      if (albumId != null && albumId.isNotEmpty) {
        try {
          final album = await connection.fetchAlbumById(albumId);
          _pushMessage(
            'Album details response: id=${album.id} title="${album.title}" artist="${album.artist}" artistId="${album.artistId}"',
          );
          full = _mergeTrackWithAlbum(full, album);
          if (full.artist.isEmpty && album.artistId.isNotEmpty) {
            final artist = await connection.fetchArtistById(album.artistId);
            _pushMessage(
              'Artist details response: id=${artist.id} name="${artist.name}"',
            );
            full = _mergeTrackWithArtist(full, artist);
          }
        } catch (err) {
          _pushMessage('Album/artist lookup failed: $err');
        }
      }
    }

    if (_playbackState.track?.id != track.id) {
      return;
    }
    _playQueue = _playQueue.map((item) => item.id == full.id ? full : item).toList();
    _updatePlayback(track: full);
  }

  Track _mergeTrackWithAlbum(Track track, Album album) {
    final albumTitle = track.album.isNotEmpty ? track.album : album.title;
    final artistName = track.artist.isNotEmpty ? track.artist : album.artist;
    return Track(
      id: track.id,
      title: track.title,
      artist: artistName,
      album: albumTitle,
      durationMs: track.durationMs,
      liked: track.liked,
      inPlaylists: track.inPlaylists,
      albumId: track.albumId ?? album.id,
      trackNo: track.trackNo,
      discNo: track.discNo,
    );
  }

  Track _mergeTrackWithArtist(Track track, Artist artist) {
    final artistName = track.artist.isNotEmpty ? track.artist : artist.name;
    return Track(
      id: track.id,
      title: track.title,
      artist: artistName,
      album: track.album,
      durationMs: track.durationMs,
      liked: track.liked,
      inPlaylists: track.inPlaylists,
      albumId: track.albumId,
      trackNo: track.trackNo,
      discNo: track.discNo,
    );
  }

  void _updatePlayback({
    Track? track,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    double? bufferRatio,
    double? volume,
    ShuffleMode? shuffleMode,
    RepeatMode? repeatMode,
    StreamMode? streamMode,
    double? bitrateKbps,
    bool? streamConnected,
    int? streamRttMs,
  }) {
    _playbackState = _playbackState.copyWith(
      track: track,
      isPlaying: isPlaying,
      position: position,
      duration: duration,
      bufferRatio: bufferRatio,
      volume: volume,
      shuffleMode: shuffleMode,
      repeatMode: repeatMode,
      streamMode: streamMode,
      bitrateKbps: bitrateKbps,
      streamConnected: streamConnected,
      streamRttMs: streamRttMs,
    );
    _playbackController.add(_playbackState);
  }

  void _pushMessage(String message) {
    _messages = [..._messages, message];
    if (_messages.length > 2000) {
      _messages = _messages.sublist(_messages.length - 2000);
    }
    _messageController.add(_messages);
  }

  void clearMessages() {
    _messages = <String>[];
    _messageController.add(_messages);
  }

  void _setArtistsLoading(bool value) {
    if (_artistsLoading == value) {
      return;
    }
    _artistsLoading = value;
    _artistsLoadingController.add(value);
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

  void _setAuthorized(bool authorized, {String? error}) {
    _authState = _authState.copyWith(
      isAuthorized: authorized,
      baseUrl: connection.baseUrl,
      error: error,
    );
    _authController.add(_authState);
  }

  void _handleApiError(ApiException err, {required String context}) {
    if (err.statusCode == 401) {
      _setAuthorized(false, error: 'Unauthorized');
      _pushMessage('Unauthorized. Please log in.');
      return;
    }
    final message = _formatApiError(err);
    _pushMessage('Failed to load $context: $message');
  }

  void _startPlayback(Track track, {Duration startOffset = Duration.zero}) {
    final settings = _streamSettings(_playbackState.streamMode);
    () async {
      try {
        _closeStreamControl();
        _updatePlayback(bitrateKbps: null);
        await _fetchStreamInfo(track, settings);
        _pushMessage('Playback track: id=${track.id} artist="${track.artist}" album="${track.album}" albumId="${track.albumId ?? ''}"');
        debugPrint(
          'Playback track: id=${track.id} artist="${track.artist}" album="${track.album}" albumId="${track.albumId ?? ''}"',
        );
        _pushMessage('Starting playback for ${track.title}');
        _pushMessage('Stream settings: mode=${settings.mode} quality=${settings.quality} frame_ms=${settings.frameMs}');
        _audioEngine.setVolume(_playbackState.volume);
        await _audioEngine.playTrack(
          track: track,
          connection: connection,
          settings: settings,
          startOffset: startOffset,
        );
      } catch (err) {
        _pushMessage('Playback failed: $err');
        _updatePlayback(isPlaying: false);
      }
    }();
  }

  void _closeStreamControl() {
    _streamControlSocket?.close();
    _streamControlSocket = null;
    _streamControlSessionId = null;
    _lastPingAt = null;
    _lastPingSentMs = null;
    _updatePlayback(streamConnected: false, streamRttMs: _lastRttMs);
  }

  Future<void> _openStreamControl(String? sessionId) async {
    if (sessionId == null || sessionId.isEmpty) {
      _closeStreamControl();
      return;
    }
    if (_streamControlSessionId == sessionId) {
      return;
    }
    _closeStreamControl();
    final url = connection.buildStreamControlUrl(sessionId);
    try {
      _pushMessage('Connecting stream control: $url');
      final socket = await WebSocket.connect(
        url,
        headers: _streamControlHeaders(),
      );
      _streamControlSocket = socket;
      _streamControlSessionId = sessionId;
      _updatePlayback(streamConnected: true);
      _pushMessage('Stream control connected');
      socket.listen(
        (message) {
          if (message is String) {
            _handleStreamControlMessage(message);
          }
        },
        onDone: _closeStreamControl,
        onError: (_) => _closeStreamControl(),
      );
    } catch (err) {
      _pushMessage('Stream control connection failed: $err');
      _closeStreamControl();
    }
  }

  Map<String, String> _streamControlHeaders() {
    final token = connection.token;
    if (token == null || token.isEmpty) {
      return const {};
    }
    return {'Authorization': 'Bearer $token'};
  }

  void _sendStreamControlUpdate(Duration position, Duration bufferedAhead) {
    final socket = _streamControlSocket;
    if (socket == null) {
      return;
    }
    _maybeSendPing();
    final payload = <String, dynamic>{
      'position_ms': position.inMilliseconds,
      'buffer_ms': bufferedAhead.inMilliseconds,
      'paused': !_playbackState.isPlaying,
    };
    socket.add(jsonEncode(payload));
  }

  void _maybeSendPing() {
    final now = DateTime.now();
    final last = _lastPingAt;
    if (last != null && now.difference(last) < const Duration(seconds: 5)) {
      return;
    }
    _lastPingAt = now;
    _lastPingSentMs = now.millisecondsSinceEpoch;
    final payload = <String, dynamic>{
      'type': 'ping',
      'ts': _lastPingSentMs,
    };
    _pushMessage('Stream control ping: ${_lastPingSentMs}');
    _streamControlSocket?.add(jsonEncode(payload));
  }

  void _handleStreamControlMessage(String message) {
    _pushMessage('Stream control message: $message');
    try {
      final decoded = jsonDecode(message);
      if (decoded is Map && decoded['type'] == 'pong') {
        final ts = decoded['ts'];
        if (ts is int) {
          final now = DateTime.now().millisecondsSinceEpoch;
          final rtt = now - ts;
          _lastRttMs = rtt;
          _updatePlayback(streamRttMs: rtt);
          _pushMessage('Stream RTT: ${rtt}ms');
        }
      }
    } catch (_) {
      // Ignore malformed messages.
    }
  }

  Future<void> _fetchStreamInfo(Track track, StreamSettings settings) async {
    try {
      final response = await connection.fetchStreamInfo(
        trackId: track.id,
        mode: settings.mode,
        quality: settings.quality,
        frameMs: settings.frameMs,
      );
      _updatePlayback(bitrateKbps: response.bitrateKbps?.toDouble());
    } catch (err) {
      _pushMessage('Stream info lookup failed: $err');
    }
  }

  StreamSettings _streamSettings(StreamMode mode) {
    switch (mode) {
      case StreamMode.auto:
        return const StreamSettings(mode: 'auto', quality: 'high', frameMs: 60);
      case StreamMode.high:
        return const StreamSettings(mode: 'fixed', quality: 'high', frameMs: 60);
      case StreamMode.medium:
        return const StreamSettings(mode: 'fixed', quality: 'medium', frameMs: 60);
      case StreamMode.low:
        return const StreamSettings(mode: 'fixed', quality: 'low', frameMs: 60);
    }
  }

  String _extractErrorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] != null) {
        return decoded['error'].toString();
      }
    } catch (_) {
      // Ignore parse errors and fall back to raw body.
    }
    return body;
  }

  String _formatApiError(ApiException err) {
    final detail = _extractErrorMessage(err.body).trim();
    if (detail.isEmpty) {
      return 'HTTP ${err.statusCode}';
    }
    return 'HTTP ${err.statusCode}: $detail';
  }

  String _shuffleQueryMode(ShuffleMode mode) {
    switch (mode) {
      case ShuffleMode.off:
        return 'off';
      case ShuffleMode.all:
        return 'all';
      case ShuffleMode.artist:
        return 'artist';
      case ShuffleMode.album:
        return 'album';
      case ShuffleMode.custom:
        return 'custom';
    }
  }

  List<Track> _shuffleTracks(List<Track> tracks) {
    final shuffled = List<Track>.from(tracks);
    shuffled.shuffle(_shuffleRandom);
    return shuffled;
  }

  void _handleTrackFinished() {
    if (_autoAdvanceInFlight) {
      return;
    }
    _autoAdvanceInFlight = true;
    if (_playbackState.repeatMode == RepeatMode.one) {
      final track = _playbackState.track;
      if (track == null) {
        _updatePlayback(isPlaying: false, position: Duration.zero, bufferRatio: 0.0);
        _autoAdvanceInFlight = false;
        return;
      }
      () async {
        if (_playQueue.isEmpty) {
          _updatePlayback(
            track: track,
            isPlaying: true,
            position: Duration.zero,
            duration: Duration(milliseconds: track.durationMs),
            bufferRatio: 0.0,
          );
          _startPlayback(track);
          _autoAdvanceInFlight = false;
          return;
        }
        await _playCurrent();
      }();
      return;
    }
    if (_playQueue.isEmpty) {
      if (_playbackState.shuffleMode != ShuffleMode.off) {
        () async {
          final ensured = await _ensureShuffleQueue(play: true);
          if (!ensured) {
            _updatePlayback(isPlaying: false, position: Duration.zero, bufferRatio: 0.0);
          }
          _autoAdvanceInFlight = false;
        }();
        return;
      }
      _updatePlayback(isPlaying: false, position: Duration.zero, bufferRatio: 0.0);
      _autoAdvanceInFlight = false;
      return;
    }
    nextTrack();
  }

  void _maybeAutoAdvance(Duration position, Duration bufferedAhead) {
    // Disable position-based auto-advance; rely on audio engine completion.
    return;
  }

  RepeatMode _parseRepeatMode(String? value) {
    switch (value?.toLowerCase().trim()) {
      case 'one':
        return RepeatMode.one;
      default:
        return RepeatMode.off;
    }
  }

  Future<void> _loadPlaybackSettings() async {
    try {
      final settings = await connection.fetchPlaybackSettings();
      _updatePlayback(repeatMode: _parseRepeatMode(settings.repeatMode));
    } catch (err) {
      _pushMessage('Failed to load playback settings: $err');
    }
  }

  Future<void> _persistPlaybackSettings(RepeatMode mode) async {
    try {
      await connection.updatePlaybackSettings(
        repeatMode: mode == RepeatMode.one ? 'one' : 'off',
      );
    } catch (err) {
      _pushMessage('Failed to update playback settings: $err');
    }
  }
}
