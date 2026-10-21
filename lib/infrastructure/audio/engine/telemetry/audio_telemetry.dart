part of 'package:phonolite_app/infrastructure/audio/engine/audio_engine.dart';

class _AudioTelemetry {
  final _PlaybackSession _host;
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

  _AudioTelemetry(this._host);

  int get _positionMs =>
      _host._baseOffsetMs + _playedSamples * 1000 ~/ math.max(1, _host._sampleRate * _host._channels);

  void _reportBuffer({bool force = false, bool suspended = false}) {
    final quic = _host._quic;

    if (quic == null || !_PlaybackSession._serverBackpressureEnabled) {
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final targetMs = _host._encodedReadAheadTargetMs;
    final int bufferedMs;

    if (suspended) {
      bufferedMs = targetMs;
    } else if (_host._waitingForHeader) {
      bufferedMs = 0;
    } else {
      bufferedMs = _host._encodedCache.bufferedAheadMs(_positionMs);
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
    quic.sendBufferStats(bufferMs: bufferedMs, targetMs: targetMs, force: true);
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
          }
        } catch (_) {
          // Ignore stats poll failures.
        }
      }

      int? rttMs;

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

      _host._sendPlaybackMessage({
        'type': 'stats',
        'position_ms': position.inMilliseconds,
        'buffered_ms': _host._isLocalFile
            ? bufferedMs
            : math.max(bufferedMs, _host._encodedCache.bufferedAheadMs(position.inMilliseconds)),
        'bitrate_kbps': _host._isLocalFile ? null : _currentBitrateKbps(),
        'rtt_ms': _host._isLocalFile ? null : rttMs,
        'local': _host._isLocalFile,
      });
    } finally {
      _statsCollectionInFlight = false;
    }
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

  bool get _reportedStart => _ownerTelemetry._reportedStart;

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
