part of '../audio_engine.dart';

class _AdaptiveAudioBufferPolicy {
  final _PlaybackSession _host;
  bool _quickStart = false;
  bool _startupBufferFilled = false;
  bool _isLoopbackHost = false;
  int _networkProfileLevel = 0;
  int _stableBufferTicks = 0;
  int? _lastObservedRttMs;
  bool _startedPlayback = false;
  int _sampleRate = 48000;
  double _prebufferSeconds = 0.3;
  double _rebufferMinSeconds = 0.08;
  double _rebufferTargetSeconds = 0.3;
  int _prebufferTargetSamples = 0;
  int _rebufferMinSamples = 0;
  int _rebufferTargetSamples = 0;
  int _pumpChunkSamples = 0;

  _AdaptiveAudioBufferPolicy(this._host);

  int get _encodedReadAheadTargetMs {
    final prepared = _host._gaplessSource;
    if (prepared != null && prepared._isPrepared && !prepared._announced) return 2000;
    if (_host._userPaused) {
      return 2000;
    }

    return _isLoopbackHost ? 3000 : 8000;
  }

  void _configureBufferProfile(String host) {
    _isLoopbackHost = host == 'localhost' || host == '127.0.0.1' || host == '::1';
    _networkProfileLevel = 0;
    _stableBufferTicks = 0;
    _lastObservedRttMs = null;
    _applyBufferProfile(log: true);
  }

  void _configureLocalBufferProfile() {
    _isLoopbackHost = true;
    _networkProfileLevel = 0;
    _stableBufferTicks = 0;
    _lastObservedRttMs = null;
    _applyBufferProfile(log: true);
  }

  void _applyBufferProfile({bool log = false}) {
    double prebufferSeconds;
    double rebufferMinSeconds;
    double rebufferTargetSeconds;

    if (_isLoopbackHost) {
      prebufferSeconds = _PlaybackSession._prebufferSecondsLocal;
      rebufferMinSeconds = _PlaybackSession._rebufferMinSecondsLocal;
      rebufferTargetSeconds = _PlaybackSession._rebufferTargetSecondsLocal;
    } else {
      prebufferSeconds = 0.12;
      rebufferMinSeconds = 0.08;
      rebufferTargetSeconds = 0.3;

      if (_networkProfileLevel >= 1) {
        prebufferSeconds = math.max(prebufferSeconds, 0.2);
        rebufferMinSeconds = math.max(rebufferMinSeconds, 0.12);
        rebufferTargetSeconds = math.max(rebufferTargetSeconds, 0.5);
      }

      if (_networkProfileLevel >= 2) {
        prebufferSeconds = math.max(prebufferSeconds, 0.3);
        rebufferMinSeconds = math.max(rebufferMinSeconds, 0.2);
        rebufferTargetSeconds = math.max(rebufferTargetSeconds, 0.8);
      }
    }

    final changed =
        prebufferSeconds != _prebufferSeconds ||
        rebufferMinSeconds != _rebufferMinSeconds ||
        rebufferTargetSeconds != _rebufferTargetSeconds;

    _prebufferSeconds = prebufferSeconds;
    _rebufferMinSeconds = rebufferMinSeconds;
    _rebufferTargetSeconds = rebufferTargetSeconds;
    _refreshBufferTargets();

    if (log || changed) {
      _host._log(
        'Buffer profile: level=$_networkProfileLevel '
        'prebuffer=${_prebufferSeconds.toStringAsFixed(1)}s '
        'rebuffer_min=${_rebufferMinSeconds.toStringAsFixed(1)}s '
        'rebuffer_target=${_rebufferTargetSeconds.toStringAsFixed(1)}s'
        '${_lastObservedRttMs == null ? '' : ' rtt=${_lastObservedRttMs}ms'}',
      );
    }
  }

