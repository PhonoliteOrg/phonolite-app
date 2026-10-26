part of 'package:phonolite_app/application/app/app_controller.dart';

class _PlaybackCoordinator {
  final AppController _host;
  final _playbackStarts = RequestGeneration();
  bool _wantsPlayback = false;
  bool _audioOutputStarted = false;
  DateTime? _lastStartPlaybackAt;
  String? _lastStartPlaybackTrackId;
  int? _lastStartPlaybackOffsetMs;
  final _playbackController = StreamController<PlaybackState>.broadcast();
  late PlaybackState _playbackState;
  List<OutputDevice> _outputDevices = <OutputDevice>[];
  int _outputDeviceId = kDefaultOutputDeviceId;
  String? _outputDeviceName;

  _PlaybackCoordinator(this._host);

  Stream<PlaybackState> get playbackStream => _playbackController.stream;

  PlaybackState get playbackState => _playbackState;

  List<OutputDevice> get outputDevices => List.unmodifiable(_outputDevices);

  int get outputDeviceId => _outputDeviceId;

  String? get outputDeviceName => _outputDeviceName;

  bool get _hasActiveRemotePlayback {
    return _playbackState.track != null &&
        _playbackState.isPlaying &&
        !_playbackState.isLocalPlayback &&
        _host._audioEngine.hasActivePlayer;
  }

  Future<void> stop() => _stop();

  Future<void> nextTrack({bool fromAutoAdvance = false}) async {
    try {
      if (!fromAutoAdvance) {
        _host._armAutoAdvanceGuard();
      }

      if (_playbackState.shuffleMode != ShuffleMode.off && _playbackState.shuffleScope == ActionScope.server) {
        await _host._shuffleCoordinator._navigateServerShuffle(1);
        return;
      }

      if (_playbackState.shuffleMode != ShuffleMode.off) {
        final ensured = await _host._ensureShuffleQueue(play: false);

        if (!ensured && _host._playQueue.isEmpty) {
          _host._pushMessage('No shuffle queue available');

          return;
        }
      } else if (_playbackState.queueSource == PlaybackQueueSource.offline && _host._playQueue.isEmpty) {
        _host._pushMessage('No queue to advance');

        return;
      } else if (_host._playQueue.isEmpty ||
          (_host._queueShuffleMode != ShuffleMode.off && _host._queueShuffleMode != _playbackState.shuffleMode)) {
        final ensured = await _host._ensureAlbumQueueFromCurrent();

        if (!ensured && _host._playQueue.isEmpty) {
          _host._pushMessage('No album queue available');

          return;
        }
      }

      if (_host._playQueue.isEmpty) {
        _host._pushMessage('No queue to advance');

        return;
      }

      _host._syncPlayIndexWithCurrent();
      _host._playIndex = (_host._playIndex + 1) % _host._playQueue.length;

      await _playCurrent();
    } on ApiException catch (err) {
      _host._handleApiError(err, context: 'next track');
    } catch (err) {
      _host._pushMessage('Failed to move to next track: $err');
    } finally {
      if (fromAutoAdvance) {
        _host._autoAdvanceInFlight = false;
      }
    }
  }

