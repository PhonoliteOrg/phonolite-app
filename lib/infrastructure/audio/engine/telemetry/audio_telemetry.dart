part of '../audio_engine.dart';

class _AudioTelemetry {
  final _PlaybackSession _host;
  final Stopwatch _deliveryClock = Stopwatch()..start();
  final AudioQualityTimeline _qualityTimeline = AudioQualityTimeline();
  int _lastBufferReportAtMs = 0;
  int _lastReportedBufferMs = -1;
  int _lastReportedTargetMs = -1;
  bool _reportedStart = false;
  int _lastQuicStatsLogAtMs = 0;
  Timer? _statsTimer;
  bool _statsCollectionInFlight = false;
  int _queuedToPlayerSamples = 0;
  int _playedSamples = 0;
  int _bytesReceived = 0;
  int _lastBitrateBytes = 0;
  DateTime? _lastBitrateAt;
  AudioFileDecoder? _fileStatsDecoder;
  int _lastOriginalRecoveryAttempts = 0;
  Duration? _lastOriginalDeliveryAt;
  int _originalDeliveryEpoch = -1;
  int _lastOriginalDeliveryBytes = 0;
  int _lastOriginalAcceptedMs = 0;

  _AudioTelemetry(this._host);

  int get _positionMs =>
      _host._baseOffsetMs + _playedSamples * 1000 ~/ math.max(1, _host._sampleRate * _host._channels);

