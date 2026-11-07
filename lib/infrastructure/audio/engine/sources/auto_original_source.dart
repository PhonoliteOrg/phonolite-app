part of '../audio_engine.dart';

/// A bounded, parallel Original decoder. Opus keeps its presentation clock and
/// encoded safety reserve; only the PCM selected for that clock changes.
class _AutoOriginalSource {
  final _PlaybackSession _host;
  final AutoOriginalPolicy _policy = AutoOriginalPolicy();
  final Stopwatch _clock = Stopwatch()..start();
  AudioOriginalDescriptor? _descriptor;
  AudioFileDecoder? _decoder;
  AlignedPcmBuffer? _buffer;
  AudioRenditionMixer? _mixer;
  Future<void>? _run;
  Future<void>? _resetting;
  bool _closed = false;
  bool _disabled = false;
  bool _failed = false;
  bool _complete = false;
  bool _renderingOriginal = false;
  bool _warmWaiting = false;
  bool _warmAttempted = false;
  AudioAutoQualityScope? _probeScope;
  int _generation = 0;
  int _cursorFrame = 0;
  int _producedFrames = 0;
  int _deliveryMicroseconds = 0;

  _AutoOriginalSource(this._host);

  Duration get _now => _host._autoOriginalNow?.call() ?? _clock.elapsed;

  int get reserveMs => (_buffer?.availableAt(_cursorFrame) ?? 0) * 1000 ~/ math.max(1, _host._sampleRate);

  double get _deliveryRatio => _producedFrames * 1000000 / math.max(1, _host._sampleRate * _deliveryMicroseconds);

  void describe(Object? value) {
    final next = AudioOriginalDescriptor.tryParse(value);
    final previous = _descriptor;
    if (previous != null &&
        next != null &&
        (previous.sourceVersion != next.sourceVersion || previous.totalLength != next.totalLength)) {
      throw AudioSourceRejected('The Auto Original source changed during playback.');
    }

    _descriptor = next;
    if (next == null && _buffer != null) {
      _failed = true;
    }
  }

  void notifyNetworkChange(int generation) => _decoder?.notifyNetworkChange(generation);

  bool get _audibleOccurrence {
    final source = _host._gaplessSource;

    return source == null || !source._isPrepared || source._announced;
  }

  void rememberAudible(AudioStreamQuality? quality) {
    if (quality == AudioStreamQuality.original &&
        _renderingOriginal &&
        !_failed &&
        !_host._userPaused &&
        _audibleOccurrence &&
        _probeScope == _host._autoQualityScope) {
      _host.autoQualityHistory?.rememberOriginal(_host._autoQualityScope);
    }
  }