  Future<void> prevTrack({bool fromAutoAdvance = false}) async {
    try {
      if (!fromAutoAdvance) {
        _host._armAutoAdvanceGuard();
      }

      if (_playbackState.shuffleMode != ShuffleMode.off && _playbackState.shuffleScope == ActionScope.server) {
        await _host._shuffleCoordinator._navigateServerShuffle(-1);
        return;
      }

      if (_playbackState.shuffleMode != ShuffleMode.off) {
        final ensured = await _host._ensureShuffleQueue(play: false);

        if (!ensured && _host._playQueue.isEmpty) {
          _host._pushMessage('No shuffle queue available');

          return;
        }
      } else if (_playbackState.queueSource == PlaybackQueueSource.offline && _host._playQueue.isEmpty) {
        _host._pushMessage('No queue to rewind');

        return;
      } else if (_host._playQueue.isEmpty ||
          (_host._queueShuffleMode != ShuffleMode.off && _host._queueShuffleMode != _playbackState.shuffleMode)) {
        final ensured = await _host._ensureAlbumQueueFromCurrent();

        if (!ensured && _host._playQueue.isEmpty) {
          _host._pushMessage('No album queue available');

          return;
        }
      }

      if (_host._playQueue.isEmpty) {
        _host._pushMessage('No queue to rewind');

        return;
      }

      _host._syncPlayIndexWithCurrent();
      _host._playIndex = (_host._playIndex - 1) < 0 ? _host._playQueue.length - 1 : _host._playIndex - 1;

      await _playCurrent();
    } on ApiException catch (err) {
      _host._handleApiError(err, context: 'previous track');
    } catch (err) {
      _host._pushMessage('Failed to move to previous track: $err');
    }
  }

  Future<void> pause(bool paused) async {
    try {
      _wantsPlayback = !paused;
      _host._awaitingStreamReconnect = false;
      _host._streamRecoveryTimer?.cancel();
      _host._streamRecoveryTimer = null;

      if (!paused) {
        if (_playbackState.track == null) {
          final shuffleEnabled = _playbackState.shuffleMode != ShuffleMode.off;

          if (shuffleEnabled) {
            final started = await _host._ensureShuffleQueue(play: true);

            if (!started) {
              _wantsPlayback = false;
              _updatePlayback(isPlaying: false);
            }
          } else {
            _host._pushMessage('No track selected');
            _wantsPlayback = false;
            _updatePlayback(isPlaying: false);
          }

          return;
        }
      }

      _updatePlayback(isPlaying: !paused, isLoading: paused ? false : null);

      if (paused) {
        _host._audioEngine.pause();
      } else if (_playbackState.track != null) {
        if (!_host._audioEngine.hasActivePlayer) {
          _host._lastInterruptedStreamRestartAt = null;
          _startPlayback(_playbackState.track!, startOffset: _playbackState.position);
        } else {
          _host._audioEngine.resume();
        }
      }

      await _host._pushNowPlayingUpdate(force: true);
    } on ApiException catch (err) {
      _host._handleApiError(err, context: 'pause');
    } catch (err) {
      _host._pushMessage('Failed to pause: $err');
    }
  }

  void updateShuffleMode(ShuffleMode mode, {ActionScope? scope}) {
    _host._shuffleCoordinator._clearServerShuffleSession();
    final nextScope = scope ?? _playbackState.shuffleScope;

    _updatePlayback(shuffleMode: mode, shuffleScope: nextScope);
    _host._pushMessage('Shuffle: ${nextScope.name} ${mode.name}');

    if (mode != ShuffleMode.off) {
      _host._queueShuffleMode = ShuffleMode.off;
      _host._queueShuffleScope = null;
      _host._queueShuffleArtistId = null;
      _host._queueShuffleAlbumId = null;
      _host._queueShufflePlaylistId = null;
    }
  }

  void toggleRepeatMode() {
    final next = _playbackState.repeatMode == PlaybackRepeatMode.off ? PlaybackRepeatMode.one : PlaybackRepeatMode.off;

    _updatePlayback(repeatMode: next);
    _host._pushMessage('Repeat: ${next.name}');

    if (_host._authState.isAuthorized) {
      () async {
        await _host._persistPlaybackSettings(next);
      }();
    }
  }

  void updateStreamMode(StreamMode mode) {
    if (mode == _playbackState.streamMode) {
      return;
    }

    _updatePlayback(streamMode: mode);
    _host._pushMessage('Stream: ${mode.name}');

    final track = _playbackState.track;

    if (track != null &&
        !_playbackState.isLocalPlayback &&
        (_playbackState.isPlaying || _host._audioEngine.hasActivePlayer)) {
      // A paused output must also adopt the selected encoder settings. The
      // restart preserves _wantsPlayback, so prebuffering does not resume it.
      // Settings changes are distinct requests even at the same track/offset.
      _lastStartPlaybackAt = null;
      _startPlayback(track, startOffset: _playbackState.position);
    }
  }

