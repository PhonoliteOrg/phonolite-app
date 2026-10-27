part of '../audio_engine.dart';

class _AudioSeekCoordinator {
  final _PlaybackSession _host;
  int _baseOffsetMs = 0;
  int? _pendingSeekMs;
  int? _pendingSeekRequestedAtMs;
  int _nextSeekId = 0;
  int? _pendingSeekId;
  int? _activeSeekId;
  int _seekRequestGeneration = 0;
  int _seekReadyRequestId = 0;
  Timer? _seekDeadline;
  EncodedAudioCursor? _cachedSeek;
  bool _pumpSuspended = false;
  bool _remotePlaybackComplete = false;

  _AudioSeekCoordinator(this._host);

  Future<void> seekTo(Duration position, {int requestId = 0}) async {
    final output = _host._player;

    if (output != null) {
      try {
        final done = await _host._collectListeningSamples(output);

        _host._playedSamples += done;
      } catch (_) {}
    }

    _host._listening.flush();

    _seekRequestGeneration++;
    final generation = _seekRequestGeneration;

    _failSeek('superseded');
    _seekReadyRequestId = requestId;

    final ms = math.max(0, position.inMilliseconds);

    _pendingSeekRequestedAtMs = DateTime.now().millisecondsSinceEpoch;
    _host._quickStart = true;
    _host._streamEnded = false;
    _remotePlaybackComplete = false;

    void handleSeekTimeout() {
      if (!_host._isActive || _seekReadyRequestId != requestId) {
        return;
      }

      _failSeek('timeout');
      _host.requestStop(outcome: 'seek_timeout');
      _host._sendPlaybackMessage({'type': 'state', 'active': false, 'paused': false});
    }

    _seekDeadline = Timer(const Duration(seconds: 5), handleSeekTimeout);

    if (_host._isFileSource) {
      _pendingSeekMs = ms;

      return;
    }

    final quic = _host._quic;

    if (quic == null) {
      _failSeek('unavailable');

      return;
    }

    final cached = _host._encodedCache.seek(ms);

    _host._decodeCursor = null;
    _host._decodedThroughSample = null;
    _cachedSeek = null;
    _host._incomingSegment = null;
    _host._rawReader.reset();

    void handleOutputResetError(Object error) {
      if (generation != _seekRequestGeneration || !_host._isActive) {
        return;
      }

      _host._log('Unable to flush audio output: $error');
      _failSeek('output_error');
      _host.requestStop(outcome: 'output_error');
      _host._sendPlaybackMessage({'type': 'state', 'active': false, 'paused': false});
    }

    _host._outputReset = _resetOutputForSeek(ms).catchError(handleOutputResetError);

    if (cached != null) {
      // A cached seek requires neither server transcoding nor retransmission.
      quic.suspendAudio();
      _host._waitingForHeader = false;
      _pendingSeekId = null;
      _cachedSeek = cached;
      _host._remoteContinuation = false;
      _host._reportBuffer(force: true, suspended: true);

      return;
    }

    _host._requestRemoteRange(ms, continuation: false);
  }

  void _failSeek(String outcome) {
    _seekDeadline?.cancel();
    _seekDeadline = null;

    final requestId = _seekReadyRequestId;

    if (requestId != 0) {
      _host._sendPlaybackMessage({'type': 'seek_failed', 'request_id': requestId, 'outcome': outcome});
      _seekReadyRequestId = 0;
    }
  }

  void _markSeekReady() {
    _seekDeadline?.cancel();
    _seekDeadline = null;

    final requestId = _seekReadyRequestId;

    if (requestId != 0) {
      _host._sendPlaybackMessage({'type': 'seek_ready', 'request_id': requestId});
      _seekReadyRequestId = 0;
    }
  }

  Future<void> _resetOutputForSeek(int ms) async {
    final epoch = ++_host._outputEpoch;

    _pumpSuspended = true;
    _host._buffer = null;

    final player = _host._player;

    if (player != null) {
      player.pause();

      try {
        await _host._collectListeningSamples(player);
        _host._listening.flush();
      } catch (_) {}

      await player.flush();

      if (!_host._isActive || epoch != _host._outputEpoch || !identical(player, _host._player)) {
        return;
      }
    }

    _baseOffsetMs = ms;
    _host._queuedToPlayerSamples = 0;
    _host._playedSamples = 0;
    _host._startedPlayback = false;
    _host._reportedStart = false;
    _host._startupBufferFilled = false;
    _host._autoPaused = false;
    _host._paused = _host._userPaused;
    _pumpSuspended = false;
  }

  int _allocateSeekId() {
    _nextSeekId = (_nextSeekId + 1) & 0x7fffffff;

    if (_nextSeekId == 0) {
      _nextSeekId = 1;
    }

    return _nextSeekId;
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _AudioSeekCoordinatorFacade {
  _AudioSeekCoordinator get _ownerSeek;

  int get _baseOffsetMs => _ownerSeek._baseOffsetMs;

  set _baseOffsetMs(int value) => _ownerSeek._baseOffsetMs = value;

  int? get _pendingSeekMs => _ownerSeek._pendingSeekMs;

  set _pendingSeekMs(int? value) => _ownerSeek._pendingSeekMs = value;

  int? get _pendingSeekRequestedAtMs => _ownerSeek._pendingSeekRequestedAtMs;

  set _pendingSeekRequestedAtMs(int? value) => _ownerSeek._pendingSeekRequestedAtMs = value;

  int? get _pendingSeekId => _ownerSeek._pendingSeekId;

  set _pendingSeekId(int? value) => _ownerSeek._pendingSeekId = value;

  int? get _activeSeekId => _ownerSeek._activeSeekId;

  set _activeSeekId(int? value) => _ownerSeek._activeSeekId = value;

  int get _seekRequestGeneration => _ownerSeek._seekRequestGeneration;

  EncodedAudioCursor? get _cachedSeek => _ownerSeek._cachedSeek;

  set _cachedSeek(EncodedAudioCursor? value) => _ownerSeek._cachedSeek = value;

  bool get _pumpSuspended => _ownerSeek._pumpSuspended;

  set _pumpSuspended(bool value) => _ownerSeek._pumpSuspended = value;

  bool get _remotePlaybackComplete => _ownerSeek._remotePlaybackComplete;

  set _remotePlaybackComplete(bool value) => _ownerSeek._remotePlaybackComplete = value;

  Future<void> seekTo(Duration position, {int requestId = 0}) => _ownerSeek.seekTo(position, requestId: requestId);

  void _failSeek(String outcome) => _ownerSeek._failSeek(outcome);

  void _markSeekReady() => _ownerSeek._markSeekReady();

  Future<void> _resetOutputForSeek(int ms) => _ownerSeek._resetOutputForSeek(ms);

  int _allocateSeekId() => _ownerSeek._allocateSeekId();
}
