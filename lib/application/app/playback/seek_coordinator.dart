part of 'package:phonolite_app/application/app/app_controller.dart';

class _SeekCoordinator {
  final AppController _host;
  String? _lastSeekTrackId;
  bool _seeking = false;
  int _seekOriginMs = 0;
  int _seekTargetMs = 0;
  SeekDirection _seekDirection = SeekDirection.none;
  bool _isScrubbing = false;
  final _seekRequests = RequestGeneration();
  int? _pendingSeekGeneration;
  int _displayPositionMs = 0;
  int _actualPositionMs = 0;
  int _bufferedEndHighWaterMs = 0;

  _SeekCoordinator(this._host);

  void previewSeek(Duration position) {
    final track = _host._playbackState.track;
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
    _host._updatePlayback(
      position: clamped,
      isPlaying: _host._playbackState.isPlaying,
      bufferRatio: 0.0,
      nowPlaying: false,
    );
  }

  Future<void> seekTo(Duration position) async {
    final track = _host._playbackState.track;
    if (track == null) {
      return;
    }

    final requestGeneration = _seekRequests.advance();

    _pendingSeekGeneration = requestGeneration;
    _host._armAutoAdvanceGuard(AppController._seekCompletionGuard);
    _host._suppressAutoAdvanceUntil = DateTime.now().add(AppController._seekCompletionGuard);

    final clamped = _clampSeekTarget(position);

    _lastSeekTrackId = track.id;
    _seeking = true;
    _seekTargetMs = clamped.inMilliseconds;

    if (!_isScrubbing) {
      _seekOriginMs = _displayPositionMs;
    }

    _seekDirection = _seekDirectionFor(_seekOriginMs, _seekTargetMs);
    _host._audioOutputStarted = false;
    _host._bumpNowPlayingEpoch();
    _resetPlaybackPositionTracking(position: clamped);
    _resetBufferedEndHighWater(position: clamped);
    _host._updatePlayback(position: clamped, isPlaying: _host._wantsPlayback, bufferRatio: 0.0);
    await _commitSeek(clamped, requestGeneration);

    if (_host._disposed || !_seekRequests.isCurrent(requestGeneration)) {
      return;
    }

    await _host._pushNowPlayingUpdate(force: true);
  }

  Future<void> _commitSeek(Duration target, int requestGeneration) async {
    final track = _host._playbackState.track;
    if (track == null) {
      return;
    }

    _finishScrub();

    var inlineSeek = false;

    try {
      inlineSeek = await _host._audioEngine.seekTo(target);
    } catch (_) {
      inlineSeek = false;
    }

    if (_host._disposed || !_seekRequests.isCurrent(requestGeneration) || _host._playbackState.track?.id != track.id) {
      return;
    }

    _clearSeekHold(target);

    if (inlineSeek) {
      _host._pushMessage(
        'Seek commit: inline seek to ${target.inMilliseconds}ms '
        '(playing=${_host._wantsPlayback ? 'yes' : 'no'})',
      );
    } else {
      _restartPlaybackForSeek(track: track, target: target, reason: 'engine unavailable');
    }
  }

  void _beginScrub() {
    if (_isScrubbing) {
      return;
    }

    _isScrubbing = true;
    _seekRequests.advance();
    _seekOriginMs = _displayPositionMs;
    _seekDirection = SeekDirection.none;
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
    _seekRequests.advance();
    _host._wantsPlayback = false;
    _host._playbackStarts.advance();

    _pendingSeekGeneration = null;
    _host._awaitingStreamReconnect = false;
    _host._streamRecoveryTimer?.cancel();
    _host._streamRecoveryTimer = null;

    _seeking = false;
    _seekOriginMs = positionMs;
    _seekTargetMs = positionMs;
    _seekDirection = SeekDirection.none;
    _lastSeekTrackId = null;

    _host._ignoreCompleteUntil = null;
    _host._suppressAutoAdvanceUntil = null;
    _host._autoAdvanceInFlight = false;

    _host._lastInterruptedStreamRestartAt = null;
    _host._lastInterruptedStreamRestartTrackId = null;
    _host._lastInterruptedStreamRestartPositionMs = null;

    _resetPlaybackPositionTracking(position: Duration(milliseconds: positionMs));
    _resetBufferedEndHighWater(position: Duration(milliseconds: positionMs));
  }

  void _restartPlaybackForSeek({required Track track, required Duration target, required String reason}) {
    _host._pushMessage(
      'Seek commit: restarting stream at ${target.inMilliseconds}ms '
      '(reason=$reason, playing=${_host._wantsPlayback ? 'yes' : 'no'})',
    );
    _host._lastStartPlaybackAt = null;
    _host._startPlayback(track, startOffset: target);
  }

