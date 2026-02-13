import 'dart:async';

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'app_log.dart';
import 'auth_state.dart';
import 'auth_storage.dart';
import 'models.dart';
import 'server_connection.dart';
import 'audio_engine.dart';

enum ShuffleMode { off, all, artist, album, custom }

enum RepeatMode { off, one }

enum StreamMode { auto, high, medium, low }

enum LocalNetworkPermissionState { unknown, granted, denied }

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
    _logListener = _addLogEntry;
    AppLogger.instance.attach(_logListener, includeHistory: true);
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
      onStats: (position, bufferedAhead, bitrateKbps, rttMs) {
        final duration = _playbackState.duration;
        final clamped = duration == Duration.zero
            ? position
            : position > duration
                ? duration
                : position;
        _actualPositionMs = clamped.inMilliseconds;
        _updateDisplayPosition(_actualPositionMs, bufferedAhead.inMilliseconds);
        final bufferedTotal = clamped + bufferedAhead;
        final bufferRatio = duration == Duration.zero
            ? 0.0
            : (bufferedTotal.inMilliseconds / duration.inMilliseconds)
                .clamp(0.0, 1.0);
        _maybeClearSeekHold(clamped, bufferedAhead);
        final nextRtt = rttMs ?? _playbackState.streamRttMs;
        _updatePlayback(
          position: Duration(milliseconds: _displayPositionMs),
          bufferRatio: bufferRatio,
          bitrateKbps: bitrateKbps,
          streamConnected: true,
          streamRttMs: nextRtt,
        );
        _maybeAutoAdvance(clamped, bufferedAhead);
      },
      onStreamInfo: null,
      onComplete: _handleTrackFinished,
      onStarted: () {
        if (_resumeAfterSeek) {
          _resumeAfterSeek = false;
          _pushMessage('Seek: stream ready; resuming playback.');
          if (_playbackState.isPlaying) {
            _audioEngine.resume();
          }
        }
        _clearInlineSeekWatchdog();
        if (!_audioOutputStarted) {
          _audioOutputStarted = true;
          _pushNowPlayingUpdate(force: true);
        }
      },
    );
    _configureLocalNetworkPermissions();
    _configureNowPlaying();
    _startHealthMonitor();
  }

  final ServerConnection connection;
  late final AudioEngine _audioEngine;
  final MethodChannel _nowPlayingChannel =
      const MethodChannel('phonolite/now_playing');
  final MethodChannel _permissionsChannel =
      const MethodChannel('phonolite/permissions');
  final AuthStorage _authStorage = const AuthStorage();
  late final LogListener _logListener;
  AuthCredentials? _savedCredentials;
  bool _restoringSession = false;
  LocalNetworkPermissionState _localNetworkPermissionState =
      LocalNetworkPermissionState.unknown;
  DateTime? _lastNowPlayingSentAt;
  String? _lastNowPlayingTrackId;
  bool? _lastNowPlayingIsPlaying;
  int _lastNowPlayingPositionMs = -1;
  int _lastNowPlayingEpochSent = -1;
  bool _nowPlayingReady = false;
  DateTime? _lastSeekAt;
  int? _lastSeekMs;
  String? _lastSeekTrackId;
  bool _seeking = false;
  int _seekTargetMs = 0;
  bool _isScrubbing = false;
  bool _scrubWasPlaying = false;
  bool _scrubPaused = false;
  bool _resumeAfterSeek = false;
  int _seekEpoch = 0;
  int? _inlineSeekEpoch;
  Timer? _inlineSeekWatchdog;
  Timer? _seekDebounceTimer;
  int? _pendingSeekCommitMs;
  String? _pendingSeekCommitTrackId;
  static const Duration _seekDebounceDelay = Duration(milliseconds: 180);
  bool _audioOutputStarted = false;
  int _displayPositionMs = 0;
  int _actualPositionMs = 0;
  int _nowPlayingEpoch = 0;
  Uint8List? _nowPlayingArtworkBytes;
  String? _nowPlayingArtworkUrl;
  String? _nowPlayingArtworkToken;
  bool _nowPlayingArtworkFetchInFlight = false;
  DateTime? _lastStartPlaybackAt;
  String? _lastStartPlaybackTrackId;
  int? _lastStartPlaybackOffsetMs;
  Timer? _healthTimer;
  bool _healthPingInFlight = false;
  int? _quicPort;

  final _artistsController = StreamController<List<Artist>>.broadcast();
  final _albumsController = StreamController<List<Album>>.broadcast();
  final _tracksController = StreamController<List<Track>>.broadcast();
  final _playlistsController = StreamController<List<Playlist>>.broadcast();
  final _playlistTracksController = StreamController<List<Track>>.broadcast();
  final _likedController = StreamController<List<Track>>.broadcast();
  final _statsController = StreamController<StatsResponse?>.broadcast();
  final _searchController = StreamController<List<SearchResult>>.broadcast();
  final _messageController = StreamController<List<LogEntry>>.broadcast();
  final _playbackController = StreamController<PlaybackState>.broadcast();
  final _authController = StreamController<AuthState>.broadcast();
  final _localNetworkPermissionController =
      StreamController<LocalNetworkPermissionState>.broadcast();
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
  List<LogEntry> _messages = <LogEntry>[];
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
  DateTime? _ignoreCompleteUntil;
  ShuffleMode _queueShuffleMode = ShuffleMode.off;
  String? _queueShuffleScope;
  String? _queueShufflePlaylistId;
  String? _queueShuffleArtistId;
  String? _queueShuffleAlbumId;
  String? _lastArtistId;
  String? _lastAlbumId;
  String? _currentPlaylistId;
  final Map<String, String> _albumIdByKey = <String, String>{};

  Stream<List<Artist>> get artistsStream => _artistsController.stream;
  Stream<List<Album>> get albumsStream => _albumsController.stream;
  Stream<List<Track>> get tracksStream => _tracksController.stream;
  Stream<List<Playlist>> get playlistsStream => _playlistsController.stream;
  Stream<List<Track>> get playlistTracksStream => _playlistTracksController.stream;
  Stream<List<Track>> get likedStream => _likedController.stream;
  Stream<StatsResponse?> get statsStream => _statsController.stream;
  Stream<List<SearchResult>> get searchStream => _searchController.stream;
  Stream<List<LogEntry>> get messageStream => _messageController.stream;
  Stream<PlaybackState> get playbackStream => _playbackController.stream;
  Stream<AuthState> get authStream => _authController.stream;
  Stream<LocalNetworkPermissionState> get localNetworkPermissionStream =>
      _localNetworkPermissionController.stream;
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
  List<LogEntry> get messages => _messages;
  StatsResponse? get stats => _stats;
  PlaybackState get playbackState => _playbackState;
  AuthState get authState => _authState;
  LocalNetworkPermissionState get localNetworkPermissionState =>
      _localNetworkPermissionState;
  bool get localNetworkPermissionSupported {
    if (kIsWeb) {
      return false;
    }
    if (Platform.isIOS) {
      return true;
    }
    return defaultTargetPlatform == TargetPlatform.iOS;
  }

  Future<void> openAppSettings() async {
    if (!localNetworkPermissionSupported) {
      return;
    }
    try {
      await _permissionsChannel.invokeMethod('openAppSettings');
    } catch (_) {}
  }

  Future<void> refreshLocalNetworkPermission() async {
    if (!localNetworkPermissionSupported) {
      return;
    }
    await _refreshLocalNetworkPermission();
  }

  bool get artistsLoading => _artistsLoading;
  bool get albumsLoading => _albumsLoading;
  bool get tracksLoading => _tracksLoading;
  bool get searchLoading => _searchLoading;
  List<OutputDevice> get outputDevices => _outputDevices;
  int get outputDeviceId => _outputDeviceId;
  String? get outputDeviceName => _outputDeviceName;
  bool get hasSavedCredentials => _savedCredentials != null;
  String? get savedUsername => _savedCredentials?.username;
  String? get savedBaseUrl => _savedCredentials?.baseUrl;

  void dispose() {
    _clearNowPlaying();
    _healthTimer?.cancel();
    _healthTimer = null;
    _isScrubbing = false;
    _scrubWasPlaying = false;
    _scrubPaused = false;
    _resumeAfterSeek = false;
    _clearInlineSeekWatchdog();
    _seekDebounceTimer?.cancel();
    _seekDebounceTimer = null;
    _pendingSeekCommitMs = null;
    _pendingSeekCommitTrackId = null;
    AppLogger.instance.detach(_logListener);
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
    _localNetworkPermissionController.close();
    _artistsLoadingController.close();
    _albumsLoadingController.close();
    _tracksLoadingController.close();
    _searchLoadingController.close();
    _audioEngine.dispose();
    _closeStreamControl();
  }

  void handleAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _audioEngine.stop();
      _closeStreamControl();
    }
  }

  Future<void> loginWithPassword({
    required String baseUrl,
    required String username,
    required String password,
    bool rememberMe = false,
  }) async {
    try {
      connection.setBaseUrl(baseUrl);
      await _refreshServerPorts();
      final token = await connection.login(username: username, password: password);
      _setAuthorized(true, error: null);
      await _loadPlaybackSettings();
      if (rememberMe) {
        final credentials = AuthCredentials(
          baseUrl: connection.baseUrl,
          token: token,
          username: username,
        );
        await _authStorage.write(credentials);
        _savedCredentials = credentials;
      } else {
        await _authStorage.clear();
        _savedCredentials = null;
      }
    } on ApiException catch (err) {
      final message = '${_formatApiError(err)} (POST ${connection.baseUrl}/auth/login)';
      _setAuthorized(false, error: message);
      _pushMessage('Login failed: $message', level: LogLevel.error);
    } catch (err) {
      _setAuthorized(false, error: err.toString());
      _pushMessage('Login failed: $err', level: LogLevel.error);
    }
  }

  void loginWithToken({required String baseUrl, required String token}) {
    connection.setBaseUrl(baseUrl);
    connection.setToken(token);
    _setAuthorized(true, error: null);
    () async {
      await _refreshServerPorts();
      await _loadPlaybackSettings();
    }();
  }

  Future<bool> probeServer(String input) async {
    try {
      final resolved = await connection.resolveBaseUrl(input);
      connection.setBaseUrl(resolved);
      await _refreshServerPorts();
      _setAuthorized(false, error: null);
      return true;
    } catch (err) {
      final message = err.toString();
      _setAuthorized(false, error: message);
      _pushMessage('Server connection failed: $message', level: LogLevel.warning);
      return false;
    }
  }

  Future<void> logout({bool clearSaved = true}) async {
    connection.setToken(null);
    _setAuthorized(false, error: null);
    _audioEngine.stop();
    _playQueue = <Track>[];
    _playIndex = 0;
    _autoAdvanceInFlight = false;
    _quicPort = null;
    _clearNowPlaying();
    if (clearSaved) {
      await _authStorage.clear();
      _savedCredentials = null;
    }
  }

  Future<AuthCredentials?> loadSavedCredentials() async {
    if (_savedCredentials != null) {
      return _savedCredentials;
    }
    final credentials = await _authStorage.read();
    _savedCredentials = credentials;
    return credentials;
  }

  Future<void> restoreSession() async {
    if (_restoringSession || _authState.isAuthorized) {
      return;
    }
    _restoringSession = true;
    try {
      final credentials = await loadSavedCredentials();
      if (credentials == null) {
        return;
      }
      connection.setBaseUrl(credentials.baseUrl);
      if (credentials.token.trim().isEmpty) {
        await logout(clearSaved: true);
        return;
      }
      connection.setToken(credentials.token);
      await _refreshServerPorts();
      try {
        final settings = await connection.fetchPlaybackSettings();
        _updatePlayback(repeatMode: _parseRepeatMode(settings.repeatMode));
        _setAuthorized(true, error: null);
      } on ApiException catch (err) {
        _pushMessage('Auto-login failed: ${_formatApiError(err)}');
        await logout(clearSaved: true);
      } catch (err) {
        _pushMessage('Auto-login failed: $err');
        await logout(clearSaved: true);
      }
    } finally {
      _restoringSession = false;
    }
  }

  void _configureLocalNetworkPermissions() {
    if (!Platform.isIOS) {
      return;
    }
    _permissionsChannel.setMethodCallHandler((call) async {
      if (call.method != 'localNetworkPermission') {
        return;
      }
      final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
      final status = args['status']?.toString().toLowerCase().trim() ?? '';
      switch (status) {
        case 'granted':
          _setLocalNetworkPermission(LocalNetworkPermissionState.granted);
          break;
        case 'denied':
          _setLocalNetworkPermission(LocalNetworkPermissionState.denied);
          break;
        case 'unknown':
          _setLocalNetworkPermission(LocalNetworkPermissionState.unknown);
          break;
        default:
          break;
      }
    });
    _refreshLocalNetworkPermission();
  }

  Future<void> _refreshLocalNetworkPermission() async {
    try {
      await _permissionsChannel.invokeMethod('refreshLocalNetworkPermission');
      final result =
          await _permissionsChannel.invokeMethod('getLocalNetworkPermission');
      final status = result?.toString().toLowerCase().trim() ?? '';
      switch (status) {
        case 'granted':
          _setLocalNetworkPermission(LocalNetworkPermissionState.granted);
          break;
        case 'denied':
          _setLocalNetworkPermission(LocalNetworkPermissionState.denied);
          break;
        case 'unknown':
          _setLocalNetworkPermission(LocalNetworkPermissionState.unknown);
          break;
        default:
          break;
      }
    } catch (_) {}
  }

  void _setLocalNetworkPermission(LocalNetworkPermissionState value) {
    if (_localNetworkPermissionState == value) {
      return;
    }
    _localNetworkPermissionState = value;
    _localNetworkPermissionController.add(value);
  }

  void _configureNowPlaying() {
    if (!Platform.isIOS) {
      return;
    }
    _nowPlayingReady = true;
    _nowPlayingChannel.setMethodCallHandler((call) async {
      if (call.method != 'remoteCommand') {
        return;
      }
      final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
      final type = args['type']?.toString() ?? '';
      switch (type) {
        case 'play':
          await pause(false);
          break;
        case 'pause':
          await pause(true);
          break;
        case 'next':
          await nextTrack();
          break;
        case 'prev':
          await prevTrack();
          break;
        case 'seek':
          final raw = args['position'];
          final seconds = raw is num ? raw.toDouble() : double.tryParse('$raw');
          if (seconds != null) {
            final ms = (seconds * 1000).round();
            await seekTo(Duration(milliseconds: ms));
          }
          break;
        default:
          break;
      }
    });
    _pushNowPlayingUpdate(force: true);
  }

  Future<void> _clearNowPlaying() async {
    if (!Platform.isIOS) {
      return;
    }
    try {
      await _nowPlayingChannel.invokeMethod('clearNowPlaying');
    } catch (_) {}
  }

  Future<void> _pushNowPlayingUpdate({bool force = false}) async {
    if (!Platform.isIOS || !_nowPlayingReady) {
      return;
    }
    final track = _playbackState.track;
    if (track == null) {
      await _clearNowPlaying();
      return;
    }
    final now = DateTime.now();
    var positionMs = _playbackState.position.inMilliseconds;
    final isPlaying = _playbackState.isPlaying;
    if (_seeking && _lastSeekTrackId != null && _lastSeekTrackId != track.id) {
      _seeking = false;
      _lastSeekAt = null;
      _lastSeekMs = null;
      _lastSeekTrackId = null;
    }
    final nowPlayingIsPlaying = isPlaying;
    final lastSentAt = _lastNowPlayingSentAt;
    if (!force &&
        track.id == _lastNowPlayingTrackId &&
        nowPlayingIsPlaying == _lastNowPlayingIsPlaying &&
        _nowPlayingEpoch == _lastNowPlayingEpochSent &&
        lastSentAt != null &&
        now.difference(lastSentAt) < const Duration(seconds: 1) &&
        (positionMs - _lastNowPlayingPositionMs).abs() < 900) {
      return;
    }

    final durationMs = _playbackState.duration.inMilliseconds;
    if (durationMs > 0 && positionMs > durationMs) {
      positionMs = durationMs;
    }

    final albumId = track.albumId ?? '';
    final artworkUrl =
        albumId.isNotEmpty ? connection.buildAlbumCoverUrl(albumId) : null;
    final token = connection.token ?? '';
    _maybeFetchNowPlayingArtwork(artworkUrl, token);

    final payload = <String, dynamic>{
      'epoch': _nowPlayingEpoch,
      'trackId': track.id,
      'title': track.title,
      'artist': track.artist,
      'album': track.album,
      'duration': durationMs / 1000.0,
      'position': positionMs / 1000.0,
      'isPlaying': nowPlayingIsPlaying,
      'artworkUrl': artworkUrl ?? '',
      'token': token,
    };
    if (_nowPlayingArtworkBytes != null) {
      payload['artworkBytes'] = _nowPlayingArtworkBytes;
    }
    try {
      await _nowPlayingChannel.invokeMethod('setNowPlaying', payload);
      _lastNowPlayingSentAt = now;
      _lastNowPlayingTrackId = track.id;
      _lastNowPlayingIsPlaying = nowPlayingIsPlaying;
      _lastNowPlayingPositionMs = positionMs;
      _lastNowPlayingEpochSent = _nowPlayingEpoch;
    } catch (_) {}
  }

  void _maybeFetchNowPlayingArtwork(String? artworkUrl, String token) {
    if (!Platform.isIOS) {
      return;
    }
    if (artworkUrl == null || artworkUrl.isEmpty) {
      _nowPlayingArtworkBytes = null;
      _nowPlayingArtworkUrl = null;
      _nowPlayingArtworkToken = null;
      return;
    }
    final sameSource =
        artworkUrl == _nowPlayingArtworkUrl && token == _nowPlayingArtworkToken;
    if (sameSource && _nowPlayingArtworkBytes != null) {
      return;
    }
    if (_nowPlayingArtworkFetchInFlight && sameSource) {
      return;
    }
    _nowPlayingArtworkBytes = null;
    _nowPlayingArtworkUrl = artworkUrl;
    _nowPlayingArtworkToken = token;
    _nowPlayingArtworkFetchInFlight = true;
    _fetchNowPlayingArtwork(artworkUrl, token);
  }

  Future<void> _fetchNowPlayingArtwork(String artworkUrl, String token) async {
    try {
      final uri = Uri.parse(artworkUrl);
      final headers = <String, String>{};
      if (token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
      final response = await http.get(uri, headers: headers);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return;
      }
      final decoded = await _decodeArtworkToPng(response.bodyBytes);
      if (decoded == null) {
        return;
      }
      if (artworkUrl != _nowPlayingArtworkUrl ||
          token != _nowPlayingArtworkToken) {
        return;
      }
      _nowPlayingArtworkBytes = decoded;
      await _pushNowPlayingUpdate(force: true);
    } catch (_) {
      // Ignore artwork failures to avoid disrupting playback.
    } finally {
      _nowPlayingArtworkFetchInFlight = false;
    }
  }

  Future<Uint8List?> _decodeArtworkToPng(Uint8List bytes) async {
    if (bytes.isEmpty) {
      return null;
    }
    try {
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 1024,
        targetHeight: 1024,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<void> loadArtists() async {
    _setArtistsLoading(true);
    try {
      _artists = await connection.fetchArtists();
      _artistsController.add(_artists);
    } on ApiException catch (err) {
      _handleApiError(err, context: 'artists');
    } catch (err) {
      _pushMessage('Failed to load artists: $err', level: LogLevel.warning);
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
      _pushMessage('Failed to load albums: $err', level: LogLevel.warning);
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
      _pushMessage('Failed to load tracks: $err', level: LogLevel.warning);
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
      _pushMessage('Failed to load playlists: $err', level: LogLevel.warning);
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
      _pushMessage('Failed to load playlist tracks: $err', level: LogLevel.warning);
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
      _pushMessage('Failed to load liked tracks: $err', level: LogLevel.warning);
    }
  }

  Future<void> playLikedTrack(String trackId) async {
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
      _pushMessage('Failed to load stats: $err', level: LogLevel.warning);
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
      _armAutoAdvanceGuard();
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
      final tracks = (_currentPlaylistId == playlistId && _playlistTracks.isNotEmpty)
          ? _playlistTracks
          : await connection.fetchPlaylistTracks(playlistId);
      if (tracks.isEmpty) {
        _pushMessage('No tracks found for playlist');
        return;
      }
      var normalized = _normalizeQueueTracks(tracks);
      if (startTrackId != null) {
        normalized = await _hydrateQueueStartTrack(normalized, startTrackId);
      }
      _setQueue(normalized, startTrackId: startTrackId);
      _armAutoAdvanceGuard();
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
      final tracks = _liked.isNotEmpty ? _liked : await connection.fetchLikedTracks();
      if (tracks.isEmpty) {
        _pushMessage('No liked tracks found');
        return;
      }
      var normalized = _normalizeQueueTracks(tracks);
      if (startTrackId != null) {
        normalized = await _hydrateQueueStartTrack(normalized, startTrackId);
      }
      _setQueue(normalized, startTrackId: startTrackId);
      _armAutoAdvanceGuard();
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
        _armAutoAdvanceGuard();
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
        _armAutoAdvanceGuard();
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
      _armAutoAdvanceGuard();
      if (play) {
        await _playCurrent();
      }
    } on ApiException catch (err) {
      _handleApiError(err, context: 'queue shuffle');
    } catch (err) {
      _pushMessage('Failed to queue shuffle: $err');
    }
  }

  Future<void> nextTrack({bool fromAutoAdvance = false}) async {
    try {
      if (!fromAutoAdvance) {
        _armAutoAdvanceGuard();
      }
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
      _syncPlayIndexWithCurrent();
      _playIndex = (_playIndex + 1) % _playQueue.length;
      await _playCurrent();
    } on ApiException catch (err) {
      _handleApiError(err, context: 'next track');
    } catch (err) {
      _pushMessage('Failed to move to next track: $err');
    } finally {
      if (fromAutoAdvance) {
        _autoAdvanceInFlight = false;
      }
    }
  }

  Future<void> prevTrack({bool fromAutoAdvance = false}) async {
    try {
      if (!fromAutoAdvance) {
        _armAutoAdvanceGuard();
      }
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
      _syncPlayIndexWithCurrent();
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
      _displayPositionMs = 0;
      _updatePlayback(isPlaying: false, position: Duration.zero, bufferRatio: 0.0);
      _audioEngine.stop();
      _audioOutputStarted = false;
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
      await _pushNowPlayingUpdate(force: true);
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

  void previewSeek(Duration position) {
    final track = _playbackState.track;
    if (track == null) {
      return;
    }
    final duration = _playbackState.duration;
    final clamped = duration == Duration.zero
        ? position
        : position > duration
            ? duration
            : position < Duration.zero
                ? Duration.zero
                : position;
    _beginScrub();
    _seeking = true;
    _seekTargetMs = clamped.inMilliseconds;
    _displayPositionMs = clamped.inMilliseconds;
    _updatePlayback(
      position: clamped,
      isPlaying: _playbackState.isPlaying,
      bufferRatio: 0.0,
      nowPlaying: false,
    );
  }

  Future<void> seekTo(Duration position) async {
    final track = _playbackState.track;
    if (track == null) {
      return;
    }
    final wasPlaying = _playbackState.isPlaying;
    _armAutoAdvanceGuard();
    _suppressAutoAdvanceUntil = DateTime.now().add(const Duration(seconds: 2));
    final duration = _playbackState.duration;
    final clamped = duration == Duration.zero
        ? position
        : position > duration
            ? duration
            : position < Duration.zero
                ? Duration.zero
                : position;
    final now = DateTime.now();
    _lastSeekAt = now;
    _lastSeekMs = clamped.inMilliseconds;
    _lastSeekTrackId = track.id;
    _seeking = true;
    _seekTargetMs = clamped.inMilliseconds;
    _audioOutputStarted = false;
    _bumpNowPlayingEpoch();
    _displayPositionMs = clamped.inMilliseconds;
    _updatePlayback(position: clamped, isPlaying: wasPlaying, bufferRatio: 0.0);
    _scheduleSeekCommit(clamped);
    await _pushNowPlayingUpdate(force: true);
  }

  void _scheduleSeekCommit(Duration target) {
    _pendingSeekCommitMs = target.inMilliseconds;
    _pendingSeekCommitTrackId = _playbackState.track?.id;
    _seekDebounceTimer?.cancel();
    _seekDebounceTimer = Timer(_seekDebounceDelay, () async {
      final track = _playbackState.track;
      final pendingTrackId = _pendingSeekCommitTrackId;
      final pendingMs = _pendingSeekCommitMs;
      if (track == null || pendingTrackId == null || pendingMs == null) {
        _finishScrub();
        return;
      }
      if (track.id != pendingTrackId) {
        _finishScrub();
        return;
      }
      _pendingSeekCommitMs = null;
      _pendingSeekCommitTrackId = null;
      await _commitSeek(Duration(milliseconds: pendingMs));
    });
  }

  Future<void> _commitSeek(Duration target) async {
    final track = _playbackState.track;
    if (track == null) {
      return;
    }
    final wasPlaying = _playbackState.isPlaying;
    _resumeAfterSeek = _scrubPaused && _scrubWasPlaying && wasPlaying;
    _seekEpoch = (_seekEpoch + 1) % 1000000;
    final epoch = _seekEpoch;
    bool inlineSeek = false;
    try {
      inlineSeek = await _audioEngine.seekTo(target);
    } catch (_) {
      inlineSeek = false;
    }
    if (inlineSeek) {
      _pushMessage(
        'Seek commit: inline seek to ${target.inMilliseconds}ms '
        '(resume=${_resumeAfterSeek ? 'yes' : 'no'})',
      );
      _armInlineSeekWatchdog(
        track: track,
        target: target,
        wasPlaying: wasPlaying,
        epoch: epoch,
      );
    } else {
      _restartPlaybackForSeek(
        track: track,
        target: target,
        wasPlaying: wasPlaying,
        reason: 'inline unavailable',
      );
    }
    _finishScrub();
  }

  void _beginScrub() {
    if (_isScrubbing) {
      return;
    }
    _isScrubbing = true;
    _resumeAfterSeek = false;
    _scrubWasPlaying = _playbackState.isPlaying && !_audioEngine.isPaused;
    _scrubPaused = false;
    if (_scrubWasPlaying) {
      _scrubPaused = true;
      _audioEngine.pause();
    }
  }

  void _finishScrub() {
    _isScrubbing = false;
    _scrubPaused = false;
    _scrubWasPlaying = false;
  }

  void _armInlineSeekWatchdog({
    required Track track,
    required Duration target,
    required bool wasPlaying,
    required int epoch,
  }) {
    _inlineSeekWatchdog?.cancel();
    _inlineSeekEpoch = epoch;
    _inlineSeekWatchdog = Timer(const Duration(milliseconds: 1800), () {
      if (_inlineSeekEpoch != epoch) {
        return;
      }
      _inlineSeekEpoch = null;
      _inlineSeekWatchdog = null;
      _restartPlaybackForSeek(
        track: track,
        target: target,
        wasPlaying: wasPlaying,
        reason: 'inline stalled',
      );
    });
  }

  void _clearInlineSeekWatchdog() {
    _inlineSeekWatchdog?.cancel();
    _inlineSeekWatchdog = null;
    _inlineSeekEpoch = null;
  }

  void _restartPlaybackForSeek({
    required Track track,
    required Duration target,
    required bool wasPlaying,
    required String reason,
  }) {
    _clearInlineSeekWatchdog();
    _pushMessage(
      'Seek commit: restarting stream at ${target.inMilliseconds}ms '
      '(reason=$reason, resume=${_resumeAfterSeek ? 'yes' : 'no'})',
    );
    _startPlayback(track, startOffset: target);
    if (!wasPlaying) {
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        _audioEngine.pause();
        _updatePlayback(isPlaying: false);
      });
    }
  }

  void _maybeClearSeekHold(Duration position, Duration bufferedAhead) {
    if (!_seeking) {
      return;
    }
    final positionMs = position.inMilliseconds;
    final targetMs = _seekTargetMs;
    final reached = positionMs >= targetMs - 400;
    if (reached) {
      _seeking = false;
      _lastSeekAt = null;
      _lastSeekMs = null;
      _lastSeekTrackId = null;
      _pushNowPlayingUpdate(force: true);
    }
  }

  void _updateDisplayPosition(int actualMs, int bufferedMs) {
    final durationMs = _playbackState.duration.inMilliseconds;
    if (_isScrubbing) {
      _displayPositionMs = _seekTargetMs;
    } else if (_seeking &&
        (!_audioOutputStarted ||
            _audioEngine.isPaused ||
            !_playbackState.isPlaying)) {
      _displayPositionMs = _seekTargetMs;
    } else if (!_playbackState.isPlaying ||
        _audioEngine.isPaused ||
        !_audioOutputStarted) {
      // Hold the displayed position while paused/buffering.
    } else {
      _displayPositionMs = actualMs;
    }
    if (durationMs > 0 && _displayPositionMs > durationMs) {
      _displayPositionMs = durationMs;
    }
    if (_displayPositionMs < 0) {
      _displayPositionMs = 0;
    }
  }

  void _bumpNowPlayingEpoch() {
    _nowPlayingEpoch = (_nowPlayingEpoch + 1) % 1000000;
    if (_nowPlayingEpoch < 0) {
      _nowPlayingEpoch = 0;
    }
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

  void _armAutoAdvanceGuard([Duration duration = const Duration(milliseconds: 1200)]) {
    _ignoreCompleteUntil = DateTime.now().add(duration);
  }

  void _syncPlayIndexWithCurrent() {
    if (_playQueue.isEmpty) {
      return;
    }
    final currentId = _playbackState.track?.id;
    if (currentId == null || currentId.isEmpty) {
      return;
    }
    final idx = _playQueue.indexWhere((track) => track.id == currentId);
    if (idx >= 0 && idx != _playIndex) {
      _playIndex = idx;
    }
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
    _bumpNowPlayingEpoch();
    _displayPositionMs = 0;
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
    bool nowPlaying = true,
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
    if (nowPlaying) {
      _pushNowPlayingUpdate();
    }
  }

  void _pushMessage(String message, {LogLevel level = LogLevel.info}) {
    AppLogger.instance.log(LogEntry(message: message, level: level));
  }

  void _addLogEntry(LogEntry entry) {
    _messages = [..._messages, entry];
    if (_messages.length > 3000) {
      final trim = _messages.length >= 500 ? 500 : _messages.length;
      _messages = _messages.sublist(trim);
    }
    _messageController.add(_messages);
  }

  void clearMessages() {
    _messages = <LogEntry>[];
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
    _pushMessage('Failed to load $context: $message', level: LogLevel.warning);
  }

  void _startPlayback(Track track, {Duration startOffset = Duration.zero}) {
    final settings = _streamSettings(_playbackState.streamMode);
    final queueIds = _buildQueueIds(track.id, 3);
    final now = DateTime.now();
    final offsetMs = startOffset.inMilliseconds;
    if (_audioEngine.hasActivePlayer &&
        _lastStartPlaybackTrackId == track.id &&
        _lastStartPlaybackOffsetMs == offsetMs &&
        _lastStartPlaybackAt != null &&
        now.difference(_lastStartPlaybackAt!) <
            const Duration(milliseconds: 800)) {
      _pushMessage('Playback already active; skipping duplicate start for ${track.title}.');
      return;
    }
    _lastStartPlaybackAt = now;
    _lastStartPlaybackTrackId = track.id;
    _lastStartPlaybackOffsetMs = offsetMs;
    () async {
      try {
        _logPlaybackContext();
        _updatePlayback(bitrateKbps: null);
        _audioOutputStarted = false;
        _pushMessage(
          'Playback track: id=${track.id} artist="${track.artist}" album="${track.album}" albumId="${track.albumId ?? ''}"',
          level: LogLevel.status,
        );
        _pushMessage('Starting playback for ${track.title}');
        _pushMessage('Stream settings: mode=${settings.mode} quality=${settings.quality} frame_ms=${settings.frameMs}');
        _audioEngine.setVolume(_playbackState.volume);
        await _audioEngine.playTrack(
          track: track,
          connection: connection,
          settings: settings,
          startOffset: startOffset,
          queueTrackIds: queueIds,
          quicPort: _quicPort,
        );
      } catch (err) {
        _pushMessage('Playback failed: $err', level: LogLevel.error);
        _updatePlayback(isPlaying: false);
      }
    }();
  }

  void _logPlaybackContext() {
    _pushMessage('Server base URL: ${connection.baseUrl}');
    if (Platform.isIOS) {
      _pushMessage('Local network permission: ${_localNetworkPermissionState.name}');
      try {
        final uri = Uri.parse(connection.baseUrl);
        final host = uri.host;
        final isLoopback =
            host == 'localhost' || host == '127.0.0.1' || host == '::1';
        if (host.isNotEmpty && isLoopback) {
          _pushMessage(
            'Warning: base URL resolves to loopback on iOS. Use your LAN IP/hostname.',
            level: LogLevel.warning,
          );
        }
      } catch (_) {}
    }
  }

  void _closeStreamControl() {
    _updatePlayback(streamConnected: false, streamRttMs: null);
  }

  Future<void> _refreshServerPorts() async {
    try {
      final ports = await connection.fetchServerPorts();
      if (ports.quicEnabled && (ports.quicPort ?? 0) > 0) {
        _quicPort = ports.quicPort;
      } else {
        _quicPort = null;
      }
    } catch (err) {
      _quicPort = null;
      _pushMessage('Failed to load server ports: $err', level: LogLevel.warning);
    }
  }

  void _startHealthMonitor() {
    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(
      const Duration(seconds: 12),
      (_) => _pollHealth(),
    );
    _pollHealth();
  }

  Future<void> _pollHealth() async {
    if (_healthPingInFlight) {
      return;
    }
    if (_audioEngine.hasActivePlayer) {
      return;
    }
    _healthPingInFlight = true;
    final rttMs = await connection.pingHealthMs(
      timeout: const Duration(seconds: 4),
    );
    _healthPingInFlight = false;
    if (_audioEngine.hasActivePlayer) {
      return;
    }
    if (rttMs != null) {
      _updatePlayback(streamConnected: true, streamRttMs: rttMs);
    } else {
      _updatePlayback(streamConnected: false, streamRttMs: null);
    }
  }

  List<String> _buildQueueIds(String currentId, int count) {
    if (_playQueue.isEmpty) {
      return <String>[currentId];
    }
    final startIndex = _playQueue.indexWhere((track) => track.id == currentId);
    final index = startIndex >= 0 ? startIndex : _playIndex;
    final total = _playQueue.length;
    final limit = count.clamp(1, total);
    final ids = <String>[];
    for (var i = 0; i < limit; i++) {
      final idx = (index + i) % total;
      ids.add(_playQueue[idx].id);
    }
    return ids;
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
    if (_ignoreCompleteUntil != null &&
        DateTime.now().isBefore(_ignoreCompleteUntil!)) {
      _autoAdvanceInFlight = false;
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
    nextTrack(fromAutoAdvance: true);
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
      _pushMessage('Failed to load playback settings: $err', level: LogLevel.warning);
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