  void _refreshBufferTargets() {
    if (_sampleRate <= 0 || _host._channels <= 0) {
      return;
    }

    if (_quickStart) {
      var startSamples = _host._frameSamples * _host._channels;

      if (startSamples <= 0) {
        startSamples = (_sampleRate * _host._channels * _PlaybackSession._seekStartSeconds).round();
      }

      if (startSamples <= 0) {
        startSamples = 1;
      }

      _prebufferTargetSamples = startSamples;
      _rebufferMinSamples = (_sampleRate * _host._channels * _PlaybackSession._seekCatchupMinSeconds).round();
      _rebufferTargetSamples = (_sampleRate * _host._channels * _PlaybackSession._seekCatchupTargetSeconds).round();
      _ensureBufferCapacity();

      return;
    }

    _prebufferTargetSamples = (_sampleRate * _host._channels * _prebufferSeconds).round();
    _rebufferMinSamples = (_sampleRate * _host._channels * _rebufferMinSeconds).round();
    _rebufferTargetSamples = (_sampleRate * _host._channels * _rebufferTargetSeconds).round();
    _ensureBufferCapacity();
  }

  void _ensureBufferCapacity() {
    final maximum = _host.settings.isOriginal && !_host._isLocalFile
        ? _FileAudioSource._maximumRemotePcmBytes ~/ (_host._pcmBitsPerSample ~/ 8)
        : null;

    if (maximum != null) {
      // An extreme source rate must not make its refill gate larger than the
      // bounded precise-PCM buffer. Sample values and rate remain unchanged.
      _prebufferTargetSamples = math.min(_prebufferTargetSamples, maximum ~/ 2);
      _rebufferMinSamples = math.min(_rebufferMinSamples, maximum ~/ 4);
      _rebufferTargetSamples = math.min(_rebufferTargetSamples, maximum ~/ 2);
    }

    // Profiles can change during playback and after the short seek-start gate.
    // The refill target must fit, even while output is paused for buffering.
    final minimumSamples = math.max(
      math.max(_prebufferTargetSamples, _rebufferTargetSamples) * 2,
      _pumpChunkSamples * 4,
    );

    _host._buffer?.ensureCapacity(maximum == null ? minimumSamples : math.min(minimumSamples, maximum));
  }

  int _serverBufferTargetMs() {
    final targetSeconds = _quickStart ? _PlaybackSession._seekCatchupTargetSeconds : _rebufferTargetSeconds;
    // Backpressure must never stop delivery before the startup gate opens.
    final startupSeconds = !_startedPlayback ? _prebufferSeconds : 0.0;
    final targetMs = (math.max(targetSeconds, startupSeconds) * 1000).ceil();

    return targetMs > 0 ? targetMs : 1;
  }

  void _updateAdaptiveBufferProfile({required int bufferedMs, int? rttMs}) {
    _lastObservedRttMs = rttMs;

    if (_isLoopbackHost || _quickStart) {
      return;
    }

    var desiredLevel = _networkProfileLevel;

    if (rttMs != null) {
      if (rttMs >= 350) {
        desiredLevel = 2;
      } else if (rttMs >= 180 && desiredLevel < 1) {
        desiredLevel = 1;
      }
    }

    final stableEnough =
        !_host._autoPaused && (rttMs == null || rttMs <= 120) && bufferedMs >= (_rebufferTargetSeconds * 2000).round();

    if (stableEnough) {
      _stableBufferTicks += 1;

      if (_stableBufferTicks >= 20 && desiredLevel > 0) {
        desiredLevel -= 1;
        _stableBufferTicks = 0;
      }
    } else {
      _stableBufferTicks = 0;
    }

    if (desiredLevel != _networkProfileLevel) {
      _networkProfileLevel = desiredLevel;
      _applyBufferProfile(log: true);
    }
  }

  void _maybeRebuffer(int bufferedSamples) {
    if (_host._streamEnded) {
      if (_host._autoPaused && !_host._userPaused) {
        _resumeFromAutoPause();
      }

      return;
    }

    if (_host._userPaused || !_startedPlayback) {
      return;
    }

    // Let a short startup buffer grow without immediately auto-pausing.
    // Once enough audio has accumulated, use the steady-state thresholds.
    if (!_startupBufferFilled) {
      if (bufferedSamples >= _rebufferMinSamples) {
        _startupBufferFilled = true;
      } else if (bufferedSamples > _sampleRate * _host._channels ~/ 20) {
        return;
      }
    }

    if (!_host._autoPaused && bufferedSamples <= _rebufferMinSamples) {
      _stableBufferTicks = 0;

      if (!_quickStart && !_isLoopbackHost && _networkProfileLevel < 2) {
        _networkProfileLevel += 1;
        _applyBufferProfile(log: true);
      }

      _pauseForBuffer(bufferedSamples);

      return;
    }

    final resumeThresholdSamples = _host._reportedStart && _host._playedSamples == 0
        ? _rebufferMinSamples
        : _rebufferTargetSamples;

    if (_host._autoPaused && bufferedSamples >= resumeThresholdSamples) {
      _resumeFromAutoPause();
    }
  }