  void _reportBuffer({bool force = false, bool suspended = false}) {
    final quic = _host._quic;

    if (quic == null ||
        !_PlaybackSession._serverBackpressureEnabled ||
        _host._ownerRemote._repairRequested ||
        _host._ownerRemote._repairing) {
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final targetMs = _host._encodedReadAheadTargetMs;
    final int bufferedMs;

    if (suspended) {
      bufferedMs = targetMs;
    } else if (_host._waitingForHeader && !_host._ownerRemote._remoteContinuation) {
      bufferedMs = 0;
    } else {
      // A continuation/reconnect can wait for its next header while accepted
      // PCM and encoded audio still play. Reporting zero would falsely lower
      // Auto quality and restart its healthy-connection window every range.
      bufferedMs = _host._ownerRemote._playableMs;
    }

    // Refresh below the server's stale-report deadline; avoid per-tick chatter.
    if (!force &&
        now - _lastBufferReportAtMs < 1000 &&
        (bufferedMs - _lastReportedBufferMs).abs() < 500 &&
        targetMs == _lastReportedTargetMs) {
      return;
    }

    _lastBufferReportAtMs = now;
    _lastReportedBufferMs = bufferedMs;
    _lastReportedTargetMs = targetMs;
    try {
      quic.sendBufferStats(bufferMs: bufferedMs, targetMs: targetMs, force: true);
    } catch (_) {
      // Telemetry cannot invalidate a cached seek or stop accepted playback.
      _host._ownerRemote._repairRequested = true;
    }
  }

  void _reportStarted() {
    if (_reportedStart) {
      return;
    }

    _reportedStart = true;
    _host._quickStart = false;
    _host._refreshBufferTargets();

    final activeSeekId = _host._activeSeekId;

    if (activeSeekId != null) {
      _host._log('Seek audio resumed (seek_id=$activeSeekId).');
      _host._activeSeekId = null;
    }

    _host._log('Audio playback started.');
    _host._sendPlaybackMessage({'type': 'started'});
  }

  void _startStats() {
    _stopStats();
    _statsTimer = Timer.periodic(const Duration(milliseconds: 250), (_) => unawaited(_collectAndSendStats()));
  }

  void _stopStats() {
    _statsTimer?.cancel();
    _statsTimer = null;
    _statsCollectionInFlight = false;
  }

  Future<void> _collectAndSendStats() async {
    if (_statsCollectionInFlight) {
      return;
    }

    _statsCollectionInFlight = true;

    try {
      final player = _host._player;

      if (player != null) {
        final epoch = _host._outputEpoch;

        try {
          final done = await _host._collectListeningSamples(player);

          if (epoch != _host._outputEpoch || !identical(player, _host._player)) {
            return;
          }

          _playedSamples += done;
        } catch (_) {
          return;
        }
      }

      if (!_host._isActive) {
        return;
      }

      final buffer = _host._buffer;
      final bufferSamples = buffer?.length ?? 0;
      final queuedInPlayer = _queuedToPlayerSamples > _playedSamples ? (_queuedToPlayerSamples - _playedSamples) : 0;
      final bufferedSamples = bufferSamples + queuedInPlayer;
      final samplesPerSecond = _host._sampleRate * _host._channels;
      final bufferedMs = samplesPerSecond == 0 ? 0 : (bufferedSamples * 1000 ~/ samplesPerSecond);

      final quic = _host._quic;

      if (quic != null) {
        try {
          final stats = quic.pollStats();
          final nowMs = DateTime.now().millisecondsSinceEpoch;

          if (stats != null && nowMs - _lastQuicStatsLogAtMs >= _PlaybackSession._quicStatsLogIntervalMs) {
            _lastQuicStatsLogAtMs = nowMs;
            _host._log(stats);
            if (_host.settings.mode == 'auto' && !_host._isLocalFile) {
              _logAutoPlayback(bufferedMs: bufferedMs);
            }
          }
        } catch (_) {
          // Ignore stats poll failures.
        }
      }

      int? rttMs = _host._isLocalFile ? null : _host._fileDecoder?.transportRttMilliseconds;
      if (_host.settings.isOriginal) {
        final decoderChanged = !identical(_fileStatsDecoder, _host._fileDecoder);
        if (decoderChanged) {
          _fileStatsDecoder = _host._fileDecoder;
          _lastBitrateAt = null;
          _lastBitrateBytes = 0;
        }
        _bytesReceived = _host._fileDecoder?.transportReceivedBytes ?? _bytesReceived;
        _logOriginalDelivery(bufferedMs: bufferedMs, rttMs: rttMs, reset: decoderChanged);
        final attempts = _host._fileDecoder?.recoveryAttempts ?? 0;
        if (attempts != _lastOriginalRecoveryAttempts) {
          _lastOriginalRecoveryAttempts = attempts;
          _host._log(
            'Original transport repair: attempts=$attempts '
            'remaining_ms=${_host._fileDecoder?.recoveryRemaining.inMilliseconds ?? 0} '
            'buffered_ms=$bufferedMs rtt_ms=$rttMs.',
          );
        }
      }

      if (quic != null) {
        try {
          rttMs = quic.pollRttMs();
        } catch (_) {
          // Ignore RTT poll failures.
        }
      }

      _host._updateAdaptiveBufferProfile(bufferedMs: bufferedMs, rttMs: rttMs);

      if (quic != null) {
        try {
          _reportBuffer();
        } catch (_) {}
      }

      final playedMs = samplesPerSecond == 0 ? 0 : (_playedSamples * 1000 ~/ samplesPerSecond);
      final position = Duration(milliseconds: _host._baseOffsetMs + playedMs);

      _host._maybeRebuffer(bufferedSamples);

      final audibleQuality = _qualityTimeline.qualityAt(_playedSamples);
      _host._ownerOriginal.rememberAudible(audibleQuality);

      _host._sendPlaybackMessage({
        'type': 'stats',
        'position_ms': position.inMilliseconds,
        'buffered_ms': _host._isFileSource
            ? bufferedMs
            : math.max(bufferedMs, _host._encodedCache.bufferedAheadMs(position.inMilliseconds)),
        'bitrate_kbps': _host._isLocalFile ? null : _currentBitrateKbps(),
        'stream_quality': !_host._startedPlayback || _host._isLocalFile
            ? null
            : (_host.settings.isOriginal ? AudioStreamQuality.original : _qualityTimeline.qualityAt(_playedSamples))
                  ?.name,
        'rtt_ms': _host._isLocalFile ? null : rttMs,
        'local': _host._isLocalFile,
      });
    } finally {
      _statsCollectionInFlight = false;
    }
  }

  void _logOriginalDelivery({required int bufferedMs, required int? rttMs, required bool reset}) {
    final now = _deliveryClock.elapsed;
    final previous = _lastOriginalDeliveryAt;
    final acceptedThroughMs = _positionMs + bufferedMs;
    final epochChanged = _originalDeliveryEpoch != _host._outputEpoch;
    if (!reset && !epochChanged && previous != null && now - previous < const Duration(seconds: 5)) {
      return;
    }

    if (!reset && !epochChanged && previous != null) {
      _host._log(
        'Original delivery: interval_ms=${(now - previous).inMilliseconds} '
        'received_bytes=${math.max(0, _bytesReceived - _lastOriginalDeliveryBytes)} '
        'playable_ms=${math.max(0, acceptedThroughMs - _lastOriginalAcceptedMs)} '
        'buffered_ms=$bufferedMs rtt_ms=$rttMs '
        'paused=${_host._userPaused} refilling=${_host._autoPaused}.',
      );
    }

    _lastOriginalDeliveryAt = now;
    _originalDeliveryEpoch = _host._outputEpoch;
    _lastOriginalDeliveryBytes = _bytesReceived;
    _lastOriginalAcceptedMs = acceptedThroughMs;
  }

  void _logAutoPlayback({required int bufferedMs}) {
    final remote = _host._ownerRemote;
    final audible = _qualityTimeline.qualityAt(_playedSamples)?.name;

    _host._log(
      'Auto playback sample: diagnostics_revision=2 '
      'audible_quality=$audible position_ms=$_positionMs '
      'playable_ms=${remote._playableMs} pcm_ms=$bufferedMs '
      'target_ms=${_host._encodedReadAheadTargetMs} '
      'original_reserve_ms=${_host._ownerOriginal.reserveMs} '
      'paused=${_host._userPaused} refilling=${_host._autoPaused} '
      'waiting_header=${_host._waitingForHeader} continuation=${remote._remoteContinuation} '
      'repairing=${remote._repairing} repair_requested=${remote._repairRequested}.',
    );
  }

  double? _currentBitrateKbps() {
    final now = DateTime.now();
    final lastAt = _lastBitrateAt;

    if (lastAt == null) {
      _lastBitrateAt = now;
      _lastBitrateBytes = _bytesReceived;

      return null;
    }

    final deltaMs = now.difference(lastAt).inMilliseconds;

    if (deltaMs <= 0) {
      return null;
    }

    final deltaBytes = _bytesReceived - _lastBitrateBytes;

    if (deltaBytes <= 0) {
      return null;
    }

    _lastBitrateAt = now;
    _lastBitrateBytes = _bytesReceived;

    return (deltaBytes * 8.0) / deltaMs;
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _AudioTelemetryFacade {
  _AudioTelemetry get _ownerTelemetry;

  set _reportedStart(bool value) => _ownerTelemetry._reportedStart = value;

  int get _queuedToPlayerSamples => _ownerTelemetry._queuedToPlayerSamples;

  set _queuedToPlayerSamples(int value) => _ownerTelemetry._queuedToPlayerSamples = value;

  int get _playedSamples => _ownerTelemetry._playedSamples;

  set _playedSamples(int value) => _ownerTelemetry._playedSamples = value;

  int get _bytesReceived => _ownerTelemetry._bytesReceived;

  set _bytesReceived(int value) => _ownerTelemetry._bytesReceived = value;

  set _lastBitrateBytes(int value) => _ownerTelemetry._lastBitrateBytes = value;

  int get _positionMs => _ownerTelemetry._positionMs;

  void _reportBuffer({bool force = false, bool suspended = false}) =>
      _ownerTelemetry._reportBuffer(force: force, suspended: suspended);

  void _reportStarted() => _ownerTelemetry._reportStarted();

  void _startStats() => _ownerTelemetry._startStats();

  void _stopStats() => _ownerTelemetry._stopStats();
}