  /// A recent success permits an early probe, never unvalidated Original PCM.
  /// Bound the extra startup wait so a changed/new file cannot hold up playback.
  Future<void> prepareWarmStartup(int positionMs) async {
    if (_warmAttempted || _disabled || _closed || _resetting != null) {
      return;
    }
    _warmAttempted = true;
    final descriptor = _descriptor;
    final history = _host.autoQualityHistory;

    if (descriptor == null ||
        history == null ||
        !history.mayWarmOriginal(_host._autoQualityScope) ||
        _host._userPaused ||
        _host._pcmBitsPerSample != 32 ||
        descriptor.durationMs - positionMs < AutoOriginalPolicy.upgradeReserveMs) {
      return;
    }

    _cursorFrame = positionMs * _host._sampleRate ~/ 1000;
    _warmWaiting = true;
    final generation = _startPreparing(descriptor, positionMs ~/ 5000 * 5000);
    final deadline = Stopwatch()..start();

    try {
      while (_host._isActive &&
          !_closed &&
          !_failed &&
          generation == _generation &&
          deadline.elapsed < const Duration(seconds: 1)) {
        if (reserveMs >= AutoOriginalPolicy.upgradeReserveMs && _deliveryRatio >= 1.15) {
          break;
        }

        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    } finally {
      _warmWaiting = false;
    }
  }

  bool finishedAt(int frame) => _renderingOriginal && _complete && _buffer != null && frame >= _buffer!.endFrame;

  Int32List? continueWithoutFallback(int frame) {
    if (!_renderingOriginal || _resetting != null) {
      return null;
    }
    _cursorFrame = frame;
    final buffer = _buffer;
    buffer?.discardBefore(frame);
    final frames = math.min(_host._sampleRate ~/ 50, buffer?.availableAt(frame) ?? 0);
    if (frames <= 0) {
      return null;
    }
    final samples = buffer!.readAt(frame, frames)!;
    _cursorFrame = frame + frames;

    return _mixer!.continueOriginal(samples);
  }

  Future<void> reset() => _resetting ??= _reset().whenComplete(() => _resetting = null);

  Future<void> close() {
    _closed = true;

    return reset();
  }

  Future<void> _reset() async {
    _generation++;
    final decoder = _decoder;
    final running = _run;
    _decoder = null;
    _run = null;
    _buffer = null;
    _mixer = null;
    _renderingOriginal = false;
    _policy.reset();
    decoder?.interruptRead();
    await decoder?.close();
    await running;
  }

  ({Int32List samples, AudioStreamQuality? quality}) render(
    Int16List opus, {
    required int frame,
    required AudioStreamQuality? fallbackQuality,
  }) {
    _cursorFrame = frame;
    final frames = opus.length ~/ _host._channels;
    final buffer = _buffer;
    buffer?.discardBefore(frame);
    final available = buffer?.availableAt(frame) ?? 0;
    final original = available >= frames ? buffer?.readAt(frame, frames) : null;
    final useOriginal = _policy.select(
      now: _now,
      reserveMs: original == null ? 0 : available * 1000 ~/ _host._sampleRate,
      deliveryRatio: _deliveryRatio,
      failed: _failed || _resetting != null,
      complete: _complete,
    );
    _mixer ??= AudioRenditionMixer(channels: _host._channels, transitionFrames: _host._sampleRate ~/ 100);
    final mixed = _mixer!.mix(opus, original, useOriginal: useOriginal);

    if (useOriginal != _renderingOriginal) {
      _host._log(
        'Auto Original transition: ${useOriginal ? 'OG' : fallbackQuality?.name} '
        'at_frame=$frame reserve_ms=${available * 1000 ~/ _host._sampleRate} '
        'delivery_ratio=${_deliveryRatio.toStringAsFixed(2)}.',
      );
      _renderingOriginal = useOriginal;
      if (!useOriginal) {
        if (_audibleOccurrence && _probeScope == _host._autoQualityScope && !_complete) {
          _host.autoQualityHistory?.deferOriginal(_host._autoQualityScope);
        }

        _failed = true;
        _decoder?.interruptRead();
      }
    }

    if (!_closed && _resetting == null && _run == null && (_buffer == null || _failed)) {
      _maybePrepare(frame, fallbackQuality);
    }

    // Reading Original advances its buffer head. Reserve is measured from
    // the following presentation frame, not the block already consumed.
    _cursorFrame = frame + frames;

    return (samples: mixed, quality: useOriginal ? AudioStreamQuality.original : fallbackQuality);
  }

  void _maybePrepare(int frame, AudioStreamQuality? fallbackQuality) {
    final descriptor = _descriptor;
    if (descriptor == null ||
        _disabled ||
        !(_host.autoQualityHistory?.mayProbeOriginal(_host._autoQualityScope) ?? true)) {
      return;
    }
    final prepared = _host._gaplessSource;
    final eligible =
        !_host._userPaused &&
        _host._isActive &&
        (prepared == null || !prepared._isPrepared || prepared._announced) &&
        (fallbackQuality == AudioStreamQuality.medium || fallbackQuality == AudioStreamQuality.high);
    if (!_policy.mayPrepare(now: _now, fallbackReserveMs: _host._ownerRemote._playableMs, active: eligible)) {
      return;
    }

    // Leave time for the independent decoder to seek and prepare. Both codec
    // clocks meet at an exact five-second presentation position.
    final startMs = ((frame * 1000 ~/ _host._sampleRate + 6999) ~/ 5000) * 5000;
    if (descriptor.durationMs - startMs < AutoOriginalPolicy.upgradeReserveMs) {
      return;
    }
    _startPreparing(descriptor, startMs);
  }

  int _startPreparing(AudioOriginalDescriptor descriptor, int startMs) {
    _probeScope = _host._autoQualityScope;
    final generation = ++_generation;
    final running = _prepare(descriptor, startMs, generation);
    _run = running;
    unawaited(
      running.whenComplete(() {
        if (identical(_run, running)) {
          _run = null;
        }
      }),
    );

    return generation;
  }

  Future<void> _prepare(AudioOriginalDescriptor descriptor, int startMs, int generation) async {
    final base = Uri.parse(_host.baseUrl);
    final host = base.host == 'localhost' ? '127.0.0.1' : base.host;
    final httpPort = base.hasPort ? base.port : (base.scheme == 'https' ? 443 : 80);
    final port = (_host.quicPort ?? 0) > 0 ? _host.quicPort! : httpPort + 1;
    final uri = Uri(scheme: 'quic', host: host, port: port, pathSegments: [_host.trackId]);
    AudioFileDecoder? decoder;
    _failed = false;
    _complete = false;
    _producedFrames = 0;
    _deliveryMicroseconds = 0;
    final progress = Stopwatch()..start();
    bool current() => !_closed && !_failed && _host._isActive && generation == _generation;

    try {
      decoder =
          _host._fileDecoderFactory?.call(uri, Duration(milliseconds: startMs)) ??
          AudioFileDecoder.quic(
            host: host,
            port: port,
            trackId: _host.trackId,
            token: _host.token,
            serverPin: _host.serverPin,
            startOffset: Duration(milliseconds: startMs),
            expectedSourceMetadata: descriptor.sourceMetadata,
          );
      _decoder = decoder;
      await decoder.initialize().timeout(const Duration(seconds: 18));
      if (!current()) {
        return;
      }
      final identity = decoder.sourceMetadata;
      if (identity?['source_version'] != descriptor.sourceVersion ||
          identity?['total_length'] != descriptor.totalLength) {
        throw AudioSourceRejected('Auto Original does not match its compressed safety stream.');
      }
      final format = decoder.format;
      if (format.sampleRate < 8000 || format.channels < 1 || format.channels > 2) {
        throw StateError('The Original format cannot share the Auto output.');
      }
      var preparedStartMs = startMs;
      final futureMs = ((_cursorFrame * 1000 ~/ _host._sampleRate + 6999) ~/ 5000) * 5000;
      if (!_warmWaiting && futureMs > preparedStartMs) {
        preparedStartMs = futureMs;
        if (descriptor.durationMs - preparedStartMs < AutoOriginalPolicy.upgradeReserveMs) {
          throw StateError('The track is ending before Original can be prepared.');
        }
        final position = await decoder
            .seek(Duration(milliseconds: preparedStartMs))
            .timeout(const Duration(seconds: 18));
        if (!current()) return;
        if (position.inMilliseconds != preparedStartMs) {
          throw StateError('Original preparation could not align its presentation position.');
        }
      }
      final buffer = AlignedPcmBuffer(
        channels: _host._channels,
        capacityFrames: _host._sampleRate * AutoOriginalPolicy.targetReserveMs ~/ 1000,
        startFrame: preparedStartMs * _host._sampleRate ~/ 1000,
      );
      _buffer = buffer;
      _host._log('Auto Original preparing: start_ms=$preparedStartMs source_bps=${descriptor.averageBitrateBps}.');

      while (current()) {
        buffer.discardBefore(_cursorFrame);
        if (!_renderingOriginal && _deliveryMicroseconds > 8000000 && reserveMs < 4000) {
          throw TimeoutException('Original preparation did not build a sustainable reserve.');
        }
        if (_host._userPaused || buffer.freeFrames < _host._sampleRate ~/ 4 + 512) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          continue;
        }

        decoder.reportPlayableMilliseconds(_host._ownerRemote._playableMs);
        final started = progress.elapsedMicroseconds;
        final samples = await decoder
            .readNormalized32(outputRate: _host._sampleRate, outputChannels: _host._channels)
            .timeout(const Duration(seconds: 3));
        if (!current()) {
          return;
        }
        _deliveryMicroseconds += math.max(1, progress.elapsedMicroseconds - started);
        _producedFrames += samples.length ~/ _host._channels;
        buffer.append(samples);
        if (samples.isEmpty) {
          _complete = true;
          break;
        }
        // Let controls run between decoder-worker replies, even for cached files.
        await Future<void>.delayed(Duration.zero);
      }
    } catch (error) {
      if (generation == _generation && !_closed) {
        _failed = true;
        _policy.retire(_now);

        if (error is TimeoutException && _audibleOccurrence && _probeScope == _host._autoQualityScope) {
          _host.autoQualityHistory?.deferOriginal(_host._autoQualityScope);
        }

        _host._log('Auto Original deferred: ${error.runtimeType}; compressed playback retained.');
      }
    } finally {
      try {
        await decoder?.close();
        if (identical(_decoder, decoder)) {
          _decoder = null;
        }
      } catch (error) {
        if (generation == _generation && !_closed) {
          _failed = true;
          _policy.retire(_now);
          _host._log('Auto Original release failed: ${error.runtimeType}.');
        }
      }
    }
  }
}