  void _clearSeekHold(Duration position) {
    _pendingSeekGeneration = null;
    _seeking = false;
    _seekOriginMs = position.inMilliseconds;
    _seekTargetMs = position.inMilliseconds;
    _seekDirection = SeekDirection.none;
    _lastSeekTrackId = null;

    _host._ignoreCompleteUntil = null;
    _host._suppressAutoAdvanceUntil = null;
    _resetPlaybackPositionTracking(position: position);
  }

  void _maybeClearSeekHold(Duration position) {
    if (!_seeking || _isScrubbing || _pendingSeekGeneration != null) {
      return;
    }

    final positionMs = position.inMilliseconds;
    final targetMs = _seekTargetMs;
    final reached = switch (_seekDirection) {
      SeekDirection.forward => positionMs >= targetMs - AppController._seekCompletionToleranceMs,
      SeekDirection.backward => positionMs <= targetMs + AppController._seekCompletionToleranceMs,
      SeekDirection.none => (positionMs - targetMs).abs() <= AppController._seekCompletionToleranceMs,
    };

    if (reached) {
      _clearSeekHold(position);
      _host._pushNowPlayingUpdate(force: true);
    }
  }

  SeekDirection _seekDirectionFor(int originMs, int targetMs) {
    if (targetMs > originMs + AppController._seekCompletionToleranceMs) {
      return SeekDirection.forward;
    }

    if (targetMs < originMs - AppController._seekCompletionToleranceMs) {
      return SeekDirection.backward;
    }

    return SeekDirection.none;
  }

  Duration _clampSeekTarget(Duration position) {
    final duration = _host._playbackState.duration;
    var clamped = position;

    if (duration != Duration.zero) {
      if (position > duration) {
        clamped = duration;
      } else if (position < Duration.zero) {
        clamped = Duration.zero;
      }
    }

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

  void _updateDisplayPosition(int actualMs) {
    final durationMs = _host._playbackState.duration.inMilliseconds;

    if (_isScrubbing || _seeking) {
      _displayPositionMs = _seekTargetMs;
    } else if (!_host._playbackState.isPlaying || _host._audioEngine.isPaused || !_host._audioOutputStarted) {
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

    if (!_host._playbackState.isPlaying || _host._audioEngine.isPaused) {
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

    final bufferedRatio = (_bufferedEndHighWaterMs / durationMs).clamp(positionRatio, 1.0);

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
    final next = max(_bufferedEndHighWaterMs, max(bufferedEndMs, _displayPositionMs));

    _bufferedEndHighWaterMs = next.clamp(0, durationMs).toInt();
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _SeekFacade {
  _SeekCoordinator get _seekCoordinator;

  String? get _lastSeekTrackId => _seekCoordinator._lastSeekTrackId;

  set _lastSeekTrackId(String? value) => _seekCoordinator._lastSeekTrackId = value;

  bool get _seeking => _seekCoordinator._seeking;

  set _seeking(bool value) => _seekCoordinator._seeking = value;

  set _seekOriginMs(int value) => _seekCoordinator._seekOriginMs = value;

  int get _seekTargetMs => _seekCoordinator._seekTargetMs;

  set _seekDirection(SeekDirection value) => _seekCoordinator._seekDirection = value;

  bool get _isScrubbing => _seekCoordinator._isScrubbing;

  set _isScrubbing(bool value) => _seekCoordinator._isScrubbing = value;

  RequestGeneration get _seekRequests => _seekCoordinator._seekRequests;

  set _pendingSeekGeneration(int? value) => _seekCoordinator._pendingSeekGeneration = value;

  int get _displayPositionMs => _seekCoordinator._displayPositionMs;

  int get _actualPositionMs => _seekCoordinator._actualPositionMs;

  set _actualPositionMs(int value) => _seekCoordinator._actualPositionMs = value;

  void previewSeek(Duration position) => _seekCoordinator.previewSeek(position);

  Future<void> seekTo(Duration position) => _seekCoordinator.seekTo(position);

  void _resetPlaybackPositionTracking({Duration position = Duration.zero}) =>
      _seekCoordinator._resetPlaybackPositionTracking(position: position);

  void _resetBufferedEndHighWater({Duration position = Duration.zero}) =>
      _seekCoordinator._resetBufferedEndHighWater(position: position);

  void _resetTrackTransitionState({Duration position = Duration.zero}) =>
      _seekCoordinator._resetTrackTransitionState(position: position);

  void _maybeClearSeekHold(Duration position) => _seekCoordinator._maybeClearSeekHold(position);

  void _updateDisplayPosition(int actualMs) => _seekCoordinator._updateDisplayPosition(actualMs);

  int _correctReportedPositionMs(int reportedMs) => _seekCoordinator._correctReportedPositionMs(reportedMs);

  double _displayBufferRatio({required Duration duration}) => _seekCoordinator._displayBufferRatio(duration: duration);

  void _updateBufferedEndHighWater({
    required Duration duration,
    required Duration position,
    required Duration bufferedAhead,
  }) => _seekCoordinator._updateBufferedEndHighWater(
    duration: duration,
    position: position,
    bufferedAhead: bufferedAhead,
  );
}
