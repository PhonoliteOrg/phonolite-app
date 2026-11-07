part of '../app_controller.dart';

class _StreamRecoveryCoordinator {
  static const _retryBackoffSeconds = [2, 5, 10, 20, 30];
  final AppController _host;
  bool _awaitingStreamReconnect = false;
  Timer? _streamRecoveryTimer;
  DateTime? _nextStreamRetryAt;
  int _streamRetryAttempt = 0;
  DateTime? _lastInterruptedStreamRestartAt;
  String? _lastInterruptedStreamRestartTrackId;
  int? _lastInterruptedStreamRestartPositionMs;

  _StreamRecoveryCoordinator(this._host);

  /// Leaves accepted audio and the current occurrence owned by the worker.
  Future<void> _handleNetworkChange() async {
    final track = _host._playbackState.track;

    if (_host._disposed ||
        track == null ||
        _host._playbackState.sourceScope != ActionScope.server ||
        _host._playbackState.isLocalPlayback ||
        (!_host._wantsPlayback && !_host._audioEngine.hasActivePlayer)) {
      return;
    }

    // A different interface is a fresh recovery opportunity, independent of a
    // retry cooldown or reconnect backoff accumulated on the previous network.
    _lastInterruptedStreamRestartAt = null;
    _lastInterruptedStreamRestartTrackId = null;
    _lastInterruptedStreamRestartPositionMs = null;
    _streamRecoveryTimer?.cancel();
    _streamRecoveryTimer = null;
    _nextStreamRetryAt = null;
    _streamRetryAttempt = 0;

    if (_host._audioEngine.hasActivePlayer) {
      _awaitingStreamReconnect = false;
      _host._audioEngine.notifyNetworkChange();
      return;
    }

    _awaitingStreamReconnect = _host._wantsPlayback;
    _retryPlaybackAfterServerReconnect();
  }

  void _handleAudioEngineState(bool active, bool paused) {
    if (_host._disposed) {
      return;
    }

    _host._accountServices.reportPlaybackPresence();

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

    if (_host._playbackState.isLocalPlayback) {
      _recoverInterruptedLocalPlayback();
      return;
    }

    _recoverInterruptedRemoteStream();
  }

  void _recoverInterruptedLocalPlayback() {
    final track = _host._playbackState.track;
    final positionMs = _host._seeking ? _host._seekTargetMs : max(_host._actualPositionMs, _host._displayPositionMs);
    _retireInterruptedSeek(positionMs);
    if (track == null || !_host._wantsPlayback || _host._audioSessionSuspended || _host._isScrubbing) {
      _host._updatePlayback(isPlaying: false, isLoading: false);
      return;
    }
    if (_recentlyRetriedInterruptedStream(track, positionMs)) {
      _host._wantsPlayback = false;
      _host._audioOutputStarted = false;
      _host._updatePlayback(isPlaying: false, isLoading: false);
      _host._pushMessage('Audio output failed again; press Play to retry.', level: LogLevel.warning);
      return;
    }
    _lastInterruptedStreamRestartAt = _host._playbackClock();
    _lastInterruptedStreamRestartTrackId = track.id;
    _lastInterruptedStreamRestartPositionMs = positionMs;
    _host._audioOutputStarted = false;
    _host._updatePlayback(isLoading: true);
    _host._startPlayback(track, startOffset: Duration(milliseconds: positionMs), quickStart: false);
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

    _retireInterruptedSeek(restartPositionMs);
    if (interruptedSeek) {
      _host._actualPositionMs = restartPositionMs;
      _host._updateDisplayPosition(restartPositionMs);
    }

    if (!_host._wantsPlayback || _host._isScrubbing || _host._audioSessionSuspended) {
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

    _awaitingStreamReconnect = true;
    if (_lastInterruptedStreamRestartTrackId != track.id) _streamRetryAttempt = 0;
    final delay = _nextRetryDelay();
    _nextStreamRetryAt = _host._playbackClock().add(delay);
    _host._pushMessage('Stream interrupted; waiting for connection before retrying.', level: LogLevel.warning);
    _host._updatePlayback(isLoading: true, streamConnected: false, streamRttMs: null);
    _scheduleStreamRetry(delay);
  }

  Duration _nextRetryDelay() {
    final delay = Duration(seconds: _retryBackoffSeconds[_streamRetryAttempt]);
    _streamRetryAttempt = min(_streamRetryAttempt + 1, _retryBackoffSeconds.length - 1);
    return delay;
  }

  void _scheduleStreamRetry(Duration delay) {
    _streamRecoveryTimer?.cancel();
    final occurrence = _host._playbackStarts.current;
    bool canRetry() =>
        !_host._disposed &&
        _host._wantsPlayback &&
        !_host._audioSessionSuspended &&
        _awaitingStreamReconnect &&
        _host._playbackStarts.isCurrent(occurrence);

    _streamRecoveryTimer = Timer(delay, () async {
      _streamRecoveryTimer = null;
      if (canRetry()) {
        await _host._refreshServerAvailability(reconnectAttempt: true);
        if (canRetry() && !_host._audioEngine.hasActivePlayer && _streamRecoveryTimer == null) {
          final next = _nextRetryDelay();
          _nextStreamRetryAt = _host._playbackClock().add(next);
          _scheduleStreamRetry(next);
        }
      }
    });
  }

  void noteHealthyPlayback(Duration position, Duration bufferedAhead) {
    final last = _lastInterruptedStreamRestartPositionMs;
    if (last != null && position.inMilliseconds >= last + 2000 && bufferedAhead >= const Duration(seconds: 2)) {
      _streamRetryAttempt = 0;
    }
  }

  void _retireInterruptedSeek(int positionMs) {
    if (!_host._seeking) return;
    _host._seekRequests.advance();
    _host._pendingSeekGeneration = null;
    _host._seeking = false;
    _host._lastSeekTrackId = null;
    _host._seekDirection = SeekDirection.none;
    _host._seekOriginMs = positionMs;
    _host._audioOutputStarted = false;
  }

  void _retryPlaybackAfterServerReconnect() {
    if (_host._disposed ||
        !_awaitingStreamReconnect ||
        !_host._wantsPlayback ||
        _host._audioSessionSuspended ||
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

    final due = _nextStreamRetryAt;
    if (due != null && _host._playbackClock().isBefore(due)) {
      if (_streamRecoveryTimer == null) _scheduleStreamRetry(due.difference(_host._playbackClock()));
      return;
    }
    _nextStreamRetryAt = null;

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
