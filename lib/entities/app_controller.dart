import 'dart:async';
import 'dart:collection';

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' hide RepeatMode;

import '../platform/local_network_permission_service.dart';
import '../platform/now_playing_platform_service.dart';
import '../platform/now_playing_artwork_loader.dart';
import '../platform/now_playing_artwork.dart';
import '../platform/vehicle_surface_service.dart';
import 'app_log.dart';
import 'auth_state.dart';
import 'auth_storage.dart';
import 'connectivity_signal_source.dart';
import 'custom_shuffle_settings.dart';
import 'offline_download_manager.dart';
import 'offline_library.dart';
import 'offline_library_views.dart';
import 'offline_storage_settings.dart';
import 'playback_preferences.dart';
import 'listening_stats.dart';
import 'listening_stats_sync.dart';
import 'models.dart';
import 'metadata_event_listener.dart';
import 'local_library_selection.dart';
import 'playback_state.dart';
import 'server_connection.dart';
import 'audio_engine.dart';

export 'playback_state.dart';

enum LocalNetworkPermissionState { unknown, granted, denied }

enum _SeekDirection { none, forward, backward }

enum _OfflineQueueSource { none, tracks, localLiked, localPlaylist }

const Object _unset = Object();

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

class AppController {
  static const Duration storedSessionRestoreTimeout = Duration(seconds: 10);
  static const Duration _storedSessionRequestTimeout = Duration(seconds: 4);
  static const Duration _offlineRefreshTimeout = Duration(seconds: 5);

  AppController({
    required this.connection,
    AudioEngineFactory audioEngineFactory = AudioEngine.new,
    OfflineDownloadManager? offlineDownloadManager,
    OfflineLibraryStorage offlineStorage = const OfflineLibraryStorage(),
    AuthStorage authStorage = const AuthStorage(),
    CustomShuffleSettingsStorage customShuffleStorage =
        const CustomShuffleSettingsStorage(),
    PlaybackPreferencesStorage playbackPreferencesStorage =
        const PlaybackPreferencesStorage(),
    ConnectivitySignalSource? connectivitySignalSource,
    NowPlayingPlatformService? nowPlayingPlatformService,
    NowPlayingArtworkLoader? nowPlayingArtworkLoader,
    VehicleSurfaceService? vehicleSurfaceService,
    LocalNetworkPermissionService? localNetworkPermissionService,
    DateTime Function()? playbackClock,
    ListeningStatsService? listeningStatsService,
  }) : _audioEngineFactory = audioEngineFactory,
       _playbackClock = playbackClock ?? DateTime.now,
       _listeningStats =
           listeningStatsService ??
           ListeningStatsService(
             inMemory: Platform.environment.containsKey('FLUTTER_TEST'),
           ),
       _offlineStorage = offlineStorage,
       _offlineDownloadManager =
           offlineDownloadManager ??
           OfflineDownloadManager(
             connection: connection,
             storage: offlineStorage,
           ),
       _authStorage = authStorage,
       _customShuffleStorage = customShuffleStorage,
       _playbackPreferencesStorage = playbackPreferencesStorage,
       _connectivitySignalSource =
           connectivitySignalSource ?? ConnectivityPlusSignalSource(),
       _nowPlayingPlatform =
           nowPlayingPlatformService ?? NowPlayingPlatformService(),
       _artwork = NowPlayingArtwork(
         loader: nowPlayingArtworkLoader ?? NowPlayingArtworkLoader(),
       ),
       _vehicleSurface = vehicleSurfaceService ?? VehicleSurfaceService(),
       _localNetworkPermissions =
           localNetworkPermissionService ?? LocalNetworkPermissionService() {
    _initialBaseUrl = connection.baseUrl;
    _logListener = _addLogEntry;
    _playbackState = PlaybackState(
      track: null,
      isPlaying: false,
      isLoading: false,
      position: Duration.zero,
      duration: Duration.zero,
      bufferRatio: 0.0,
      volume: 1.0,
      shuffleMode: ShuffleMode.off,
      shuffleScope: ActionScope.server,
      repeatMode: RepeatMode.off,
      streamMode: StreamMode.high,
      bitrateKbps: null,
      streamConnected: false,
      streamRttMs: null,
      queueSource: PlaybackQueueSource.none,
      queueSourcePlaylistId: null,
      localPlaybackSource: LocalPlaybackSource.none,
      isLocalPlayback: false,
    );
    _authState = AuthState(isAuthorized: false, baseUrl: connection.baseUrl);
    _stats = StatsResponse(
      year: DateTime.now().toUtc().year,
      month: null,
      totalMinutes: 0,
      topArtists: [],
      topTracks: [],
      topGenres: [],
    );
  }

  Future<void>? _initialization;
  Future<void>? _shutdown;
  bool _initialized = false;
  bool _startupBegun = false;
  bool get isInitialized => _initialized;

  /// Starts owned audio, storage, platform subscriptions and timers once.
  /// Construction alone is inert. Injected dependencies are owned by this
  /// controller and are released by [close], including on startup failure.
  Future<void> initialize() {
    if (_disposed) {
      return Future<void>.error(StateError('Controller is closed'));
    }
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    _startupBegun = true;
    try {
      AppLogger.instance.attach(_logListener, includeHistory: true);
      connection.onTransportFailure = _handleServerTransportFailure;
      _carPlayOfflineLibrarySubscription = _offlineDownloadManager
          .librarySnapshotStream
          .listen((_) => _scheduleCarPlayStateUpdate());
      _carPlayLocalLikedSubscription = _offlineDownloadManager.localLikedStream
          .listen((_) => _scheduleCarPlayStateUpdate());
      _carPlayLocalPlaylistsSubscription = _offlineDownloadManager
          .localPlaylistsStream
          .listen((_) => _scheduleCarPlayStateUpdate());
      _audio = _audioEngineFactory(
        onMessage: _pushMessage,
        onStats:
            (position, bufferedAhead, bitrateKbps, rttMs, isLocalPlayback) {
              if (_disposed) return;
              if (!_audioOutputStarted &&
                  _playbackState.isPlaying &&
                  !_audioEngine.isPaused) {
                _audioOutputStarted = true;
                _updatePlayback(isLoading: false, nowPlaying: false);
              }
              final duration = _playbackState.duration;
              final rawClamped = duration == Duration.zero
                  ? position
                  : position > duration
                  ? duration
                  : position;
              final correctedPositionMs = _correctReportedPositionMs(
                rawClamped.inMilliseconds,
              );
              final clamped = Duration(milliseconds: correctedPositionMs);
              _actualPositionMs = correctedPositionMs;
              _updateDisplayPosition(
                _actualPositionMs,
                bufferedAhead.inMilliseconds,
              );
              _maybeClearSeekHold(clamped, bufferedAhead);
              _updateBufferedEndHighWater(
                duration: duration,
                position: Duration(milliseconds: _actualPositionMs),
                bufferedAhead: bufferedAhead,
              );
              final displayBufferRatio = _displayBufferRatio(
                duration: duration,
              );
              final nextRtt = rttMs ?? _playbackState.streamRttMs;
              _updatePlayback(
                position: Duration(milliseconds: _displayPositionMs),
                bufferRatio: displayBufferRatio,
                bitrateKbps: isLocalPlayback ? null : bitrateKbps,
                streamConnected: isLocalPlayback ? false : true,
                streamRttMs: isLocalPlayback ? null : nextRtt,
                isLocalPlayback: isLocalPlayback,
              );
              _maybeAutoAdvance(clamped, bufferedAhead);
            },
        onComplete: _handleTrackFinished,
        onStarted: () {
          if (_disposed) return;
          if (!_audioOutputStarted) {
            _audioOutputStarted = true;
            _updatePlayback(isLoading: false);
            _pushNowPlayingUpdate(force: true);
          }
        },
        onState: _handleAudioEngineState,
      );
      _audio!.onListeningSegment = _recordListeningSegment;
      _configureLocalNetworkPermissions();
      _configureNowPlaying();
      _configureCarPlay();
      _configureConnectivitySignals();
      _startHealthMonitor();
      _customShuffleLoadFuture = _loadCustomShuffleSettings();
      await Future.wait([
        _initializeListeningStats(),
        _offlineDownloadManager.load(),
        loadOfflineStorageLocations(),
        _customShuffleLoadFuture!,
        _loadPlaybackPreferences(),
      ]);
      if (!_disposed) _initialized = true;
    } catch (_) {
      if (_disposed) return;
      await close();
      rethrow;
    }
  }

  final ServerConnection connection;

  Map<String, String> get artworkHeaders => connection.authorizationHeaders;
  final ConnectivitySignalSource _connectivitySignalSource;
  final OfflineLibraryStorage _offlineStorage;
  final OfflineDownloadManager _offlineDownloadManager;
  final AudioEngineFactory _audioEngineFactory;
  AudioEngine? _audio;
  AudioEngine get _audioEngine =>
      _audio ?? (throw StateError('Call initialize() before using playback'));
  final NowPlayingPlatformService _nowPlayingPlatform;
  final NowPlayingArtwork _artwork;
  final VehicleSurfaceService _vehicleSurface;
  final LocalNetworkPermissionService _localNetworkPermissions;
  late final String _initialBaseUrl;
  final AuthStorage _authStorage;
  final CustomShuffleSettingsStorage _customShuffleStorage;
  final PlaybackPreferencesStorage _playbackPreferencesStorage;
  final ListeningStatsService _listeningStats;
  ListeningStatsSync? _listeningSync;
  StreamSubscription<void>? _listeningSubscription;
  Timer? _statsRefreshDebounce;
  Future<void>? _statsGenreRepair;
  (String, int, int)? _statsGenreRepairCursorKey;
  String? _statsGenreRepairAfterTrackId;
  final _statsCollectionController = StreamController<bool>.broadcast();
  Map<String, dynamic>? _listeningSessionContext;
  bool _listeningClosed = false;
  String? _statsServerId;
  String? _statsUserId;
  int _statsReadRevision = 0;
  bool _resettingListeningStats = false;
  bool _suspendedListeningForReset = false;

  bool get statsCollectionEnabled => _listeningStats.enabled;
  Stream<bool> get statsCollectionEnabledStream =>
      _statsCollectionController.stream;
  bool get statsSyncing => _listeningSync?.syncing ?? false;
  int get pendingStatsCount => _listeningStats.pendingCount;
  DateTime? get statsLastSyncedAt => _listeningStats.lastSyncedAt;
  String? get statsSyncMessage => _listeningStats.storageError != null
      ? 'Listening history could not be saved on this device.'
      : _listeningSync?.message;
  bool get statsServerCollectionEnabled =>
      _listeningSync?.serverCollectionEnabled ?? false;
  bool get canImportLocalStats =>
      !_resettingListeningStats &&
      _listeningStats.canImportLocalHistory &&
      statsCollectionEnabled;

  Future<void> _initializeListeningStats() async {
    _listeningSubscription = _listeningStats.changes.listen((_) {
      if (_disposed) return;
      _statsCollectionController.add(statsCollectionEnabled);
      _scheduleStatsRefresh();
    });
    try {
      await _listeningStats.initialize();
      if (_disposed) return;
      _listeningSync = ListeningStatsSync(
        history: _listeningStats,
        connection: connection,
        isAuthorized: () => !_disposed && _authState.isAuthorized,
        onChanged: _scheduleStatsRefresh,
        onIdentity: _saveListeningIdentity,
      )..start();
      await _refreshLocalStats();
    } catch (error) {
      _pushMessage(
        'Listening history storage is unavailable: $error',
        level: LogLevel.warning,
      );
    }
  }

  Future<void> _saveListeningIdentity(String serverId, String userId) async {
    _statsServerId = serverId;
    _statsUserId = userId;
    final saved = _savedCredentials;
    if (saved != null &&
        saved.baseUrl == connection.baseUrl &&
        saved.token == connection.token &&
        (saved.serverId != serverId || saved.userId != userId)) {
      await _storeSavedCredentials(
        AuthCredentials(
          baseUrl: saved.baseUrl,
          token: saved.token,
          username: saved.username,
          serverId: serverId,
          userId: userId,
          trust: saved.trust,
        ),
      );
    }
    final track = _playbackState.track;
    if (track != null &&
        (_listeningSessionContext?['account_scope'] !=
                _listeningStats.accountScope ||
            _listeningSessionContext?['history_generation'] !=
                _listeningStats.historyGeneration)) {
      _prepareListeningSession(track, newSession: true, updateActive: true);
    }
  }

  Future<void> _detachListeningAccount({int? expectedSessionRevision}) async {
    _statsServerId = _statsUserId = null;
    _listeningSessionContext = null;
    _audio?.configureListening(null, discardPending: false);
    if (_listeningStats.storageError == null) {
      try {
        await _listeningStats.setAccount();
      } catch (error) {
        _pushMessage(
          'Could not switch listening history: $error',
          level: LogLevel.warning,
        );
        return;
      }
    }
    if (_disposed ||
        (expectedSessionRevision != null &&
            connection.sessionRevision != expectedSessionRevision)) {
      return;
    }
    final playback = _playbackState;
    if (playback.isLocalPlayback && playback.track != null) {
      _prepareListeningSession(
        playback.track!,
        newSession: true,
        updateActive: true,
      );
    }
    await _refreshLocalStats();
  }

  void _scheduleStatsRefresh() {
    if (_disposed) return;
    _statsRefreshDebounce?.cancel();
    _statsRefreshDebounce = Timer(const Duration(milliseconds: 100), () {
      unawaited(_refreshLocalStats());
    });
  }

  Future<void> _refreshLocalStats() async {
    if (_disposed || _listeningStats.storageError != null) {
      if (!_disposed) _statsController.add(_stats);
      return;
    }
    final revision = ++_statsReadRevision;
    try {
      final result = await _listeningStats.stats(
        year: _stats?.year,
        month: _stats?.month,
      );
      if (_disposed || revision != _statsReadRevision) return;
      _stats = result;
      _statsController.add(result);
    } catch (_) {
      if (!_disposed) _statsController.add(_stats);
    }
  }

  Future<void> setStatsCollectionEnabled(bool value) async {
    if (_disposed || value == statsCollectionEnabled) return;
    // Disable the worker immediately, before any disk or network operation.
    if (!value) _audio?.configureListening(null);
    _listeningSessionContext = null;
    try {
      await _listeningStats.setEnabled(value);
      if (_disposed) return;
      final track = _playbackState.track;
      if (value && track != null) {
        _prepareListeningSession(track, newSession: true, updateActive: true);
      }
      _statsCollectionController.add(statsCollectionEnabled);
      final sync = _listeningSync;
      if (sync != null) {
        // Saving this setting never waits for a poor server connection.
        // Immediate sync also queues preference delivery after an in-flight batch.
        unawaited(sync.sync(immediate: true));
      }
      await _refreshLocalStats();
    } catch (error) {
      _audio?.configureListening(null);
      _pushMessage(
        'Could not save the listening statistics setting: $error',
        level: LogLevel.warning,
      );
      _statsCollectionController.add(statsCollectionEnabled);
      _scheduleStatsRefresh();
    }
  }

  Future<void> resetLocalListeningHistory() => _resetListeningHistory(
    _listeningStats.resetLocalHistory,
    localOnly: true,
  );

  Future<void> resetListeningStatistics() => _resetListeningHistory(() async {
    final resetServer = _authState.isAuthorized;
    final sync = _listeningSync;
    if (sync != null) {
      await sync.resetListeningStatistics(resetServer: resetServer);
    } else {
      if (resetServer) {
        throw StateError('Listening statistics are not ready. Try again.');
      }
      await _listeningStats.resetDeviceHistory();
    }
  });

  Future<void> resetAccountListeningHistory() async {
    final sync = _listeningSync;
    if (!_authState.isAuthorized || sync == null) {
      throw StateError(
        'Connect and sign in to reset account listening statistics.',
      );
    }
    await _resetListeningHistory(sync.resetAccountHistory);
  }

  Future<void> _resetListeningHistory(
    Future<void> Function() reset, {
    bool localOnly = false,
  }) async {
    if (_disposed || _resettingListeningStats) {
      throw StateError(
        'Listening statistics are unavailable or already resetting.',
      );
    }
    _resettingListeningStats = true;
    final resetActiveSession =
        !localOnly || _listeningStats.accountScope == 'local';
    _suspendedListeningForReset = resetActiveSession;
    if (resetActiveSession) {
      _listeningSessionContext = null;
      _audio?.configureListening(null);
    }
    try {
      await reset();
    } finally {
      _resettingListeningStats = false;
      _suspendedListeningForReset = false;
      if (!_disposed) {
        final track = _playbackState.track;
        if (track != null &&
            (resetActiveSession ||
                (localOnly && _listeningStats.accountScope == 'local'))) {
          _prepareListeningSession(track, newSession: true, updateActive: true);
        }
        await _refreshLocalStats();
      }
    }
  }

  Future<void> importLocalListeningHistory() async {
    if (_disposed || !canImportLocalStats) return;
    await _listeningStats.importLocalHistory();
    await _refreshLocalStats();
    await _listeningSync?.sync(immediate: true);
  }

  void _recordListeningSegment(Map<String, dynamic> data) {
    if (_listeningClosed ||
        _suspendedListeningForReset ||
        !statsCollectionEnabled) {
      return;
    }
    if (data['collection_revision'] != null &&
        data['collection_revision'] != _listeningStats.preferenceRevision) {
      return;
    }
    final scope = data['account_scope']?.toString();
    final generation = (data['history_generation'] as num?)?.toInt();
    try {
      final event = ListeningEvent.fromJson(data);
      unawaited(
        _listeningStats
            .recordSegment(event, scope: scope, generation: generation)
            .catchError((Object error) {
              _pushMessage(
                'Listening history could not be saved: $error',
                level: LogLevel.warning,
              );
            }),
      );
    } catch (error) {
      _pushMessage(
        'Listening history could not be recorded: $error',
        level: LogLevel.warning,
      );
    }
  }

  void _prepareListeningSession(
    Track track, {
    bool newSession = false,
    bool updateActive = false,
  }) {
    if (_suspendedListeningForReset ||
        !statsCollectionEnabled ||
        _listeningStats.storageError != null) {
      _audio?.configureListening(null);
      return;
    }
    final previous = _listeningSessionContext;
    final identity = track.serverTrackId ?? track.id;
    if (!newSession &&
        previous?['track_id'] == identity &&
        previous?['account_scope'] == _listeningStats.accountScope &&
        previous?['history_generation'] == _listeningStats.historyGeneration) {
      _audio?.configureListening(previous, updateActive: updateActive);
      return;
    }
    final now = _playbackClock().toUtc().millisecondsSinceEpoch;
    final canUseServerMetadata =
        track.serverBaseUrl == null ||
        track.serverBaseUrl == connection.baseUrl;
    final template = ListeningEvent.fromTrack(
      track: track,
      sessionId: newListeningId(),
      deviceId: _listeningStats.deviceId,
      sessionStartedAtMs: now,
      startedAtMs: now,
      endedAtMs: now,
      listenedMs: 0,
      cachedAlbums: canUseServerMetadata ? _albums : const [],
      cachedArtists: canUseServerMetadata ? _artists : const [],
    );
    _listeningSessionContext = {
      ...template.toJson(),
      'account_scope': _listeningStats.accountScope,
      'history_generation': _listeningStats.historyGeneration,
      'collection_revision': _listeningStats.preferenceRevision,
    };
    _pushMessage(
      'Listening genre snapshot: track_id=$identity '
      'artist=${jsonEncode(track.artist)} '
      'track_tags=${jsonEncode(track.genres)} '
      'listening_genres=${jsonEncode(template.genres)}',
      level: LogLevel.debug,
    );
    _audio?.configureListening(
      _listeningSessionContext,
      updateActive: updateActive,
    );
  }

  final DateTime Function() _playbackClock;
  late final LogListener _logListener;
  AuthCredentials? _savedCredentials;
  Future<void> _savedCredentialsWriteChain = Future<void>.value();
  bool _resettingUserPassword = false;
  CustomShuffleSettings _customShuffleSettings = const CustomShuffleSettings();
  Future<void>? _customShuffleLoadFuture;
  Timer? _volumeSaveDebounce;
  Future<void> _volumeSaveChain = Future.value();
  double _pendingVolumeSave = 1.0;
  bool _volumeSaveQueued = false;
  bool _volumeTouched = false;
  bool _collectionListModeTouched = false;
  bool _restoringSession = false;
  bool _savedCredentialsInvalidated = false;
  int _restoreSessionRevision = 0;
  LocalNetworkPermissionState _localNetworkPermissionState =
      LocalNetworkPermissionState.unknown;
  DateTime? _lastNowPlayingSentAt;
  String? _lastNowPlayingTrackId;
  bool? _lastNowPlayingIsPlaying;
  int _lastNowPlayingPositionMs = -1;
  int _lastNowPlayingEpochSent = -1;
  bool _nowPlayingReady = false;
  String? _lastSeekTrackId;
  bool _seeking = false;
  int _seekOriginMs = 0;
  int _seekTargetMs = 0;
  _SeekDirection _seekDirection = _SeekDirection.none;
  bool _isScrubbing = false;
  int _seekRequestGeneration = 0;
  int? _pendingSeekGeneration;
  int _playbackStartGeneration = 0;
  bool _wantsPlayback = false;
  bool _awaitingStreamReconnect = false;
  Timer? _streamRecoveryTimer;
  static const Duration _seekCompletionGuard = Duration(seconds: 8);
  static const int _seekCompletionToleranceMs = 400;
  bool _audioOutputStarted = false;
  int _displayPositionMs = 0;
  int _actualPositionMs = 0;
  int _bufferedEndHighWaterMs = 0;
  int _nowPlayingEpoch = 0;
  DateTime? _lastStartPlaybackAt;
  DateTime? _lastInterruptedStreamRestartAt;
  String? _lastStartPlaybackTrackId;
  String? _lastInterruptedStreamRestartTrackId;
  int? _lastStartPlaybackOffsetMs;
  int? _lastInterruptedStreamRestartPositionMs;
  Timer? _healthTimer;
  Timer? _serverReconnectTimer;
  Future<void>? _serverAvailabilityFuture;
  bool _healthPingInFlight = false;
  bool _disposed = false;
  bool _appInForeground = true;
  bool _lastConnectivityAvailable = true;
  int _serverHealthFailureCount = 0;
  int _serverReconnectAttempt = 0;
  int? _quicPort;
  static const Duration _interruptedStreamRestartCooldown = Duration(
    seconds: 8,
  );
  static const int _interruptedStreamRestartPositionToleranceMs = 5000;

  final _artistsController = StreamController<List<Artist>>.broadcast();
  final _albumsController = StreamController<List<Album>>.broadcast();
  final _artistReleasesController =
      StreamController<ArtistReleases>.broadcast();
  final _tracksController = StreamController<List<Track>>.broadcast();
  final _playlistsController = StreamController<List<Playlist>>.broadcast();
  final _playlistTracksController = StreamController<List<Track>>.broadcast();
  final _likedController = StreamController<List<Track>>.broadcast();
  final _statsController = StreamController<StatsResponse?>.broadcast();
  final _searchController = StreamController<List<SearchResult>>.broadcast();
  final _artistUpdatesController = StreamController<Artist>.broadcast();
  final _albumUpdatesController = StreamController<Album>.broadcast();
  final _messageController = StreamController<List<LogEntry>>.broadcast();
  final _playbackController = StreamController<PlaybackState>.broadcast();
  final _authController = StreamController<AuthState>.broadcast();
  final _localNetworkPermissionController =
      StreamController<LocalNetworkPermissionState>.broadcast();
  final _offlineStorageLocationsController =
      StreamController<OfflineStorageLocations>.broadcast();
  final _customShuffleSettingsController =
      StreamController<CustomShuffleSettings>.broadcast();
  final _collectionListModeController = StreamController<bool>.broadcast();
  final _artistsLoadingController = StreamController<bool>.broadcast();
  final _albumsLoadingController = StreamController<bool>.broadcast();
  final _tracksLoadingController = StreamController<bool>.broadcast();
  final _searchLoadingController = StreamController<bool>.broadcast();

  List<Artist> _artists = <Artist>[];
  List<Album> _albums = <Album>[];
  ArtistReleases _artistReleases = const ArtistReleases();
  String? _artistReleasesArtistId;
  List<Track> _tracks = <Track>[];
  List<Playlist> _playlists = <Playlist>[];
  List<Track> _playlistTracks = <Track>[];
  int _playlistTracksRequestId = 0;
  List<Track> _liked = <Track>[];
  List<SearchResult> _search = <SearchResult>[];
  final _messages = ListQueue<LogEntry>();
  List<LogEntry>? _messageSnapshot;
  Timer? _messageUpdateTimer;
  StatsResponse? _stats;
  OfflineStorageLocations? _offlineStorageLocations;
  late PlaybackState _playbackState;
  late AuthState _authState;
  List<OutputDevice> _outputDevices = <OutputDevice>[];
  int _outputDeviceId = kDefaultOutputDeviceId;
  String? _outputDeviceName;
  bool _artistsLoading = false;
  int _artistsOffset = 0;
  bool _artistsHasMore = true;
  int _artistsRequestEpoch = 0;
  int _artistListSessionRevision = -1;
  int _artistReleasesRequestEpoch = 0;
  Completer<void>? _artistsPageCompleter;
  bool _albumsLoading = false;
  bool _tracksLoading = false;
  bool _searchLoading = false;
  bool _collectionListMode = false;
  int _searchRequestId = 0;
  List<Track> _playQueue = <Track>[];
  int _playIndex = 0;
  final Random _shuffleRandom = Random();
  final Random _reconnectRandom = Random();
  bool _autoAdvanceInFlight = false;
  DateTime? _suppressAutoAdvanceUntil;
  DateTime? _ignoreCompleteUntil;
  ShuffleMode _queueShuffleMode = ShuffleMode.off;
  String? _queueShuffleScope;
  String? _queueShufflePlaylistId;
  String? _queueShuffleArtistId;
  String? _queueShuffleAlbumId;
  _OfflineQueueSource _offlineQueueSource = _OfflineQueueSource.none;
  bool _customShuffleRefreshInFlight = false;
  bool _customShuffleRefreshQueued = false;
  String? _lastArtistId;
  String? _lastAlbumId;
  String? _currentPlaylistId;
  final Map<String, String> _albumIdByKey = <String, String>{};
  int _albumIdCacheSessionRevision = -1;
  int _metadataReadRevision = 0;
  Timer? _carPlayStateDebounce;
  StreamSubscription<bool>? _connectivitySubscription;
  StreamSubscription<OfflineLibrarySnapshot>?
  _carPlayOfflineLibrarySubscription;
  StreamSubscription<List<Track>>? _carPlayLocalLikedSubscription;
  StreamSubscription<List<Playlist>>? _carPlayLocalPlaylistsSubscription;
  late final MetadataEventListener _metadataEvents = MetadataEventListener(
    openStream: connection.streamMetadataEvents,
    isSessionCurrent: (baseUrl, token) =>
        !_disposed &&
        _authState.isAuthorized &&
        connection.baseUrl == baseUrl &&
        connection.token == token,
    applyEvent: _applyMetadataEvent,
    onDiagnostic: AppLogger.debug,
  );

