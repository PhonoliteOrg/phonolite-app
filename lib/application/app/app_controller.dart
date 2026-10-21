import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:phonolite_app/application/controllers/auth/server_failure_messages.dart';
import 'package:phonolite_app/application/controllers/library/catalog_controller.dart';
import 'package:phonolite_app/application/downloads/offline_download_manager.dart';
import 'package:phonolite_app/application/library/metadata_event_listener.dart';
import 'package:phonolite_app/application/listening_stats/listening_stats_sync.dart';
import 'package:phonolite_app/application/playback/now_playing_artwork.dart';
import 'package:phonolite_app/application/workflows/debounced_action.dart';
import 'package:phonolite_app/application/workflows/request_generation.dart';
import 'package:phonolite_app/data/models/auth/auth_credentials.dart';
import 'package:phonolite_app/data/models/auth/auth_state.dart';
import 'package:phonolite_app/data/models/auth/local_network_permission_state.dart';
import 'package:phonolite_app/data/models/auth/server_trust.dart';
import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/data/models/diagnostics/log_entry.dart';
import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/library/artist_credit.dart';
import 'package:phonolite_app/data/models/library/artist_releases.dart';
import 'package:phonolite_app/data/models/library/local_library_selection.dart';
import 'package:phonolite_app/data/models/library/metadata_update_event.dart';
import 'package:phonolite_app/data/models/library/search_result.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/listening_stats/listening_event.dart';
import 'package:phonolite_app/data/models/listening_stats/listening_report.dart';
import 'package:phonolite_app/data/models/listening_stats/listening_stats_snapshot.dart';
import 'package:phonolite_app/data/models/playback/custom_shuffle_settings.dart';
import 'package:phonolite_app/data/models/playback/native_now_playing_snapshot.dart';
import 'package:phonolite_app/data/models/playback/native_remote_command.dart';
import 'package:phonolite_app/data/models/playback/output_device.dart';
import 'package:phonolite_app/data/models/playback/playback_state.dart';
import 'package:phonolite_app/data/models/playback/playback_workflow_values.dart';
import 'package:phonolite_app/data/models/playback/vehicle_item.dart';
import 'package:phonolite_app/data/models/playback/vehicle_request.dart';
import 'package:phonolite_app/data/models/playback/vehicle_response.dart';
import 'package:phonolite_app/data/models/preferences/offline_storage_locations.dart';
import 'package:phonolite_app/data/projections/library/offline_library_views.dart';
import 'package:phonolite_app/data/repositories/listening_stats_service.dart';
import 'package:phonolite_app/data/storage/auth/auth_storage.dart';
import 'package:phonolite_app/data/storage/auth/server_trust_store.dart';
import 'package:phonolite_app/data/storage/logs/app_log.dart';
import 'package:phonolite_app/data/storage/offline/library/offline_library.dart';
import 'package:phonolite_app/data/storage/preferences/custom_shuffle_settings_storage.dart';
import 'package:phonolite_app/data/storage/preferences/playback_preferences.dart';
import 'package:phonolite_app/infrastructure/artwork/now_playing_artwork_loader.dart';
import 'package:phonolite_app/infrastructure/audio/engine/audio_engine.dart';
import 'package:phonolite_app/infrastructure/platform/connectivity/connectivity_signal_source.dart';
import 'package:phonolite_app/infrastructure/platform/media/now_playing_platform_service.dart'
    show NowPlayingPlatformService;
import 'package:phonolite_app/infrastructure/platform/media/vehicle_surface_service.dart';
import 'package:phonolite_app/infrastructure/platform/permissions/local_network_permission_service.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';

export 'package:phonolite_app/data/models/auth/local_network_permission_state.dart';
export 'package:phonolite_app/data/models/playback/playback_state.dart';

