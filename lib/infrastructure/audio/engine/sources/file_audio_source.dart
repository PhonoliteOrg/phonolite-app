part of '../audio_engine.dart';

class _FileAudioSource {
  final _PlaybackSession _host;
  bool _pumpRunning = false;
  bool _streamEnded = false;
  int _channels = 2;
  int _frameSamples = 0;

  _FileAudioSource(this._host);

  Future<void> _runLocalFilePlayback(String filePath) async {
    _host._log('Opening local audio file: $filePath');

    await _runFilePlayback(AudioFileDecoder.local(filePath: filePath, startOffset: _host.startOffset));
  }

  Future<void> _runOriginalFilePlayback() async {
    final base = Uri.parse(_host.baseUrl);
    final endpoint = base.replace(
      pathSegments: [...base.pathSegments.where((segment) => segment.isNotEmpty), 'stream', _host.trackId, 'original'],
      query: null,
      fragment: null,
    );

    final decoder =
        _host._fileDecoderFactory?.call(endpoint, _host.startOffset) ??
        AudioFileDecoder.remote(
          url: endpoint,
          token: _host.token,
          serverPin: _host.serverPin,
          startOffset: _host.startOffset,
        );

    await _runFilePlayback(decoder);
  }

  Future<void> _runFilePlayback(AudioFileDecoder decoder) async {
    if (_host._isLocalFile) {
      _host._configureLocalBufferProfile();
    } else {
      _host._configureBufferProfile(Uri.parse(_host.baseUrl).host);
    }
    _host._fileDecoder = decoder;
    await decoder.initialize();

    if (!_host._isActive) {
      return;
    }

    final format = decoder.format;

    _host._sampleRate = format.sampleRate;
    _host._sourceBitDepth = format.bitDepth;
    _host._pcmBitsPerSample = 32;
    _channels = format.channels;

    _host._baseOffsetMs = _host.startOffset.inMilliseconds;
    _host._quickStart = _host.quickStart && _host.startOffset.inMilliseconds > 0;

    _host._log(
      'Source decoder: ${format.sampleRate} Hz, ${format.bitDepth}-bit, ${_channels}ch, '
      'duration=${format.duration.inMilliseconds} ms',
    );

    await _createLocalPcmOutput();
    _host._startStats();

    Future<void>? pumpTask;

    if (!_pumpRunning) {
      pumpTask = _host._runPump();
    }

    final readSamples = math.max(_channels, ((_host._sampleRate * _channels * 200) / 1000).round());
    final alignedReadSamples = readSamples - (readSamples % _channels);
    final readBufferSize = alignedReadSamples > 0 ? alignedReadSamples : _channels;

    while (_host._isActive) {
      final pendingSeekMs = _host._pendingSeekMs;

      if (pendingSeekMs != null) {
        await _applyLocalSeek(decoder, pendingSeekMs);
        continue;
      }

      if (!_pumpRunning) {
        pumpTask = _host._runPump();
      }

      if (_streamEnded) {
        if (_host._autoPaused && !_host._userPaused) {
          _host._resumeFromAutoPause();
        }

        if (!_host._paused && (_host._buffer?.length ?? 0) == 0) {
          final generation = _host._seekRequestGeneration;
          final epoch = _host._outputEpoch;
          final player = _host._player!;
          final idle = await player.isIdle();

          if (!_host._isActive ||
              generation != _host._seekRequestGeneration ||
              epoch != _host._outputEpoch ||
              !identical(player, _host._player)) {
            continue;
          }

          if (idle && !_host._paused && (_host._buffer?.length ?? 0) == 0) {
            break;
          }
        }

        await Future<void>.delayed(const Duration(milliseconds: 5));
        continue;
      }

      final buffer = _host._buffer;

      if (buffer != null && !_streamEnded) {
        final minFree = _host._pumpChunkSamples > 0 ? _host._pumpChunkSamples : _channels;

        if (buffer.free < minFree) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          continue;
        }
      }

      final generation = _host._seekRequestGeneration;
      final samples = await decoder.read32(readBufferSize);

      if (!_host._isActive || generation != _host._seekRequestGeneration) {
        continue;
      }

      if (samples.isEmpty) {
        _streamEnded = true;
        continue;
      }

      await _host._writeToBuffer(samples);
    }

    _streamEnded = true;
    _host._log('Source file ended.');

