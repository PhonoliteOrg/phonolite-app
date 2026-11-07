part of '../app_controller.dart';

class _NativeMediaCoordinator {
  final AppController _host;
  DateTime? _lastNowPlayingSentAt;
  String? _lastNowPlayingTrackId;
  bool? _lastNowPlayingIsPlaying;
  int _lastNowPlayingPositionMs = -1;
  int _lastNowPlayingEpochSent = -1;
  bool _nowPlayingReady = false;
  int _nowPlayingEpoch = 0;
  bool _audioInterrupted = false;
  int _interruptionRevision = 0;
  Future<void>? _audioResetInFlight;

  _NativeMediaCoordinator(this._host);

  void _configureNowPlaying() {
    if (!_host._nowPlayingPlatform.isSupported) {
      return;
    }

    _nowPlayingReady = true;

    Future<void> handleRemoteCommand(NativeRemoteCommand command) async {
      if (_host._disposed) {
        return;
      }

      AppLogger.debug('Native media command: ${command.action.name}');

      switch (command.action) {
        case NativeRemoteAction.play:
          await _host.pause(false);
          break;
        case NativeRemoteAction.pause:
          await _host.pause(true);
          break;
        case NativeRemoteAction.next:
          await _runPlaybackSelection(_host.nextTrack);
          break;
        case NativeRemoteAction.previous:
          await _runPlaybackSelection(_host.prevTrack);
          break;
        case NativeRemoteAction.toggleLike:
          final track = _host._playbackState.track;

          if (track != null) {
            await _host.toggleLike(track);
          }

          break;
        case NativeRemoteAction.startLibraryShuffle:
          _host.updateShuffleMode(ShuffleMode.all, scope: ActionScope.server);
          await _host.pause(false);
          break;
        case NativeRemoteAction.seek:
          final position = command.position;

          if (position != null) {
            await _host.seekTo(position);
          }

          break;
        case NativeRemoteAction.audioInterruptionBegan:
          _interruptionRevision++;
          if (!_audioInterrupted) {
            _audioInterrupted = true;
            _host._audioEngine.pause();
            _host._updatePlayback(isPlaying: false, isLoading: false);
            await _pushNowPlayingUpdate(force: true);
          }
          break;
        case NativeRemoteAction.audioInterruptionEnded:
        case NativeRemoteAction.audioInterruptionEndedPaused:
          if (!_audioInterrupted) break;
          _interruptionRevision++;
          _audioInterrupted = false;
          await _host.pause(command.action == NativeRemoteAction.audioInterruptionEndedPaused || !_host._wantsPlayback);
          break;
        case NativeRemoteAction.audioServicesReset:
          await _resetAudioServices();
          break;
        case NativeRemoteAction.audioRouteChanged:
          if (_host._playbackState.track != null && (_host._wantsPlayback || _host._audioEngine.hasActivePlayer)) {
            await _resetAudioServices(preservePlaybackIntent: true);
          }
          break;
        case NativeRemoteAction.unknown:
          break;
      }
    }

    _host._nowPlayingPlatform.setRemoteCommandHandler(handleRemoteCommand);
    _pushNowPlayingUpdate(force: true);
  }

  /// Selecting a track is an explicit playback request, just like pressing Play.
  Future<T> _runPlaybackSelection<T>(Future<T> Function() select) async {
    final playback = _host._playbackCoordinator;
    final previousStart = playback._playbackStarts.current;
    final intent = playback._playbackIntents.current;
    final result = await select();

    // iOS may never send interruption end. Recover only after a selection
    // actually starts, and preserve any newer user Pause received while loading.
    if (!_host._disposed &&
        _audioInterrupted &&
        _host._wantsPlayback &&
        playback._playbackIntents.isCurrent(intent) &&
        playback._playbackStarts.current != previousStart) {
      AppLogger.debug('Explicit track selection is retrying interrupted audio for ${_host._playbackState.track?.id}.');
      await _host.pause(false);
    }

    return result;
  }

  Future<void> _reactivateInterruptedSession() async {
    if (!_audioInterrupted) {
      return;
    }

    final revision = _interruptionRevision;
    try {
      final activated = await _host._nowPlayingPlatform.activateAudioSession();
      if (activated && !_host._disposed && revision == _interruptionRevision) {
        _audioInterrupted = false;
        AppLogger.debug('Audio session reactivated after explicit Play.');
      } else if (!activated) {
        AppLogger.debug('Audio session activation declined; playback remains interrupted until another Play request.');
      }
    } catch (error) {
      AppLogger.debug('Audio session reactivation was not accepted: $error');
    }
  }

  Future<void> _resetAudioServices({bool preservePlaybackIntent = false}) {
    if (!preservePlaybackIntent) {
      // A system reset requires explicit Play even when it arrives during a
      // route rebuild. Route changes retain interruption and user-pause intent.
      _interruptionRevision++;
      _audioInterrupted = false;
      _host._wantsPlayback = false;
    }

    return _audioResetInFlight ??= _rebuildAudioServices().whenComplete(() => _audioResetInFlight = null);
  }

  void _reportAudioResetFailure(Object error) {
    if (_host._disposed) return;
    _host._wantsPlayback = false;
    _host._updatePlayback(isPlaying: false, isLoading: false);
    _host._pushMessage('Audio output reset failed; press Play to retry: $error', level: LogLevel.warning);
  }