part 'package:phonolite_app/application/app/collections/favorites_coordinator.dart';
part 'package:phonolite_app/application/app/collections/playlist_coordinator.dart';
part 'package:phonolite_app/application/app/diagnostics/diagnostics_coordinator.dart';
part 'package:phonolite_app/application/app/downloads/download_coordinator.dart';
part 'package:phonolite_app/application/app/library/library_coordinator.dart';
part 'package:phonolite_app/application/app/library/playback_track_resolver.dart';
part 'package:phonolite_app/application/app/library/vehicle_library_coordinator.dart';
part 'package:phonolite_app/application/app/listening_stats/listening_stats_coordinator.dart';
part 'package:phonolite_app/application/app/local_data/local_data_coordinator.dart';
part 'package:phonolite_app/application/app/playback/native_media_coordinator.dart';
part 'package:phonolite_app/application/app/playback/playback_coordinator.dart';
part 'package:phonolite_app/application/app/playback/playback_queue.dart';
part 'package:phonolite_app/application/app/playback/seek_coordinator.dart';
part 'package:phonolite_app/application/app/playback/shuffle_coordinator.dart';
part 'package:phonolite_app/application/app/playback/stream_recovery_coordinator.dart';
part 'package:phonolite_app/application/app/preferences/preferences_coordinator.dart';
part 'package:phonolite_app/application/app/session/local_network_permission_coordinator.dart';
part 'package:phonolite_app/application/app/session/server_availability_coordinator.dart';
part 'package:phonolite_app/application/app/session/session_coordinator.dart';

const Object _unset = Object();