    if (_host._autoPaused && !_host._userPaused) {
      _host._resumeFromAutoPause();
    }

    if (pumpTask != null) {
      await pumpTask;
    }

    if (_host._isActive) {
      _host._listening.flush(endReason: 'finished');
      _host._sendPlaybackMessage({'type': 'complete'});
    }
  }

  Future<void> _applyLocalSeek(AudioFileDecoder decoder, int requestedMs) async {
    final seekId = _host._allocateSeekId();
    final requestGeneration = _host._seekRequestGeneration;
    // Container seeking needs a position inside the final packet. FLAC can
    // reject an exact EOF timestamp before the pump can acknowledge readiness.
    final durationMs = decoder.format.duration.inMilliseconds;
    final targetMs = math.max(0, durationMs > 0 ? math.min(requestedMs, durationMs - 1) : requestedMs);

    await _host._resetOutputForSeek(targetMs);

    if (!_host._isActive || requestGeneration != _host._seekRequestGeneration) {
      return;
    }

    _host._pendingSeekMs = null;
    _host._pendingSeekId = null;
    _host._activeSeekId = seekId;

    final actual = await decoder.seek(Duration(milliseconds: targetMs));

    if (!_host._isActive || requestGeneration != _host._seekRequestGeneration) {
      return;
    }

    _host._baseOffsetMs = actual.inMilliseconds;

    final requestedAtMs = _host._pendingSeekRequestedAtMs;

    if (requestedAtMs != null) {
      final latencyMs = DateTime.now().millisecondsSinceEpoch - requestedAtMs;

      _host._log('File seek accepted after ${latencyMs}ms (seek_id=$seekId).');
    }

    _host._pendingSeekRequestedAtMs = null;

    await _createLocalPcmOutput();
    _host._pumpSuspended = false;
  }

  Future<void> _createLocalPcmOutput() async {
    _frameSamples = (_host._sampleRate * 20 / 1000).round();
    _host._pumpChunkSamples = ((_host._sampleRate * _channels * _PlaybackSession._pumpChunkMs) / 1000).round();

    if (_host._pumpChunkSamples <= 0) {
      _host._pumpChunkSamples = math.max(1, _frameSamples * _channels);
    }

    _host._refreshBufferTargets();

    final double targetSeconds;

    if (_host._quickStart) {
      targetSeconds = _PlaybackSession._seekCatchupTargetSeconds;
    } else if (_host._prebufferSeconds > _host._rebufferTargetSeconds) {
      targetSeconds = _host._prebufferSeconds;
    } else {
      targetSeconds = _host._rebufferTargetSeconds;
    }

    final capacitySamples = (targetSeconds * 4.0 * _host._sampleRate * _channels).round();
    final minCapacitySamples = _host._rebufferTargetSamples * 2;
    var finalCapacity = capacitySamples;

    if (minCapacitySamples > finalCapacity) {
      finalCapacity = minCapacitySamples;
    }

    final minPumpCapacity = _host._pumpChunkSamples * 4;

    if (minPumpCapacity > finalCapacity) {
      finalCapacity = minPumpCapacity;
    }

    _host._buffer = PcmRingBuffer(finalCapacity, bitsPerSample: _host._pcmBitsPerSample);

    try {
      await _host._configurePcmOutput();
    } catch (error) {
      if (!_host._isLocalFile) {
        throw AudioSourceRejected(
          'The selected output could not open Original audio at ${_host._sampleRate} Hz '
          'and ${_host._sourceBitDepth}-bit precision: $error',
        );
      }

      rethrow;
    }
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _FileAudioSourceFacade {
  _FileAudioSource get _ownerFile;

  bool get _pumpRunning => _ownerFile._pumpRunning;

  set _pumpRunning(bool value) => _ownerFile._pumpRunning = value;

  bool get _streamEnded => _ownerFile._streamEnded;

  set _streamEnded(bool value) => _ownerFile._streamEnded = value;

  int get _channels => _ownerFile._channels;

  set _channels(int value) => _ownerFile._channels = value;

  int get _frameSamples => _ownerFile._frameSamples;

  set _frameSamples(int value) => _ownerFile._frameSamples = value;

  Future<void> _runLocalFilePlayback(String filePath) => _ownerFile._runLocalFilePlayback(filePath);

  Future<void> _runOriginalFilePlayback() => _ownerFile._runOriginalFilePlayback();
}
