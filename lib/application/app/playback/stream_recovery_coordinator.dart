part of '../app_controller.dart';

class _StreamRecoveryCoordinator {
  final AppController _host;
  bool _awaitingStreamReconnect = false;
  Timer? _streamRecoveryTimer;
  DateTime? _lastInterruptedStreamRestartAt;
  String? _lastInterruptedStreamRestartTrackId;
  int? _lastInterruptedStreamRestartPositionMs;

  _StreamRecoveryCoordinator(this._host);

  void _handleAudioEngineState(bool active, bool paused) {
    if (_host._disposed) {
      return;
    }

    if (active || paused) {
      return;
    }

    if (_host._audio?.sourceRejected == true) {
      _host._wantsPlayback = false;
      _host._audioOutputStarted = false;
      _awaitingStreamReconnect = false;
      _streamRecoveryTimer?.cancel();
      _streamRecoveryTimer = null;

      _host._seekRequests.advance();
      _host._pendingSeekGeneration = null;
      _host._seeking = false;
      _host._lastSeekTrackId = null;
      _host._seekDirection = SeekDirection.none;
      _host._updatePlayback(isPlaying: false, isLoading: false, streamConnected: false, streamRttMs: null);

      return;
    }

    _recoverInterruptedRemoteStream();
  }

  void _recoverInterruptedRemoteStream() {
    final track = _host._playbackState.track;

    if (_host._disposed || track == null || _host._playbackState.isLocalPlayback) {
      return;
    }

    // A transport failure can arrive before the matching seek marker or output.
    // Restart from the latest requested position rather than stale output stats.
    final interruptedSeek = _host._seeking;
    final restartPositionMs = interruptedSeek
        ? _host._seekTargetMs
        : max(_host._actualPositionMs, _host._displayPositionMs);

    if (interruptedSeek) {
      _host._seekRequests.advance();
      _host._pendingSeekGeneration = null;
      _host._seeking = false;
      _host._lastSeekTrackId = null;
      _host._seekDirection = SeekDirection.none;
      _host._seekOriginMs = restartPositionMs;
      _host._audioOutputStarted = false;
    }

    if (!_host._wantsPlayback || _host._isScrubbing) {
      _host._updatePlayback(isLoading: false, streamConnected: false, streamRttMs: null);

      return;
    }

    if (!_host._canAttemptRemotePlayback) {
      _awaitingStreamReconnect = _host._wantsPlayback;
      _host._updatePlayback(
        isPlaying: _host._wantsPlayback,
        isLoading: false,
        streamConnected: false,
        streamRttMs: null,
      );

      return;
    }

    if (_recentlyRetriedInterruptedStream(track, restartPositionMs)) {
      _host._pushMessage('Stream interrupted again; waiting for server reconnect.', level: LogLevel.warning);
      _awaitingStreamReconnect = true;
      _host._updatePlayback(
        isPlaying: _host._wantsPlayback,
        isLoading: false,
        streamConnected: false,
        streamRttMs: null,
      );
      unawaited(_host._refreshServerAvailability(reconnectAttempt: true));

      return;
    }

    _lastInterruptedStreamRestartAt = _host._playbackClock();
    _lastInterruptedStreamRestartTrackId = track.id;
    _lastInterruptedStreamRestartPositionMs = restartPositionMs;
    _awaitingStreamReconnect = false;

    _host._pushMessage(
      interruptedSeek
          ? 'Stream interrupted during seek; reconnecting from the requested position.'
          : 'Stream interrupted; reconnecting from current position.',
      level: LogLevel.warning,
    );
    _host._updatePlayback(isLoading: true, streamConnected: false, streamRttMs: null);

    _host._startPlayback(track, startOffset: Duration(milliseconds: restartPositionMs), quickStart: false);
  }

  void _retryPlaybackAfterServerReconnect() {
    if (_host._disposed ||
        !_awaitingStreamReconnect ||
        !_host._wantsPlayback ||
        _host._isScrubbing ||
        !_host._canAttemptRemotePlayback ||
        _host._audioEngine.hasActivePlayer) {
      return;
    }

    final track = _host._playbackState.track;

    if (track == null || _host._playbackState.isLocalPlayback) {
      return;
    }

    final positionMs = max(_host._actualPositionMs, _host._displayPositionMs);

    if (_recentlyRetriedInterruptedStream(track, positionMs)) {
      if (_streamRecoveryTimer == null) {
        final delay =
            AppController._interruptedStreamRestartCooldown -
            _host._playbackClock().difference(_lastInterruptedStreamRestartAt!);

        void retryAfterCooldown() {
          _streamRecoveryTimer = null;

          if (!_host._disposed && _host._wantsPlayback && _awaitingStreamReconnect) {
            unawaited(_host._refreshServerAvailability(reconnectAttempt: true));
          }
        }

        _streamRecoveryTimer = Timer(delay, retryAfterCooldown);
      }

      return;
    }

    _streamRecoveryTimer?.cancel();
    _streamRecoveryTimer = null;
    _awaitingStreamReconnect = false;
    _lastInterruptedStreamRestartAt = _host._playbackClock();
    _lastInterruptedStreamRestartTrackId = track.id;
    _lastInterruptedStreamRestartPositionMs = positionMs;
    _host._updatePlayback(isPlaying: true, isLoading: true);

    _host._startPlayback(track, startOffset: Duration(milliseconds: positionMs), quickStart: false);
  }

  bool _recentlyRetriedInterruptedStream(Track track, int positionMs) {
    final lastRestartAt = _lastInterruptedStreamRestartAt;
    final lastTrackId = _lastInterruptedStreamRestartTrackId;
    final lastPositionMs = _lastInterruptedStreamRestartPositionMs;

    if (lastRestartAt == null || lastTrackId == null || lastPositionMs == null || lastTrackId != track.id) {
      return false;
    }

    if (_host._playbackClock().difference(lastRestartAt) >= AppController._interruptedStreamRestartCooldown) {
      return false;
    }

    return (positionMs - lastPositionMs).abs() <= AppController._interruptedStreamRestartPositionToleranceMs;
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _StreamRecoveryFacade {
  _StreamRecoveryCoordinator get _recoveryCoordinator;

  set _awaitingStreamReconnect(bool value) => _recoveryCoordinator._awaitingStreamReconnect = value;

  Timer? get _streamRecoveryTimer => _recoveryCoordinator._streamRecoveryTimer;

  set _streamRecoveryTimer(Timer? value) => _recoveryCoordinator._streamRecoveryTimer = value;

  set _lastInterruptedStreamRestartAt(DateTime? value) => _recoveryCoordinator._lastInterruptedStreamRestartAt = value;

  set _lastInterruptedStreamRestartTrackId(String? value) =>
      _recoveryCoordinator._lastInterruptedStreamRestartTrackId = value;

  set _lastInterruptedStreamRestartPositionMs(int? value) =>
      _recoveryCoordinator._lastInterruptedStreamRestartPositionMs = value;

  void _handleAudioEngineState(bool active, bool paused) =>
      _recoveryCoordinator._handleAudioEngineState(active, paused);

  void _retryPlaybackAfterServerReconnect() => _recoveryCoordinator._retryPlaybackAfterServerReconnect();
}