  void setVolume(double value) {
    _host._volumeTouched = true;
    _applyVolume(value, persist: true);
  }

  Future<List<OutputDevice>> listOutputDevices({bool refresh = false}) async {
    if (_outputDevices.isNotEmpty && !refresh) {
      return _host.outputDevices;
    }

    _outputDevices = await _host._audioEngine.listOutputDevices();

    final current = _outputDevices.firstWhere(
      (device) => device.id == _outputDeviceId,
      orElse: () => OutputDevice(id: kDefaultOutputDeviceId, name: 'System Default'),
    );

    _outputDeviceId = current.id;
    _outputDeviceName = current.name;

    return _host.outputDevices;
  }

  Future<void> selectOutputDevice(OutputDevice device) async {
    if (_outputDeviceId == device.id) {
      return;
    }

    final wasPlaying = _playbackState.isPlaying;

    _outputDeviceId = device.id;
    _outputDeviceName = device.name;
    _host._audioEngine.setOutputDevice(device.id);
    _host._pushMessage('Output device: ${device.name}');

    final track = _playbackState.track;
    if (track == null) {
      return;
    }

    if (_host._audioEngine.hasActivePlayer || wasPlaying) {
      _lastStartPlaybackAt = null;
      _startPlayback(track, startOffset: _playbackState.position);
    }
  }

  Future<void> _stop({bool requireFileRelease = false}) async {
    _host._shuffleCoordinator._clearServerShuffleSession();
    try {
      _host._resetTrackTransitionState();
      _host._listeningSessionContext = null;

      final shouldDisableShuffle =
          _playbackState.shuffleScope == ActionScope.local ||
          _playbackState.shuffleMode == ShuffleMode.album ||
          _playbackState.shuffleMode == ShuffleMode.artist ||
          _playbackState.shuffleMode == ShuffleMode.currentPlaylist;

      _host._playQueue = <Track>[];
      _host._playIndex = 0;
      _host._queueShuffleMode = ShuffleMode.off;
      _host._queueShuffleScope = null;
      _host._queueShuffleArtistId = null;
      _host._queueShuffleAlbumId = null;
      _host._queueShufflePlaylistId = null;
      _host._offlineQueueSource = OfflineQueueSource.none;
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

      await _host._audioEngine.stop(waitForRelease: requireFileRelease);

      _audioOutputStarted = false;
      _closeStreamControl();
    } on ApiException catch (err) {
      _host._handleApiError(err, context: 'stop');

      if (requireFileRelease) {
        rethrow;
      }
    } catch (err) {
      _host._pushMessage('Failed to stop: $err');

      if (requireFileRelease) {
        rethrow;
      }
    }
  }

  void _applyVolume(double value, {required bool persist}) {
    final clamped = value.clamp(0.0, 1.0);

    _host._audioEngine.setVolume(clamped);
    _updatePlayback(volume: clamped);

    if (persist) {
      _scheduleVolumeSave(clamped);
    }
  }

  void _scheduleVolumeSave(double value) {
    _host._pendingVolumeSave = value;
    _host._volumeSaveQueued = true;
    _host._volumeSaveDebounce.cancel();
    _host._volumeSaveDebounce.schedule(const Duration(milliseconds: 350), _flushVolumeSave);
  }

  void _flushVolumeSave() {
    if (!_host._volumeSaveQueued) {
      return;
    }

    _host._volumeSaveQueued = false;
    final value = _host._pendingVolumeSave;

    _host._volumeSaveChain = _host._volumeSaveChain.then((_) => _host._playbackPreferencesStorage.writeVolume(value));
  }