  Future<void> _rebuildAudioServices() async {
    final track = _host._playbackState.track;
    final position = Duration(milliseconds: max(_host._actualPositionMs, _host._displayPositionMs));
    final starts = _host._playbackCoordinator._playbackStarts;
    final generation = starts.current;
    // Hardware route changes can invalidate the AudioQueue playback clock.
    // Fresh output waits for release and applies the latest playback intent.
    _host._audioEngine.pause();
    _host._updatePlayback(isPlaying: false, isLoading: false);
    _host._gaplessCoordinator.invalidate();
    await _host._audioEngine.resetOutput();
    if (!_host._disposed &&
        track != null &&
        starts.isCurrent(generation) &&
        _host._playbackState.track?.id == track.id) {
      _host._startPlayback(track, startOffset: position, quickStart: false);
    }
    await _pushNowPlayingUpdate(force: true);
  }

  Future<void> _clearNowPlaying() async {
    _host._artwork.clear();

    if (!_host._nowPlayingPlatform.isSupported) {
      return;
    }

    try {
      await _host._nowPlayingPlatform.clearNowPlaying();
    } catch (_) {}
  }

  Future<void> _pushNowPlayingUpdate({bool force = false}) async {
    if (_host._disposed) {
      return;
    }

    if (!_host._nowPlayingPlatform.isSupported || !_nowPlayingReady) {
      return;
    }

    final track = _host._playbackState.track;

    if (track == null) {
      await _clearNowPlaying();

      return;
    }

    final now = DateTime.now();
    var positionMs = _host._playbackState.position.inMilliseconds;
    final isPlaying = _host._playbackState.isPlaying;

    if (_host._seeking && _host._lastSeekTrackId != null && _host._lastSeekTrackId != track.id) {
      _host._seeking = false;
      _host._lastSeekTrackId = null;
    }

    final lastSentAt = _lastNowPlayingSentAt;

    if (!force &&
        track.id == _lastNowPlayingTrackId &&
        isPlaying == _lastNowPlayingIsPlaying &&
        _nowPlayingEpoch == _lastNowPlayingEpochSent &&
        lastSentAt != null &&
        now.difference(lastSentAt) < const Duration(seconds: 1) &&
        (positionMs - _lastNowPlayingPositionMs).abs() < 900) {
      return;
    }

    final durationMs = _host._playbackState.duration.inMilliseconds;

    if (durationMs > 0 && positionMs > durationMs) {
      positionMs = durationMs;
    }

    final albumId = track.albumId ?? '';
    final artworkUrl = albumId.isNotEmpty && !_host._playbackState.isLocalPlayback
        ? _host.connection.buildAlbumCoverUrl(albumId)
        : null;
    final localArtworkPath = _host._playbackState.isLocalPlayback ? track.albumArtPath?.trim() : null;
    final token = _host.connection.token ?? '';
    final nativeArtwork = _host._nowPlayingPlatform.loadsArtworkNatively;

    if (!nativeArtwork) {
      _maybeLoadNowPlayingArtwork(artworkUrl: artworkUrl, localPath: localArtworkPath, token: token);
    }

    // iOS loads artwork natively; other platforms receive the cached PNG.
    final payload = NativeNowPlayingSnapshot(
      epoch: _nowPlayingEpoch,
      trackId: track.id,
      title: track.title,
      artist: track.artist,
      album: track.album,
      duration: Duration(milliseconds: durationMs),
      position: Duration(milliseconds: positionMs),
      isPlaying: isPlaying,
      liked: track.liked,
      artworkKey: NowPlayingArtwork.sourceKey(url: artworkUrl, localPath: localArtworkPath) ?? '',
      artworkUrl: artworkUrl,
      token: token,
      serverPin: _host.connection.trust?.spki,
      artworkPath: localArtworkPath,
      artworkBytes: nativeArtwork ? null : _host._artwork.bytes,
    );

    try {
      await _host._nowPlayingPlatform.publish(payload);
      _lastNowPlayingSentAt = now;
      _lastNowPlayingTrackId = track.id;
      _lastNowPlayingIsPlaying = isPlaying;
      _lastNowPlayingPositionMs = positionMs;
      _lastNowPlayingEpochSent = _nowPlayingEpoch;
    } catch (_) {}
  }

  void _maybeLoadNowPlayingArtwork({required String? artworkUrl, required String? localPath, required String token}) {
    if (!_host._nowPlayingPlatform.isSupported || _host._disposed) {
      return;
    }

    Future<void> publishChangedArtwork(bool changed) async {
      if (changed && !_host._disposed) {
        await _pushNowPlayingUpdate(force: true);
      }
    }

    unawaited(_host._artwork.load(url: artworkUrl, localPath: localPath, token: token).then(publishChangedArtwork));
  }

  void _bumpNowPlayingEpoch() {
    _nowPlayingEpoch = (_nowPlayingEpoch + 1) % 1000000;

    if (_nowPlayingEpoch < 0) {
      _nowPlayingEpoch = 0;
    }
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _NativeMediaFacade {
  _NativeMediaCoordinator get _nativeCoordinator;

  bool get _audioSessionSuspended =>
      _nativeCoordinator._audioInterrupted || _nativeCoordinator._audioResetInFlight != null;

  void _configureNowPlaying() => _nativeCoordinator._configureNowPlaying();

  Future<void> _clearNowPlaying() => _nativeCoordinator._clearNowPlaying();

  Future<void> _pushNowPlayingUpdate({bool force = false}) => _nativeCoordinator._pushNowPlayingUpdate(force: force);

  void _bumpNowPlayingEpoch() => _nativeCoordinator._bumpNowPlayingEpoch();
}
