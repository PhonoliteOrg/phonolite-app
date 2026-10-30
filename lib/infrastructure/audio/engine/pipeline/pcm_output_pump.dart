part of '../audio_engine.dart';

class _PcmOutputPump {
  final _PlaybackSession _host;

  _PcmOutputPump(this._host);

  Future<void> _runPump() async {
    _host._pumpRunning = true;

    try {
      while (_host._isActive) {
        final player = _host._player;
        final buffer = _host._buffer;

        if (player == null || buffer == null || _host._pumpSuspended) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          continue;
        }

        if (!_host._startedPlayback) {
          if (buffer.length == 0 && _host._streamEnded) {
            _host._markSeekReady();
            if (player is _GaplessSourceOutput) await player.finish();

            return;
          }

          if (!_host._streamEnded && buffer.length < _host._prebufferTargetSamples) {
            await Future<void>.delayed(const Duration(milliseconds: 5));
            continue;
          }

          _host._startedPlayback = true;
          _host._markSeekReady();

          if (!_host._paused) {
            player.resume();
          }

          _host._reportStarted();
        }

        if (_host._paused) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          continue;
        }

        final chunk = buffer.read(_host._pumpChunkSamples);

        if (chunk == null || chunk.isEmpty) {
          if (_host._streamEnded) {
            await _drainPlayer(player);

            return;
          }

          await Future<void>.delayed(const Duration(milliseconds: 5));
          continue;
        }

        if (_host._pumpSuspended || !identical(player, _host._player) || !identical(buffer, _host._buffer)) {
          continue;
        }

        final epoch = _host._outputEpoch;

        try {
          await _writeSamples(player, chunk);
        } catch (error) {
          if (!_host._isActive) {
            return;
          }

          if (epoch != _host._outputEpoch || !identical(player, _host._player)) {
            continue;
          }

          rethrow;
        }
      }
    } catch (error) {
      if (_host._isActive) {
        _host._log('Audio output failed: $error');
        _host.requestStop(outcome: 'output_error');
        _host._sendPlaybackMessage({'type': 'state', 'active': false, 'paused': false});
      }
    } finally {
      _host._pumpRunning = false;
    }
  }

  Future<void> _writeToBuffer(List<int> samples) async {
    final buffer = _host._buffer;
    if (buffer == null) {
      return;
    }

    final epoch = _host._outputEpoch;
    final generation = _host._seekRequestGeneration;
    var offset = 0;

    while (offset < samples.length &&
        _host._isActive &&
        epoch == _host._outputEpoch &&
        generation == _host._seekRequestGeneration &&
        identical(buffer, _host._buffer)) {
      final written = buffer.write(samples, offset);

      if (written == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        continue;
      }

      offset += written;
    }
  }

  Future<void> _writeSamples(AudioPcmOutput player, List<int> samples) async {
    final epoch = _host._outputEpoch;

    if (samples is Int32List) {
      await player.writePcm32(samples);
    } else if (samples is Int16List) {
      await player.write(samples);
    } else {
      throw StateError('PCM output requires a typed sample buffer.');
    }

    if (epoch != _host._outputEpoch || !identical(player, _host._player)) {
      return;
    }

    _host._queuedToPlayerSamples += samples.length;
  }

  Future<void> _drainPlayer(AudioPcmOutput player) async {
    if (player is _GaplessSourceOutput) await player.finish();
    final epoch = _host._outputEpoch;

    while (_host._isActive) {
      bool idle;

      try {
        final done = await _host._collectListeningSamples(player);

        if (epoch != _host._outputEpoch || !identical(player, _host._player)) {
          return;
        }

        _host._playedSamples += done;
        idle = await player.isIdle();

        if (epoch != _host._outputEpoch || !identical(player, _host._player)) {
          return;
        }
      } catch (_) {
        return;
      }

      if (idle) {
        try {
          final tail = await _host._collectListeningSamples(player);

          if (epoch == _host._outputEpoch && identical(player, _host._player)) {
            _host._playedSamples += tail;
          }
        } catch (_) {}

        return;
      }

      await Future<void>.delayed(const Duration(milliseconds: 10));

      if (!identical(player, _host._player)) {
        return;
      }
    }
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _PcmOutputPumpFacade {
  _PcmOutputPump get _ownerPump;

  Future<void> _runPump() => _ownerPump._runPump();

  Future<void> _writeToBuffer(List<int> samples) => _ownerPump._writeToBuffer(samples);
}