  Future<void> _playCurrent() async {
    if (_host._playQueue.isEmpty) {
      return;
    }

    _host._autoAdvanceInFlight = false;

    final track = _host._playQueue[_host._playIndex];

    _host._playQueue = _host._playQueue.map((item) => item.id == track.id ? track : item).toList();
    _host._pushMessage(
      'Now playing: id=${track.id} artist="${track.artist}" album="${track.album}" albumId="${track.albumId ?? ''}"',
    );
    _host._bumpNowPlayingEpoch();
    _host._resetTrackTransitionState();
    _wantsPlayback = true;
    _updatePlayback(
      track: track,
      isPlaying: true,
      position: Duration.zero,
      duration: Duration(milliseconds: track.durationMs),
      bufferRatio: 0.0,
    );
    _startPlayback(track);
    _host._shuffleCoordinator._prefetchServerShuffle();

    if (_playbackState.queueSource != PlaybackQueueSource.offline) {
      final server = _host.connection.baseUrl;
      final token = _host.connection.token;
      final metadataRevision = _host._metadataReadRevision;

      // Metadata is display data; do not delay audio while fetching it.
      for (final queued in _host._playQueue.skip(_host._playIndex).take(2)) {
        if (!_host._needsTrackHydration(queued)) {
          continue;
        }

        Future<void> hydrateQueuedMetadata() async {
          try {
            final full = await _host._hydrateTrackForPlayback(queued);

            if (_host._disposed ||
                server != _host.connection.baseUrl ||
                token != _host.connection.token ||
                metadataRevision != _host._metadataReadRevision) {
              return;
            }

            _host._playQueue = _host._playQueue
                .map(
                  (item) => item.id == full.id ? full.copyWith(liked: item.liked, inPlaylists: item.inPlaylists) : item,
                )
                .toList();

            final current = _playbackState.track;

            if (current?.id == full.id) {
              _updatePlayback(
                track: full.copyWith(liked: current!.liked, inPlaylists: current.inPlaylists),
                duration: Duration(milliseconds: full.durationMs),
              );
            }
          } catch (error) {
            _host._pushMessage('Playback metadata lookup failed: $error');
          }
        }

        unawaited(hydrateQueuedMetadata());
      }
    }
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
    PlaybackRepeatMode? repeatMode,
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
    if (_host._disposed) {
      return;
    }

    final resolvedLocalPlaybackSource =
        localPlaybackSource ??
        (queueSource != null && queueSource != PlaybackQueueSource.offline ? LocalPlaybackSource.none : null);

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
      bitrateKbps: bitrateKbps ?? _playbackState.bitrateKbps,
      streamConnected: streamConnected,
      streamRttMs: streamRttMs ?? _playbackState.streamRttMs,
      queueSource: queueSource,
      queueSourcePlaylistId: queueSourcePlaylistId == _unset
          ? _playbackState.queueSourcePlaylistId
          : queueSourcePlaylistId,
      localPlaybackSource: resolvedLocalPlaybackSource,
      isLocalPlayback: isLocalPlayback,
    );
    _playbackController.add(_playbackState);