/// Owns application workflows and their current state observations.
///
/// State streams support multiple listeners, deliver asynchronously and do not
/// replay an initial value. Read the corresponding getter for the current state;
/// reading and subscribing are separate operations. Operations report failures
/// through their futures or application messages. [close] closes owned streams.
class AppController
    with
        _ListeningStatsFacade,
        _SessionFacade,
        _PreferencesFacade,
        _LocalNetworkPermissionFacade,
        _NativeMediaFacade,
        _SeekFacade,
        _PlaybackFacade,
        _StreamRecoveryFacade,
        _ServerAvailabilityFacade,
        _LibraryFacade,
        _PlaylistFacade,
        _FavoritesFacade,
        _DiagnosticsFacade,
        _LocalDataFacade,
        _PlaybackQueueFacade,
        _ShuffleFacade,
        _PlaybackTrackResolverFacade,
        _VehicleLibraryFacade,
        _DownloadFacade {
  static const Duration storedSessionRestoreTimeout = Duration(seconds: 10);
  static const Duration _storedSessionRequestTimeout = Duration(seconds: 4);
  static const Duration _offlineRefreshTimeout = Duration(seconds: 5);
  static const Duration _seekCompletionGuard = Duration(seconds: 8);
  static const int _seekCompletionToleranceMs = 400;
  static const Duration _interruptedStreamRestartCooldown = Duration(seconds: 8);
  static const int _interruptedStreamRestartPositionToleranceMs = 5000;
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
  static const Duration _serverLogoutBestEffortTimeout = Duration(milliseconds: 750);

  @override
  late final _DownloadCoordinator _downloadsCoordinator;
  @override
  late final _VehicleLibraryCoordinator _vehicleCoordinator;
  @override
  late final _PlaybackTrackResolver _resolverCoordinator;
  @override
  late final _ShuffleCoordinator _shuffleCoordinator;
  @override
  late final _PlaybackQueue _queueCoordinator;
  @override
  late final _LocalDataCoordinator _localDataCoordinator;
  @override
  late final _DiagnosticsCoordinator _diagnosticsCoordinator;
  @override
  late final _FavoritesCoordinator _favoritesCoordinator;
  @override
  late final _PlaylistCoordinator _playlistsCoordinator;
  @override
  late final _LibraryCoordinator _libraryCoordinator;
  @override
  late final _ServerAvailabilityCoordinator _availabilityCoordinator;
  @override
  late final _StreamRecoveryCoordinator _recoveryCoordinator;
  @override
  late final _PlaybackCoordinator _playbackCoordinator;
  @override
  late final _SeekCoordinator _seekCoordinator;
  @override
  late final _NativeMediaCoordinator _nativeCoordinator;
  @override
  late final _LocalNetworkPermissionCoordinator _permissionsCoordinator;
  @override
  late final _PreferencesCoordinator _preferencesCoordinator;
  @override
  late final _SessionCoordinator _sessionCoordinator;
  @override
  late final _ListeningStatsCoordinator _statsCoordinator;
  late final CatalogController catalog = CatalogController(connection);
  Future<void>? _initialization;
  Future<void>? _shutdown;
  bool _initialized = false;
  bool _startupBegun = false;
  final ServerConnection connection;
  final ConnectivitySignalSource _connectivitySignalSource;
  final OfflineLibraryStorage _offlineStorage;
  final OfflineDownloadManager _offlineDownloadManager;
  final AudioEngineFactory _audioEngineFactory;
  final NowPlayingPlatformService _nowPlayingPlatform;
  final NowPlayingArtwork _artwork;
  final VehicleSurfaceService _vehicleSurface;
  final LocalNetworkPermissionService _localNetworkPermissions;
  final AuthStorage _authStorage;
  final CustomShuffleSettingsStorage _customShuffleStorage;
  final PlaybackPreferencesStorage _playbackPreferencesStorage;
  final ListeningStatsService _listeningStats;
  final DateTime Function() _playbackClock;
  late final LogListener _logListener;
  bool _disposed = false;

  AppController({
    required this.connection,
    AudioEngineFactory audioEngineFactory = AudioEngine.new,
    OfflineDownloadManager? offlineDownloadManager,
    OfflineLibraryStorage offlineStorage = const OfflineLibraryStorage(),
    AuthStorage authStorage = const AuthStorage(),
    CustomShuffleSettingsStorage customShuffleStorage = const CustomShuffleSettingsStorage(),
    PlaybackPreferencesStorage playbackPreferencesStorage = const PlaybackPreferencesStorage(),
    ConnectivitySignalSource? connectivitySignalSource,
    NowPlayingPlatformService? nowPlayingPlatformService,
    NowPlayingArtworkLoader? nowPlayingArtworkLoader,
    VehicleSurfaceService? vehicleSurfaceService,
    LocalNetworkPermissionService? localNetworkPermissionService,
    ListeningStatsService? listeningStatsService,
    DateTime Function()? playbackClock,
  }) : _audioEngineFactory = audioEngineFactory,
       _playbackClock = playbackClock ?? DateTime.now,
       _listeningStats =
           listeningStatsService ?? ListeningStatsService(inMemory: Platform.environment.containsKey('FLUTTER_TEST')),
       _offlineStorage = offlineStorage,
       _offlineDownloadManager =
           offlineDownloadManager ?? OfflineDownloadManager(connection: connection, storage: offlineStorage),
       _authStorage = authStorage,
       _customShuffleStorage = customShuffleStorage,
       _playbackPreferencesStorage = playbackPreferencesStorage,
       _connectivitySignalSource = connectivitySignalSource ?? ConnectivityPlusSignalSource(),
       _nowPlayingPlatform = nowPlayingPlatformService ?? NowPlayingPlatformService(),
       _artwork = NowPlayingArtwork(loader: nowPlayingArtworkLoader ?? NowPlayingArtworkLoader()),
       _vehicleSurface = vehicleSurfaceService ?? VehicleSurfaceService(),
       _localNetworkPermissions = localNetworkPermissionService ?? LocalNetworkPermissionService() {
    // Create state owners in the same zone as the parent and before UI subscriptions.
    _downloadsCoordinator = _DownloadCoordinator(this);
    _vehicleCoordinator = _VehicleLibraryCoordinator(this);
    _resolverCoordinator = _PlaybackTrackResolver(this);
    _shuffleCoordinator = _ShuffleCoordinator(this);
    _queueCoordinator = _PlaybackQueue(this);
    _localDataCoordinator = _LocalDataCoordinator(this);
    _diagnosticsCoordinator = _DiagnosticsCoordinator(this);
    _favoritesCoordinator = _FavoritesCoordinator(this);
    _playlistsCoordinator = _PlaylistCoordinator(this);
    _libraryCoordinator = _LibraryCoordinator(this);
    _availabilityCoordinator = _ServerAvailabilityCoordinator(this);
    _recoveryCoordinator = _StreamRecoveryCoordinator(this);
    _playbackCoordinator = _PlaybackCoordinator(this);
    _seekCoordinator = _SeekCoordinator(this);
    _nativeCoordinator = _NativeMediaCoordinator(this);
    _permissionsCoordinator = _LocalNetworkPermissionCoordinator(this);
    _preferencesCoordinator = _PreferencesCoordinator(this);
    _sessionCoordinator = _SessionCoordinator(this);
    _statsCoordinator = _ListeningStatsCoordinator(this);

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
      repeatMode: PlaybackRepeatMode.off,
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

  bool get isInitialized => _initialized;

  Map<String, String> get artworkHeaders => connection.authorizationHeaders;

  AudioEngine get _audioEngine => _audio ?? (throw StateError('Call initialize() before using playback'));

  bool get statsCollectionEnabled => _listeningStats.enabled;

  int get pendingStatsCount => _listeningStats.pendingCount;

  DateTime? get statsLastSyncedAt => _listeningStats.lastSyncedAt;

  Stream<List<OfflineTrackDownload>> get offlineDownloadsStream => _offlineDownloadManager.stream;

  Stream<OfflineDownloadSnapshot> get offlineDownloadSnapshotStream => _offlineDownloadManager.downloadSnapshotStream;

  Stream<OfflineLibrarySnapshot> get offlineLibrarySnapshotStream => _offlineDownloadManager.librarySnapshotStream;

  Stream<List<Track>> get localLikedStream => _offlineDownloadManager.localLikedStream;

  Stream<List<Playlist>> get localPlaylistsStream => _offlineDownloadManager.localPlaylistsStream;

  Stream<List<Track>> get localPlaylistTracksStream => _offlineDownloadManager.localPlaylistTracksStream;

  List<OfflineTrackDownload> get offlineDownloads => _offlineDownloadManager.downloads;

  OfflineDownloadSnapshot get offlineDownloadSnapshot => _offlineDownloadManager.downloadSnapshot;

  OfflineLibrarySnapshot get offlineLibrarySnapshot => _offlineDownloadManager.librarySnapshot;

  List<OfflineDownloadJob> get offlineDownloadJobs => _offlineDownloadManager.jobs;

  List<Track> get offlineTracks => _offlineDownloadManager.localDownloadedTracks();

  List<Track> get localLiked => _offlineDownloadManager.localLiked;

  List<Playlist> get localPlaylists => _offlineDownloadManager.localPlaylists;

  List<Track> get localPlaylistTracks => _offlineDownloadManager.localPlaylistTracks;

  CustomShuffleSettings get customShuffleSettings => CustomShuffleSettings(
    artistIds: customShuffleArtistIds,
    genres: customShuffleGenres,
    localArtistIds: localCustomShuffleArtistIds,
    localGenres: localCustomShuffleGenres,
  );

  bool get localNetworkPermissionSupported => _localNetworkPermissions.isSupported;

  /// Starts owned audio, storage, platform subscriptions and timers once.
  /// Construction alone is inert. Injected dependencies are owned by this
  /// controller and are released by [close], including on startup failure.
  Future<void> initialize() {
    if (_disposed) {
      return Future<void>.error(StateError('Controller is closed'));
    }

    return _initialization ??= _initialize();
  }

  void dispose() => unawaited(close());

  /// Awaitable, idempotent release of resources, including partial startup.
  Future<void> close() => _shutdown ??= _close();

  Future<void> openAppSettings() async {
    if (!localNetworkPermissionSupported) {
      return;
    }

    try {
      await _localNetworkPermissions.openAppSettings();
    } catch (_) {}
  }

  void handleAppLifecycleState(AppLifecycleState state) {
    if (_disposed || !_startupBegun) {
      return;
    }

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

  Future<void> _initialize() async {
    _startupBegun = true;

    try {
      AppLogger.instance.attach(_logListener, includeHistory: true);
      connection.onTransportFailure = _handleServerTransportFailure;

      _carPlayOfflineLibrarySubscription = _offlineDownloadManager.librarySnapshotStream.listen(
        (_) => _scheduleCarPlayStateUpdate(),
      );
      _carPlayLocalLikedSubscription = _offlineDownloadManager.localLikedStream.listen(
        (_) => _scheduleCarPlayStateUpdate(),
      );
      _carPlayLocalPlaylistsSubscription = _offlineDownloadManager.localPlaylistsStream.listen(
        (_) => _scheduleCarPlayStateUpdate(),
      );

      _audio = _audioEngineFactory(
        onMessage: _pushMessage,
        onStats: _handleAudioStats,
        onComplete: _handleTrackFinished,
        onStarted: _handleAudioStarted,
        onState: _handleAudioEngineState,
      );
      _audio!.onListeningSegment = _recordListeningSegment;
      await _audio!.initialize();

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

      if (!_disposed) {
        _initialized = true;
      }
    } catch (_) {
      if (_disposed) {
        return;
      }

      await close();

      rethrow;
    }
  }

  void _handleAudioStats(
    Duration position,
    Duration bufferedAhead,
    double? bitrateKbps,
    int? rttMs,
    bool isLocalPlayback,
  ) {
    if (_disposed) {
      return;
    }

    if (!_audioOutputStarted && _playbackState.isPlaying && !_audioEngine.isPaused) {
      _audioOutputStarted = true;
      _updatePlayback(isLoading: false, nowPlaying: false);
    }

    final duration = _playbackState.duration;
    var rawClamped = position;

    if (duration != Duration.zero && position > duration) {
      rawClamped = duration;
    }

    final correctedPositionMs = _correctReportedPositionMs(rawClamped.inMilliseconds);
    final clamped = Duration(milliseconds: correctedPositionMs);

    _actualPositionMs = correctedPositionMs;
    _updateDisplayPosition(_actualPositionMs);
    _maybeClearSeekHold(clamped);
    _updateBufferedEndHighWater(
      duration: duration,
      position: Duration(milliseconds: _actualPositionMs),
      bufferedAhead: bufferedAhead,
    );

    final displayBufferRatio = _displayBufferRatio(duration: duration);
    final nextRtt = rttMs ?? _playbackState.streamRttMs;

    _updatePlayback(
      position: Duration(milliseconds: _displayPositionMs),
      bufferRatio: displayBufferRatio,
      bitrateKbps: isLocalPlayback ? null : bitrateKbps,
      streamConnected: !isLocalPlayback,
      streamRttMs: isLocalPlayback ? null : nextRtt,
      isLocalPlayback: isLocalPlayback,
    );
    _maybeAutoAdvance(clamped, bufferedAhead);
  }

  void _handleAudioStarted() {
    if (_disposed) {
      return;
    }

    if (!_audioOutputStarted) {
      _audioOutputStarted = true;
      _updatePlayback(isLoading: false);
      _pushNowPlayingUpdate(force: true);
    }
  }

  Future<void> _close() async {
    _disposed = true;
    _initialized = false;
    _sessionRestores.advance();

    _statsRefreshDebounce.cancel();
    await _listeningSync?.close();
    await _listeningSubscription?.cancel();

    if (_startupBegun) {
      connection.onTransportFailure = null;
    }

    _stopMetadataEventListener();

    final clearNowPlaying = _startupBegun ? _clearNowPlaying() : Future<void>.value();

    _artwork.clear();

    _healthTimer?.cancel();
    _healthTimer = null;
    _stopServerReconnectLoop(resetAttempts: true);

    _isScrubbing = false;
    _seekRequests.advance();
    _playbackStarts.advance();
    _wantsPlayback = false;

    _streamRecoveryTimer?.cancel();
    _streamRecoveryTimer = null;

    _volumeSaveDebounce.cancel();
    _carPlayStateDebounce.cancel();
    _flushVolumeSave();

    final cancellations = <Future<void>>[
      if (_connectivitySubscription != null) _connectivitySubscription!.cancel(),
      if (_carPlayOfflineLibrarySubscription != null) _carPlayOfflineLibrarySubscription!.cancel(),
      if (_carPlayLocalLikedSubscription != null) _carPlayLocalLikedSubscription!.cancel(),
      if (_carPlayLocalPlaylistsSubscription != null) _carPlayLocalPlaylistsSubscription!.cancel(),
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

    if (_audio != null) {
      _audio!.onListeningSegment = null;
    }

    await _listeningStats.close();
  }
}