  static const int _serverUnavailableHealthFailureThreshold = 2;
  static const List<Duration> _serverReconnectForegroundBackoff = <Duration>[
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 20),
    Duration(seconds: 30),
  ];
  static const List<Duration> _serverReconnectBackgroundBackoff = <Duration>[
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(seconds: 60),
    Duration(seconds: 120),
  ];
  static const Duration _serverReconnectJitterMax = Duration(milliseconds: 750);
  static const Duration _serverLogoutBestEffortTimeout = Duration(
    milliseconds: 750,
  );

  Stream<List<Artist>> get artistsStream => _artistsController.stream;
  Stream<List<Album>> get albumsStream => _albumsController.stream;
  Stream<ArtistReleases> get artistReleasesStream =>
      _artistReleasesController.stream;
  Stream<List<Track>> get tracksStream => _tracksController.stream;
  Stream<List<Playlist>> get playlistsStream => _playlistsController.stream;
  Stream<List<Track>> get playlistTracksStream =>
      _playlistTracksController.stream;
  Stream<List<Track>> get likedStream => _likedController.stream;
  Stream<StatsResponse?> get statsStream => _statsController.stream;
  Stream<List<SearchResult>> get searchStream => _searchController.stream;
  Stream<Artist> watchArtist(String artistId) =>
      _artistUpdatesController.stream.where((artist) => artist.id == artistId);
  Stream<Album> watchAlbum(String albumId) =>
      _albumUpdatesController.stream.where((album) => album.id == albumId);
  Stream<List<LogEntry>> get messageStream => _messageController.stream;
  Stream<PlaybackState> get playbackStream => _playbackController.stream;
  Stream<AuthState> get authStream => _authController.stream;
  Stream<List<OfflineTrackDownload>> get offlineDownloadsStream =>
      _offlineDownloadManager.stream;
  Stream<OfflineDownloadSnapshot> get offlineDownloadSnapshotStream =>
      _offlineDownloadManager.downloadSnapshotStream;
  Stream<OfflineLibrarySnapshot> get offlineLibrarySnapshotStream =>
      _offlineDownloadManager.librarySnapshotStream;
  Stream<List<OfflineDownloadBatch>> get offlineDownloadBatchesStream =>
      _offlineDownloadManager.batchStream;
  Stream<List<OfflineDownloadJob>> get offlineDownloadJobsStream =>
      _offlineDownloadManager.jobStream;
  Stream<List<Track>> get localLikedStream =>
      _offlineDownloadManager.localLikedStream;
  Stream<List<Playlist>> get localPlaylistsStream =>
      _offlineDownloadManager.localPlaylistsStream;
  Stream<List<Track>> get localPlaylistTracksStream =>
      _offlineDownloadManager.localPlaylistTracksStream;
  Stream<LocalNetworkPermissionState> get localNetworkPermissionStream =>
      _localNetworkPermissionController.stream;
  Stream<OfflineStorageLocations> get offlineStorageLocationsStream =>
      _offlineStorageLocationsController.stream;
  Stream<CustomShuffleSettings> get customShuffleSettingsStream =>
      _customShuffleSettingsController.stream;
  Stream<bool> get collectionListModeStream =>
      _collectionListModeController.stream;
  Stream<bool> get artistsLoadingStream => _artistsLoadingController.stream;
  Stream<bool> get albumsLoadingStream => _albumsLoadingController.stream;
  Stream<bool> get tracksLoadingStream => _tracksLoadingController.stream;
  Stream<bool> get searchLoadingStream => _searchLoadingController.stream;

  List<Artist> get artists => List.unmodifiable(_artists);
  List<Album> get albums => List.unmodifiable(_albums);
  ArtistReleases get artistReleases => _artistReleases;
  List<Track> get tracks => List.unmodifiable(_tracks);
  List<Playlist> get playlists => List.unmodifiable(_playlists);
  List<Track> get playlistTracks => List.unmodifiable(_playlistTracks);
  List<Track> get liked => List.unmodifiable(_liked);
  List<SearchResult> get searchResults => List.unmodifiable(_search);
  List<LogEntry> get messages =>
      _messageSnapshot ??= List<LogEntry>.unmodifiable(_messages);
  StatsResponse? get stats => _stats;
  PlaybackState get playbackState => _playbackState;
  AuthState get authState => _authState;
  List<OfflineTrackDownload> get offlineDownloads =>
      _offlineDownloadManager.downloads;
  OfflineDownloadSnapshot get offlineDownloadSnapshot =>
      _offlineDownloadManager.downloadSnapshot;
  OfflineLibrarySnapshot get offlineLibrarySnapshot =>
      _offlineDownloadManager.librarySnapshot;
  List<OfflineDownloadBatch> get offlineDownloadBatches =>
      _offlineDownloadManager.batches;
  List<OfflineDownloadJob> get offlineDownloadJobs =>
      _offlineDownloadManager.jobs;
  List<OfflineTrackDownload> get availableOfflineDownloads =>
      _offlineDownloadManager.downloads
          .where(_offlineDownloadAvailable)
          .toList(growable: false);
  List<Track> get offlineTracks =>
      _offlineDownloadManager.localDownloadedTracks();
  List<Track> get localLiked => _offlineDownloadManager.localLiked;
  List<Playlist> get localPlaylists => _offlineDownloadManager.localPlaylists;
  List<Track> get localPlaylistTracks =>
      _offlineDownloadManager.localPlaylistTracks;
  LocalNetworkPermissionState get localNetworkPermissionState =>
      _localNetworkPermissionState;
  OfflineStorageLocations? get offlineStorageLocations =>
      _offlineStorageLocations;
  CustomShuffleSettings get customShuffleSettings => CustomShuffleSettings(
    artistIds: customShuffleArtistIds,
    genres: customShuffleGenres,
    localArtistIds: localCustomShuffleArtistIds,
    localGenres: localCustomShuffleGenres,
  );
  List<String> get customShuffleArtistIds =>
      List.unmodifiable(_customShuffleSettings.artistIds);
  List<String> get customShuffleGenres =>
      List.unmodifiable(_customShuffleSettings.genres);
  List<String> get localCustomShuffleArtistIds =>
      List.unmodifiable(_customShuffleSettings.localArtistIds);
  List<String> get localCustomShuffleGenres =>
      List.unmodifiable(_customShuffleSettings.localGenres);
  bool get collectionListMode => _collectionListMode;
  bool get localNetworkPermissionSupported {
    return _localNetworkPermissions.isSupported;
  }

  Future<void> openAppSettings() async {
    if (!localNetworkPermissionSupported) {
      return;
    }
    try {
      await _localNetworkPermissions.openAppSettings();
    } catch (_) {}
  }

  Future<void> refreshLocalNetworkPermission() async {
    if (!localNetworkPermissionSupported) {
      return;
    }
    await _refreshLocalNetworkPermission();
  }

  bool get artistsLoading => _artistsLoading;
  bool get hasMoreArtists => _artistsHasMore;
  bool get albumsLoading => _albumsLoading;
  bool get tracksLoading => _tracksLoading;
  bool get searchLoading => _searchLoading;
  List<OutputDevice> get outputDevices => List.unmodifiable(_outputDevices);
  int get outputDeviceId => _outputDeviceId;
  String? get outputDeviceName => _outputDeviceName;
  bool get hasSavedCredentials => _savedCredentials != null;
  String? get savedUsername => _savedCredentials?.username;
  String? get savedBaseUrl => _savedCredentials?.baseUrl;
  bool get canUseServer => _authState.isAuthorized;
  bool get canResetUserPassword =>
      !_disposed &&
      !_resettingUserPassword &&
      _authState.isAuthorized &&
      _authState.baseUrl == connection.baseUrl &&
      connection.canChangeOwnPassword;

  bool get _canAttemptRemotePlayback {
    final token = connection.token;
    return token != null && token.isNotEmpty && _authState.hasSession;
  }

  bool get _hasActiveRemotePlayback {
    return _playbackState.track != null &&
        _playbackState.isPlaying &&
        !_playbackState.isLocalPlayback &&
        _audioEngine.hasActivePlayer;
  }

  OfflineTrackDownload? offlineDownloadForTrack(String trackId) {
    return _offlineDownloadManager.findForCurrentServer(trackId) ??
        _offlineDownloadManager.findLocal(trackId);
  }

  OfflineTrackDownload? availableOfflineDownloadForTrack(String trackId) {
    final currentServer = _offlineDownloadManager.findForCurrentServer(trackId);
    if (currentServer != null && _offlineDownloadAvailable(currentServer)) {
      return currentServer;
    }
    final local = _offlineDownloadManager.findLocal(trackId);
    if (local != null && _offlineDownloadAvailable(local)) {
      return local;
    }
    for (final download in _offlineDownloadManager.downloads) {
      if ((download.track.id == trackId ||
              download.track.localId == trackId ||
              download.localTrackId == trackId ||
              download.track.serverTrackId == trackId) &&
          _offlineDownloadAvailable(download)) {
        return download;
      }
    }
    return null;
  }

  Track? serverTrackForCurrentServer(Track track) {
    if (!_authState.isAuthorized) {
      return null;
    }
    final serverTrackId = track.serverTrackId;
    final serverBaseUrl = track.serverBaseUrl;
    if (serverTrackId != null &&
        serverTrackId.isNotEmpty &&
        (serverBaseUrl == null || serverBaseUrl == connection.baseUrl)) {
      return track.copyWith(id: serverTrackId);
    }
    if (track.localId == null && serverBaseUrl == null) {
      return track;
    }
    for (final download in _offlineDownloadManager.downloads) {
      if (download.serverBaseUrl != connection.baseUrl) {
        continue;
      }
      final localId = download.localTrackId ?? download.track.localId;
      final matchesLocal =
          localId != null && (track.localId == localId || track.id == localId);
      final matchesServer =
          download.track.id == track.id ||
          download.track.serverTrackId == track.serverTrackId;
      if (matchesLocal || matchesServer) {
        return download.track.copyWith(
          id: download.track.serverTrackId ?? download.track.id,
          serverBaseUrl: download.serverBaseUrl,
          serverTrackId: download.track.serverTrackId ?? download.track.id,
        );
      }
    }
    return null;
  }

  bool _offlineDownloadAvailable(OfflineTrackDownload download) {
    if (!download.isDownloaded || download.filePath == null) {
      return false;
    }
    if (kIsWeb) {
      return false;
    }
    return download.filePath!.isNotEmpty;
  }

  List<OfflineTrackDownload> _downloadsForTrackRemoval(Track track) {
    final localId =
        _nonEmptyString(track.localId) ??
        _nonEmptyString(
          _offlineDownloadManager.findLocal(track.id)?.localTrackId,
        );
    final isLocalLibraryTrack = localId != null && track.id == localId;
    if (isLocalLibraryTrack) {
      return _offlineDownloadManager.downloads
          .where((download) => _downloadLocalId(download) == localId)
          .toList(growable: false);
    }

    final serverTrackId = _nonEmptyString(track.serverTrackId) ?? track.id;
    final currentServer =
        _offlineDownloadManager.findForCurrentServer(serverTrackId) ??
        _offlineDownloadManager.findForCurrentServer(track.id);
    if (currentServer != null) {
      return <OfflineTrackDownload>[currentServer];
    }

    final fallback = availableOfflineDownloadForTrack(track.id);
    if (fallback == null) {
      return const <OfflineTrackDownload>[];
    }
    return <OfflineTrackDownload>[fallback];
  }

  Future<void> _removeOfflineDownloads(
    Iterable<OfflineTrackDownload> downloads, {
    required String label,
    OfflineDeletionScope scope = const OfflineDeletionScope.track(),
  }) async {
    final byKey = <String, OfflineTrackDownload>{
      for (final download in downloads) _offlineDownloadKey(download): download,
    };
    final uniqueDownloads = byKey.values.toList(growable: false);
    if (uniqueDownloads.isEmpty) {
      return;
    }

    final shouldStopPlayback = uniqueDownloads.any(
      _downloadMatchesCurrentLocalPlayback,
    );
    if (shouldStopPlayback) {
      await stop();
    }

    await _offlineDownloadManager.removeDownloads(
      uniqueDownloads,
      scope: scope,
    );
    if (!shouldStopPlayback) {
      _pruneRemovedDownloadsFromOfflineQueue(uniqueDownloads);
    }

    final trimmedLabel = label.trim().isEmpty ? 'track' : label.trim();
    if (uniqueDownloads.length == 1) {
      _pushMessage('Removed download for $trimmedLabel from this device.');
    } else {
      _pushMessage(
        'Removed ${uniqueDownloads.length} downloads for $trimmedLabel from this device.',
      );
    }
  }

  void _pruneRemovedDownloadsFromOfflineQueue(
    List<OfflineTrackDownload> downloads,
  ) {
    if (_playbackState.queueSource != PlaybackQueueSource.offline ||
        _playQueue.isEmpty) {
      return;
    }
    final nextQueue = _playQueue
        .where(
          (track) => !downloads.any(
            (download) => _downloadMatchesTrackIdentity(download, track),
          ),
        )
        .toList(growable: false);
    if (nextQueue.length == _playQueue.length) {
      return;
    }
    _playQueue = nextQueue;
    if (_playQueue.isEmpty) {
      _playIndex = 0;
      return;
    }
    final current = _playbackState.track;
    final currentIndex = current == null
        ? -1
        : _playQueue.indexWhere((track) => _sameTrackIdentity(track, current));
    if (currentIndex >= 0) {
      _playIndex = currentIndex;
    } else if (_playIndex >= _playQueue.length) {
      _playIndex = max(0, _playQueue.length - 1);
    }
  }

  bool _downloadMatchesCurrentLocalPlayback(OfflineTrackDownload download) {
    if (!_playbackState.isLocalPlayback) {
      return false;
    }
    final current = _playbackState.track;
    if (current == null) {
      return false;
    }
    return _downloadMatchesTrackIdentity(download, current);
  }

  bool _downloadMatchesTrackIdentity(
    OfflineTrackDownload download,
    Track track,
  ) {
    final localId = _downloadLocalId(download);
    if (localId != null &&
        (track.id == localId || _nonEmptyString(track.localId) == localId)) {
      return true;
    }

    final serverTrackId = _serverTrackId(download);
    if (track.id != serverTrackId && track.serverTrackId != serverTrackId) {
      return false;
    }
    final serverBaseUrl = _nonEmptyString(track.serverBaseUrl);
    return serverBaseUrl == null || serverBaseUrl == download.serverBaseUrl;
  }

  bool _sameTrackIdentity(Track left, Track right) {
    if (left.id == right.id) {
      return true;
    }
    final leftLocalId = _nonEmptyString(left.localId);
    final rightLocalId = _nonEmptyString(right.localId);
    return leftLocalId != null && leftLocalId == rightLocalId;
  }

  String? _downloadLocalId(OfflineTrackDownload download) {
    return _nonEmptyString(download.localTrackId) ??
        _nonEmptyString(download.track.localId);
  }

  String _serverTrackId(OfflineTrackDownload download) {
    return download.track.serverTrackId ?? download.track.id;
  }

  String _offlineDownloadKey(OfflineTrackDownload download) {
    return '${download.serverBaseUrl}\n${_serverTrackId(download)}';
  }

  String? _nonEmptyString(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  void dispose() => unawaited(close());

  /// Awaitable, idempotent release of resources, including partial startup.
  Future<void> close() => _shutdown ??= _close();

  Future<void> _close() async {
    _disposed = true;
    _initialized = false;
    _restoreSessionRevision++;
    _statsRefreshDebounce?.cancel();
    await _listeningSync?.close();
    await _listeningSubscription?.cancel();
    if (_startupBegun) {
      connection.onTransportFailure = null;
    }
    _stopMetadataEventListener();
    final clearNowPlaying = _startupBegun
        ? _clearNowPlaying()
        : Future<void>.value();
    _artwork.clear();
    _healthTimer?.cancel();
    _healthTimer = null;
    _stopServerReconnectLoop(resetAttempts: true);
    _isScrubbing = false;
    _seekRequestGeneration++;
    _playbackStartGeneration++;
    _wantsPlayback = false;
    _streamRecoveryTimer?.cancel();
    _streamRecoveryTimer = null;
    _volumeSaveDebounce?.cancel();
    _volumeSaveDebounce = null;
    _carPlayStateDebounce?.cancel();
    _carPlayStateDebounce = null;
    _flushVolumeSave();
    final cancellations = <Future<void>>[
      if (_connectivitySubscription != null)
        _connectivitySubscription!.cancel(),
      if (_carPlayOfflineLibrarySubscription != null)
        _carPlayOfflineLibrarySubscription!.cancel(),
      if (_carPlayLocalLikedSubscription != null)
        _carPlayLocalLikedSubscription!.cancel(),
      if (_carPlayLocalPlaylistsSubscription != null)
        _carPlayLocalPlaylistsSubscription!.cancel(),
    ];
    if (_startupBegun) {
      _nowPlayingPlatform.dispose();
      _vehicleSurface.dispose();
      _localNetworkPermissions.dispose();
    }
    AppLogger.instance.detach(_logListener);
    _messageUpdateTimer?.cancel();
    _messageUpdateTimer = null;
    _artistsController.close();
    _albumsController.close();
    _artistReleasesController.close();
    _tracksController.close();
    _playlistsController.close();
    _playlistTracksController.close();
    _likedController.close();
    _statsController.close();
    _statsCollectionController.close();
    _searchController.close();
    _artistUpdatesController.close();
    _albumUpdatesController.close();
    _messageController.close();
    _playbackController.close();
    _authController.close();
    _localNetworkPermissionController.close();
    _offlineStorageLocationsController.close();
    _customShuffleSettingsController.close();
    _collectionListModeController.close();
    _artistsLoadingController.close();
    _albumsLoadingController.close();
    _tracksLoadingController.close();
    _searchLoadingController.close();
    _closeStreamControl();
    await Future.wait([
      clearNowPlaying,
      ...cancellations,
      if (_audio != null) _audio!.dispose(),
      _offlineDownloadManager.dispose(),
      _volumeSaveChain,
    ]);
    _listeningClosed = true;
    if (_audio != null) _audio!.onListeningSegment = null;
    await _listeningStats.close();
  }

  void handleAppLifecycleState(AppLifecycleState state) {
    if (_disposed || !_startupBegun) return;
    final wasForeground = _appInForeground;
    _appInForeground = state == AppLifecycleState.resumed;
    if (_appInForeground && !wasForeground) {
      unawaited(_listeningSync?.sync(immediate: true) ?? Future<void>.value());
    }
    if (state == AppLifecycleState.detached) {
      _audioEngine.stop();
      _closeStreamControl();
    }
    if (_authState.status != SessionStatus.serverUnavailable) {
      return;
    }
    if (_appInForeground && !wasForeground) {
      unawaited(_triggerImmediateServerReconnect(reason: 'app resumed'));
      return;
    }
    if (_appInForeground != wasForeground) {
      _serverReconnectTimer?.cancel();
      _serverReconnectTimer = null;
      _scheduleServerReconnect();
    }
  }

  Future<void> loginWithPassword({
    required String baseUrl,
    required String username,
    required String password,
    bool rememberMe = false,
  }) async {
    _statsServerId = _statsUserId = null;
    if (_listeningStats.storageError == null) {
      await _listeningStats.setAccount();
    }
    _listeningSessionContext = null;
    final playingTrack = _playbackState.track;
    if (playingTrack != null) {
      _prepareListeningSession(
        playingTrack,
        newSession: true,
        updateActive: true,
      );
    }
    _setSessionStatus(SessionStatus.checking, error: null);
    try {
      connection.setBaseUrl(baseUrl);
      final token = await connection.login(
        username: username,
        password: password,
      );
      await _refreshServerPorts();
      _serverHealthFailureCount = 0;
      _setAuthorized(true, error: null);
      await _loadPlaybackSettings();
      unawaited(_offlineDownloadManager.resumePausedForCurrentServer());
      unawaited(_offlineDownloadManager.repairOfflineMetadataFragments());
      if (rememberMe) {
        final credentials = AuthCredentials(
          baseUrl: connection.baseUrl,
          token: token,
          username: username,
          serverId: _statsServerId,
          userId: _statsUserId,
          trust: connection.trust!,
        );
        await _storeSavedCredentials(credentials);
      } else {
        await _clearSavedCredentials();
      }
    } on ApiException catch (err) {
      final message = '${_formatApiError(err)} (OPAQUE sign-in)';
      _setSessionStatus(SessionStatus.serverReachable, error: message);
      _pushMessage('Login failed: $message', level: LogLevel.error);
    } catch (err) {
      _setSessionStatus(SessionStatus.offline, error: err.toString());
      _pushMessage('Login failed: $err', level: LogLevel.error);
    }
  }

  Future<void> downloadTrack(Track track) async {
    if (!_authState.isAuthorized) {
      _pushMessage(
        'Connect to a server before downloading ${track.title}.',
        level: LogLevel.warning,
      );
      return;
    }
    try {
      final queuedCount = await _offlineDownloadManager.downloadTrack(track);
      if (queuedCount > 0) {
        _pushMessage('Queued ${track.title} for download.');
      } else {
        _pushMessage('${track.title} is already downloaded or queued.');
      }
    } catch (err) {
      _pushMessage(
        'Failed to queue ${track.title}: $err',
        level: LogLevel.warning,
      );
    }
  }

  Future<void> downloadAlbum(Album album, List<Track> tracks) async {
    await _downloadTrackCollection(
      tracks,
      label: album.title,
      kind: 'album',
      sourceId: album.id,
      emptyMessage: 'No tracks found to download for ${album.title}.',
    );
  }

  Future<void> downloadPlaylist(
    Playlist playlist,
    List<Track> tracks, {
    required String name,
    String? description,
    PlaylistImageEdit imageEdit = const PlaylistImageEdit.keep(),
  }) async {
    if (!_authState.isAuthorized) {
      throw StateError('Connect to a server before downloading a playlist.');
    }
    try {
      await _offlineDownloadManager.downloadPlaylist(
        playlist,
        tracks,
        name: name,
        description: description,
        imageEdit: imageEdit,
      );
      _pushMessage('Saved local copy of $name.');
    } catch (err) {
      _pushMessage(
        'Failed to download playlist $name: $err',
        level: LogLevel.warning,
      );
      rethrow;
    }
  }

  Future<void> downloadArtist(Artist artist, List<Album> albums) async {
    if (!_requireServer('downloading ${artist.name}')) {
      return;
    }
    if (albums.isEmpty) {
      _pushMessage('No albums found to download for ${artist.name}.');
      return;
    }
    try {
      final queuedCount = await _offlineDownloadManager.queueArtist(
        artist,
        albums,
      );
      if (queuedCount == 0) {
        _pushMessage(
          'All tracks are already downloaded or queued for ${artist.name}.',
        );
        return;
      }
      final queuedTrackLabel = queuedCount == 1 ? 'track' : 'tracks';
      _pushMessage('Queued $queuedCount $queuedTrackLabel for ${artist.name}.');
    } catch (err) {
      _pushMessage(
        'Failed to queue downloads for ${artist.name}: $err',
        level: LogLevel.warning,
      );
    }
  }

  Future<void> _downloadTrackCollection(
    Iterable<Track> tracks, {
    required String label,
    required String emptyMessage,
    String kind = 'tracks',
    String? sourceId,
  }) async {
    if (!_requireServer('downloading $label')) {
      return;
    }
    final uniqueTracks = <String, Track>{};
    for (final track in tracks) {
      final id = track.id.trim();
      if (id.isEmpty) {
        continue;
      }
      uniqueTracks[id] = track;
    }
    if (uniqueTracks.isEmpty) {
      _pushMessage(emptyMessage);
      return;
    }
    final pending = uniqueTracks.values
        .where((track) => !_downloadQueuedOrAvailable(track))
        .toList(growable: false);
    if (pending.isEmpty) {
      _pushMessage('All tracks are already downloaded or queued for $label.');
      return;
    }
    try {
      final queuedCount = await _offlineDownloadManager.queueTracks(
        pending,
        label: label,
        kind: kind,
        sourceId: sourceId,
      );
      if (queuedCount == 0) {
        _pushMessage('All tracks are already downloaded or queued for $label.');
        return;
      }
      final queuedTrackLabel = queuedCount == 1 ? 'track' : 'tracks';
      _pushMessage('Queued $queuedCount $queuedTrackLabel for $label.');
    } catch (err) {
      _pushMessage(
        'Failed to queue downloads for $label: $err',
        level: LogLevel.warning,
      );
    }
  }

  bool _downloadQueuedOrAvailable(Track track) {
    final download = offlineDownloadForTrack(track.id);
    if (download == null) {
      return false;
    }
    if (download.status == OfflineDownloadStatus.queued ||
        download.status == OfflineDownloadStatus.preparing ||
        download.status == OfflineDownloadStatus.downloading ||
        download.status == OfflineDownloadStatus.validating ||
        download.status == OfflineDownloadStatus.removing) {
      return true;
    }
    return availableOfflineDownloadForTrack(track.id) != null;
  }

  bool _offlineDownloadPausable(OfflineDownloadStatus status) {
    return status == OfflineDownloadStatus.queued ||
        status == OfflineDownloadStatus.preparing ||
        status == OfflineDownloadStatus.downloading ||
        status == OfflineDownloadStatus.validating;
  }

  Future<void> removeOfflineTrack(String trackId) async {
    final download = offlineDownloadForTrack(trackId);
    if (download == null) {
      return;
    }
    await removeOfflineDownload(download);
  }

  Future<void> pauseOfflineDownload(OfflineTrackDownload download) async {
    await _offlineDownloadManager.pauseDownload(download);
  }

  Future<void> resumeOfflineDownload(OfflineTrackDownload download) async {
    await _offlineDownloadManager.resumeDownload(download);
  }

  Future<void> pauseOfflineDownloadJob(OfflineDownloadJob job) async {
    await _offlineDownloadManager.pauseDownloadJob(job);
    final label = job.label?.trim();
    _pushMessage(
      'Paused downloads for ${label == null || label.isEmpty ? job.kind : label}.',
    );
  }

  Future<void> resumeOfflineDownloadJob(OfflineDownloadJob job) async {
    await _offlineDownloadManager.resumeDownloadJob(job);
    final label = job.label?.trim();
    _pushMessage(
      'Resumed downloads for ${label == null || label.isEmpty ? job.kind : label}.',
    );
  }

  Future<void> pauseAllOfflineDownloads() async {
    final serverBaseUrls = <String>{
      for (final download in _offlineDownloadManager.downloads)
        if (_offlineDownloadPausable(download.status))
          download.serverBaseUrl.trim(),
      for (final job in _offlineDownloadManager.jobs)
        if (_offlineDownloadPausable(job.status)) job.serverBaseUrl.trim(),
    }..removeWhere((baseUrl) => baseUrl.isEmpty);
    if (serverBaseUrls.isEmpty) {
      _pushMessage('No active downloads to pause.');
      return;
    }
    for (final serverBaseUrl in serverBaseUrls) {
      await _offlineDownloadManager.pauseDownloadsForServer(serverBaseUrl);
    }
    _pushMessage('Paused downloads.');
  }

  Future<void> retryOfflineDownload(OfflineTrackDownload download) async {
    await _offlineDownloadManager.retryDownload(download);
  }

  Future<void> cancelOfflineDownload(OfflineTrackDownload download) async {
    await _offlineDownloadManager.cancelDownload(download);
  }

  Future<void> cancelOfflineDownloadJob(OfflineDownloadJob job) async {
    await _offlineDownloadManager.cancelDownloadJob(job);
    final label = job.label?.trim();
    _pushMessage(
      'Canceled downloads for ${label == null || label.isEmpty ? job.kind : label}.',
    );
  }

  Future<void> removeOfflineDownload(OfflineTrackDownload download) async {
    await removeOfflineDownloads(<OfflineTrackDownload>[
      download,
    ], label: download.track.title);
  }

  Future<void> removeOfflineDownloads(
    Iterable<OfflineTrackDownload> downloads, {
    String? label,
    OfflineDeletionScope scope = const OfflineDeletionScope.track(),
  }) async {
    final downloadList = downloads.toList(growable: false);
    final fallbackLabel = downloadList.length == 1
        ? downloadList.single.track.title
        : 'selection';
    await _removeOfflineDownloads(
      downloadList,
      label: label ?? fallbackLabel,
      scope: scope,
    );
  }

  Future<void> removeDownloadedTrack(Track track) async {
    await removeDownloadedTracks(<Track>[track], label: track.title);
  }

  Future<void> removeDownloadedTracks(
    Iterable<Track> tracks, {
    String? label,
    OfflineDeletionScope scope = const OfflineDeletionScope.track(),
  }) async {
    final trackList = tracks.toList(growable: false);
    final downloads = <OfflineTrackDownload>[
      for (final track in trackList) ..._downloadsForTrackRemoval(track),
    ];
    if (downloads.isEmpty) {
      final trimmedLabel = label?.trim();
      final messageLabel = trimmedLabel == null || trimmedLabel.isEmpty
          ? trackList.length == 1
                ? trackList.single.title
                : 'selection'
          : trimmedLabel;
      _pushMessage(
        'No downloaded file available to remove for $messageLabel.',
        level: LogLevel.warning,
      );
      return;
    }
    final fallbackLabel = trackList.length == 1
        ? trackList.single.title
        : 'selection';
    await _removeOfflineDownloads(
      downloads,
      label: label ?? fallbackLabel,
      scope: scope,
    );
  }

  Future<void> clearFailedOfflineDownloads() async {
    await _offlineDownloadManager.clearFailedAndCorrupt();
  }

  Future<void> resumePausedOfflineDownloads() async {
    if (!_requireServer('resuming paused downloads')) {
      return;
    }
    final baseUrl = connection.baseUrl;
    final pausedDownloads = _offlineDownloadManager.downloads
        .where(
          (download) =>
              download.serverBaseUrl == baseUrl &&
              download.status == OfflineDownloadStatus.paused,
        )
        .length;
    final pausedJobs = _offlineDownloadManager.jobs
        .where(
          (job) =>
              job.serverBaseUrl == baseUrl &&
              job.status == OfflineDownloadStatus.paused,
        )
        .toList(growable: false);
    if (pausedDownloads == 0 && pausedJobs.isEmpty) {
      _pushMessage('No paused downloads to resume.');
      return;
    }
    for (final job in pausedJobs) {
      await _offlineDownloadManager.resumeDownloadJob(job);
    }
    await _offlineDownloadManager.resumePausedForCurrentServer();
    _pushMessage('Resumed paused downloads.');
  }

  Future<void> clearPausedAndCachedOfflineDownloads() async {
    final removable = _offlineDownloadManager.downloads
        .where(
          (download) =>
              download.status == OfflineDownloadStatus.paused ||
              download.status == OfflineDownloadStatus.failed ||
              download.status == OfflineDownloadStatus.corrupt ||
              download.status == OfflineDownloadStatus.canceled,
        )
        .toList(growable: false);
    if (removable.isEmpty) {
      _pushMessage('No partial or failed downloads to clear.');
      return;
    }
    await _removeOfflineDownloads(removable, label: 'partial/failed downloads');
  }

  Future<void> resetOfflineData() async {
    try {
      if (_playbackState.isLocalPlayback ||
          _playbackState.queueSource == PlaybackQueueSource.offline) {
        await stop();
      }
      await _offlineDownloadManager.resetLocalData();
      await loadOfflineStorageLocations();
      await clearMessages();
      _pushMessage('Reset all local downloads, metadata, and logs.');
    } catch (err) {
      _pushMessage('Failed to reset local data: $err', level: LogLevel.warning);
    }
  }

  Future<void> refreshLibrary() async {
    var offlineRefreshCompleted = true;
    try {
      await _offlineDownloadManager.load().timeout(_offlineRefreshTimeout);
      await loadOfflineStorageLocations().timeout(_offlineRefreshTimeout);
    } on TimeoutException {
      offlineRefreshCompleted = false;
      _pushMessage(
        'Offline library refresh timed out; continuing with server refresh.',
        level: LogLevel.warning,
      );
    } catch (err) {
      offlineRefreshCompleted = false;
      _pushMessage(
        'Failed to refresh offline library: $err',
        level: LogLevel.warning,
      );
    }
    if (_authState.isAuthorized) {
      await loadArtists(refresh: true);
      _pushMessage(
        offlineRefreshCompleted
            ? 'Library refreshed from device and server.'
            : 'Server library refreshed; offline refresh did not complete.',
      );
      return;
    }
    if (offlineRefreshCompleted) {
      _pushMessage('Offline library refreshed from device.');
    }
  }

  Future<void> loadOfflineStorageLocations() async {
    try {
      final locations = await _offlineStorage.resolveStorageLocations();
      _offlineStorageLocations = locations;
      if (!_offlineStorageLocationsController.isClosed) {
        _offlineStorageLocationsController.add(locations);
      }
    } catch (err) {
      _pushMessage('Failed to load offline storage settings: $err');
    }
  }

  Future<void> updateOfflineMetadataDirectory(String? path) async {
    await _updateOfflineStorageLocation(
      metadataDirectory: path,
      message: 'Offline metadata storage updated.',
    );
  }

  Future<void> updateOfflineDownloadsDirectory(String? path) async {
    await _updateOfflineStorageLocation(
      downloadsDirectory: path,
      message: 'Offline download storage updated.',
    );
  }

  Future<void> resetOfflineMetadataDirectory() async {
    await updateOfflineMetadataDirectory(null);
  }

  Future<void> resetOfflineDownloadsDirectory() async {
    await updateOfflineDownloadsDirectory(null);
  }

  Future<void> _updateOfflineStorageLocation({
    Object? metadataDirectory = _unset,
    Object? downloadsDirectory = _unset,
    required String message,
  }) async {
    try {
      if (metadataDirectory != _unset && downloadsDirectory != _unset) {
        await _offlineStorage.updateStorageLocations(
          metadataDirectory: metadataDirectory,
          downloadsDirectory: downloadsDirectory,
        );
      } else if (metadataDirectory != _unset) {
        await _offlineStorage.updateStorageLocations(
          metadataDirectory: metadataDirectory,
        );
      } else if (downloadsDirectory != _unset) {
        await _offlineStorage.updateStorageLocations(
          downloadsDirectory: downloadsDirectory,
        );
      }
      await loadOfflineStorageLocations();
      await _offlineDownloadManager.load();
      _pushMessage(message);
    } catch (err) {
      _pushMessage('Failed to update offline storage: $err');
    }
  }

  void loginWithToken({required String baseUrl, required String token}) {
    _statsServerId = _statsUserId = null;
    _listeningSessionContext = null;
    _audio?.configureListening(null, discardPending: false);
    final resetStatsAccount = _listeningStats.storageError == null
        ? _listeningStats.setAccount()
        : Future<void>.value();
    connection.setBaseUrl(baseUrl);
    connection.setToken(token);
    _serverHealthFailureCount = 0;
    _setAuthorized(true, error: null);
    () async {
      await resetStatsAccount;
      final playingTrack = _playbackState.track;
      if (!_disposed && playingTrack != null) {
        _prepareListeningSession(
          playingTrack,
          newSession: true,
          updateActive: true,
        );
      }
      await _refreshLocalStats();
      await _refreshServerPorts();
      await _loadPlaybackSettings();
      await _offlineDownloadManager.resumePausedForCurrentServer();
      unawaited(_offlineDownloadManager.repairOfflineMetadataFragments());
    }();
  }

  Future<bool> probeServer(String input) async {
    _setSessionStatus(SessionStatus.checking, error: null);
    try {
      final resolved = await connection.resolveBaseUrl(input);
      await connection.verifyServerConnection(resolved);
      if (_disposed) return false;
      connection.setBaseUrl(resolved);
      _serverHealthFailureCount = 0;
      // Reachability is confirmed; OPAQUE sign-in authenticates the account and
      // establishes server trust before any credentials or tokens can be used.
      _setSessionStatus(SessionStatus.serverReachable, error: null);
      return true;
    } catch (err) {
      final message = err.toString();
      _setSessionStatus(SessionStatus.offline, error: message);
      _pushMessage(
        'Server connection failed: $message',
        level: LogLevel.warning,
      );
      return false;
    }
  }

  Future<void> logout({bool clearSaved = true}) async {
    final serverBaseUrl = connection.baseUrl;
    final preserveLocalPlayback =
        _playbackState.isLocalPlayback && _playbackState.track != null;
    _stopMetadataEventListener();
    _beginBestEffortServerLogout();
    _pauseDownloadsForDisconnectedServer(serverBaseUrl);
    connection.setToken(null);
    _serverHealthFailureCount = 0;
    _serverReconnectAttempt = 0;
    _setSessionStatus(SessionStatus.offline, error: null);
    await _detachListeningAccount();
    _quicPort = null;
    if (preserveLocalPlayback) {
      _closeStreamControl();
    } else {
      _clearPlaybackForServerDisconnect();
    }
    if (clearSaved) {
      await _clearSavedCredentials();
    }
  }

  Future<void> resetUserPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (!canResetUserPassword) {
      throw PasswordChangeException(
        'Connect to your authenticated server before resetting your password.',
      );
    }
    final baseUrl = connection.baseUrl;
    final token = connection.token;
    final revision = connection.sessionRevision;
    bool sessionIsCurrent() =>
        connection.baseUrl == baseUrl &&
        connection.token == token &&
        connection.sessionRevision == revision;
    _resettingUserPassword = true;
    try {
      await connection.changeOwnPassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      if (!sessionIsCurrent()) {
        throw PasswordChangeException(
          'Your server session changed. Return to settings before resetting your password.',
        );
      }
    } on PasswordChangeException catch (error) {
      if (error.requiresSignIn && sessionIsCurrent()) {
        await _signOutAfterPasswordReset();
      }
      rethrow;
    } finally {
      _resettingUserPassword = false;
    }
  }

  Future<void> _signOutAfterPasswordReset() async {
    // Invalidate restoration before the first await. An expired/revoked session
    // cannot authorize logout, so there is no additional request to send.
    _restoreSessionRevision++;
    _restoringSession = false;
    final serverBaseUrl = connection.baseUrl;
    connection.setToken(null);
    final disconnectedRevision = connection.sessionRevision;
    final clearSaved = _clearSavedCredentials();
    if (_disposed) {
      await clearSaved;
      return;
    }
    final preserveLocalPlayback =
        _playbackState.isLocalPlayback && _playbackState.track != null;
    _stopMetadataEventListener();
    _pauseDownloadsForDisconnectedServer(serverBaseUrl);
    _serverHealthFailureCount = 0;
    _serverReconnectAttempt = 0;
    _setSessionStatus(SessionStatus.offline, error: null);
    _quicPort = null;
    if (preserveLocalPlayback) {
      _closeStreamControl();
    } else {
      _clearPlaybackForServerDisconnect();
    }
    await _detachListeningAccount(
      expectedSessionRevision: disconnectedRevision,
    );
    await clearSaved;
  }

  void _beginBestEffortServerLogout() {
    if (connection.token?.isNotEmpty != true) {
      return;
    }
    unawaited(() async {
      try {
        await connection.logout(timeout: _serverLogoutBestEffortTimeout);
      } catch (err) {
        AppLogger.debug('Server logout skipped after local disconnect: $err');
      }
    }());
  }

  void _pauseDownloadsForDisconnectedServer(String serverBaseUrl) {
    unawaited(() async {
      try {
        await _offlineDownloadManager.pauseDownloadsForServer(serverBaseUrl);
      } catch (err) {
        if (_disposed) {
          return;
        }
        _pushMessage(
          'Failed to pause server downloads after disconnect: $err',
          level: LogLevel.warning,
        );
      }
    }());
  }

  void _clearPlaybackForServerDisconnect() {
    _resetTrackTransitionState();
    _audioEngine.stop();
    _playQueue = <Track>[];
    _playIndex = 0;
    _queueShuffleMode = ShuffleMode.off;
    _queueShuffleScope = null;
    _queueShuffleArtistId = null;
    _queueShuffleAlbumId = null;
    _queueShufflePlaylistId = null;
    _offlineQueueSource = _OfflineQueueSource.none;
    _lastStartPlaybackAt = null;
    _lastStartPlaybackTrackId = null;
    _lastStartPlaybackOffsetMs = null;
    _audioOutputStarted = false;
    _updatePlayback(
      track: null,
      isPlaying: false,
      isLoading: false,
      position: Duration.zero,
      duration: Duration.zero,
      bufferRatio: 0.0,
      bitrateKbps: null,
      streamConnected: false,
      streamRttMs: null,
      isLocalPlayback: false,
      queueSource: PlaybackQueueSource.none,
      queueSourcePlaylistId: null,
      localPlaybackSource: LocalPlaybackSource.none,
    );
    _clearNowPlaying();
  }

  Future<AuthCredentials?> loadSavedCredentials() async {
    if (_savedCredentialsInvalidated) {
      return null;
    }
    if (_savedCredentials != null) {
      return _savedCredentials;
    }
    final credentials = await _authStorage.read();
    if (_savedCredentialsInvalidated) {
      return null;
    }
    _savedCredentials = credentials;
    return credentials;
  }

  Future<void> restoreSession() async {
    if (_restoringSession || _authState.isAuthorized) {
      return;
    }
    _restoringSession = true;
    final revision = ++_restoreSessionRevision;
    _setSessionStatus(SessionStatus.checking, error: null);
    try {
      await _restoreSessionInternal(
        revision,
      ).timeout(storedSessionRestoreTimeout);
    } on TimeoutException {
      if (_isRestoreSessionCurrent(revision)) {
        _pushMessage(
          'Auto-login timed out after ${storedSessionRestoreTimeout.inSeconds}s.',
          level: LogLevel.warning,
        );
        _setSessionStatus(
          SessionStatus.serverUnavailable,
          error: 'Saved server unavailable',
        );
      }
    } finally {
      if (_isRestoreSessionCurrent(revision)) {
        _restoringSession = false;
      }
    }
  }

  Future<void> startFreshLoginFlow() async {
    _restoreSessionRevision++;
    _restoringSession = false;
    await logout(clearSaved: true);
    connection.setBaseUrl(_initialBaseUrl);
    _setAuthorized(false, error: null);
  }

  bool _isRestoreSessionCurrent(int revision) {
    return !_disposed && _restoreSessionRevision == revision;
  }

  Future<void> _restoreSessionInternal(int revision) async {
    final credentials = await loadSavedCredentials();
    if (!_isRestoreSessionCurrent(revision) || credentials == null) {
      if (_isRestoreSessionCurrent(revision)) {
        _setSessionStatus(SessionStatus.offline, error: null);
      }
      return;
    }

    connection.setBaseUrl(credentials.baseUrl);
    if (credentials.token.trim().isEmpty) {
      await _clearSavedCredentials();
      connection.setToken(null);
      _setSessionStatus(SessionStatus.offline, error: null);
      return;
    }

    connection.setTrust(credentials.trust);
    connection.setToken(credentials.token);
    if (_listeningStats.storageError == null &&
        credentials.serverId != null &&
        credentials.userId != null) {
      _statsServerId = credentials.serverId;
      _statsUserId = credentials.userId;
      await _listeningStats.setAccount(
        serverId: credentials.serverId,
        userId: credentials.userId,
      );
      if (!_isRestoreSessionCurrent(revision)) return;
      await _refreshLocalStats();
    }
    try {
      final settings = await connection.fetchPlaybackSettings(
        timeout: _storedSessionRequestTimeout,
        retryable: false,
      );
      if (!_isRestoreSessionCurrent(revision)) {
        return;
      }
      _updatePlayback(repeatMode: _parseRepeatMode(settings.repeatMode));
      _serverHealthFailureCount = 0;
      _setAuthorized(true, error: null);
      unawaited(_offlineDownloadManager.resumePausedForCurrentServer());
      unawaited(_offlineDownloadManager.repairOfflineMetadataFragments());
      unawaited(
        _refreshServerPorts(
          timeout: _storedSessionRequestTimeout,
          retryable: false,
        ),
      );
    } on ApiException catch (err) {
      if (!_isRestoreSessionCurrent(revision)) {
        return;
      }
      _pushMessage('Auto-login failed: ${_formatApiError(err)}');
      if (err.statusCode == 401) {
        connection.setToken(null);
        final detach = _detachListeningAccount();
        await _clearSavedCredentials();
        await detach;
        if (!_isRestoreSessionCurrent(revision)) return;
        _setSessionStatus(SessionStatus.offline, error: 'Saved login expired');
      } else {
        _setSessionStatus(
          SessionStatus.serverUnavailable,
          error: 'Saved server unavailable',
        );
      }
    } catch (err) {
      if (!_isRestoreSessionCurrent(revision)) {
        return;
      }
      _pushMessage('Auto-login failed: $err');
      _setSessionStatus(
        SessionStatus.serverUnavailable,
        error: 'Saved server unavailable',
      );
    }
  }

  Future<void> _storeSavedCredentials(AuthCredentials credentials) async {
    _savedCredentialsInvalidated = false;
    _savedCredentials = credentials;
    await _queueSavedCredentialsWrite(() => _authStorage.write(credentials));
  }

  Future<void> _clearSavedCredentials() async {
    _savedCredentialsInvalidated = true;
    _savedCredentials = null;
    await _queueSavedCredentialsWrite(_authStorage.clear);
  }

  Future<void> _queueSavedCredentialsWrite(Future<void> Function() operation) {
    // A newly remembered session must be written after an earlier sign-out's
    // deletion, even when the platform secure storage operations finish late.
    final pending = _savedCredentialsWriteChain
        .catchError((Object _) {})
        .then((_) => operation());
    _savedCredentialsWriteChain = pending;
    return pending;
  }

  void _configureLocalNetworkPermissions() {
    if (!_localNetworkPermissions.isSupported) {
      return;
    }
    _localNetworkPermissions.setStatusHandler((status) {
      _handleLocalNetworkPermissionStatus(status);
    });
    _refreshLocalNetworkPermission();
  }

  Future<void> _refreshLocalNetworkPermission() async {
    try {
      await _localNetworkPermissions.refreshPermission();
      _handleLocalNetworkPermissionStatus(
        await _localNetworkPermissions.getPermission(),
      );
    } catch (_) {}
  }

  void _handleLocalNetworkPermissionStatus(String status) {
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
  }

  void _setLocalNetworkPermission(LocalNetworkPermissionState value) {
    if (_disposed) return;
    if (_localNetworkPermissionState == value) {
      return;
    }
    _localNetworkPermissionState = value;
    _localNetworkPermissionController.add(value);
  }

  void _configureNowPlaying() {
    if (!_nowPlayingPlatform.isSupported) {
      return;
    }
    _nowPlayingReady = true;
    _nowPlayingPlatform.setRemoteCommandHandler((command) async {
      if (_disposed) return;
      switch (command.type) {
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
        case 'toggleLike':
          final track = _playbackState.track;
          if (track != null) {
            await toggleLike(track);
          }
          break;
        case 'startLibraryShuffle':
          updateShuffleMode(ShuffleMode.all, scope: ActionScope.server);
          await pause(false);
          break;
        case 'seek':
          final raw = command.arguments['position'];
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

  void _configureCarPlay() {
    if (!_vehicleSurface.isSupported) {
      return;
    }
    _vehicleSurface.setMethodHandler((method, args) async {
      if (_disposed) return null;
      switch (method) {
        case 'getCarPlayState':
          return _carPlayGetState();
        case 'getHomeActions':
          return _carPlayGetLegacyHomeActions();
        case 'getAuthState':
          return {
            'authorized': _authState.isAuthorized,
            'hasSession': _authState.hasSession,
            'status': _authState.status.name,
          };
        case 'getArtists':
          return _carPlayGetArtists(_carPlayScope(args));
        case 'getAlbums':
          final artistId = args['artistId']?.toString() ?? '';
          return _carPlayGetAlbums(_carPlayScope(args), artistId);
        case 'getPlaylists':
          return _carPlayGetPlaylists(_carPlayScope(args));
        case 'getLibraryStatus':
          return _carPlayGetLibraryStatus(_carPlayScope(args));
        case 'playAlbum':
          final albumId = args['albumId']?.toString() ?? '';
          return _carPlayPlayAlbum(_carPlayScope(args), albumId);
        case 'playPlaylist':
          final playlistId = args['playlistId']?.toString() ?? '';
          return _carPlayPlayPlaylist(_carPlayScope(args), playlistId);
        case 'playLiked':
          return _carPlayPlayLiked(_carPlayScope(args));
        case 'startShuffle':
          final kind = args['kind']?.toString() ?? 'library';
          return _carPlayStartShuffle(
            _carPlayScope(args),
            kind,
            artistId: args['artistId']?.toString(),
            albumId: args['albumId']?.toString(),
            playlistId: args['playlistId']?.toString(),
          );
        case 'startLibraryShuffle':
          return _carPlayStartShuffle('server', 'library');
        case 'startLikedShuffle':
          return _carPlayStartShuffle('server', 'liked');
        case 'startCustomShuffle':
          return _carPlayStartShuffle('server', 'custom');
        default:
          return null;
      }
    });
    _notifyCarPlayState();
  }

  void _notifyCarPlayAuthState(bool authorized) {
    _notifyCarPlayState();
  }

  void _scheduleCarPlayStateUpdate() {
    if (_disposed) return;
    if (!_vehicleSurface.isSupported) {
      return;
    }
    _carPlayStateDebounce?.cancel();
    _carPlayStateDebounce = Timer(
      const Duration(milliseconds: 250),
      _notifyCarPlayState,
    );
  }

  void _notifyCarPlayState() {
    if (_disposed) return;
    if (!_vehicleSurface.isSupported) {
      return;
    }
    final payload = _carPlayStatePayload();
    _vehicleSurface.notifyState(payload).catchError((_) {});
    _vehicleSurface
        .notifyAuthorization(payload['serverAvailable'] == true)
        .catchError((_) {});
  }

  Map<String, dynamic> _carPlayOk() => const {'ok': true};

  Map<String, dynamic> _carPlayError(String code) => {
    'error': code,
    'items': const [],
  };

  Map<String, dynamic>? _carPlayServerAvailabilityError() {
    if (_authState.isAuthorized) {
      return null;
    }
    return _carPlayError(
      _authState.status == SessionStatus.serverUnavailable
          ? 'server_unavailable'
          : 'unauthorized',
    );
  }

  Map<String, dynamic> _carPlayList(List<Map<String, dynamic>> items) => {
    'items': items,
  };

  String _carPlayScope(Map<String, dynamic> args) {
    return args['scope']?.toString() == 'local' ? 'local' : 'server';
  }

  Future<Map<String, dynamic>> _carPlayGetState() async {
    if (_authState.status == SessionStatus.serverUnavailable) {
      unawaited(
        _triggerImmediateServerReconnect(reason: 'vehicle state request'),
      );
    }
    await _offlineDownloadManager.load();
    return _carPlayStatePayload();
  }

  Map<String, dynamic> _carPlayStatePayload() {
    final serverAvailable = _authState.isAuthorized;
    final localAvailable = offlineTracks.isNotEmpty;
    return {
      'serverAvailable': serverAvailable,
      'localAvailable': localAvailable,
      'hasAnySource': serverAvailable || localAvailable,
    };
  }

  Future<Map<String, dynamic>> _carPlayGetArtists(String scope) async {
    if (scope == 'local') {
      await _offlineDownloadManager.load();
      final groups = offlineLibrarySnapshot.artistGroups;
      final items = groups
          .map(
            (group) => {
              'id': group.id,
              'title': group.name,
              'subtitle':
                  '${group.soloAlbums.length} albums'
                  '${group.collabAlbums.isEmpty ? '' : ' · ${group.collabAlbums.length} collab albums'}',
              if (_carPlayFileUrl(group.coverPath) != null)
                'artworkUrl': _carPlayFileUrl(group.coverPath),
            },
          )
          .toList();
      return _carPlayList(items);
    }
    final serverError = _carPlayServerAvailabilityError();
    if (serverError != null) {
      return serverError;
    }
    if (_artists.isEmpty && !_artistsLoading) {
      await loadArtists();
    }
    final items = _artists
        .map(
          (artist) => {
            'id': artist.id,
            'title': artist.name,
            'subtitle':
                '${artist.releaseCount} albums'
                '${artist.collabAlbumCount == 0 ? '' : ' · ${artist.collabAlbumCount} collab albums'}',
          },
        )
        .toList();
    return _carPlayList(items);
  }

  Future<Map<String, dynamic>> _carPlayGetLegacyHomeActions() async {
    if (!_authState.isAuthorized) {
      final unavailable = _authState.status == SessionStatus.serverUnavailable;
      return _carPlayList([
        {
          'id': 'startLibraryShuffle',
          'title': 'Start Library Shuffle',
          'subtitle': unavailable
              ? 'Server unavailable'
              : 'Connect to a server',
          'enabled': false,
        },
        {
          'id': 'startLikedShuffle',
          'title': 'Start Liked Shuffle',
          'subtitle': unavailable
              ? 'Server unavailable'
              : 'Connect to a server',
          'enabled': false,
        },
        {
          'id': 'startCustomShuffle',
          'title': 'Start Custom Shuffle',
          'subtitle': unavailable
              ? 'Server unavailable'
              : 'Connect to a server',
          'enabled': false,
        },
      ]);
    }

    final actions = <Map<String, dynamic>>[
      {
        'id': 'startLibraryShuffle',
        'title': 'Start Library Shuffle',
        'subtitle': 'Shuffle all tracks',
        'enabled': true,
      },
    ];

    var liked = _liked;
    if (liked.isEmpty) {
      try {
        liked = await connection.fetchLikedTracks();
      } catch (_) {
        liked = const <Track>[];
      }
    }
    actions.add({
      'id': 'startLikedShuffle',
      'title': 'Start Liked Shuffle',
      'subtitle': liked.isNotEmpty
          ? 'Shuffle liked songs'
          : 'No liked songs yet',
      'enabled': liked.isNotEmpty,
    });

    await _ensureCustomShuffleSettingsLoaded();
    final customReady =
        _customShuffleSettings.artistIds.isNotEmpty ||
        _customShuffleSettings.genres.isNotEmpty;
    actions.add({
      'id': 'startCustomShuffle',
      'title': 'Start Custom Shuffle',
      'subtitle': customReady
          ? 'Shuffle with your rules'
          : 'Set up custom shuffle',
      'enabled': customReady,
    });

    return _carPlayList(actions);
  }

  Future<Map<String, dynamic>> _carPlayGetAlbums(
    String scope,
    String artistId,
  ) async {
    if (scope == 'local') {
      await _offlineDownloadManager.load();
      final group = _carPlayLocalArtistGroup(artistId);
      if (group == null) {
        return _carPlayError('missing_artist');
      }
      final items = group.albums
          .map(
            (album) => {
              'id': album.id,
              'title': album.title,
              'subtitle': album.metadata?.year != null
                  ? album.metadata!.year.toString()
                  : '${album.tracks.length} tracks',
              if (_carPlayFileUrl(album.coverPath) != null)
                'artworkUrl': _carPlayFileUrl(album.coverPath),
            },
          )
          .toList();
      return _carPlayList(items);
    }
    final serverError = _carPlayServerAvailabilityError();
    if (serverError != null) {
      return serverError;
    }
    if (artistId.isEmpty) {
      return _carPlayError('missing_artist');
    }
    await loadAlbums(artistId);
    final token = connection.token ?? '';
    final items = _albums
        .map(
          (album) => {
            'id': album.id,
            'title': album.title,
            'subtitle': album.year != null
                ? album.year.toString()
                : '${album.trackCount} tracks',
            'artworkUrl': connection.buildAlbumCoverUrl(album.id),
            'token': token,
            'serverPin': connection.trust?.spki,
          },
        )
        .toList();
    return _carPlayList(items);
  }

  Future<Map<String, dynamic>> _carPlayGetPlaylists(String scope) async {
    if (scope == 'local') {
      await loadLocalPlaylists();
      final items = localPlaylists
          .map(
            (playlist) => {
              'id': playlist.id,
              'title': playlist.name,
              'subtitle': '${playlist.trackIds.length} tracks',
            },
          )
          .toList();
      return _carPlayList(items);
    }
    final serverError = _carPlayServerAvailabilityError();
    if (serverError != null) {
      return serverError;
    }
    if (_playlists.isEmpty) {
      await loadPlaylists();
    }
    final items = _playlists
        .map(
          (playlist) => {
            'id': playlist.id,
            'title': playlist.name,
            'subtitle': '${playlist.trackIds.length} tracks',
          },
        )
        .toList();
    return _carPlayList(items);
  }

  Future<Map<String, dynamic>> _carPlayGetLibraryStatus(String scope) async {
    if (scope == 'local') {
      if (localLiked.isEmpty) {
        await loadLocalLikedTracks();
      }
      return {'likedAvailable': localLiked.isNotEmpty};
    }
    final serverError = _carPlayServerAvailabilityError();
    if (serverError != null) {
      return {'likedAvailable': false, 'error': serverError['error']};
    }
    final liked = await _carPlayServerLikedTracks();
    return {'likedAvailable': liked.isNotEmpty};
  }

  Future<Map<String, dynamic>> _carPlayPlayAlbum(
    String scope,
    String albumId,
  ) async {
    if (albumId.isEmpty) {
      return _carPlayError('missing_album');
    }
    if (scope == 'local') {
      await _offlineDownloadManager.load();
      final album = _carPlayLocalAlbumGroup(albumId);
      if (album == null || album.tracks.isEmpty) {
        return _carPlayError('missing_album');
      }
      updateShuffleMode(ShuffleMode.off, scope: ActionScope.local);
      await playOfflineTrack(album.tracks.first.id, tracks: album.tracks);
      return _carPlayOk();
    }
    final serverError = _carPlayServerAvailabilityError();
    if (serverError != null) {
      return serverError;
    }
    updateShuffleMode(ShuffleMode.off, scope: ActionScope.server);
    await queueAlbum(albumId);
    return _carPlayOk();
  }

  Future<Map<String, dynamic>> _carPlayPlayPlaylist(
    String scope,
    String playlistId,
  ) async {
    if (playlistId.isEmpty) {
      return _carPlayError('missing_playlist');
    }
    if (scope == 'local') {
      updateShuffleMode(ShuffleMode.off, scope: ActionScope.local);
      await playLocalPlaylistFromTop(playlistId);
      return _carPlayOk();
    }
    final serverError = _carPlayServerAvailabilityError();
    if (serverError != null) {
      return serverError;
    }
    updateShuffleMode(ShuffleMode.off, scope: ActionScope.server);
    await queuePlaylist(playlistId);
    return _carPlayOk();
  }

  Future<Map<String, dynamic>> _carPlayPlayLiked(String scope) async {
    if (scope == 'local') {
      if (localLiked.isEmpty) {
        await loadLocalLikedTracks();
      }
      if (localLiked.isEmpty) {
        return _carPlayError('liked_empty');
      }
      updateShuffleMode(ShuffleMode.off, scope: ActionScope.local);
      await playLocalLikedTrack(localLiked.first.id);
      return _carPlayOk();
    }
    final serverError = _carPlayServerAvailabilityError();
    if (serverError != null) {
      return serverError;
    }
    updateShuffleMode(ShuffleMode.off, scope: ActionScope.server);
    await queueLiked();
    return _carPlayOk();
  }

  Future<Map<String, dynamic>> _carPlayStartShuffle(
    String scope,
    String kind, {
    String? artistId,
    String? albumId,
    String? playlistId,
  }) async {
    if (scope == 'local') {
      if (kind == 'custom') {
        await _ensureCustomShuffleSettingsLoaded();
        if (_customShuffleSettings.localArtistIds.isEmpty &&
            _customShuffleSettings.localGenres.isEmpty) {
          return _carPlayError('custom_empty');
        }
      }
      final mode = switch (kind) {
        'artist' => ShuffleMode.artist,
        'album' => ShuffleMode.album,
        'playlist' => ShuffleMode.currentPlaylist,
        'custom' => ShuffleMode.custom,
        'liked' => ShuffleMode.liked,
        _ => ShuffleMode.all,
      };
      updateShuffleMode(mode, scope: ActionScope.local);
      await queueLocalShuffle(
        playlistId: playlistId,
        artistId: artistId,
        albumId: albumId,
        play: true,
      );
      return _carPlayOk();
    }

    final serverError = _carPlayServerAvailabilityError();
    if (serverError != null) {
      return serverError;
    }

    if (kind == 'custom') {
      await _ensureCustomShuffleSettingsLoaded();
      if (_customShuffleSettings.artistIds.isEmpty &&
          _customShuffleSettings.genres.isEmpty) {
        return _carPlayError('custom_empty');
      }
      updateShuffleMode(ShuffleMode.custom, scope: ActionScope.server);
      await queueShuffle(scope: 'library', play: true);
      return _carPlayOk();
    }

    if (kind == 'liked') {
      updateShuffleMode(ShuffleMode.liked, scope: ActionScope.server);
      await queueShuffle(scope: 'liked', play: true);
      return _carPlayOk();
    }

    updateShuffleMode(ShuffleMode.all, scope: ActionScope.server);
    await queueShuffle(scope: 'library', play: true);
    return _carPlayOk();
  }

  Future<List<Track>> _carPlayServerLikedTracks() async {
    if (!_authState.isAuthorized) {
      return const <Track>[];
    }
    if (_liked.isNotEmpty) {
      return _liked;
    }
    try {
      return await connection.fetchLikedTracks();
    } catch (_) {
      return const <Track>[];
    }
  }

  OfflineArtistGroup? _carPlayLocalArtistGroup(String artistId) {
    return _localLibrary.artist(artistId);
  }

  OfflineAlbumGroup? _carPlayLocalAlbumGroup(String albumId) {
    return _localLibrary.album(albumId);
  }

  String? _carPlayFileUrl(String? path) {
    final trimmed = path?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return Uri.file(trimmed).toString();
  }

  Future<void> _clearNowPlaying() async {
    _artwork.clear();
    if (!_nowPlayingPlatform.isSupported) {
      return;
    }
    try {
      await _nowPlayingPlatform.clearNowPlaying();
    } catch (_) {}
  }

  Future<void> _pushNowPlayingUpdate({bool force = false}) async {
    if (_disposed) return;
    if (!_nowPlayingPlatform.isSupported || !_nowPlayingReady) {
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
    final artworkUrl = albumId.isNotEmpty && !_playbackState.isLocalPlayback
        ? connection.buildAlbumCoverUrl(albumId)
        : null;
    final localArtworkPath = _playbackState.isLocalPlayback
        ? track.albumArtPath?.trim()
        : null;
    final token = connection.token ?? '';
    _maybeLoadNowPlayingArtwork(
      artworkUrl: artworkUrl,
      localPath: localArtworkPath,
      token: token,
    );

    final payload = <String, dynamic>{
      'epoch': _nowPlayingEpoch,
      'trackId': track.id,
      'title': track.title,
      'artist': track.artist,
      'album': track.album,
      'duration': durationMs / 1000.0,
      'position': positionMs / 1000.0,
      'isPlaying': nowPlayingIsPlaying,
      'liked': track.liked,
      'artworkKey': _artwork.key ?? '',
      // Let iOS load artwork even when Flutter's image decoder is suspended
      // while the lock screen or CarPlay is in use.
      if (artworkUrl != null) 'artworkUrl': artworkUrl,
      if (artworkUrl != null) 'token': token,
      if (artworkUrl != null) 'serverPin': connection.trust?.spki,
      if (localArtworkPath != null) 'artworkPath': localArtworkPath,
    };
    final artworkBytes = _artwork.bytes;
    if (artworkBytes != null) {
      payload['artworkBytes'] = artworkBytes;
    }
    try {
      await _nowPlayingPlatform.setNowPlaying(payload);
      _lastNowPlayingSentAt = now;
      _lastNowPlayingTrackId = track.id;
      _lastNowPlayingIsPlaying = nowPlayingIsPlaying;
      _lastNowPlayingPositionMs = positionMs;
      _lastNowPlayingEpochSent = _nowPlayingEpoch;
    } catch (_) {}
  }

  void _maybeLoadNowPlayingArtwork({
    required String? artworkUrl,
    required String? localPath,
    required String token,
  }) {
    if (!_nowPlayingPlatform.isSupported || _disposed) return;
    unawaited(
      _artwork.load(url: artworkUrl, localPath: localPath, token: token).then((
        changed,
      ) async {
        if (changed && !_disposed) await _pushNowPlayingUpdate(force: true);
      }),
    );
  }

  Future<void> loadArtists({bool refresh = false}) async {
    if (!_requireServer('loading artists')) {
      return;
    }
    if (refresh && _artistsPageCompleter != null) {
      await _artistsPageCompleter!.future;
    }
    if (refresh) {
      _artistsRequestEpoch++;
      _artists = <Artist>[];
      _artistsOffset = 0;
      _artistsHasMore = true;
      _artistsController.add(List.unmodifiable(_artists));
    }
    if (_artists.isNotEmpty || !_artistsHasMore) {
      return;
    }
    await loadMoreArtists();
  }

  Future<void> loadMoreArtists() async {
    if (!_requireServer('loading artists')) {
      return;
    }
    if (!_artistsHasMore) {
      return;
    }
    final inFlight = _artistsPageCompleter;
    if (inFlight != null) {
      await inFlight.future;
      return;
    }
    final completer = Completer<void>();
    final requestEpoch = _artistsRequestEpoch;
    final sessionRevision = connection.sessionRevision;
    _artistsPageCompleter = completer;
    const pageSize = ServerConnection.artistsPageSize;
    _setArtistsLoading(true);
    try {
      final page = await connection.fetchArtistsPage(
        limit: pageSize,
        offset: _artistsOffset,
        includeContributors: false,
      );
      if (_disposed ||
          sessionRevision != connection.sessionRevision ||
          requestEpoch != _artistsRequestEpoch) {
        return;
      }
      if (page.isEmpty) {
        _artistsHasMore = false;
        if (_artistsOffset == 0) {
          _artists = <Artist>[];
          _artistsController.add(List.unmodifiable(_artists));
        }
        return;
      }
      _artists = [..._artists, ...page];
      _artistsOffset += page.length;
      _artistsHasMore = page.length == pageSize;
      _artistsController.add(List.unmodifiable(_artists));
    } on ApiException catch (err) {
      if (_disposed ||
          sessionRevision != connection.sessionRevision ||
          requestEpoch != _artistsRequestEpoch) {
        return;
      }
      _handleApiError(err, context: 'artists');
    } catch (err) {
      if (_disposed ||
          sessionRevision != connection.sessionRevision ||
          requestEpoch != _artistsRequestEpoch) {
        return;
      }
      _pushMessage('Failed to load artists: $err', level: LogLevel.warning);
    } finally {
      if (identical(_artistsPageCompleter, completer)) {
        _artistsPageCompleter = null;
      }
      if (!completer.isCompleted) {
        completer.complete();
      }
      _setArtistsLoading(false);
    }
  }

  Future<void> loadAllArtists() async {
    await loadArtists();
    while (_artistsHasMore) {
      await loadMoreArtists();
    }
  }

  Future<void> loadArtistReleases(String artistId) async {
    if (!_requireServer('loading artist releases')) return;
    final epoch = ++_artistReleasesRequestEpoch;
    final sessionRevision = connection.sessionRevision;
    _lastArtistId = artistId;
    _artistReleasesArtistId = artistId;
    _artistReleases = const ArtistReleases();
    _albums = [];
    _artistReleasesController.add(_artistReleases);
    _albumsController.add(const []);
    _setAlbumsLoading(true);
    try {
      final fetched = await connection.fetchArtistReleases(artistId);
      if (_disposed ||
          epoch != _artistReleasesRequestEpoch ||
          sessionRevision != connection.sessionRevision) {
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
        _cacheAlbumId(album: album);
      }
      _albumsController.add(List.unmodifiable(_albums));
      _artistReleasesController.add(_artistReleases);
      final artistIndex = _artists.indexWhere(
        (artist) => artist.id == artistId,
      );
      if (artistIndex >= 0) {
        final updated = _artists[artistIndex].copyWith(
          albumCount: _artistReleases.albums.length,
          collabAlbumCount: _artistReleases.collabAlbums.length,
          appearanceCount: _artistReleases.appearsOn.length,
          otherCreditCount: _artistReleases.otherCredits.length,
          releaseCount: _artistReleases.releaseCount,
        );
        _artists = [..._artists]..[artistIndex] = updated;
        _artistsController.add(List.unmodifiable(_artists));
        _artistUpdatesController.add(updated);
      }
    } on ApiException catch (err) {
      if (_disposed ||
          epoch != _artistReleasesRequestEpoch ||
          sessionRevision != connection.sessionRevision) {
        return;
      }
      _handleApiError(err, context: 'artist releases');
    } catch (err) {
      if (_disposed ||
          epoch != _artistReleasesRequestEpoch ||
          sessionRevision != connection.sessionRevision) {
        return;
      }
      _pushMessage(
        'Failed to load artist releases: $err',
        level: LogLevel.warning,
      );
    } finally {
      if (epoch == _artistReleasesRequestEpoch) _setAlbumsLoading(false);
    }
  }

  Future<void> loadAlbums(String artistId) async {
    if (!_requireServer('loading albums')) {
      return;
    }
    _setAlbumsLoading(true);
    try {
      _lastArtistId = artistId;
      _albums = <Album>[];
      _albumsController.add(List.unmodifiable(_albums));
      _albums = _sortAlbumsByReleaseYear(
        await connection.fetchAlbums(artistId),
      );
      for (final album in _albums) {
        _cacheAlbumId(album: album);
      }
      _albumsController.add(List.unmodifiable(_albums));
    } on ApiException catch (err) {
      _handleApiError(err, context: 'albums');
    } catch (err) {
      _pushMessage('Failed to load albums: $err', level: LogLevel.warning);
    } finally {
      _setAlbumsLoading(false);
    }
  }

  Future<void> loadTracks(String albumId) async {
    if (!_requireServer('loading tracks')) {
      return;
    }
    _setTracksLoading(true);
    try {
      _lastAlbumId = albumId;
      _tracks = <Track>[];
      _tracksController.add(List.unmodifiable(_tracks));
      _tracks = await connection.fetchTracks(albumId);
      for (final track in _tracks) {
        _cacheTrackAlbumId(track, fallbackAlbumId: albumId);
      }
      _tracksController.add(List.unmodifiable(_tracks));
    } on ApiException catch (err) {
      _handleApiError(err, context: 'tracks');
    } catch (err) {
      _pushMessage('Failed to load tracks: $err', level: LogLevel.warning);
    } finally {
      _setTracksLoading(false);
    }
  }

  Future<void> loadPlaylists() async {
    if (!_requireServer('loading playlists')) {
      return;
    }
    try {
      _playlists = await connection.fetchPlaylists();
      _playlistsController.add(List.unmodifiable(_playlists));
    } on ApiException catch (err) {
      _handleApiError(err, context: 'playlists');
    } catch (err) {
      _pushMessage('Failed to load playlists: $err', level: LogLevel.warning);
    }
  }

  Future<void> loadLocalPlaylists() async {
    await _offlineDownloadManager.loadLocalPlaylists();
  }

  Future<void> loadPlaylistTracks(String playlistId) async {
    if (!_requireServer('loading playlist tracks')) {
      return;
    }
    final requestId = ++_playlistTracksRequestId;
    final changedPlaylist = _currentPlaylistId != playlistId;
    _currentPlaylistId = playlistId;
    if (changedPlaylist && _playlistTracks.isNotEmpty) {
      _playlistTracks = <Track>[];
      _playlistTracksController.add(List.unmodifiable(_playlistTracks));
    }
    try {
      final tracks = await connection.fetchPlaylistTracks(playlistId);
      if (requestId != _playlistTracksRequestId ||
          _currentPlaylistId != playlistId) {
        return;
      }
      _playlistTracks = tracks;
      for (final track in _playlistTracks) {
        _cacheTrackAlbumId(track);
      }
      _playlistTracksController.add(List.unmodifiable(_playlistTracks));
    } on ApiException catch (err) {
      if (requestId != _playlistTracksRequestId ||
          _currentPlaylistId != playlistId) {
        return;
      }
      _handleApiError(err, context: 'playlist tracks');
    } catch (err) {
      if (requestId != _playlistTracksRequestId ||
          _currentPlaylistId != playlistId) {
        return;
      }
      _pushMessage(
        'Failed to load playlist tracks: $err',
        level: LogLevel.warning,
      );
    }
  }

  Future<void> loadLocalPlaylistTracks(String playlistId) async {
    await _offlineDownloadManager.loadLocalPlaylistTracks(playlistId);
  }

  Future<void> loadLikedTracks() async {
    if (!_requireServer('loading liked tracks')) {
      return;
    }
    try {
      _liked = await connection.fetchLikedTracks();
      for (final track in _liked) {
        _cacheTrackAlbumId(track);
      }
      _likedController.add(List.unmodifiable(_liked));
    } on ApiException catch (err) {
      _handleApiError(err, context: 'liked tracks');
    } catch (err) {
      _pushMessage(
        'Failed to load liked tracks: $err',
        level: LogLevel.warning,
      );
    }
  }

  Future<void> loadLocalLikedTracks() async {
    await _offlineDownloadManager.loadLocalLikedTracks();
  }

  Future<void> playLikedTrack(String trackId) async {
    await queueLiked(startTrackId: trackId);
  }

  Future<void> playLocalLikedTrack(String trackId) async {
    final tracks = localLiked;
    if (tracks.isEmpty) {
      await loadLocalLikedTracks();
    }
    await playOfflineTrack(trackId, tracks: localLiked, localLikedQueue: true);
  }

  Future<void> queueLocalPlaylist(
    String playlistId, {
    String? startTrackId,
  }) async {
    if (_playbackState.shuffleMode != ShuffleMode.off) {
      if (_playbackState.shuffleScope == ActionScope.local) {
        await queueLocalShuffle(
          playlistId: _playbackState.shuffleMode == ShuffleMode.currentPlaylist
              ? playlistId
              : null,
          startTrackId: startTrackId,
        );
        return;
      }
      updateShuffleMode(ShuffleMode.off, scope: ActionScope.local);
    }
    await loadLocalPlaylistTracks(playlistId);
    final tracks = localPlaylistTracks;
    if (tracks.isEmpty) {
      _pushMessage('No downloaded tracks found for local playlist');
      return;
    }
    _setQueue(
      tracks,
      startTrackId: startTrackId,
      queueSource: PlaybackQueueSource.offline,
      queueSourcePlaylistId: playlistId,
      offlineQueueSource: _OfflineQueueSource.localPlaylist,
    );
    _queueShuffleMode = ShuffleMode.off;
    _queueShuffleScope = null;
    _armAutoAdvanceGuard();
    await _playCurrent();
  }

  Future<void> playLocalPlaylistFromTop(String playlistId) async {
    if (_playbackState.shuffleMode != ShuffleMode.off) {
      updateShuffleMode(ShuffleMode.off, scope: ActionScope.local);
    }
    await queueLocalPlaylist(playlistId);
  }

  Future<void> playOfflineTrack(
    String trackId, {
    List<Track>? tracks,
    bool localLikedQueue = false,
  }) async {
    if (_playbackState.shuffleMode != ShuffleMode.off) {
      if (_playbackState.shuffleScope == ActionScope.local) {
        final mode = _playbackState.shuffleMode;
        if (await _localShuffleCanStartFromTrack(mode, trackId)) {
          await queueLocalShuffle(startTrackId: trackId);
          return;
        }
      }
      updateShuffleMode(ShuffleMode.off, scope: ActionScope.local);
    }
    final available = <String, Track>{
      for (final track in offlineTracks) track.id: track,
      for (final download in availableOfflineDownloads) ...{
        download.track.id: download.track,
        if (download.localTrackId != null)
          download.localTrackId!: download.track.copyWith(
            id: download.localTrackId!,
            localId: download.localTrackId,
            serverBaseUrl: download.serverBaseUrl,
            serverTrackId: download.track.serverTrackId ?? download.track.id,
          ),
      },
    };
    final queue = (tracks ?? available.values.toList())
        .where(
          (track) =>
              available.containsKey(track.id) ||
              (track.localId != null && available.containsKey(track.localId)),
        )
        .toList(growable: false);
    if (queue.isEmpty || !available.containsKey(trackId)) {
      _pushMessage('Downloaded track is not available on this device.');
      return;
    }
    _setQueue(
      queue,
      startTrackId: trackId,
      queueSource: PlaybackQueueSource.offline,
      offlineQueueSource: localLikedQueue
          ? _OfflineQueueSource.localLiked
          : _OfflineQueueSource.tracks,
    );
    _queueShuffleMode = ShuffleMode.off;
    _queueShuffleScope = null;
    _armAutoAdvanceGuard();
    await _playCurrent();
  }

  Future<bool> _localShuffleCanStartFromTrack(
    ShuffleMode mode,
    String trackId,
  ) async {
    switch (mode) {
      case ShuffleMode.all:
      case ShuffleMode.artist:
      case ShuffleMode.album:
        return _localLibrary.track(trackId) != null;
      case ShuffleMode.liked:
        return _localTrackIsLiked(trackId);
      case ShuffleMode.custom:
        await _ensureCustomShuffleSettingsLoaded();
        final track = _localLibrary.track(trackId);
        if (track == null) {
          return false;
        }
        final artistIds = _customShuffleSettings.localArtistIds.toSet();
        final genres = _customShuffleSettings.localGenres
            .map((genre) => genre.toLowerCase())
            .toSet();
        if (artistIds.isEmpty && genres.isEmpty) {
          return false;
        }
        return _localLibrary.matchesCustomShuffle(
          track,
          artistIds: artistIds,
          genres: genres,
        );
      case ShuffleMode.currentPlaylist:
      case ShuffleMode.off:
        return false;
    }
  }

  Future<void> loadStats({int? year, int? month}) async {
    if (_disposed) return;
    _stats = StatsResponse(
      year: year ?? _stats?.year ?? DateTime.now().toUtc().year,
      month: month,
      totalMinutes: _stats?.totalMinutes ?? 0,
      totalListeningMs: _stats?.totalListeningMs ?? 0,
      totalPlays: _stats?.totalPlays ?? 0,
      uniqueTracks: _stats?.uniqueTracks ?? 0,
      uniqueArtists: _stats?.uniqueArtists ?? 0,
      otherGenreListeningMs: _stats?.otherGenreListeningMs ?? 0,
      unclassifiedListeningMs: _stats?.unclassifiedListeningMs ?? 0,
      topArtists: _stats?.topArtists ?? [],
      topTracks: _stats?.topTracks ?? [],
      topGenres: _stats?.topGenres ?? [],
    );
    await _refreshLocalStats();
    unawaited(_repairListeningGenreMetadata());
    await _listeningSync?.sync(immediate: true);
    await _refreshLocalStats();
  }

  Future<void> _repairListeningGenreMetadata() {
    final running = _statsGenreRepair;
    if (running != null) return running;
    final work = _resolveListeningGenreMetadata().catchError((Object error) {
      if (!_disposed) {
        _pushMessage(
          'Listening genre metadata could not be refreshed: $error',
          level: LogLevel.debug,
        );
      }
    });
    _statsGenreRepair = work;
    return work.whenComplete(() {
      if (identical(_statsGenreRepair, work)) _statsGenreRepair = null;
    });
  }

  Future<void> _resolveListeningGenreMetadata() async {
    if (_disposed || _listeningStats.storageError != null) return;
    final scope = _listeningStats.accountScope;
    final generation = _listeningStats.historyGeneration;
    final revision = connection.sessionRevision;
    final server = connection.baseUrl;
    bool current() =>
        !_disposed &&
        scope == _listeningStats.accountScope &&
        generation == _listeningStats.historyGeneration &&
        revision == connection.sessionRevision;
    final key = (scope, generation, revision);
    if (_statsGenreRepairCursorKey != key) {
      _statsGenreRepairCursorKey = key;
      _statsGenreRepairAfterTrackId = null;
    }
    var candidates = await _listeningStats.genreMetadataCandidateEvents(
      afterTrackId: _statsGenreRepairAfterTrackId,
    );
    if (current() &&
        candidates.isEmpty &&
        _statsGenreRepairAfterTrackId != null) {
      _statsGenreRepairAfterTrackId = null;
      candidates = await _listeningStats.genreMetadataCandidateEvents();
    }
    if (!current() || candidates.isEmpty) return;
    final cached = <String, Track>{};
    for (final track in [
      if (scope != 'local') ...[
        ..._tracks,
        ..._playlistTracks,
        ..._liked,
        ..._playQueue,
      ],
      ...offlineLibrarySnapshot.tracks,
    ]) {
      // In-memory catalog tracks without an origin can survive a connection
      // switch. Only downloads with a known matching origin are authoritative.
      if (scope != 'local' && track.serverBaseUrl != server) {
        continue;
      }
      cached[track.serverTrackId ?? track.id] = track;
    }
    final albums = <String, Future<Album>>{};
    Future<Album> album(String id) =>
        albums.putIfAbsent(id, () => connection.fetchAlbumById(id));
    List<String> genres(Track track, {Album? release}) {
      final useCatalog =
          scope != 'local' &&
          (track.serverBaseUrl == null || track.serverBaseUrl == server);
      return ListeningEvent.fromTrack(
        track: track,
        sessionId: '',
        deviceId: '',
        sessionStartedAtMs: 0,
        startedAtMs: 0,
        endedAtMs: 0,
        listenedMs: 0,
        eventId: '',
        cachedAlbums: [
          if (release != null) release,
          if (useCatalog) ..._albums,
        ],
        cachedArtists: useCatalog ? _artists : const [],
      ).genres;
    }

    Future<MapEntry<String, List<String>>?> resolve(
      ListeningEvent saved,
    ) async {
      if (!current()) return null;
      final known = cached[saved.trackId];
      if (known != null &&
          (known.listeningGenres.isNotEmpty ||
              known.offlineAlbum?.genres.isNotEmpty == true)) {
        return MapEntry(saved.trackId, genres(known));
      }
      if (scope == 'local' || !_authState.isAuthorized) return null;
      try {
        final track = await connection.fetchTrackById(saved.trackId);
        if (!current()) return null;
        Album? release;
        if (track.listeningGenres.isEmpty &&
            track.albumId?.isNotEmpty == true) {
          try {
            release = await album(track.albumId!);
          } on ApiException catch (albumError) {
            if (albumError.statusCode != 404) rethrow;
          }
        }
        return MapEntry(saved.trackId, genres(track, release: release));
      } on ApiException catch (error) {
        if (error.statusCode != 404) rethrow;
        if (saved.albumId.isEmpty || !current()) return null;
        // A removed recording can still have its identified release in the
        // catalog. Never match unrelated releases or artists by display name.
        try {
          final release = await album(saved.albumId);
          if (release.id == saved.albumId && release.genres.isNotEmpty) {
            return MapEntry(saved.trackId, release.genres);
          }
        } on ApiException catch (albumError) {
          if (albumError.statusCode != 404) rethrow;
        }
        return null;
      }
    }

    // A screen refresh repairs at most 50 historical tracks. Existing maps
    // persist. The cursor advances past missing recordings and wraps so that
    // temporary failures can be retried without starving later recordings.
    final metadata = <String, List<String>>{};
    var failed = 0;
    Object? lastError;
    Future<MapEntry<String, List<String>>?> resolveSafely(
      ListeningEvent saved,
    ) async {
      try {
        return await resolve(saved);
      } catch (error) {
        failed++;
        lastError = error;
        return null;
      }
    }

    try {
      for (
        var offset = 0;
        offset < candidates.length && current();
        offset += 4
      ) {
        final batch = candidates.skip(offset).take(4);
        final results = await Future.wait(batch.map(resolveSafely));
        if (!current()) return;
        for (final entry in results) {
          if (entry != null) metadata[entry.key] = entry.value;
        }
      }
      if (current()) {
        _statsGenreRepairAfterTrackId = candidates.last.trackId;
        if (failed > 0) {
          _pushMessage(
            'Genre metadata refresh skipped $failed recordings: $lastError',
            level: LogLevel.debug,
          );
        }
      }
    } finally {
      if (current() && metadata.isNotEmpty) {
        await _listeningStats.updateGenreMetadata(
          metadata,
          scope: scope,
          generation: generation,
        );
      }
    }
  }

  Future<void> search(String query, {String filter = 'all'}) async {
    final trimmed = query.trim();
    final requestId = ++_searchRequestId;
    if (!_authState.isAuthorized) {
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
      final results = await connection.search(trimmed, filter: filter);
      if (requestId != _searchRequestId) {
        return;
      }
      _search = results;
      _searchController.add(List.unmodifiable(_search));
    } on ApiException catch (err) {
      if (requestId != _searchRequestId) {
        return;
      }
      _handleApiError(err, context: 'search');
    } catch (err) {
      if (requestId != _searchRequestId) {
        return;
      }
      _pushMessage('Search failed: $err');
    } finally {
      if (requestId == _searchRequestId) {
        _setSearchLoading(false);
      }
    }
  }

  Future<void> selectSearchResult(SearchResult result) async {
    if (!_requireServer('opening search results')) {
      return;
    }
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
    if (_shouldUseLocalUserData(track)) {
      await toggleLocalLike(track);
      return;
    }
    if (!_requireServer('updating likes')) {
      return;
    }
    try {
      final liked = !track.liked;
      final state = await connection.setLikeState(track.id, liked);
      _updateLike(track.id, state?.liked ?? liked, knownTrack: track);
      await _pushNowPlayingUpdate(force: true);
    } on ApiException catch (err) {
      _handleApiError(err, context: 'like');
    } catch (err) {
      _pushMessage('Failed to update like: $err');
    }
  }

  Future<void> toggleLocalLike(Track track) async {
    final localId = _localTrackIdFor(track);
    if (localId == null) {
      _pushMessage(
        'Download ${track.title} before saving it to local liked songs.',
        level: LogLevel.warning,
      );
      return;
    }
    final currentlyLiked =
        track.liked ||
        localLiked.any((item) => item.localId == localId || item.id == localId);
    try {
      await _offlineDownloadManager.setLocalLike(track, !currentlyLiked);
      _updateLocalLike(localId, !currentlyLiked);
      await _pushNowPlayingUpdate(force: true);
    } catch (err) {
      _pushMessage('Failed to update local like: $err');
    }
  }

  Future<void> createPlaylist(
    String name, {
    String? description,
    PlaylistImageEdit imageEdit = const PlaylistImageEdit.keep(),
  }) async {
    if (!_requireServer('creating playlists')) {
      return;
    }
    try {
      var playlist = await connection.createPlaylist(
        name,
        description: description,
      );
      _playlists = [..._playlists, playlist];
      _playlistsController.add(List.unmodifiable(_playlists));
      playlist = await _applyServerPlaylistImageEdit(playlist, imageEdit);
      _replaceServerPlaylist(playlist);
    } on ApiException catch (err) {
      _handleApiError(err, context: 'create playlist');
    } catch (err) {
      _pushMessage('Failed to create playlist: $err');
    }
  }

  Future<void> createLocalPlaylist(
    String name, {
    String? description,
    PlaylistImageEdit imageEdit = const PlaylistImageEdit.keep(),
  }) async {
    try {
      final playlist = await _offlineDownloadManager.createLocalPlaylist(
        name,
        description: description,
      );
      if (imageEdit.kind != PlaylistImageEditKind.keep) {
        await _offlineDownloadManager.updateLocalPlaylistImage(
          playlist.id,
          imageEdit,
        );
      }
    } catch (err) {
      _pushMessage('Failed to create local playlist: $err');
    }
  }

  Future<void> renamePlaylist(
    String playlistId,
    String name, {
    String? description,
    PlaylistImageEdit imageEdit = const PlaylistImageEdit.keep(),
  }) async {
    if (!_requireServer('renaming playlists')) {
      return;
    }
    try {
      var updated = await connection.renamePlaylist(
        playlistId,
        name,
        description: description,
      );
      _replaceServerPlaylist(updated);
      updated = await _applyServerPlaylistImageEdit(updated, imageEdit);
      _replaceServerPlaylist(updated);
    } on ApiException catch (err) {
      _handleApiError(err, context: 'rename playlist');
    } catch (err) {
      _pushMessage('Failed to rename playlist: $err');
    }
  }

  Future<void> renameLocalPlaylist(
    String playlistId,
    String name, {
    String? description,
    PlaylistImageEdit imageEdit = const PlaylistImageEdit.keep(),
  }) async {
    try {
      await _offlineDownloadManager.renameLocalPlaylist(
        playlistId,
        name,
        description: description,
      );
      if (imageEdit.kind != PlaylistImageEditKind.keep) {
        await _offlineDownloadManager.updateLocalPlaylistImage(
          playlistId,
          imageEdit,
        );
      }
    } catch (err) {
      _pushMessage('Failed to rename local playlist: $err');
    }
  }

  Future<Playlist> _applyServerPlaylistImageEdit(
    Playlist playlist,
    PlaylistImageEdit imageEdit,
  ) {
    return switch (imageEdit.kind) {
      PlaylistImageEditKind.keep => Future.value(playlist),
      PlaylistImageEditKind.clear =>
        playlist.imageRef == null
            ? Future.value(playlist)
            : connection.deletePlaylistCover(playlist.id),
      PlaylistImageEditKind.replace => connection.uploadPlaylistCover(
        playlist.id,
        imageEdit.bytes ?? const <int>[],
        imageEdit.contentType ?? 'application/octet-stream',
      ),
    };
  }

  void _replaceServerPlaylist(Playlist updated) {
    _playlists = _playlists
        .map((playlist) => playlist.id == updated.id ? updated : playlist)
        .toList();
    _playlistsController.add(List.unmodifiable(_playlists));
  }

  Future<void> deletePlaylist(String playlistId) async {
    if (!_requireServer('deleting playlists')) {
      return;
    }
    try {
      await connection.deletePlaylist(playlistId);
      _playlists = _playlists
          .where((playlist) => playlist.id != playlistId)
          .toList();
      _playlistsController.add(List.unmodifiable(_playlists));
      if (_currentPlaylistId == playlistId) {
        _currentPlaylistId = null;
        _playlistTracks = <Track>[];
        _playlistTracksController.add(List.unmodifiable(_playlistTracks));
      }
    } on ApiException catch (err) {
      _handleApiError(err, context: 'delete playlist');
    } catch (err) {
      _pushMessage('Failed to delete playlist: $err');
    }
  }

  Future<void> deleteLocalPlaylist(String playlistId) async {
    try {
      await _offlineDownloadManager.deleteLocalPlaylist(playlistId);
    } catch (err) {
      _pushMessage('Failed to delete local playlist: $err');
    }
  }

  Future<void> updatePlaylistTracks(
    String playlistId,
    List<String> trackIds,
  ) async {
    if (!_requireServer('updating playlists')) {
      return;
    }
    try {
      final updated = await connection.updatePlaylistTracks(
        playlistId,
        trackIds,
      );
      _playlists = _playlists
          .map((playlist) => playlist.id == updated.id ? updated : playlist)
          .toList();
      _playlistsController.add(List.unmodifiable(_playlists));
    } on ApiException catch (err) {
      _handleApiError(err, context: 'update playlist');
    } catch (err) {
      _pushMessage('Failed to update playlist: $err');
    }
  }

  Future<void> addTrackToPlaylist(Playlist playlist, Track track) async {
    if (!_requireServer('updating playlists')) {
      return;
    }
    try {
      final resolved = _playlists.firstWhere(
        (item) => item.id == playlist.id,
        orElse: () => playlist,
      );
      if (resolved.trackIds.contains(track.id)) {
        _pushMessage('Track already in playlist: ${resolved.name}');
        return;
      }
      final updatedIds = [...resolved.trackIds, track.id];
      final updated = await connection.updatePlaylistTracks(
        resolved.id,
        updatedIds,
      );
      _playlists = _playlists
          .map((item) => item.id == updated.id ? updated : item)
          .toList();
      _playlistsController.add(List.unmodifiable(_playlists));
      if (_currentPlaylistId == resolved.id) {
        final exists = _playlistTracks.any((item) => item.id == track.id);
        if (!exists) {
          _playlistTracks = [..._playlistTracks, track];
          _playlistTracksController.add(List.unmodifiable(_playlistTracks));
        }
      }
      _pushMessage('Added to playlist: ${resolved.name}');
    } on ApiException catch (err) {
      _handleApiError(err, context: 'update playlist');
    } catch (err) {
      _pushMessage('Failed to update playlist: $err');
    }
  }

  Future<void> addTrackToLocalPlaylist(Playlist playlist, Track track) async {
    if (_localTrackIdFor(track) == null) {
      _pushMessage(
        'Download ${track.title} before adding it to a local playlist.',
        level: LogLevel.warning,
      );
      return;
    }
    try {
      final updated = await _offlineDownloadManager.addLocalTrackToPlaylist(
        playlist,
        track,
      );
      if (updated != null) {
        _pushMessage('Added to local playlist: ${updated.name}');
      }
    } catch (err) {
      _pushMessage('Failed to update local playlist: $err');
    }
  }

  Future<void> removeTrackFromPlaylist(Playlist playlist, Track track) async {
    if (!_requireServer('updating playlists')) {
      return;
    }
    try {
      final resolved = _playlists.firstWhere(
        (item) => item.id == playlist.id,
        orElse: () => playlist,
      );
      if (!resolved.trackIds.contains(track.id)) {
        _pushMessage('Track not in playlist: ${resolved.name}');
        return;
      }
      final updatedIds = resolved.trackIds
          .where((id) => id != track.id)
          .toList();
      final updated = await connection.updatePlaylistTracks(
        resolved.id,
        updatedIds,
      );
      _playlists = _playlists
          .map((item) => item.id == updated.id ? updated : item)
          .toList();
      _playlistsController.add(List.unmodifiable(_playlists));
      if (_currentPlaylistId == resolved.id) {
        _playlistTracks = _playlistTracks
            .where((item) => item.id != track.id)
            .toList();
        _playlistTracksController.add(List.unmodifiable(_playlistTracks));
      }
      _pushMessage('Removed from playlist: ${resolved.name}');
    } on ApiException catch (err) {
      _handleApiError(err, context: 'update playlist');
    } catch (err) {
      _pushMessage('Failed to update playlist: $err');
    }
  }

  Future<void> removeTrackFromLocalPlaylist(
    Playlist playlist,
    Track track,
  ) async {
    try {
      final updated = await _offlineDownloadManager
          .removeLocalTrackFromPlaylist(playlist, track);
      if (updated != null) {
        _pushMessage('Removed from local playlist: ${updated.name}');
      }
    } catch (err) {
      _pushMessage('Failed to update local playlist: $err');
    }
  }

  Future<void> queueAlbum(String albumId, {String? startTrackId}) async {
    if (!_requireServer('playing albums from the server')) {
      return;
    }
    try {
      if (_playbackState.shuffleMode != ShuffleMode.off &&
          _playbackState.shuffleScope != ActionScope.server) {
        updateShuffleMode(ShuffleMode.off, scope: ActionScope.server);
      }
      if (startTrackId != null) {
        await _maybeDisableShuffleForTrackSelection(startTrackId);
        if (_playbackState.shuffleMode != ShuffleMode.off &&
            _playbackState.shuffleMode != ShuffleMode.liked) {
          updateShuffleMode(ShuffleMode.off, scope: ActionScope.server);
        }
      }
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
      _pushMessage(
        'Queue album: $albumId${startTrackId == null ? '' : ' (start $startTrackId)'}',
      );
      final tracks = _lastAlbumId == albumId && _tracks.isNotEmpty
          ? List<Track>.of(_tracks)
          : await connection.fetchTracks(albumId);
      if (tracks.isEmpty) {
        _pushMessage('No tracks found for album');
        return;
      }
      final normalized = tracks
          .map(
            (track) => (track.albumId == null || track.albumId!.isEmpty)
                ? track.copyWith(albumId: albumId)
                : track,
          )
          .toList();
      _setQueue(
        normalized,
        startTrackId: startTrackId,
        queueSource: PlaybackQueueSource.none,
      );
      _armAutoAdvanceGuard();
      await _playCurrent();
    } on ApiException catch (err) {
      _handleApiError(err, context: 'queue album');
    } catch (err) {
      _pushMessage('Failed to queue album: $err');
    }
  }

  Future<void> queuePlaylist(String playlistId, {String? startTrackId}) async {
    if (!_requireServer('playing playlists from the server')) {
      return;
    }
    try {
      if (_playbackState.shuffleMode != ShuffleMode.off &&
          _playbackState.shuffleScope != ActionScope.server) {
        updateShuffleMode(ShuffleMode.off, scope: ActionScope.server);
      }
      if (startTrackId != null) {
        await _maybeDisableShuffleForTrackSelection(startTrackId);
      }
      if (_playbackState.shuffleMode != ShuffleMode.off) {
        if (_playbackState.shuffleMode == ShuffleMode.all) {
          await queueShuffle(scope: 'library', startTrackId: startTrackId);
          return;
        }
        if ((_playbackState.shuffleMode == ShuffleMode.album ||
                _playbackState.shuffleMode == ShuffleMode.artist) &&
            startTrackId != null) {
          final context = await _resolveAlbumArtistForTrack(startTrackId);
          await queueShuffle(
            scope: 'library',
            artistId: context.artistId,
            albumId: context.albumId,
            startTrackId: startTrackId,
            queueSourceOverride: PlaybackQueueSource.playlist,
            queueSourcePlaylistIdOverride: playlistId,
          );
          if (_playQueue.isNotEmpty) {
            _updatePlayback(
              queueSource: PlaybackQueueSource.playlist,
              queueSourcePlaylistId: playlistId,
              nowPlaying: false,
            );
          }
        } else {
          await queueShuffle(
            scope: 'playlist',
            playlistId: playlistId,
            startTrackId: startTrackId,
            queueSourceOverride: PlaybackQueueSource.playlist,
            queueSourcePlaylistIdOverride: playlistId,
          );
          if (_playQueue.isNotEmpty) {
            _updatePlayback(
              queueSource: PlaybackQueueSource.playlist,
              queueSourcePlaylistId: playlistId,
              nowPlaying: false,
            );
          }
        }
        return;
      }
      _pushMessage(
        'Queue playlist: $playlistId${startTrackId == null ? '' : ' (start $startTrackId)'}',
      );
      final tracks =
          (_currentPlaylistId == playlistId && _playlistTracks.isNotEmpty)
          ? _playlistTracks
          : await connection.fetchPlaylistTracks(playlistId);
      if (tracks.isEmpty) {
        _pushMessage('No tracks found for playlist');
        return;
      }
      final normalized = _normalizeQueueTracks(tracks);
      _setQueue(
        normalized,
        startTrackId: startTrackId,
        queueSource: PlaybackQueueSource.playlist,
        queueSourcePlaylistId: playlistId,
      );
      _armAutoAdvanceGuard();
      await _playCurrent();
    } on ApiException catch (err) {
      _handleApiError(err, context: 'queue playlist');
    } catch (err) {
      _pushMessage('Failed to queue playlist: $err');
    }
  }

  Future<void> playPlaylistFromTop(String playlistId) async {
    if (_playbackState.shuffleMode != ShuffleMode.off) {
      updateShuffleMode(ShuffleMode.off, scope: ActionScope.server);
    }
    await queuePlaylist(playlistId);
  }

  Future<void> queueLiked({String? startTrackId}) async {
    if (!_requireServer('playing liked songs from the server')) {
      return;
    }
    try {
      if (_playbackState.shuffleMode != ShuffleMode.off &&
          _playbackState.shuffleScope != ActionScope.server) {
        updateShuffleMode(ShuffleMode.off, scope: ActionScope.server);
      }
      if (_playbackState.shuffleMode != ShuffleMode.off &&
          _playbackState.shuffleMode != ShuffleMode.liked) {
        updateShuffleMode(ShuffleMode.off, scope: ActionScope.server);
      }
      if (_playbackState.shuffleMode != ShuffleMode.liked) {
        _queueShuffleMode = ShuffleMode.off;
        _queueShuffleScope = null;
        _queueShuffleArtistId = null;
        _queueShuffleAlbumId = null;
        _queueShufflePlaylistId = null;
      }
      if (startTrackId != null) {
        await _maybeDisableShuffleForTrackSelection(startTrackId);
      }
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
            queueSourceOverride: PlaybackQueueSource.liked,
          );
        } else {
          await queueShuffle(
            scope: 'liked',
            startTrackId: startTrackId,
            queueSourceOverride: PlaybackQueueSource.liked,
          );
        }
        return;
      }
      _pushMessage(
        'Queue liked${startTrackId == null ? '' : ' (start $startTrackId)'}',
      );
      final tracks = _liked.isNotEmpty
          ? _liked
          : await connection.fetchLikedTracks();
      if (tracks.isEmpty) {
        _pushMessage('No liked tracks found');
        return;
      }
      final normalized = _normalizeQueueTracks(tracks);
      _setQueue(
        normalized,
        startTrackId: startTrackId,
        queueSource: PlaybackQueueSource.liked,
      );
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
    PlaybackQueueSource? queueSourceOverride,
    String? queueSourcePlaylistIdOverride,
  }) {
    return queueServerShuffle(
      scope: scope,
      playlistId: playlistId,
      artistId: artistId,
      albumId: albumId,
      play: play,
      startTrackId: startTrackId,
      queueSourceOverride: queueSourceOverride,
      queueSourcePlaylistIdOverride: queueSourcePlaylistIdOverride,
    );
  }

  Future<void> queueServerShuffle({
    required String scope,
    String? playlistId,
    String? artistId,
    String? albumId,
    bool play = true,
    String? startTrackId,
    PlaybackQueueSource? queueSourceOverride,
    String? queueSourcePlaylistIdOverride,
  }) async {
    if (!_requireServer('starting server shuffle')) {
      return;
    }
    try {
      if (_playbackState.shuffleMode == ShuffleMode.off) {
        _pushMessage('Shuffle is off');
        return;
      }
      if (_playbackState.shuffleScope != ActionScope.server) {
        _pushMessage('Server shuffle requires a server playback scope');
        return;
      }

      final queueSource =
          queueSourceOverride ??
          (scope == 'playlist'
              ? PlaybackQueueSource.playlist
              : scope == 'liked'
              ? PlaybackQueueSource.liked
              : _playbackState.shuffleMode == ShuffleMode.liked
              ? PlaybackQueueSource.liked
              : PlaybackQueueSource.none);
      final queueSourcePlaylistId = queueSource == PlaybackQueueSource.playlist
          ? (queueSourcePlaylistIdOverride ?? playlistId)
          : null;

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
        final normalized = _normalizeQueueTracks(_shuffleTracks(tracks));
        _setQueue(
          normalized,
          startTrackId: startTrackId,
          queueSource: queueSource,
          queueSourcePlaylistId: queueSourcePlaylistId,
        );
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
        final normalized = _normalizeQueueTracks(_shuffleTracks(tracks));
        _setQueue(
          normalized,
          startTrackId: startTrackId,
          queueSource: queueSource,
          queueSourcePlaylistId: queueSourcePlaylistId,
        );
        _armAutoAdvanceGuard();
        if (play) {
          await _playCurrent();
        }
        return;
      }

      if (_playbackState.shuffleMode == ShuffleMode.artist &&
          artistId == null) {
        _pushMessage('Select an artist to shuffle');
        return;
      }
      if (_playbackState.shuffleMode == ShuffleMode.album && albumId == null) {
        _pushMessage('Select an album to shuffle');
        return;
      }

      final mode = _shuffleQueryMode(_playbackState.shuffleMode);
      final isCustom = _playbackState.shuffleMode == ShuffleMode.custom;
      if (isCustom) {
        await _ensureCustomShuffleSettingsLoaded();
      }
      final customArtistIds = isCustom
          ? _customShuffleSettings.artistIds
          : null;
      final customGenres = isCustom ? _customShuffleSettings.genres : null;
      if (isCustom &&
          (customArtistIds == null || customArtistIds.isEmpty) &&
          (customGenres == null || customGenres.isEmpty)) {
        _pushMessage('Custom shuffle has no filters; using full library.');
      }
      final tracks = await connection.fetchShuffleTracks(
        mode: mode,
        artistId: artistId,
        albumId: albumId,
        artistIds: customArtistIds,
        genres: customGenres,
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
      _setQueue(
        _shuffleTracks(tracks),
        startTrackId: startTrackId,
        queueSource: queueSource,
        queueSourcePlaylistId: queueSourcePlaylistId,
      );
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

  Future<void> queueLocalShuffle({
    String? playlistId,
    String? artistId,
    String? albumId,
    bool play = true,
    String? startTrackId,
  }) async {
    try {
      final mode = _playbackState.shuffleMode;
      if (mode == ShuffleMode.off) {
        _pushMessage('Shuffle is off');
        return;
      }
      if (_playbackState.shuffleScope != ActionScope.local) {
        _pushMessage('Local shuffle requires a local playback scope');
        return;
      }

      List<Track> tracks;
      _OfflineQueueSource offlineSource;
      String? sourcePlaylistId;
      String contextScope;
      String? contextArtistId;
      String? contextAlbumId;

      if (mode == ShuffleMode.currentPlaylist) {
        sourcePlaylistId =
            playlistId ??
            (_playbackState.queueSource == PlaybackQueueSource.offline
                ? _playbackState.queueSourcePlaylistId
                : null);
        if (sourcePlaylistId == null || sourcePlaylistId.isEmpty) {
          _pushMessage('Select a local playlist to shuffle');
          return;
        }
        await loadLocalPlaylistTracks(sourcePlaylistId);
        tracks = localPlaylistTracks;
        offlineSource = _OfflineQueueSource.localPlaylist;
        contextScope = 'localPlaylist';
      } else if (mode == ShuffleMode.liked) {
        if (localLiked.isEmpty) {
          await loadLocalLikedTracks();
        }
        tracks = localLiked;
        offlineSource = _OfflineQueueSource.localLiked;
        contextScope = 'localLiked';
      } else if (mode == ShuffleMode.artist) {
        contextArtistId = _resolveLocalShuffleArtistId(
          startTrackId: startTrackId,
          artistId: artistId,
        );
        if (contextArtistId == null || contextArtistId.isEmpty) {
          _pushMessage('Select a local artist to shuffle');
          return;
        }
        final group = _localLibrary.artist(contextArtistId);
        if (group == null) {
          _pushMessage('No downloaded tracks found for local artist');
          return;
        }
        tracks = group.tracksForArtist;
        offlineSource = _OfflineQueueSource.tracks;
        contextScope = 'localArtist';
      } else if (mode == ShuffleMode.album) {
        contextAlbumId = _resolveLocalShuffleAlbumId(
          startTrackId: startTrackId,
          albumId: albumId,
        );
        if (contextAlbumId == null || contextAlbumId.isEmpty) {
          _pushMessage('Select a local album to shuffle');
          return;
        }
        final group = _localLibrary.album(contextAlbumId);
        if (group == null) {
          _pushMessage('No downloaded tracks found for local album');
          return;
        }
        tracks = group.tracks;
        offlineSource = _OfflineQueueSource.tracks;
        contextScope = 'localAlbum';
      } else if (mode == ShuffleMode.custom) {
        await _ensureCustomShuffleSettingsLoaded();
        final artistIds = _customShuffleSettings.localArtistIds.toSet();
        final genres = _customShuffleSettings.localGenres
            .map((genre) => genre.toLowerCase())
            .toSet();
        if (artistIds.isEmpty && genres.isEmpty) {
          _pushMessage('Local custom shuffle has no filters.');
          return;
        }
        tracks = offlineTracks
            .where(
              (track) => _localLibrary.matchesCustomShuffle(
                track,
                artistIds: artistIds,
                genres: genres,
              ),
            )
            .toList(growable: false);
        offlineSource = _OfflineQueueSource.tracks;
        contextScope = 'localCustom';
      } else {
        tracks = offlineTracks;
        offlineSource = _OfflineQueueSource.tracks;
        contextScope = 'localLibrary';
      }

      if (tracks.isEmpty) {
        _pushMessage('No downloaded tracks found for shuffle');
        return;
      }

      _rememberShuffleContext(
        scope: contextScope,
        playlistId: sourcePlaylistId,
        artistId: contextArtistId,
        albumId: contextAlbumId,
      );
      _setQueue(
        _shuffleTracks(tracks),
        startTrackId: startTrackId,
        queueSource: PlaybackQueueSource.offline,
        queueSourcePlaylistId: sourcePlaylistId,
        offlineQueueSource: offlineSource,
      );
      _armAutoAdvanceGuard();
      if (play) {
        await _playCurrent();
      }
    } catch (err) {
      _pushMessage('Failed to queue local shuffle: $err');
    }
  }

  String? _resolveLocalShuffleArtistId({
    String? startTrackId,
    String? artistId,
  }) {
    final fromStart = _localLibrary.artistForTrackId(startTrackId)?.id;
    if (fromStart != null && fromStart.isNotEmpty) {
      return fromStart;
    }
    final current = _playbackState.track;
    if (current != null) {
      final fromCurrent = _localLibrary.artistForTrack(current)?.id;
      if (fromCurrent != null && fromCurrent.isNotEmpty) {
        return fromCurrent;
      }
    }
    final explicit = artistId?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }
    if (_queueShuffleScope == 'localArtist' &&
        _queueShuffleArtistId != null &&
        _queueShuffleArtistId!.isNotEmpty) {
      return _queueShuffleArtistId;
    }
    return null;
  }

  String? _resolveLocalShuffleAlbumId({String? startTrackId, String? albumId}) {
    final fromStart = _localLibrary.albumForTrackId(startTrackId)?.id;
    if (fromStart != null && fromStart.isNotEmpty) {
      return fromStart;
    }
    final current = _playbackState.track;
    if (current != null) {
      final fromCurrent = _localLibrary.albumForTrack(current)?.id;
      if (fromCurrent != null && fromCurrent.isNotEmpty) {
        return fromCurrent;
      }
    }
    final explicit = albumId?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }
    if (_queueShuffleScope == 'localAlbum' &&
        _queueShuffleAlbumId != null &&
        _queueShuffleAlbumId!.isNotEmpty) {
      return _queueShuffleAlbumId;
    }
    return null;
  }

  LocalLibrarySelection get _localLibrary => LocalLibrarySelection(
    tracks: offlineTracks,
    artists: offlineLibrarySnapshot.artistGroups,
  );

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
      } else if (_playbackState.queueSource == PlaybackQueueSource.offline &&
          _playQueue.isEmpty) {
        _pushMessage('No queue to advance');
        return;
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
      } else if (_playbackState.queueSource == PlaybackQueueSource.offline &&
          _playQueue.isEmpty) {
        _pushMessage('No queue to rewind');
        return;
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
      _playIndex = (_playIndex - 1) < 0
          ? _playQueue.length - 1
          : _playIndex - 1;
      await _playCurrent();
    } on ApiException catch (err) {
      _handleApiError(err, context: 'previous track');
    } catch (err) {
      _pushMessage('Failed to move to previous track: $err');
    }
  }

  Future<void> stop() async {
    try {
      _resetTrackTransitionState();
      _listeningSessionContext = null;
      final shouldDisableShuffle =
          _playbackState.shuffleScope == ActionScope.local ||
          _playbackState.shuffleMode == ShuffleMode.album ||
          _playbackState.shuffleMode == ShuffleMode.artist ||
          _playbackState.shuffleMode == ShuffleMode.currentPlaylist;
      _playQueue = <Track>[];
      _playIndex = 0;
      _queueShuffleMode = ShuffleMode.off;
      _queueShuffleScope = null;
      _queueShuffleArtistId = null;
      _queueShuffleAlbumId = null;
      _queueShufflePlaylistId = null;
      _offlineQueueSource = _OfflineQueueSource.none;
      _updatePlayback(
        track: null,
        isPlaying: false,
        isLoading: false,
        position: Duration.zero,
        duration: Duration.zero,
        bufferRatio: 0.0,
        bitrateKbps: null,
        isLocalPlayback: false,
        shuffleMode: shouldDisableShuffle ? ShuffleMode.off : null,
        queueSource: PlaybackQueueSource.none,
        queueSourcePlaylistId: null,
      );
      _audioEngine.stop();
      _audioOutputStarted = false;
      _closeStreamControl();
    } on ApiException catch (err) {
      _handleApiError(err, context: 'stop');
    } catch (err) {
      _pushMessage('Failed to stop: $err');
    }
  }

  Future<void> pause(bool paused) async {
    try {
      _wantsPlayback = !paused;
      _awaitingStreamReconnect = false;
      _streamRecoveryTimer?.cancel();
      _streamRecoveryTimer = null;
      if (!paused) {
        if (_playbackState.track == null) {
          final shuffleEnabled = _playbackState.shuffleMode != ShuffleMode.off;
          if (shuffleEnabled) {
            final started = await _ensureShuffleQueue(play: true);
            if (!started) {
              _wantsPlayback = false;
              _updatePlayback(isPlaying: false);
            }
          } else {
            _pushMessage('No track selected');
            _wantsPlayback = false;
            _updatePlayback(isPlaying: false);
          }
          return;
        }
      }

      _updatePlayback(isPlaying: !paused, isLoading: paused ? false : null);
      if (paused) {
        _audioEngine.pause();
      } else if (_playbackState.track != null) {
        if (!_audioEngine.hasActivePlayer) {
          _lastInterruptedStreamRestartAt = null;
          _startPlayback(
            _playbackState.track!,
            startOffset: _playbackState.position,
          );
        } else {
          _audioEngine.resume();
        }
      }
      await _pushNowPlayingUpdate(force: true);
    } on ApiException catch (err) {
      _handleApiError(err, context: 'pause');
    } catch (err) {
      _pushMessage('Failed to pause: $err');
    }
  }

  void updateShuffleMode(ShuffleMode mode, {ActionScope? scope}) {
    final nextScope = scope ?? _playbackState.shuffleScope;
    _updatePlayback(shuffleMode: mode, shuffleScope: nextScope);
    _pushMessage('Shuffle: ${nextScope.name} ${mode.name}');
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
    if (_authState.isAuthorized) {
      () async {
        await _persistPlaybackSettings(next);
      }();
    }
  }

  void updateStreamMode(StreamMode mode) {
    _updatePlayback(streamMode: mode);
    _pushMessage('Stream: ${mode.name}');
    final track = _playbackState.track;
    if (track != null &&
        _playbackState.isPlaying &&
        !_playbackState.isLocalPlayback) {
      _startPlayback(track, startOffset: _playbackState.position);
    }
  }

  void setVolume(double value) {
    _volumeTouched = true;
    _applyVolume(value, persist: true);
  }

  void _applyVolume(double value, {required bool persist}) {
    final clamped = value.clamp(0.0, 1.0);
    _audioEngine.setVolume(clamped);
    _updatePlayback(volume: clamped);
    if (persist) {
      _scheduleVolumeSave(clamped);
    }
  }

  void _scheduleVolumeSave(double value) {
    _pendingVolumeSave = value;
    _volumeSaveQueued = true;
    _volumeSaveDebounce?.cancel();
    _volumeSaveDebounce = Timer(
      const Duration(milliseconds: 350),
      _flushVolumeSave,
    );
  }

  void _flushVolumeSave() {
    if (!_volumeSaveQueued) {
      return;
    }
    _volumeSaveQueued = false;
    final value = _pendingVolumeSave;
    _volumeSaveChain = _volumeSaveChain.then(
      (_) => _playbackPreferencesStorage.writeVolume(value),
    );
  }

  Future<List<OutputDevice>> listOutputDevices({bool refresh = false}) async {
    if (_outputDevices.isNotEmpty && !refresh) {
      return outputDevices;
    }
    _outputDevices = await _audioEngine.listOutputDevices();
    final current = _outputDevices.firstWhere(
      (device) => device.id == _outputDeviceId,
      orElse: () =>
          OutputDevice(id: kDefaultOutputDeviceId, name: 'System Default'),
    );
    _outputDeviceId = current.id;
    _outputDeviceName = current.name;
    return outputDevices;
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
      _lastStartPlaybackAt = null;
      _startPlayback(track, startOffset: _playbackState.position);
    }
  }

  void previewSeek(Duration position) {
    final track = _playbackState.track;
    if (track == null) {
      return;
    }
    final clamped = _clampSeekTarget(position);
    _beginScrub();
    _seeking = true;
    _seekTargetMs = clamped.inMilliseconds;
    _seekDirection = _seekDirectionFor(_seekOriginMs, _seekTargetMs);
    _resetPlaybackPositionTracking(position: clamped);
    _resetBufferedEndHighWater(position: clamped);
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
    final requestGeneration = ++_seekRequestGeneration;
    _pendingSeekGeneration = requestGeneration;
    _armAutoAdvanceGuard(_seekCompletionGuard);
    _suppressAutoAdvanceUntil = DateTime.now().add(_seekCompletionGuard);
    final clamped = _clampSeekTarget(position);
    _lastSeekTrackId = track.id;
    _seeking = true;
    _seekTargetMs = clamped.inMilliseconds;
    if (!_isScrubbing) {
      _seekOriginMs = _displayPositionMs;
    }
    _seekDirection = _seekDirectionFor(_seekOriginMs, _seekTargetMs);
    _audioOutputStarted = false;
    _bumpNowPlayingEpoch();
    _resetPlaybackPositionTracking(position: clamped);
    _resetBufferedEndHighWater(position: clamped);
    _updatePlayback(
      position: clamped,
      isPlaying: _wantsPlayback,
      bufferRatio: 0.0,
    );
    await _commitSeek(clamped, requestGeneration);
    if (_disposed || requestGeneration != _seekRequestGeneration) return;
    await _pushNowPlayingUpdate(force: true);
  }

  Future<void> _commitSeek(Duration target, int requestGeneration) async {
    final track = _playbackState.track;
    if (track == null) {
      return;
    }
    _finishScrub();
    var inlineSeek = false;
    try {
      inlineSeek = await _audioEngine.seekTo(target);
    } catch (_) {
      inlineSeek = false;
    }
    if (_disposed ||
        requestGeneration != _seekRequestGeneration ||
        _playbackState.track?.id != track.id) {
      return;
    }
    _clearSeekHold(target);
    if (inlineSeek) {
      _pushMessage(
        'Seek commit: inline seek to ${target.inMilliseconds}ms '
        '(playing=${_wantsPlayback ? 'yes' : 'no'})',
      );
    } else {
      _restartPlaybackForSeek(
        track: track,
        target: target,
        reason: 'engine unavailable',
      );
    }
  }

  void _beginScrub() {
    if (_isScrubbing) {
      return;
    }
    _isScrubbing = true;
    _seekRequestGeneration++;
    _seekOriginMs = _displayPositionMs;
    _seekDirection = _SeekDirection.none;
  }

  void _finishScrub() {
    _isScrubbing = false;
  }

  void _resetPlaybackPositionTracking({Duration position = Duration.zero}) {
    final positionMs = max(0, position.inMilliseconds);
    _displayPositionMs = positionMs;
    _actualPositionMs = positionMs;
  }

  void _resetBufferedEndHighWater({Duration position = Duration.zero}) {
    _bufferedEndHighWaterMs = max(0, position.inMilliseconds);
  }

  void _resetTrackTransitionState({Duration position = Duration.zero}) {
    final positionMs = max(0, position.inMilliseconds);
    _isScrubbing = false;
    _seekRequestGeneration++;
    _wantsPlayback = false;
    _playbackStartGeneration++;
    _pendingSeekGeneration = null;
    _awaitingStreamReconnect = false;
    _streamRecoveryTimer?.cancel();
    _streamRecoveryTimer = null;
    _seeking = false;
    _seekOriginMs = positionMs;
    _seekTargetMs = positionMs;
    _seekDirection = _SeekDirection.none;
    _lastSeekTrackId = null;
    _ignoreCompleteUntil = null;
    _suppressAutoAdvanceUntil = null;
    _autoAdvanceInFlight = false;
    _lastInterruptedStreamRestartAt = null;
    _lastInterruptedStreamRestartTrackId = null;
    _lastInterruptedStreamRestartPositionMs = null;
    _resetPlaybackPositionTracking(
      position: Duration(milliseconds: positionMs),
    );
    _resetBufferedEndHighWater(position: Duration(milliseconds: positionMs));
  }

  void _restartPlaybackForSeek({
    required Track track,
    required Duration target,
    required String reason,
  }) {
    _pushMessage(
      'Seek commit: restarting stream at ${target.inMilliseconds}ms '
      '(reason=$reason, playing=${_wantsPlayback ? 'yes' : 'no'})',
    );
    _lastStartPlaybackAt = null;
    _startPlayback(track, startOffset: target);
  }

  void _clearSeekHold(Duration position) {
    _pendingSeekGeneration = null;
    _seeking = false;
    _seekOriginMs = position.inMilliseconds;
    _seekTargetMs = position.inMilliseconds;
    _seekDirection = _SeekDirection.none;
    _lastSeekTrackId = null;
    _ignoreCompleteUntil = null;
    _suppressAutoAdvanceUntil = null;
    _resetPlaybackPositionTracking(position: position);
  }

  void _maybeClearSeekHold(Duration position, Duration bufferedAhead) {
    if (!_seeking || _isScrubbing || _pendingSeekGeneration != null) {
      return;
    }
    final positionMs = position.inMilliseconds;
    final targetMs = _seekTargetMs;
    final reached = switch (_seekDirection) {
      _SeekDirection.forward =>
        positionMs >= targetMs - _seekCompletionToleranceMs,
      _SeekDirection.backward =>
        positionMs <= targetMs + _seekCompletionToleranceMs,
      _SeekDirection.none =>
        (positionMs - targetMs).abs() <= _seekCompletionToleranceMs,
    };
    if (reached) {
      _clearSeekHold(position);
      _pushNowPlayingUpdate(force: true);
    }
  }

  _SeekDirection _seekDirectionFor(int originMs, int targetMs) {
    if (targetMs > originMs + _seekCompletionToleranceMs) {
      return _SeekDirection.forward;
    }
    if (targetMs < originMs - _seekCompletionToleranceMs) {
      return _SeekDirection.backward;
    }
    return _SeekDirection.none;
  }

  Duration _clampSeekTarget(Duration position) {
    final duration = _playbackState.duration;
    var clamped = duration == Duration.zero
        ? position
        : position > duration
        ? duration
        : position < Duration.zero
        ? Duration.zero
        : position;
    final durationMs = duration.inMilliseconds;
    if (durationMs <= 0) {
      return clamped;
    }
    final tailGuardMs = _seekTailGuardMs(durationMs);
    if (tailGuardMs <= 0) {
      return clamped;
    }
    final safeMaxMs = max(0, durationMs - tailGuardMs);
    if (clamped.inMilliseconds > safeMaxMs) {
      clamped = Duration(milliseconds: safeMaxMs);
    }
    return clamped;
  }

  int _seekTailGuardMs(int durationMs) {
    if (durationMs <= 2000) {
      return 250;
    }
    if (durationMs <= 10000) {
      return 500;
    }
    return 1200;
  }

  void _updateDisplayPosition(int actualMs, int bufferedMs) {
    final durationMs = _playbackState.duration.inMilliseconds;
    if (_isScrubbing) {
      _displayPositionMs = _seekTargetMs;
    } else if (_seeking) {
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

  int _correctReportedPositionMs(int reportedMs) {
    if (_isScrubbing || _seeking) {
      return reportedMs;
    }
    if (!_playbackState.isPlaying || _audioEngine.isPaused) {
      return reportedMs;
    }
    final floorMs = max(_actualPositionMs, _displayPositionMs);
    if (floorMs <= 0) {
      return reportedMs;
    }
    if (reportedMs < floorMs) {
      return floorMs;
    }
    return reportedMs;
  }

  double _displayBufferRatio({required Duration duration}) {
    final durationMs = duration.inMilliseconds;
    if (durationMs <= 0) {
      return 0.0;
    }
    final positionRatio = (_displayPositionMs / durationMs).clamp(0.0, 1.0);
    if (_isScrubbing || _seeking) {
      return positionRatio.toDouble();
    }
    final bufferedRatio = (_bufferedEndHighWaterMs / durationMs).clamp(
      positionRatio,
      1.0,
    );
    return bufferedRatio.toDouble();
  }

  void _updateBufferedEndHighWater({
    required Duration duration,
    required Duration position,
    required Duration bufferedAhead,
  }) {
    final durationMs = duration.inMilliseconds;
    if (durationMs <= 0) {
      _bufferedEndHighWaterMs = 0;
      return;
    }
    if (_isScrubbing || _seeking) {
      return;
    }
    final positionMs = max(0, position.inMilliseconds);
    final bufferedAheadMs = max(0, bufferedAhead.inMilliseconds);
    final bufferedEndMs = positionMs + bufferedAheadMs;
    final next = max(
      _bufferedEndHighWaterMs,
      max(bufferedEndMs, _displayPositionMs),
    );
    _bufferedEndHighWaterMs = next.clamp(0, durationMs).toInt();
  }

  void _bumpNowPlayingEpoch() {
    _nowPlayingEpoch = (_nowPlayingEpoch + 1) % 1000000;
    if (_nowPlayingEpoch < 0) {
      _nowPlayingEpoch = 0;
    }
  }

  void _updateLike(String trackId, bool liked, {Track? knownTrack}) {
    _tracks = _tracks
        .map(
          (track) => track.id == trackId ? track.copyWith(liked: liked) : track,
        )
        .toList();
    _playlistTracks = _playlistTracks
        .map(
          (track) => track.id == trackId ? track.copyWith(liked: liked) : track,
        )
        .toList();
    _playQueue = _playQueue
        .map(
          (track) => track.id == trackId ? track.copyWith(liked: liked) : track,
        )
        .toList();
    final current = _playbackState.track;
    if (current != null && current.id == trackId) {
      _updatePlayback(track: current.copyWith(liked: liked));
    }
    if (liked) {
      final existing = _knownLikedTrack(trackId, knownTrack: knownTrack);
      if (existing != null) {
        _liked = [
          existing,
          ..._liked.where(
            (track) => track.id != trackId && track.serverTrackId != trackId,
          ),
        ];
      } else {
        AppLogger.debug(
          'Skipped adding liked track $trackId because metadata is not loaded.',
        );
      }
    } else {
      _liked = _liked
          .where(
            (track) => track.id != trackId && track.serverTrackId != trackId,
          )
          .toList();
    }

    _tracksController.add(List.unmodifiable(_tracks));
    _playlistTracksController.add(List.unmodifiable(_playlistTracks));
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
    return findIn(_tracks) ??
        findIn(_playlistTracks) ??
        findIn(_playQueue) ??
        (_playbackState.track != null
            ? findIn(<Track>[_playbackState.track!])
            : null) ??
        findIn(_liked);
  }

  Track _asServerLikedTrack(String trackId, Track track) {
    return track.copyWith(
      id: trackId,
      localId: null,
      serverBaseUrl: track.serverBaseUrl ?? connection.baseUrl,
      serverTrackId: track.serverTrackId ?? trackId,
      liked: true,
    );
  }

  void _updateLocalLike(String localTrackId, bool liked) {
    _playQueue = _playQueue
        .map(
          (track) => (track.localId == localTrackId || track.id == localTrackId)
              ? track.copyWith(liked: liked)
              : track,
        )
        .toList();
    if (!liked) {
      _pruneTrackFromLocalLikedQueue(localTrackId);
    }
    final current = _playbackState.track;
    if (current != null &&
        (current.localId == localTrackId || current.id == localTrackId)) {
      _updatePlayback(track: current.copyWith(liked: liked));
    }
  }

  void _pruneTrackFromLocalLikedQueue(String localTrackId) {
    if (_playbackState.queueSource != PlaybackQueueSource.offline ||
        _offlineQueueSource != _OfflineQueueSource.localLiked ||
        _playQueue.isEmpty) {
      return;
    }

    final oldQueue = _playQueue;
    final current = _playbackState.track;
    final currentIndex = current == null
        ? -1
        : oldQueue.indexWhere((track) => _sameTrackIdentity(track, current));
    final effectiveIndex = currentIndex >= 0
        ? currentIndex
        : _playIndex.clamp(0, oldQueue.length - 1).toInt();
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

    _playQueue = nextQueue;
    if (_playQueue.isEmpty) {
      _playIndex = 0;
      return;
    }

    final currentWasRemoved =
        current != null && _trackMatchesLocalId(current, localTrackId);
    if (currentWasRemoved) {
      _playIndex = min(effectiveIndex, _playQueue.length) - 1;
      return;
    }
    _playIndex = (effectiveIndex - removedBeforeEffectiveIndex)
        .clamp(0, _playQueue.length - 1)
        .toInt();
  }

  bool _trackMatchesLocalId(Track track, String localTrackId) {
    return track.id == localTrackId || track.localId == localTrackId;
  }

  bool _localTrackIsLiked(String trackId) {
    return localLiked.any(
      (track) =>
          track.id == trackId ||
          track.localId == trackId ||
          track.serverTrackId == trackId,
    );
  }

  bool _shouldUseLocalUserData(Track track) {
    if (_playbackState.isLocalPlayback &&
        _playbackState.track != null &&
        (_playbackState.track!.id == track.id ||
            _playbackState.track!.localId == track.localId)) {
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
    final download = availableOfflineDownloadForTrack(track.id);
    return download?.localTrackId ?? download?.track.localId;
  }

  void _setQueue(
    List<Track> tracks, {
    String? startTrackId,
    required PlaybackQueueSource queueSource,
    String? queueSourcePlaylistId,
    _OfflineQueueSource offlineQueueSource = _OfflineQueueSource.none,
  }) {
    _playQueue = tracks;
    _offlineQueueSource = queueSource == PlaybackQueueSource.offline
        ? offlineQueueSource
        : _OfflineQueueSource.none;
    if (startTrackId != null) {
      final idx = tracks.indexWhere((track) => track.id == startTrackId);
      _playIndex = idx >= 0 ? idx : 0;
    } else {
      _playIndex = 0;
    }
    _autoAdvanceInFlight = false;
    _updatePlayback(
      queueSource: queueSource,
      queueSourcePlaylistId:
          queueSource == PlaybackQueueSource.playlist ||
              (queueSource == PlaybackQueueSource.offline &&
                  offlineQueueSource == _OfflineQueueSource.localPlaylist)
          ? queueSourcePlaylistId
          : null,
      localPlaybackSource: queueSource == PlaybackQueueSource.offline
          ? _localPlaybackSourceFor(offlineQueueSource)
          : LocalPlaybackSource.none,
      nowPlaying: false,
    );
  }

  LocalPlaybackSource _localPlaybackSourceFor(_OfflineQueueSource source) {
    return switch (source) {
      _OfflineQueueSource.localLiked => LocalPlaybackSource.liked,
      _OfflineQueueSource.localPlaylist => LocalPlaybackSource.playlist,
      _OfflineQueueSource.tracks => LocalPlaybackSource.library,
      _OfflineQueueSource.none => LocalPlaybackSource.none,
    };
  }

  void _armAutoAdvanceGuard([
    Duration duration = const Duration(milliseconds: 1200),
  ]) {
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

    if (_playbackState.shuffleMode == ShuffleMode.currentPlaylist) {
      final playlistId =
          _playbackState.queueSource == PlaybackQueueSource.playlist
          ? _playbackState.queueSourcePlaylistId
          : null;
      if (playlistId == null || playlistId.isEmpty) {
        _pushMessage('Shuffle current playlist requires a playlist source.');
        return null;
      }
      return _ShuffleContext(scope: 'playlist', playlistId: playlistId);
    }

    return const _ShuffleContext(scope: 'library');
  }

  Future<bool> _ensureShuffleQueue({bool play = true}) async {
    if (_playbackState.shuffleScope == ActionScope.local) {
      return _ensureLocalShuffleQueue(play: play);
    }
    return _ensureServerShuffleQueue(play: play);
  }

  Future<bool> _ensureServerShuffleQueue({bool play = true}) async {
    if (_playbackState.shuffleMode == ShuffleMode.off) {
      return false;
    }
    if (_playQueue.isNotEmpty &&
        _queueShuffleMode == _playbackState.shuffleMode &&
        _queueShuffleScope != null) {
      if (play && _playbackState.track == null) {
        _playIndex = _playIndex.clamp(0, _playQueue.length - 1);
        await _playCurrent();
      }
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

  Future<bool> _ensureLocalShuffleQueue({bool play = true}) async {
    if (_playbackState.shuffleMode == ShuffleMode.off) {
      return false;
    }
    if (_playQueue.isNotEmpty &&
        _queueShuffleMode == _playbackState.shuffleMode &&
        _queueShuffleScope != null &&
        _queueShuffleScope!.startsWith('local')) {
      if (play && _playbackState.track == null) {
        _playIndex = _playIndex.clamp(0, _playQueue.length - 1);
        await _playCurrent();
      }
      return true;
    }
    final startTrackId = play ? null : _playbackState.track?.id;
    final playlistId = _playbackState.shuffleMode == ShuffleMode.currentPlaylist
        ? (_queueShufflePlaylistId ??
              (_playbackState.queueSource == PlaybackQueueSource.offline
                  ? _playbackState.queueSourcePlaylistId
                  : null))
        : null;
    await queueLocalShuffle(
      playlistId: playlistId,
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
    _setQueue(
      tracks,
      startTrackId: current.id,
      queueSource: PlaybackQueueSource.none,
    );
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

  Future<void> _maybeDisableShuffleForTrackSelection(String trackId) async {
    if (_playbackState.shuffleScope != ActionScope.server) {
      return;
    }
    final mode = _playbackState.shuffleMode;
    if (mode != ShuffleMode.liked && mode != ShuffleMode.custom) {
      return;
    }
    final shouldDisable = await _shouldDisableShuffleForTrackSelection(
      trackId,
      mode,
    );
    if (shouldDisable) {
      updateShuffleMode(ShuffleMode.off, scope: ActionScope.server);
    }
  }

  Future<bool> _shouldDisableShuffleForTrackSelection(
    String trackId,
    ShuffleMode mode,
  ) async {
    if (mode == ShuffleMode.liked) {
      final isLiked = _liked.any((track) => track.id == trackId);
      if (isLiked) {
        return false;
      }
      if (_liked.isNotEmpty) {
        return true;
      }
      try {
        final full = await connection.fetchTrackById(trackId);
        return !full.liked;
      } catch (err) {
        _pushMessage('Failed to confirm liked status: $err');
        return true;
      }
    }

    if (mode == ShuffleMode.custom) {
      try {
        await _ensureCustomShuffleSettingsLoaded();
        final customArtists = _customShuffleSettings.artistIds;
        final customGenres = _customShuffleSettings.genres;
        if (customArtists.isEmpty && customGenres.isEmpty) {
          return false;
        }

        final track = await connection.fetchTrackById(trackId);
        final artistIds = <String>{
          for (final credit in track.credits)
            if (credit.isPerformingArtist && credit.artistId.trim().isNotEmpty)
              credit.artistId.trim(),
          if (track.artistId?.trim().isNotEmpty ?? false)
            track.artistId!.trim(),
        };
        if (artistIds.any(customArtists.contains)) {
          return false;
        }
        final genreFilter = customGenres
            .map((genre) => genre.trim().toLowerCase())
            .toSet();
        bool matchesGenre(Iterable<String> genres) => genres.any(
          (genre) => genreFilter.contains(genre.trim().toLowerCase()),
        );
        if (genreFilter.isNotEmpty && matchesGenre(track.genres)) {
          return false;
        }
        final albumId = track.albumId;
        final album = albumId?.trim().isNotEmpty == true
            ? await connection.fetchAlbumById(albumId!)
            : null;
        artistIds.addAll([
          if (album?.artistId.trim().isNotEmpty ?? false)
            album!.artistId.trim(),
          for (final credit in album?.credits ?? const <ArtistCredit>[])
            if (credit.isAlbumArtist && credit.artistId.trim().isNotEmpty)
              credit.artistId.trim(),
        ]);
        if (artistIds.any(customArtists.contains)) {
          return false;
        }

        if (genreFilter.isNotEmpty) {
          if (matchesGenre(album?.genres ?? const <String>[])) {
            return false;
          }
          for (final artistId in artistIds) {
            try {
              final cached = [
                ..._artists,
                ...track.offlineArtists,
                if (track.offlineArtist != null) track.offlineArtist!,
              ].where((artist) => artist.id == artistId).firstOrNull;
              final artist =
                  cached ?? await connection.fetchArtistById(artistId);
              if (artist.id == artistId && matchesGenre(artist.genres)) {
                return false;
              }
            } catch (_) {
              // A missing profile must not hide another contributor's genres.
            }
          }
        }

        return true;
      } catch (err) {
        _pushMessage('Failed to resolve custom shuffle match: $err');
        return true;
      }
    }

    return false;
  }

  Future<void> _playCurrent() async {
    if (_playQueue.isEmpty) return;
    _autoAdvanceInFlight = false;
    final track = _playQueue[_playIndex];
    _playQueue = _playQueue
        .map((item) => item.id == track.id ? track : item)
        .toList();
    _pushMessage(
      'Now playing: id=${track.id} artist="${track.artist}" album="${track.album}" albumId="${track.albumId ?? ''}"',
    );
    _bumpNowPlayingEpoch();
    _resetTrackTransitionState();
    _wantsPlayback = true;
    _updatePlayback(
      track: track,
      isPlaying: true,
      position: Duration.zero,
      duration: Duration(milliseconds: track.durationMs),
      bufferRatio: 0.0,
    );
    _startPlayback(track);
    if (_playbackState.queueSource != PlaybackQueueSource.offline) {
      final server = connection.baseUrl;
      final token = connection.token;
      final metadataRevision = _metadataReadRevision;
      // Metadata is display data; do not delay audio while fetching it.
      for (final queued in _playQueue.skip(_playIndex).take(2)) {
        if (!_needsTrackHydration(queued)) continue;
        unawaited(() async {
          try {
            final full = await _hydrateTrackForPlayback(queued);
            if (_disposed ||
                server != connection.baseUrl ||
                token != connection.token ||
                metadataRevision != _metadataReadRevision) {
              return;
            }
            _playQueue = _playQueue
                .map(
                  (item) => item.id == full.id
                      ? full.copyWith(
                          liked: item.liked,
                          inPlaylists: item.inPlaylists,
                        )
                      : item,
                )
                .toList();
            final current = _playbackState.track;
            if (current?.id == full.id) {
              _updatePlayback(
                track: full.copyWith(
                  liked: current!.liked,
                  inPlaylists: current.inPlaylists,
                ),
                duration: Duration(milliseconds: full.durationMs),
              );
            }
          } catch (error) {
            _pushMessage('Playback metadata lookup failed: $error');
          }
        }());
      }
    }
  }

  Future<Track> _hydrateTrackForPlayback(Track track) async {
    final sessionRevision = connection.sessionRevision;
    final metadataRevision = _metadataReadRevision;
    Track full = track;
    try {
      full = await connection.fetchTrackById(track.id);
      _pushMessage(
        'Track details response: id=${full.id} artist="${full.artist}" album="${full.album}" albumId="${full.albumId ?? ''}"',
      );
    } catch (err) {
      _pushMessage('Track details lookup failed: $err');
    }
    if (connection.sessionRevision != sessionRevision ||
        metadataRevision != _metadataReadRevision) {
      return track;
    }

    var resolvedAlbumId = full.albumId ?? track.albumId;
    if ((resolvedAlbumId == null || resolvedAlbumId.isEmpty) &&
        full.artist.isNotEmpty &&
        full.album.isNotEmpty) {
      final key = _albumKey(full.artist, full.album);
      resolvedAlbumId = _albumIdByKey[key];
      if (resolvedAlbumId == '') return full;
      if (resolvedAlbumId == null || resolvedAlbumId.isEmpty) {
        resolvedAlbumId = await _resolveAlbumIdBySearch(
          artist: full.artist,
          album: full.album,
        );
        if (connection.sessionRevision != sessionRevision ||
            metadataRevision != _metadataReadRevision) {
          return track;
        }
        if (resolvedAlbumId != null && resolvedAlbumId.isNotEmpty) {
          _rememberAlbumId(key, resolvedAlbumId);
        }
      }
      if (resolvedAlbumId != null && resolvedAlbumId.isNotEmpty) {
        full = full.copyWith(albumId: resolvedAlbumId);
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
        full = full.copyWith(albumId: albumId);
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
    if (_albumIdCacheSessionRevision != connection.sessionRevision) {
      _albumIdByKey.clear();
      _albumIdCacheSessionRevision = connection.sessionRevision;
    }
    return '${artist.trim().toLowerCase()}|${album.trim().toLowerCase()}';
  }

  void _cacheAlbumId({required Album album}) {
    final key = _albumKey(album.artist, album.title);
    if (key == '|' || album.id.isEmpty) {
      return;
    }
    _rememberAlbumId(key, album.id);
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
    _rememberAlbumId(key, albumId);
  }

  void _rememberAlbumId(String key, String albumId) {
    final previous = _albumIdByKey[key];
    // An empty entry marks multiple releases sharing the same artist and title.
    _albumIdByKey[key] = previous == null || previous == albumId ? albumId : '';
  }

  String _normalizeLookup(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
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
    if (normalizedArtist.isEmpty) return null;
    final query = [
      artist,
      album,
    ].where((part) => part.trim().isNotEmpty).join(' ');
    if (query.isEmpty) {
      return null;
    }
    try {
      final results = await connection.search(query, filter: 'album');
      if (results.isEmpty) {
        return null;
      }
      final matches = <String>{};
      for (final result in results) {
        if (result.kind != 'album' || result.id.isEmpty) continue;
        final title = _normalizeLookup(result.title);
        if (title != normalizedAlbum) {
          continue;
        }
        final subtitle = _normalizeLookup(result.subtitle ?? '');
        if (subtitle == normalizedArtist) {
          matches.add(result.id);
        }
      }
      // A shared title or a partial artist name cannot identify a recording.
      // Multiple exact releases remain ambiguous without an explicit album ID.
      if (matches.length == 1) return matches.single;
    } catch (err) {
      _pushMessage('Album search fallback failed: $err');
    }
    return null;
  }

  List<Track> _normalizeQueueTracks(List<Track> tracks) {
    return tracks.map((track) {
      if (track.albumId != null && track.albumId!.isNotEmpty) {
        return track;
      }
      final key = _albumKey(track.artist, track.album);
      final albumId = _albumIdByKey[key];
      if (albumId == null || albumId.isEmpty) {
        return track;
      }
      return track.copyWith(albumId: albumId);
    }).toList();
  }

  Track _mergeTrackWithAlbum(Track track, Album album) {
    final albumTitle = track.album.isNotEmpty ? track.album : album.title;
    final artistName = track.artist.isNotEmpty ? track.artist : album.artist;
    return track.copyWith(
      artist: artistName,
      album: albumTitle,
      albumId: track.albumId ?? album.id,
    );
  }

  Track _mergeTrackWithArtist(Track track, Artist artist) {
    final artistName = track.artist.isNotEmpty ? track.artist : artist.name;
    return track.copyWith(artist: artistName);
  }

  void _updatePlayback({
    Object? track = _unset,
    bool? isPlaying,
    bool? isLoading,
    Duration? position,
    Duration? duration,
    double? bufferRatio,
    double? volume,
    ShuffleMode? shuffleMode,
    ActionScope? shuffleScope,
    RepeatMode? repeatMode,
    StreamMode? streamMode,
    double? bitrateKbps,
    bool? streamConnected,
    int? streamRttMs,
    PlaybackQueueSource? queueSource,
    Object? queueSourcePlaylistId = _unset,
    LocalPlaybackSource? localPlaybackSource,
    bool? isLocalPlayback,
    bool nowPlaying = true,
  }) {
    if (_disposed) return;
    final resolvedLocalPlaybackSource =
        localPlaybackSource ??
        (queueSource != null && queueSource != PlaybackQueueSource.offline
            ? LocalPlaybackSource.none
            : null);
    _playbackState = _playbackState.copyWith(
      track: track == _unset ? _playbackState.track : track,
      isPlaying: isPlaying,
      isLoading: isLoading,
      position: position,
      duration: duration,
      bufferRatio: bufferRatio,
      volume: volume,
      shuffleMode: shuffleMode,
      shuffleScope: shuffleScope,
      repeatMode: repeatMode,
      streamMode: streamMode,
      bitrateKbps: bitrateKbps,
      streamConnected: streamConnected,
      streamRttMs: streamRttMs,
      queueSource: queueSource,
      queueSourcePlaylistId: queueSourcePlaylistId == _unset
          ? _playbackState.queueSourcePlaylistId
          : queueSourcePlaylistId,
      localPlaybackSource: resolvedLocalPlaybackSource,
      isLocalPlayback: isLocalPlayback,
    );
    _playbackController.add(_playbackState);
    if (nowPlaying) {
      _pushNowPlayingUpdate();
    }
  }

  void _pushMessage(String message, {LogLevel level = LogLevel.info}) {
    if (_disposed) return;
    AppLogger.instance.log(LogEntry(message: message, level: level));
  }

  void _addLogEntry(LogEntry entry) {
    if (_disposed) return;
    _messages.add(entry);
    if (_messages.length > 3000) {
      _messages.removeFirst();
    }
    _messageSnapshot = null;
    if (!_messageController.hasListener) return;
    // Publish at most ten snapshots per second during noisy download/playback
    // bursts, and avoid copying history at all when no UI is observing it.
    _messageUpdateTimer ??= Timer(const Duration(milliseconds: 100), () {
      _messageUpdateTimer = null;
      if (!_disposed && _messageController.hasListener) {
        _messageController.add(messages);
      }
    });
  }

  Future<void> clearMessages() {
    _messageUpdateTimer?.cancel();
    _messageUpdateTimer = null;
    _messages.clear();
    _messageSnapshot = null;
    _messageController.add(messages);
    return AppLogger.instance.clear();
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
    _setSessionStatus(
      authorized ? SessionStatus.authenticated : SessionStatus.offline,
      error: error,
    );
  }

  void _setSessionStatus(
    SessionStatus status, {
    String? error,
    bool? isReconnecting,
  }) {
    if (_disposed) return;
    if (_artistListSessionRevision != connection.sessionRevision) {
      _artistListSessionRevision = connection.sessionRevision;
      _artistsRequestEpoch++;
      _artistReleasesRequestEpoch++;
      _artists = [];
      _albums = [];
      _artistReleases = const ArtistReleases();
      _artistsOffset = 0;
      _artistsHasMore = true;
      _lastArtistId = null;
      _artistReleasesArtistId = null;
      _artistsController.add(const []);
      _albumsController.add(const []);
      _artistReleasesController.add(_artistReleases);
    }
    _authState = _authState.copyWith(
      status: status,
      baseUrl: connection.baseUrl,
      error: error,
      isReconnecting: isReconnecting,
    );
    _authController.add(_authState);
    _notifyCarPlayAuthState(_authState.isAuthorized);
    if (_authState.isAuthorized) {
      _startMetadataEventListener();
      unawaited(_listeningSync?.sync(immediate: true) ?? Future<void>.value());
    } else {
      _stopMetadataEventListener();
    }
    _syncServerReconnectLoop();
  }

  bool get _shouldAutoReconnectServer {
    final token = connection.token;
    return _authState.status == SessionStatus.serverUnavailable &&
        token != null &&
        token.isNotEmpty;
  }

  void _configureConnectivitySignals() {
    _connectivitySubscription = _connectivitySignalSource.availabilityStream
        .listen(
          _handleConnectivityAvailabilityChanged,
          onError: (Object error) {
            _pushMessage(
              'Network change monitor failed: $error',
              level: LogLevel.warning,
            );
          },
        );
    unawaited(
      _connectivitySignalSource
          .hasConnectivity()
          .then((available) {
            if (_disposed) return;
            _lastConnectivityAvailable = available;
            if (available &&
                _authState.status == SessionStatus.serverUnavailable) {
              unawaited(
                _triggerImmediateServerReconnect(reason: 'network available'),
              );
            }
          })
          .catchError((_) {}),
    );
  }

  void _handleConnectivityAvailabilityChanged(bool available) {
    if (_disposed) return;
    final wasAvailable = _lastConnectivityAvailable;
    _lastConnectivityAvailable = available;
    if (available && !wasAvailable) {
      unawaited(_triggerImmediateServerReconnect(reason: 'network restored'));
    }
  }

  void _syncServerReconnectLoop() {
    if (_disposed) {
      _stopServerReconnectLoop(resetAttempts: true);
      return;
    }
    if (_shouldAutoReconnectServer) {
      _scheduleServerReconnect();
    } else {
      _stopServerReconnectLoop(resetAttempts: true);
    }
  }

  void _stopServerReconnectLoop({required bool resetAttempts}) {
    _serverReconnectTimer?.cancel();
    _serverReconnectTimer = null;
    if (resetAttempts) {
      _serverReconnectAttempt = 0;
    }
  }

  void _scheduleServerReconnect() {
    if (!_shouldAutoReconnectServer ||
        _serverReconnectTimer != null ||
        _serverAvailabilityFuture != null) {
      return;
    }
    final delay = _serverReconnectDelayForAttempt(_serverReconnectAttempt);
    _serverReconnectTimer = Timer(delay, () {
      _serverReconnectTimer = null;
      unawaited(_refreshServerAvailability(reconnectAttempt: true));
    });
  }

  Duration _serverReconnectDelayForAttempt(int attempt) {
    final backoff = _appInForeground
        ? _serverReconnectForegroundBackoff
        : _serverReconnectBackgroundBackoff;
    final base = backoff[min(attempt, backoff.length - 1)];
    final jitterMs = _serverReconnectJitterMax.inMilliseconds <= 0
        ? 0
        : _reconnectRandom.nextInt(
            _serverReconnectJitterMax.inMilliseconds + 1,
          );
    return base + Duration(milliseconds: jitterMs);
  }

  Future<void> retryServerConnection() async {
    _pushMessage('Retrying server connection...');
    await _triggerImmediateServerReconnect(reason: 'manual retry');
  }

  Future<void> _triggerImmediateServerReconnect({required String reason}) {
    assert(reason.isNotEmpty);
    if (!_shouldAutoReconnectServer) {
      _syncServerReconnectLoop();
      return Future<void>.value();
    }
    _serverReconnectTimer?.cancel();
    _serverReconnectTimer = null;
    return _refreshServerAvailability(reconnectAttempt: true);
  }

  void _setServerReconnecting(bool value) {
    if (_disposed) return;
    if (_authState.status != SessionStatus.serverUnavailable ||
        _authState.isReconnecting == value) {
      return;
    }
    _authState = _authState.copyWith(
      baseUrl: connection.baseUrl,
      error: _authState.error,
      isReconnecting: value,
    );
    _authController.add(_authState);
    _notifyCarPlayAuthState(_authState.isAuthorized);
  }

  void _startMetadataEventListener() {
    final token = connection.token;
    if (token == null || token.isEmpty) return;
    _metadataEvents.start(baseUrl: connection.baseUrl, token: token);
  }

  void _stopMetadataEventListener() => _metadataEvents.stop();

  Future<void> _applyMetadataEvent(MetadataUpdateEvent event) async {
    // A read started before this update may still contain the old metadata.
    connection.invalidateMetadataReads();
    _albumIdByKey.clear();
    _metadataReadRevision++;
    switch (event.kind) {
      case 'artist':
        await _refreshMetadataArtist(event.artistId ?? event.id);
        break;
      case 'album':
        await _refreshMetadataAlbum(event.albumId ?? event.id);
        break;
      case 'album_artists':
        final shouldReloadAlbums = _metadataEventMayAffectCurrentArtist(event);
        await _refreshMetadataAlbum(
          event.albumId ?? event.id,
          reloadCurrentArtistAlbums: shouldReloadAlbums,
        );
        await loadArtists(refresh: true);
        break;
    }
  }

  Future<void> _refreshMetadataArtist(String artistId) async {
    if (artistId.trim().isEmpty) {
      return;
    }
    final sessionRevision = connection.sessionRevision;
    try {
      final updated = await connection.fetchArtistById(artistId);
      if (_disposed ||
          !_authState.isAuthorized ||
          connection.sessionRevision != sessionRevision) {
        return;
      }
      final index = _artists.indexWhere((artist) => artist.id == updated.id);
      final effective = updated;
      if (index >= 0) {
        final next = [..._artists];
        next[index] = effective;
        _artists = next;
        _artistsController.add(List.unmodifiable(_artists));
      }
      _artistUpdatesController.add(effective);
      if (updated.name.trim().isNotEmpty) {
        _updateLoadedTrackMetadata(
          (track) => _trackWithUpdatedArtistCredit(track, updated),
        );
      }
      unawaited(
        _offlineDownloadManager.refreshOfflineMetadataForArtist(artistId),
      );
      if (_artistReleasesArtistId == artistId) {
        await loadArtistReleases(artistId);
      }
    } catch (err) {
      AppLogger.debug('Failed to refresh artist metadata for $artistId: $err');
    }
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
    final performers = credits
        .where((credit) => credit.isPerformingArtist)
        .toList();
    final display = StringBuffer();
    for (var i = 0; i < performers.length; i++) {
      display.write(performers[i].displayName);
      if (i < performers.length - 1) {
        display.write(
          performers[i].joinPhrase.isEmpty ? ', ' : performers[i].joinPhrase,
        );
      }
    }
    return track.copyWith(
      artist: performers.isEmpty ? track.artist : display.toString(),
      artistIds: performers.map((credit) => credit.artistId).toList(),
      artistNames: performers.map((credit) => credit.name).toList(),
      artistCredits: credits,
    );
  }

  Future<void> _refreshMetadataAlbum(
    String albumId, {
    bool reloadCurrentArtistAlbums = false,
  }) async {
    if (albumId.trim().isEmpty) {
      return;
    }
    final sessionRevision = connection.sessionRevision;
    try {
      final fetched = await connection.fetchAlbumById(albumId);
      if (_disposed ||
          !_authState.isAuthorized ||
          connection.sessionRevision != sessionRevision) {
        return;
      }
      var updated = await _albumWithDisplayArtist(fetched);
      if (_disposed ||
          !_authState.isAuthorized ||
          connection.sessionRevision != sessionRevision) {
        return;
      }
      final index = _albums.indexWhere((album) => album.id == updated.id);
      if (index >= 0) {
        updated = _albumWithListFallbacks(updated, existing: _albums[index]);
        final next = [..._albums];
        next[index] = updated;
        _albums = _sortAlbumsByReleaseYear(next);
        _cacheAlbumId(album: updated);
        _albumsController.add(List.unmodifiable(_albums));
      }
      _albumUpdatesController.add(updated);
      unawaited(
        _offlineDownloadManager.refreshOfflineMetadataForAlbum(albumId),
      );
      await _refreshLoadedTracksForAlbum(albumId, sessionRevision);
      if (_disposed ||
          !_authState.isAuthorized ||
          connection.sessionRevision != sessionRevision) {
        return;
      }

      final artistId = _lastArtistId;
      if ((reloadCurrentArtistAlbums ||
              _artistReleases.collabAlbums.any(
                (entry) => entry.album.id == albumId,
              ) ||
              _artistReleases.appearsOn.any(
                (entry) => entry.album.id == albumId,
              ) ||
              _artistReleases.otherCredits.any(
                (entry) => entry.album.id == albumId,
              ) ||
              _albums.any((album) => album.id == albumId)) &&
          artistId != null &&
          artistId.trim().isNotEmpty) {
        if (_artistReleasesArtistId == artistId) {
          await loadArtistReleases(artistId);
        } else {
          await loadAlbums(artistId);
        }
      }
    } catch (err) {
      AppLogger.debug('Failed to refresh album metadata for $albumId: $err');
    }
  }

  Future<void> _refreshLoadedTracksForAlbum(
    String albumId,
    int sessionRevision,
  ) async {
    final remotePlayback =
        !_playbackState.isLocalPlayback &&
        _playbackState.queueSource != PlaybackQueueSource.offline;
    final loaded = <Track>[
      ..._tracks,
      ..._playlistTracks,
      ..._liked,
      if (remotePlayback) ..._playQueue,
      if (remotePlayback && _playbackState.track != null) _playbackState.track!,
    ];
    if (_lastAlbumId != albumId &&
        !loaded.any((track) => track.albumId == albumId)) {
      return;
    }
    final metadataRevision = _metadataReadRevision;
    final fetched = await connection.fetchTracks(albumId);
    if (_disposed ||
        !_authState.isAuthorized ||
        connection.sessionRevision != sessionRevision ||
        metadataRevision != _metadataReadRevision) {
      return;
    }
    final byId = {for (final track in fetched) track.id: track};
    _updateLoadedTrackMetadata((track) {
      final updated = byId[track.id];
      if (updated == null) return track;
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
    });
  }

  void _updateLoadedTrackMetadata(Track Function(Track) update) {
    List<Track> apply(List<Track> tracks) => tracks.map(update).toList();
    _tracks = apply(_tracks);
    _playlistTracks = apply(_playlistTracks);
    _liked = apply(_liked);
    _tracksController.add(List.unmodifiable(_tracks));
    _playlistTracksController.add(List.unmodifiable(_playlistTracks));
    _likedController.add(List.unmodifiable(_liked));
    if (_playbackState.isLocalPlayback ||
        _playbackState.queueSource == PlaybackQueueSource.offline) {
      return;
    }
    _playQueue = apply(_playQueue);
    final current = _playbackState.track;
    if (current == null) return;
    final updated = update(current);
    if (!identical(current, updated)) {
      _bumpNowPlayingEpoch();
      _updatePlayback(track: updated);
    }
  }

  Future<Album> _albumWithDisplayArtist(Album album) async {
    if (album.artist.trim().isNotEmpty) {
      return album;
    }
    final loaded = _loadedAlbum(album.id);
    final loadedArtist = loaded?.artist.trim();
    if (loaded?.artistId == album.artistId &&
        loadedArtist != null &&
        loadedArtist.isNotEmpty) {
      return album.copyWith(artist: loadedArtist);
    }
    if (album.artistId.trim().isEmpty) {
      return album;
    }
    try {
      final artist = await connection.fetchArtistById(album.artistId);
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
    return albums.toList(growable: false)..sort(_compareAlbumsByReleaseYear);
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
    return _albums.any(
      (album) => album.id == albumId || album.artistId == artistId,
    );
  }

  bool _requireServer(String action) {
    if (_authState.isAuthorized) {
      return true;
    }
    if (_authState.status == SessionStatus.serverUnavailable) {
      _pushMessage(
        'Server is unavailable before $action. Reconnecting in the background.',
        level: LogLevel.warning,
      );
      unawaited(_triggerImmediateServerReconnect(reason: 'server action'));
      return false;
    }
    _pushMessage(
      'Connect to a server before $action.',
      level: LogLevel.warning,
    );
    return false;
  }

  Future<void> loadCustomShuffleSettings() async {
    await _ensureCustomShuffleSettingsLoaded(force: true);
  }

  Future<void> updateCustomShuffleSettings({
    List<String>? artistIds,
    List<String>? genres,
    List<String>? localArtistIds,
    List<String>? localGenres,
  }) async {
    final next = CustomShuffleSettings(
      artistIds: _normalizeCustomList(
        artistIds ?? _customShuffleSettings.artistIds,
      ),
      genres: _normalizeCustomList(
        genres ?? _customShuffleSettings.genres,
        lowerCase: true,
      ),
      localArtistIds: _normalizeCustomList(
        localArtistIds ?? _customShuffleSettings.localArtistIds,
      ),
      localGenres: _normalizeCustomList(
        localGenres ?? _customShuffleSettings.localGenres,
        lowerCase: true,
      ),
    );
    _customShuffleSettings = next;
    _customShuffleSettingsController.add(customShuffleSettings);
    await _customShuffleStorage.write(next);
    await _refreshCustomShuffleQueueIfNeeded();
  }

  void setCollectionListMode(bool value, {bool persist = true}) {
    if (persist) {
      _collectionListModeTouched = true;
    }
    if (_collectionListMode == value) {
      return;
    }
    _collectionListMode = value;
    _collectionListModeController.add(value);
    if (persist) {
      _persistCollectionListMode(value);
    }
  }

  void toggleCollectionListMode() {
    setCollectionListMode(!_collectionListMode);
  }

  void _persistCollectionListMode(bool value) {
    _volumeSaveChain = _volumeSaveChain.then(
      (_) => _playbackPreferencesStorage.writeCollectionListMode(value),
    );
  }

  Future<void> _loadCustomShuffleSettings() async {
    final settings = await _customShuffleStorage.read();
    if (_disposed) return;
    _customShuffleSettings = settings;
    _customShuffleSettingsController.add(customShuffleSettings);
  }

  Future<void> _loadPlaybackPreferences() async {
    final storedCollectionListMode = await _playbackPreferencesStorage
        .readCollectionListMode();
    if (_disposed) return;
    if (!_collectionListModeTouched && storedCollectionListMode != null) {
      setCollectionListMode(storedCollectionListMode, persist: false);
    }
    final storedVolume = await _playbackPreferencesStorage.readVolume();
    if (_disposed) return;
    if (storedVolume == null) {
      return;
    }
    if (_volumeTouched) {
      return;
    }
    _applyVolume(storedVolume, persist: false);
  }

  Future<void> _ensureCustomShuffleSettingsLoaded({bool force = false}) async {
    if (force || _customShuffleLoadFuture == null) {
      _customShuffleLoadFuture = _loadCustomShuffleSettings();
    }
    await _customShuffleLoadFuture;
  }

  Future<void> _refreshCustomShuffleQueueIfNeeded() async {
    if (_playbackState.shuffleMode != ShuffleMode.custom) {
      return;
    }
    final scope = _playbackState.shuffleScope;
    if (scope != ActionScope.server && scope != ActionScope.local) {
      return;
    }
    final hasActiveShuffle =
        _playQueue.isNotEmpty ||
        _queueShuffleScope != null ||
        _playbackState.isPlaying ||
        _playbackState.track != null;
    if (!hasActiveShuffle) {
      _queueShuffleMode = ShuffleMode.off;
      _queueShuffleScope = null;
      return;
    }
    if (scope == ActionScope.local) {
      if (_customShuffleSettings.localArtistIds.isEmpty &&
          _customShuffleSettings.localGenres.isEmpty) {
        _pushMessage('Local custom shuffle has no filters.');
        updateShuffleMode(ShuffleMode.off, scope: ActionScope.local);
        return;
      }
      await _refreshLocalCustomShuffleQueue();
      return;
    }
    await _refreshCustomShuffleQueue();
  }

  Future<void> _refreshCustomShuffleQueue() async {
    if (_customShuffleRefreshInFlight) {
      _customShuffleRefreshQueued = true;
      return;
    }
    _customShuffleRefreshInFlight = true;
    try {
      do {
        _customShuffleRefreshQueued = false;
        final scope = _queueShuffleScope ?? 'library';
        final playlistId = _queueShufflePlaylistId;
        final artistId = _queueShuffleArtistId;
        final albumId = _queueShuffleAlbumId;
        final startTrackId = _playbackState.track?.id;
        await queueShuffle(
          scope: scope,
          playlistId: playlistId,
          artistId: artistId,
          albumId: albumId,
          play: false,
          startTrackId: startTrackId,
        );
      } while (_customShuffleRefreshQueued);
    } finally {
      _customShuffleRefreshInFlight = false;
    }
  }

  Future<void> _refreshLocalCustomShuffleQueue() async {
    if (_customShuffleRefreshInFlight) {
      _customShuffleRefreshQueued = true;
      return;
    }
    _customShuffleRefreshInFlight = true;
    try {
      do {
        _customShuffleRefreshQueued = false;
        await queueLocalShuffle(
          play: false,
          startTrackId: _playbackState.track?.id,
        );
      } while (_customShuffleRefreshQueued);
    } finally {
      _customShuffleRefreshInFlight = false;
    }
  }

  List<String> _normalizeCustomList(
    List<String> values, {
    bool lowerCase = false,
  }) {
    final seen = <String>{};
    final result = <String>[];
    for (final raw in values) {
      var value = raw.trim();
      if (value.isEmpty) {
        continue;
      }
      if (lowerCase) {
        value = value.toLowerCase();
      }
      if (seen.add(value)) {
        result.add(value);
      }
    }
    return result;
  }

  void _handleApiError(ApiException err, {required String context}) {
    if (err.statusCode == 401) {
      unawaited(
        _offlineDownloadManager.pauseDownloadsForServer(connection.baseUrl),
      );
      connection.setToken(null);
      _serverHealthFailureCount = 0;
      _serverReconnectAttempt = 0;
      unawaited(_detachListeningAccount());
      _setSessionStatus(SessionStatus.offline, error: 'Unauthorized');
      _pushMessage('Unauthorized. Please log in.');
      return;
    }
    final message = _formatApiError(err);
    _pushMessage('Failed to load $context: $message', level: LogLevel.warning);
  }

  Future<void> _handleReconnectUnauthorized() async {
    unawaited(
      _offlineDownloadManager.pauseDownloadsForServer(connection.baseUrl),
    );
    connection.setToken(null);
    _serverHealthFailureCount = 0;
    _serverReconnectAttempt = 0;
    final detach = _detachListeningAccount();
    await _clearSavedCredentials();
    await detach;
    _setSessionStatus(SessionStatus.offline, error: 'Saved login expired');
    _pushMessage('Saved login expired. Please log in.');
  }

  void _handleServerTransportFailure(Object error) {
    if (!_canAttemptRemotePlayback) {
      return;
    }
    _recordServerAvailabilityFailure(
      error: 'Server unavailable: $error',
      reconnectAttempt: false,
    );
  }

  void _markServerUnavailable({required String error}) {
    if (!_canAttemptRemotePlayback) {
      return;
    }
    _serverHealthFailureCount = max(
      _serverHealthFailureCount,
      _serverUnavailableHealthFailureThreshold,
    );
    _serverReconnectAttempt = 0;
    _quicPort = null;
    unawaited(
      _offlineDownloadManager.pauseDownloadsForServer(connection.baseUrl),
    );
    _setSessionStatus(SessionStatus.serverUnavailable, error: error);
    _pushMessage(error, level: LogLevel.warning);
  }

  void _restoreServerAvailability({int? rttMs}) {
    if (_disposed) return;
    if (_authState.status != SessionStatus.serverUnavailable) {
      return;
    }
    final token = connection.token;
    if (token == null || token.isEmpty) {
      _setSessionStatus(SessionStatus.offline, error: null);
      return;
    }
    _serverHealthFailureCount = 0;
    _setSessionStatus(SessionStatus.authenticated, error: null);
    if (!_audioEngine.hasActivePlayer) {
      _updatePlayback(streamConnected: true, streamRttMs: rttMs);
    }
    _pushMessage('Server connection restored.');
    unawaited(_refreshServerPorts(timeout: const Duration(seconds: 4)));
    unawaited(_loadPlaybackSettings());
    unawaited(_offlineDownloadManager.resumePausedForCurrentServer());
    unawaited(_offlineDownloadManager.repairOfflineMetadataFragments());
    _retryPlaybackAfterServerReconnect();
  }

  void _startPlayback(
    Track track, {
    Duration startOffset = Duration.zero,
    bool quickStart = true,
  }) {
    final settings = _streamSettings(_playbackState.streamMode);
    final queueIds = _buildQueueIds(track.id, 3);
    final offlineDownload = availableOfflineDownloadForTrack(track.id);
    final shouldUseLocal =
        _playbackState.queueSource == PlaybackQueueSource.offline ||
        !_canAttemptRemotePlayback;
    final now = _playbackClock();
    final offsetMs = startOffset.inMilliseconds;
    if (_audioEngine.hasActivePlayer &&
        _lastStartPlaybackTrackId == track.id &&
        _lastStartPlaybackOffsetMs == offsetMs &&
        _lastStartPlaybackAt != null &&
        now.difference(_lastStartPlaybackAt!) <
            const Duration(milliseconds: 800)) {
      _pushMessage(
        'Playback already active; skipping duplicate start for ${track.title}.',
      );
      return;
    }
    _lastStartPlaybackAt = now;
    _lastStartPlaybackTrackId = track.id;
    _lastStartPlaybackOffsetMs = offsetMs;
    _awaitingStreamReconnect = false;
    _streamRecoveryTimer?.cancel();
    _streamRecoveryTimer = null;
    final startGeneration = ++_playbackStartGeneration;
    _prepareListeningSession(track, newSession: startOffset == Duration.zero);
    _seekRequestGeneration++;
    final initialPaused = !_wantsPlayback;
    _resetPlaybackPositionTracking(position: startOffset);
    _resetBufferedEndHighWater(position: startOffset);
    () async {
      if (shouldUseLocal) {
        if (offlineDownload == null) {
          _pushMessage(
            'No downloaded file available for ${track.title}.',
            level: LogLevel.warning,
          );
          _updatePlayback(isPlaying: false, isLoading: false);
          return;
        }
        await _startLocalPlayback(
          track,
          offlineDownload,
          startOffset: startOffset,
          initialPaused: initialPaused,
          startGeneration: startGeneration,
        );
        return;
      }
      try {
        _logPlaybackContext();
        _updatePlayback(
          isPlaying: !initialPaused,
          bitrateKbps: null,
          bufferRatio: 0.0,
          streamConnected: false,
          streamRttMs: null,
          isLocalPlayback: false,
          isLoading: true,
        );
        _audioOutputStarted = false;
        _pushMessage(
          'Playback track: id=${track.id} artist="${track.artist}" album="${track.album}" albumId="${track.albumId ?? ''}"',
          level: LogLevel.status,
        );
        _pushMessage('Starting playback for ${track.title}');
        _pushMessage(
          'Stream settings: mode=${settings.mode} quality=${settings.quality} frame_ms=${settings.frameMs}',
        );
        _audioEngine.setVolume(_playbackState.volume);
        await _audioEngine.playTrack(
          track: track,
          connection: connection,
          settings: settings,
          startOffset: startOffset,
          queueTrackIds: queueIds,
          quicPort: _quicPort,
          quickStart: quickStart,
          initialPaused: initialPaused,
        );
      } catch (err) {
        if (_disposed || startGeneration != _playbackStartGeneration) return;
        if (offlineDownload != null) {
          _pushMessage(
            'Remote playback failed; using downloaded file for ${track.title}.',
            level: LogLevel.warning,
          );
          await _startLocalPlayback(
            track,
            offlineDownload,
            startOffset: startOffset,
            initialPaused: !_wantsPlayback,
            startGeneration: startGeneration,
          );
          return;
        }
        _pushMessage('Playback failed: $err', level: LogLevel.error);
        _updatePlayback(isPlaying: false, isLoading: false);
      }
    }();
  }

  Future<void> _startLocalPlayback(
    Track track,
    OfflineTrackDownload download, {
    Duration startOffset = Duration.zero,
    required bool initialPaused,
    required int startGeneration,
  }) async {
    final filePath = download.filePath;
    if (filePath == null || !File(filePath).existsSync()) {
      _pushMessage(
        'Downloaded file is missing for ${track.title}.',
        level: LogLevel.warning,
      );
      _updatePlayback(isPlaying: false, isLoading: false);
      return;
    }

    try {
      _updatePlayback(
        isPlaying: !initialPaused,
        bitrateKbps: null,
        bufferRatio: 0.0,
        streamConnected: false,
        streamRttMs: null,
        isLocalPlayback: true,
        isLoading: true,
      );
      _audioOutputStarted = false;
      _pushMessage('Playing downloaded file: ${track.title}');
      _audioEngine.setVolume(_playbackState.volume);
      await _audioEngine.playLocalFile(
        track: track,
        filePath: filePath,
        contentType: download.contentType,
        startOffset: startOffset,
        initialPaused: initialPaused,
      );
    } catch (err) {
      if (_disposed || startGeneration != _playbackStartGeneration) return;
      _pushMessage('Local playback failed: $err', level: LogLevel.error);
      _updatePlayback(isPlaying: false, isLoading: false);
    }
  }

  void _logPlaybackContext() {
    _pushMessage('Server base URL: ${connection.baseUrl}');
    if (Platform.isIOS) {
      _pushMessage(
        'Local network permission: ${_localNetworkPermissionState.name}',
      );
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

  void _handleAudioEngineState(bool active, bool paused) {
    if (_disposed) return;
    if (active || paused) {
      return;
    }
    _recoverInterruptedRemoteStream();
  }

  void _recoverInterruptedRemoteStream() {
    final track = _playbackState.track;
    if (_disposed || track == null || _playbackState.isLocalPlayback) {
      return;
    }
    // A transport failure can arrive before the matching seek marker or output.
    // Restart from the latest requested position rather than stale output stats.
    final interruptedSeek = _seeking;
    final restartPositionMs = interruptedSeek
        ? _seekTargetMs
        : max(_actualPositionMs, _displayPositionMs);
    if (interruptedSeek) {
      _seekRequestGeneration++;
      _pendingSeekGeneration = null;
      _seeking = false;
      _lastSeekTrackId = null;
      _seekDirection = _SeekDirection.none;
      _seekOriginMs = restartPositionMs;
      _audioOutputStarted = false;
    }
    if (!_wantsPlayback || _isScrubbing) {
      _updatePlayback(
        isLoading: false,
        streamConnected: false,
        streamRttMs: null,
      );
      return;
    }
    if (!_canAttemptRemotePlayback) {
      _awaitingStreamReconnect = _wantsPlayback;
      _updatePlayback(
        isPlaying: _wantsPlayback,
        isLoading: false,
        streamConnected: false,
        streamRttMs: null,
      );
      return;
    }

    if (_recentlyRetriedInterruptedStream(track, restartPositionMs)) {
      _pushMessage(
        'Stream interrupted again; waiting for server reconnect.',
        level: LogLevel.warning,
      );
      _awaitingStreamReconnect = true;
      _updatePlayback(
        isPlaying: _wantsPlayback,
        isLoading: false,
        streamConnected: false,
        streamRttMs: null,
      );
      unawaited(_refreshServerAvailability(reconnectAttempt: true));
      return;
    }

    _lastInterruptedStreamRestartAt = _playbackClock();
    _lastInterruptedStreamRestartTrackId = track.id;
    _lastInterruptedStreamRestartPositionMs = restartPositionMs;
    _awaitingStreamReconnect = false;
    _pushMessage(
      interruptedSeek
          ? 'Stream interrupted during seek; reconnecting from the requested position.'
          : 'Stream interrupted; reconnecting from current position.',
      level: LogLevel.warning,
    );
    _updatePlayback(isLoading: true, streamConnected: false, streamRttMs: null);
    _startPlayback(
      track,
      startOffset: Duration(milliseconds: restartPositionMs),
      quickStart: false,
    );
  }

  void _retryPlaybackAfterServerReconnect() {
    if (_disposed ||
        !_awaitingStreamReconnect ||
        !_wantsPlayback ||
        _isScrubbing ||
        !_canAttemptRemotePlayback ||
        _audioEngine.hasActivePlayer) {
      return;
    }
    final track = _playbackState.track;
    if (track == null || _playbackState.isLocalPlayback) return;
    final positionMs = max(_actualPositionMs, _displayPositionMs);
    if (_recentlyRetriedInterruptedStream(track, positionMs)) {
      if (_streamRecoveryTimer == null) {
        final delay =
            _interruptedStreamRestartCooldown -
            _playbackClock().difference(_lastInterruptedStreamRestartAt!);
        _streamRecoveryTimer = Timer(delay, () {
          _streamRecoveryTimer = null;
          if (!_disposed && _wantsPlayback && _awaitingStreamReconnect) {
            unawaited(_refreshServerAvailability(reconnectAttempt: true));
          }
        });
      }
      return;
    }
    _streamRecoveryTimer?.cancel();
    _streamRecoveryTimer = null;
    _awaitingStreamReconnect = false;
    _lastInterruptedStreamRestartAt = _playbackClock();
    _lastInterruptedStreamRestartTrackId = track.id;
    _lastInterruptedStreamRestartPositionMs = positionMs;
    _updatePlayback(isPlaying: true, isLoading: true);
    _startPlayback(
      track,
      startOffset: Duration(milliseconds: positionMs),
      quickStart: false,
    );
  }

  bool _recentlyRetriedInterruptedStream(Track track, int positionMs) {
    final lastRestartAt = _lastInterruptedStreamRestartAt;
    final lastTrackId = _lastInterruptedStreamRestartTrackId;
    final lastPositionMs = _lastInterruptedStreamRestartPositionMs;
    if (lastRestartAt == null ||
        lastTrackId == null ||
        lastPositionMs == null ||
        lastTrackId != track.id) {
      return false;
    }
    if (_playbackClock().difference(lastRestartAt) >=
        _interruptedStreamRestartCooldown) {
      return false;
    }
    return (positionMs - lastPositionMs).abs() <=
        _interruptedStreamRestartPositionToleranceMs;
  }

  Future<void> _refreshServerPorts({
    Duration timeout = const Duration(seconds: 8),
    bool retryable = true,
  }) async {
    try {
      final ports = await connection.fetchServerPorts(
        timeout: timeout,
        retryable: retryable,
      );
      if (ports.quicEnabled && (ports.quicPort ?? 0) > 0) {
        _quicPort = ports.quicPort;
      } else {
        _quicPort = null;
      }
    } catch (err) {
      _quicPort = null;
      _pushMessage(
        'Failed to load server ports: $err',
        level: LogLevel.warning,
      );
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

  Future<void> refreshServerAvailability() async {
    await _refreshServerAvailability();
  }

  Future<void> _refreshServerAvailability({
    bool reconnectAttempt = false,
  }) async {
    final active = _serverAvailabilityFuture;
    if (active != null) {
      if (reconnectAttempt) {
        _setServerReconnecting(true);
      }
      return active;
    }
    final future = _runServerAvailabilityRefresh(
      reconnectAttempt: reconnectAttempt,
    );
    _serverAvailabilityFuture = future.whenComplete(() {
      _serverAvailabilityFuture = null;
      if (!_disposed) {
        _syncServerReconnectLoop();
      }
    });
    return _serverAvailabilityFuture!;
  }

  Future<void> _runServerAvailabilityRefresh({
    required bool reconnectAttempt,
  }) async {
    if (_healthPingInFlight) {
      return;
    }
    _healthPingInFlight = true;
    if (reconnectAttempt) {
      _setServerReconnecting(true);
    }
    try {
      final rttMs = await connection.pingHealthMs(
        timeout: const Duration(seconds: 4),
      );
      if (_disposed) return;
      if (_authState.status == SessionStatus.serverUnavailable) {
        if (rttMs == null) {
          _recordServerAvailabilityFailure(
            error: _authState.error ?? 'Server unavailable',
            reconnectAttempt: reconnectAttempt,
          );
          return;
        }
        await connection.fetchCapabilities();
        _serverHealthFailureCount = 0;
        _serverReconnectAttempt = 0;
        _restoreServerAvailability(rttMs: rttMs);
        return;
      }
      if (rttMs != null) {
        _serverHealthFailureCount = 0;
        if (!_audioEngine.hasActivePlayer) {
          _updatePlayback(streamConnected: true, streamRttMs: rttMs);
        }
        _retryPlaybackAfterServerReconnect();
        return;
      }
      _recordServerAvailabilityFailure(
        error: 'Server unavailable',
        reconnectAttempt: false,
      );
    } on ApiException catch (err) {
      if (err.statusCode == 401) {
        await _handleReconnectUnauthorized();
      } else {
        _recordServerAvailabilityFailure(
          error: 'Server unavailable: ${_formatApiError(err)}',
          reconnectAttempt: reconnectAttempt,
        );
      }
    } catch (err) {
      _recordServerAvailabilityFailure(
        error: 'Server unavailable: $err',
        reconnectAttempt: reconnectAttempt,
      );
    } finally {
      _healthPingInFlight = false;
      if (_authState.status == SessionStatus.serverUnavailable &&
          _authState.isReconnecting) {
        _setServerReconnecting(false);
      }
    }
  }

  void _recordServerAvailabilityFailure({
    required String error,
    required bool reconnectAttempt,
  }) {
    if (_disposed) return;
    _serverHealthFailureCount++;
    if (_hasActiveRemotePlayback) {
      return;
    }
    if (!_audioEngine.hasActivePlayer) {
      _updatePlayback(streamConnected: false, streamRttMs: null);
    }
    if (_authState.status == SessionStatus.serverUnavailable) {
      if (reconnectAttempt) {
        _serverReconnectAttempt++;
      }
      _setSessionStatus(
        SessionStatus.serverUnavailable,
        error: error,
        isReconnecting: false,
      );
      return;
    }
    if (_authState.isAuthorized &&
        _serverHealthFailureCount >= _serverUnavailableHealthFailureThreshold) {
      _markServerUnavailable(error: 'Server unavailable');
    }
  }

  Future<void> _pollHealth() => _refreshServerAvailability(
    reconnectAttempt: _authState.status == SessionStatus.serverUnavailable,
  );

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
        return const StreamSettings(mode: 'auto', quality: 'high', frameMs: 20);
      case StreamMode.high:
        return const StreamSettings(
          mode: 'fixed',
          quality: 'high',
          frameMs: 20,
        );
      case StreamMode.medium:
        return const StreamSettings(
          mode: 'fixed',
          quality: 'medium',
          frameMs: 20,
        );
      case StreamMode.low:
        return const StreamSettings(mode: 'fixed', quality: 'low', frameMs: 20);
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
      case ShuffleMode.liked:
        return 'liked';
      case ShuffleMode.currentPlaylist:
        return 'playlist';
    }
  }

  List<Track> _shuffleTracks(List<Track> tracks) {
    final shuffled = List<Track>.from(tracks);
    shuffled.shuffle(_shuffleRandom);
    return shuffled;
  }

  void _handleTrackFinished() {
    if (_disposed) return;
    if (!_wantsPlayback) return;
    if (_autoAdvanceInFlight) {
      return;
    }
    final now = DateTime.now();
    final seekStillResolving =
        _isScrubbing ||
        _seeking ||
        (_suppressAutoAdvanceUntil != null &&
            now.isBefore(_suppressAutoAdvanceUntil!) &&
            (!_audioOutputStarted || _playbackState.isLoading));
    if (seekStillResolving) {
      _autoAdvanceInFlight = false;
      return;
    }
    if (_ignoreCompleteUntil != null && now.isBefore(_ignoreCompleteUntil!)) {
      _autoAdvanceInFlight = false;
      return;
    }
    _autoAdvanceInFlight = true;
    _listeningSessionContext = null;
    if (_playbackState.repeatMode == RepeatMode.one) {
      final track = _playbackState.track;
      if (track == null) {
        _wantsPlayback = false;
        _updatePlayback(
          isPlaying: false,
          position: Duration.zero,
          bufferRatio: 0.0,
        );
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
            _wantsPlayback = false;
            _updatePlayback(
              isPlaying: false,
              position: Duration.zero,
              bufferRatio: 0.0,
            );
          }
          _autoAdvanceInFlight = false;
        }();
        return;
      }
      _updatePlayback(
        isPlaying: false,
        position: Duration.zero,
        bufferRatio: 0.0,
      );
      _wantsPlayback = false;
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
      _pushMessage(
        'Failed to load playback settings: $err',
        level: LogLevel.warning,
      );
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