  int _bufferedAudioMs() {
    final samplesPerSecond = _sampleRate * _host._channels;

    if (samplesPerSecond <= 0) {
      return 0;
    }

    final bufferSamples = _host._buffer?.length ?? 0;
    final queuedInPlayer = _host._queuedToPlayerSamples > _host._playedSamples
        ? (_host._queuedToPlayerSamples - _host._playedSamples)
        : 0;

    return ((bufferSamples + queuedInPlayer) * 1000 ~/ samplesPerSecond);
  }

  void _pauseForBuffer(int bufferedSamples) {
    final player = _host._player;
    if (player == null) {
      return;
    }

    final samplesPerSecond = _sampleRate * _host._channels;
    final bufferedMs = samplesPerSecond <= 0 ? 0 : (bufferedSamples * 1000 ~/ samplesPerSecond);

    _host._log('Buffer low: buffered=${bufferedMs}ms target=${_serverBufferTargetMs()}ms; refilling.');
    player.pause();
    _host._listening.flush();
    _host._paused = true;
    _host._autoPaused = true;
    _host._sendPlaybackMessage({'type': 'state', 'active': true, 'paused': true});
  }

  void _resumeFromAutoPause() {
    if (_host._userPaused) {
      return;
    }

    final player = _host._player;
    if (player == null) {
      return;
    }

    player.resume();
    _host._paused = false;
    _host._autoPaused = false;
    _host._log('Buffer recovered: buffered=${_bufferedAudioMs()}ms target=${_serverBufferTargetMs()}ms.');
    _host._sendPlaybackMessage({'type': 'state', 'active': true, 'paused': false});
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _AdaptiveAudioBufferPolicyFacade {
  _AdaptiveAudioBufferPolicy get _ownerBuffer;

  bool get _quickStart => _ownerBuffer._quickStart;

  set _quickStart(bool value) => _ownerBuffer._quickStart = value;

  set _startupBufferFilled(bool value) => _ownerBuffer._startupBufferFilled = value;

  int get _encodedReadAheadTargetMs => _ownerBuffer._encodedReadAheadTargetMs;

  bool get _startedPlayback => _ownerBuffer._startedPlayback;

  set _startedPlayback(bool value) => _ownerBuffer._startedPlayback = value;

  int get _sampleRate => _ownerBuffer._sampleRate;

  set _sampleRate(int value) => _ownerBuffer._sampleRate = value;

  double get _prebufferSeconds => _ownerBuffer._prebufferSeconds;

  double get _rebufferTargetSeconds => _ownerBuffer._rebufferTargetSeconds;

  int get _prebufferTargetSamples => _ownerBuffer._prebufferTargetSamples;

  int get _rebufferTargetSamples => _ownerBuffer._rebufferTargetSamples;

  int get _pumpChunkSamples => _ownerBuffer._pumpChunkSamples;

  set _pumpChunkSamples(int value) => _ownerBuffer._pumpChunkSamples = value;

  void _configureBufferProfile(String host) => _ownerBuffer._configureBufferProfile(host);

  void _configureLocalBufferProfile() => _ownerBuffer._configureLocalBufferProfile();

  void _refreshBufferTargets() => _ownerBuffer._refreshBufferTargets();

  void _ensureBufferCapacity() => _ownerBuffer._ensureBufferCapacity();

  void _updateAdaptiveBufferProfile({required int bufferedMs, int? rttMs}) =>
      _ownerBuffer._updateAdaptiveBufferProfile(bufferedMs: bufferedMs, rttMs: rttMs);

  void _maybeRebuffer(int bufferedSamples) => _ownerBuffer._maybeRebuffer(bufferedSamples);

  void _resumeFromAutoPause() => _ownerBuffer._resumeFromAutoPause();
}