    if (nowPlaying) {
      _host._pushNowPlayingUpdate();
    }
  }

  void _startPlayback(Track track, {Duration startOffset = Duration.zero, bool quickStart = true}) {
    final settings = _streamSettings(_playbackState.streamMode);
    final queueIds = _host._buildQueueIds(track.id, 3);
    final offlineDownload = _host.availableOfflineDownloadForTrack(track.id);
    final shouldUseLocal =
        _playbackState.queueSource == PlaybackQueueSource.offline || !_host._canAttemptRemotePlayback;
    final now = _host._playbackClock();
    final offsetMs = startOffset.inMilliseconds;

    if (_host._audioEngine.hasActivePlayer &&
        _lastStartPlaybackTrackId == track.id &&
        _lastStartPlaybackOffsetMs == offsetMs &&
        _lastStartPlaybackAt != null &&
        now.difference(_lastStartPlaybackAt!) < const Duration(milliseconds: 800)) {
      _host._pushMessage('Playback already active; skipping duplicate start for ${track.title}.');

      return;
    }

    _lastStartPlaybackAt = now;
    _lastStartPlaybackTrackId = track.id;
    _lastStartPlaybackOffsetMs = offsetMs;
    _host._awaitingStreamReconnect = false;
    _host._streamRecoveryTimer?.cancel();
    _host._streamRecoveryTimer = null;

    final startGeneration = _playbackStarts.advance();

    _host._prepareListeningSession(track, newSession: startOffset == Duration.zero);
    _host._seekRequests.advance();

    final initialPaused = !_wantsPlayback;

    _host._resetPlaybackPositionTracking(position: startOffset);
    _host._resetBufferedEndHighWater(position: startOffset);

    Future<void> startSelectedSource() async {
      if (shouldUseLocal) {
        if (offlineDownload == null) {
          _host._pushMessage('No downloaded file available for ${track.title}.', level: LogLevel.warning);
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
        _host._pushMessage(
          'Playback track: id=${track.id} artist="${track.artist}" album="${track.album}" albumId="${track.albumId ?? ''}"',
          level: LogLevel.status,
        );
        _host._pushMessage('Starting playback for ${track.title}');
        _host._pushMessage(
          'Stream settings: mode=${settings.mode} quality=${settings.quality} frame_ms=${settings.frameMs}',
        );
        _host._audioEngine.setVolume(_playbackState.volume);

        await _host._audioEngine.playTrack(
          track: track,
          connection: _host.connection,
          settings: settings,
          startOffset: startOffset,
          queueTrackIds: queueIds,
          quicPort: _host._quicPort,
          quickStart: quickStart,
          initialPaused: initialPaused,
        );
      } catch (err) {
        if (_host._disposed || !_playbackStarts.isCurrent(startGeneration)) {
          return;
        }

        if (offlineDownload != null) {
          _host._pushMessage(
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

        _host._pushMessage('Playback failed: $err', level: LogLevel.error);
        _updatePlayback(isPlaying: false, isLoading: false);
      }
    }

    startSelectedSource();
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
      _host._pushMessage('Downloaded file is missing for ${track.title}.', level: LogLevel.warning);
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
      _host._pushMessage('Playing downloaded file: ${track.title}');
      _host._audioEngine.setVolume(_playbackState.volume);

      await _host._audioEngine.playLocalFile(
        track: track,
        filePath: filePath,
        contentType: download.contentType,
        startOffset: startOffset,
        initialPaused: initialPaused,
      );
    } catch (err) {
      if (_host._disposed || !_playbackStarts.isCurrent(startGeneration)) {
        return;
      }

      _host._pushMessage('Local playback failed: $err', level: LogLevel.error);
      _updatePlayback(isPlaying: false, isLoading: false);
    }
  }

  void _logPlaybackContext() {
    _host._pushMessage('Server base URL: ${_host.connection.baseUrl}');

    if (Platform.isIOS) {
      _host._pushMessage('Local network permission: ${_host._localNetworkPermissionState.name}');

      try {
        final uri = Uri.parse(_host.connection.baseUrl);
        final host = uri.host;
        final isLoopback = host == 'localhost' || host == '127.0.0.1' || host == '::1';

        if (host.isNotEmpty && isLoopback) {
          _host._pushMessage(
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

  StreamSettings _streamSettings(StreamMode mode) {
    switch (mode) {
      case StreamMode.auto:
        return const StreamSettings(mode: 'auto', quality: 'high', frameMs: 20);
      case StreamMode.high:
        return const StreamSettings(mode: 'fixed', quality: 'high', frameMs: 20);
      case StreamMode.medium:
        return const StreamSettings(mode: 'fixed', quality: 'medium', frameMs: 20);
      case StreamMode.low:
        return const StreamSettings(mode: 'fixed', quality: 'low', frameMs: 20);
    }
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _PlaybackFacade {
  _PlaybackCoordinator get _playbackCoordinator;

  RequestGeneration get _playbackStarts => _playbackCoordinator._playbackStarts;

  bool get _wantsPlayback => _playbackCoordinator._wantsPlayback;

  set _wantsPlayback(bool value) => _playbackCoordinator._wantsPlayback = value;

  bool get _audioOutputStarted => _playbackCoordinator._audioOutputStarted;

  set _audioOutputStarted(bool value) => _playbackCoordinator._audioOutputStarted = value;

  set _lastStartPlaybackAt(DateTime? value) => _playbackCoordinator._lastStartPlaybackAt = value;

  set _lastStartPlaybackTrackId(String? value) => _playbackCoordinator._lastStartPlaybackTrackId = value;

  set _lastStartPlaybackOffsetMs(int? value) => _playbackCoordinator._lastStartPlaybackOffsetMs = value;

  StreamController<PlaybackState> get _playbackController => _playbackCoordinator._playbackController;

  PlaybackState get _playbackState => _playbackCoordinator._playbackState;

  set _playbackState(PlaybackState value) => _playbackCoordinator._playbackState = value;

  Stream<PlaybackState> get playbackStream => _playbackCoordinator.playbackStream;

  PlaybackState get playbackState => _playbackCoordinator.playbackState;

  List<OutputDevice> get outputDevices => _playbackCoordinator.outputDevices;

  int get outputDeviceId => _playbackCoordinator.outputDeviceId;

  String? get outputDeviceName => _playbackCoordinator.outputDeviceName;

  bool get _hasActiveRemotePlayback => _playbackCoordinator._hasActiveRemotePlayback;

  Future<void> stop() => _playbackCoordinator.stop();

  Future<void> nextTrack({bool fromAutoAdvance = false}) =>
      _playbackCoordinator.nextTrack(fromAutoAdvance: fromAutoAdvance);

  Future<void> prevTrack({bool fromAutoAdvance = false}) =>
      _playbackCoordinator.prevTrack(fromAutoAdvance: fromAutoAdvance);

  Future<void> pause(bool paused) => _playbackCoordinator.pause(paused);

  void updateShuffleMode(ShuffleMode mode, {ActionScope? scope}) =>
      _playbackCoordinator.updateShuffleMode(mode, scope: scope);

  void toggleRepeatMode() => _playbackCoordinator.toggleRepeatMode();

  void updateStreamMode(StreamMode mode) => _playbackCoordinator.updateStreamMode(mode);

  void setVolume(double value) => _playbackCoordinator.setVolume(value);

  Future<List<OutputDevice>> listOutputDevices({bool refresh = false}) =>
      _playbackCoordinator.listOutputDevices(refresh: refresh);

  Future<void> selectOutputDevice(OutputDevice device) => _playbackCoordinator.selectOutputDevice(device);

  Future<void> _stop({bool requireFileRelease = false}) =>
      _playbackCoordinator._stop(requireFileRelease: requireFileRelease);

  void _applyVolume(double value, {required bool persist}) =>
      _playbackCoordinator._applyVolume(value, persist: persist);

  void _flushVolumeSave() => _playbackCoordinator._flushVolumeSave();

  Future<void> _playCurrent() => _playbackCoordinator._playCurrent();

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
    PlaybackRepeatMode? repeatMode,
    StreamMode? streamMode,
    double? bitrateKbps,
    bool? streamConnected,
    int? streamRttMs,
    PlaybackQueueSource? queueSource,
    Object? queueSourcePlaylistId = _unset,
    LocalPlaybackSource? localPlaybackSource,
    bool? isLocalPlayback,
    bool nowPlaying = true,
  }) => _playbackCoordinator._updatePlayback(
    track: track,
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
    queueSourcePlaylistId: queueSourcePlaylistId,
    localPlaybackSource: localPlaybackSource,
    isLocalPlayback: isLocalPlayback,
    nowPlaying: nowPlaying,
  );

  void _startPlayback(Track track, {Duration startOffset = Duration.zero, bool quickStart = true}) =>
      _playbackCoordinator._startPlayback(track, startOffset: startOffset, quickStart: quickStart);

  void _closeStreamControl() => _playbackCoordinator._closeStreamControl();
}
