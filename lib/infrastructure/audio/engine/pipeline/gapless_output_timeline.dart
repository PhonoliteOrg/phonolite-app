part of '../audio_engine.dart';

/// One native output, with independently cancellable source leases. Decoder
/// lifetimes never own the device. Only confirmed device consumption advances
/// the audible occurrence; writes and preparation cannot change now-playing.
class _GaplessOutputTimeline {
  final bool normalize;
  final _AudioProgressDeadline _progress;
  final AudioPcmOutput Function(int rate, int channels, int device, int bits, int validBits)? factory;
  final List<_GaplessSourceOutput> _sources = [];
  final ListQueue<_GaplessOutputSpan> _spans = ListQueue();
  AudioPcmOutput? _output;
  _GaplessSourceOutput? _writing;
  _GaplessSourceOutput? _audible;
  Future<void>? _polling;
  Future<void> _configuration = Future<void>.value();
  int _rate = 0, _channels = 0, _bits = 0, _validBits = 0, _device = -1;
  bool _closed = false;
  bool _aborting = false;
  Future<void>? _abortCompletion;
  bool _userPaused = false;
  bool _devicePaused = false;
  double _volume = 1;

  _GaplessOutputTimeline({this.factory, this.normalize = false, Duration progressTimeout = const Duration(seconds: 5)})
    : _progress = _AudioProgressDeadline(progressTimeout);

  _GaplessSourceOutput addSource({required void Function() onAudible, void Function(bool)? onAbort}) {
    _sources.removeWhere(
      (item) => !identical(item, _writing) && (item._cancelled || (item._sealed && item._played >= item._written)),
    );
    final source = _GaplessSourceOutput(this, onAudible, onAbort);
    _sources.add(source);
    _writing ??= source;
    if (identical(_writing, source)) source._activate();
    final previous = _writing;
    if (previous != null && previous._sealed) _advance(previous);
    return source;
  }

  void _advance(_GaplessSourceOutput source) {
    if (_aborting || _closed) return;
    if (!identical(_writing, source) || !source._sealed) return;
    final index = _sources.indexOf(source);
    for (var i = index + 1; i < _sources.length; i++) {
      final next = _sources[i];
      if (next._cancelled) continue;
      _writing = next;
      next._activate();
      return;
    }
  }

  Future<void> _configure(_GaplessSourceOutput source) async {
    final configured = _configuration.then((_) => _configureNow(source));
    _configuration = configured.catchError((Object _) {});
    await configured;
  }

  Future<void> _configureNow(_GaplessSourceOutput source) async {
    if (_closed || source._cancelled) throw StateError('Audio occurrence was cancelled.');
    // A prepared source can describe its format without opening a device.
    if (!source._activated.isCompleted) return;
    if (normalize && _output != null && _device == source.device && _validBits >= source.validBits) {
      _configureConverter(source);
      return;
    }
    if (_output != null &&
        _rate == source.rate &&
        _channels == source.channels &&
        _bits == source.bits &&
        _device == source.device &&
        _validBits >= source.validBits) {
      return;
    }
    // Preserving Original precision/rate can require renegotiation. Never
    // reinterpret PCM or silently discard source bits to disguise that change.
    while (_spans.isNotEmpty && !_closed && !source._cancelled) {
      await poll();
      if (_spans.isNotEmpty) await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    if (_closed || source._cancelled) throw StateError('Audio occurrence was cancelled.');
    final previous = _output;
    _output = null;
    await previous?.dispose();
    _rate = source.rate;
    _channels = source.channels;
    _bits = normalize ? 32 : source.bits;
    _validBits = _bits;
    _device = source.device;
    AudioPcmOutput makeOutput() =>
        factory?.call(_rate, _channels, _device, _bits, _validBits) ??
        createAudioPcmOutput(
          sampleRate: _rate,
          channels: _channels,
          deviceId: _device,
          bitsPerSample: _bits,
          validBitsPerSample: _validBits,
        );
    var output = makeOutput();
    _output = output;
    try {
      try {
        await output.initialize();
      } catch (_) {
        // Pre-Android-12 outputs can represent 24 integer bits through float.
        // Keep that existing precision policy while allowing a common PCM32
        // container for 16/24-bit sources; 32-bit sources never take this path.
        if (!Platform.isAndroid || _bits != 32 || source.validBits > 24) rethrow;
        await output.dispose();
        _validBits = 24;
        output = makeOutput();
        _output = output;
        await output.initialize();
      }
      if (_closed || source._cancelled) throw StateError('Audio occurrence was cancelled.');
      output.setVolume(_volume);
      _devicePaused = _userPaused;
      _progress.reset();
      if (_userPaused) output.pause();
      _configureConverter(source);
    } catch (_) {
      if (identical(_output, output)) _output = null;
      await output.dispose();
      rethrow;
    }
  }

  void _configureConverter(_GaplessSourceOutput source) {
    if (normalize) {
      source._converter ??= PcmStreamConverter(
        inputRate: source.rate,
        inputChannels: source.channels,
        outputRate: _rate,
        outputChannels: _channels,
        inputBits: source.bits,
        outputBits: _bits,
      );
    }
  }

  void _credit(_GaplessSourceOutput source) {
    var played = math.min(
      source._written,
      (source._devicePlayed ~/ math.max(1, _channels)) * source.rate ~/ math.max(1, _rate) * source.channels,
    );
    if (source._sealed && source._deviceWritten > 0 && source._devicePlayed >= source._deviceWritten) {
      played = source._written;
    }
    final newlyPlayed = math.max(0, played - source._played);
    source._pendingDone += newlyPlayed;
    source._played += newlyPlayed;
  }

  Future<void> poll() => _polling ??= _poll().whenComplete(() => _polling = null);

  Future<void> _poll() async {
    final output = _output;
    if (output == null || _closed) return;

    // Probe native completion only for a sealed tail. Doing this during an
    // active source can leave an end-of-stream request waiting throughout the
    // song, eventually timing out while audio is still flowing.
    if (_spans.isNotEmpty && _spans.last.source._sealed && !_userPaused && !_devicePaused && !_aborting) {
      await output.isIdle().timeout(_progress.timeout);
      if (!identical(output, _output) || _closed) return;
    }

    var done = await output.collectDoneSamples().timeout(_progress.timeout);
    if (!identical(output, _output) || _closed) return;
    _progress.check(
      waiting: _spans.isNotEmpty && !_userPaused && !_devicePaused && !_aborting,
      progressed: done > 0,
      operation: 'Audio output',
    );
    while (done > 0 && _spans.isNotEmpty) {
      final span = _spans.first;
      final take = math.min(done, span.remaining);
      if (!span.source._cancelled) {
        span.source._devicePlayed += take;
        _credit(span.source);
        if (!span.source._announced && take > 0) {
          span.source._announced = true;
          _audible = span.source;
          span.source.onAudible();
        }
      }
      span.remaining -= take;
      done -= take;
      if (span.remaining == 0) _spans.removeFirst();
    }
  }

  Future<void> write(_GaplessSourceOutput source, List<int> samples) async {
    final generation = source._generation;
    await source._activated.future;
    if (_closed || _aborting || source._cancelled || generation != source._generation) return;
    await _configure(source);
    if (_closed || _aborting || source._cancelled || generation != source._generation) return;
    source._written += samples.length;
    final converted = source._converter?.process(samples) ?? samples;
    await writeConverted(source, converted, generation: generation);
  }

  Future<void> writeConverted(_GaplessSourceOutput source, List<int> samples, {int? generation}) async {
    generation ??= source._generation;
    if (samples.isEmpty || _aborting) return;
    // Native backpressure owns refill when available. Audible progress also
    // includes hardware latency; using it to cap those writes can starve the
    // native queue before enough audio reaches a higher-latency device.
    final maximumQueued = math.max(_channels, _rate * _channels ~/ 8);
    while (_output is! BoundedAudioPcmOutput &&
        _spans.fold<int>(0, (sum, span) => sum + span.remaining) >= maximumQueued &&
        !_closed &&
        !_aborting &&
        !source._cancelled &&
        generation == source._generation) {
      await poll();
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    if (_closed || _aborting || source._cancelled || generation != source._generation) return;
    final output = _output!;
    // Register before awaiting: a progress poll can race a native write's ack.
    final span = _GaplessOutputSpan(source, samples.length);
    if (_spans.isEmpty) _progress.reset();
    _spans.add(span);
    source._deviceWritten += samples.length;
    try {
      final writing = samples is Int32List ? output.writePcm32(samples) : output.write(samples as Int16List);
      if (output is BoundedAudioPcmOutput) {
        await _waitForBoundedWrite(writing);
      } else {
        await writing;
      }
    } catch (_) {
      if (_spans.remove(span)) source._deviceWritten -= span.remaining;
      rethrow;
    }
  }

  Future<void> _waitForBoundedWrite(Future<void> writing) async {
    final completed = Completer<void>();
    unawaited(
      writing.then<void>(
        (_) {
          if (!completed.isCompleted) completed.complete();
        },
        onError: (Object error, StackTrace stack) {
          if (!completed.isCompleted) completed.completeError(error, stack);
        },
      ),
    );

    // A blocked native write must still advance the shared playback clock or
    // reach its deadline. Statistics collection alone does not fail playback.
    var checking = false;
    final timer = Timer.periodic(const Duration(milliseconds: 5), (_) async {
      if (checking || completed.isCompleted) return;
      checking = true;
      try {
        await poll();
      } catch (error, stack) {
        if (!completed.isCompleted) completed.completeError(error, stack);
      } finally {
        checking = false;
      }
    });

    try {
      await completed.future;
    } finally {
      timer.cancel();
    }
  }

  void pause() {
    _userPaused = true;
    pauseOutput();
  }

  void resume() {
    _userPaused = false;
    resumeOutput();
  }

  void pauseOutput() {
    _devicePaused = true;
    _progress.reset();
    _output?.pause();
  }

  void resumeOutput() {
    _devicePaused = false;
    _progress.reset();
    _output?.resume();
  }

  void setVolume(double value) {
    _volume = value;
    _output?.setVolume(value);
  }

  Future<void> flush() async {
    await poll();
    _spans.clear();
    _progress.reset();
    await _output?.flush();
    for (final source in _sources) {
      source._written = source._played;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _progress.reset();
    for (final source in _sources) {
      source._cancelled = true;
      source._activate();
    }
    _spans.clear();
    final output = _output;
    _output = null;
    await output?.dispose();
  }

  Future<void> abort() => _abortCompletion ??= _abort();
  Future<void> _abort() async {
    _aborting = true;
    _output?.pause();
    try {
      await poll();
    } catch (_) {
      /* A failed output must still close. */
    }
    await close();
  }
}

class _GaplessOutputSpan {
  final _GaplessSourceOutput source;
  int remaining;
  _GaplessOutputSpan(this.source, this.remaining);
}

class _GaplessSourceOutput implements AudioPcmOutput, AudioPcm32Output {
  final _GaplessOutputTimeline timeline;
  final void Function() onAudible;
  final void Function(bool)? onAbort;
  final Completer<void> _activated = Completer<void>();
  int rate = 0, channels = 0, bits = 16, validBits = 16, device = -1;
  int _written = 0, _played = 0, _pendingDone = 0;
  int _deviceWritten = 0, _devicePlayed = 0;
  PcmStreamConverter? _converter;
  int _generation = 0;
  bool _isPrepared = false;
  bool _sealed = false, _cancelled = false, _announced = false;
  _GaplessSourceOutput(this.timeline, this.onAudible, this.onAbort);
  Future<void> abort() async {
    onAbort?.call(true);
    try {
      await timeline.abort();
    } finally {
      onAbort?.call(false);
    }
  }

  void _activate() {
    if (!_activated.isCompleted) _activated.complete();
  }

  void configure(int rate, int channels, int device, int bits, int validBits) {
    this.rate = rate;
    this.channels = channels;
    this.device = device;
    this.bits = bits;
    this.validBits = validBits;
  }

  Future<void> finish() async {
    if (_sealed || _cancelled) return;
    final converter = _converter;
    final generation = _generation;
    if (converter != null) {
      await timeline.writeConverted(this, converter.process(const [], endOfInput: true), generation: generation);
    }
    if (generation != _generation || _cancelled) return;
    _sealed = true;
    timeline._credit(this);
    if (_deviceWritten > 0 || _announced || !_isPrepared) timeline._advance(this);
  }

  void cancel() {
    _generation++;
    _cancelled = true;
    _sealed = true;
    _activate();
  }

  @override
  Future<void> initialize() => timeline._configure(this);
  @override
  Future<void> dispose() async {
    if (!_sealed) cancel();
  }

  @override
  Future<void> write(Int16List samples) => timeline.write(this, samples);
  @override
  Future<void> writePcm32(Int32List samples) => timeline.write(this, samples);
  @override
  Future<void> flush() async {
    _generation++;
    await timeline.flush();
    _sealed = false;
    _written = _played = _pendingDone = 0;
    _deviceWritten = _devicePlayed = 0;
    _converter = null;
    timeline._writing = this;
  }

  @override
  void setVolume(double value) => timeline.setVolume(value);
  @override
  void pause() {
    if (identical(timeline._audible, this)) timeline.pauseOutput();
  }

  @override
  void resume() {
    if (!timeline._userPaused && (identical(timeline._audible, this) || identical(timeline._writing, this))) {
      timeline.resumeOutput();
    }
  }

  @override
  Future<int> collectDoneSamples() async {
    await timeline.poll();
    final done = _pendingDone;
    _pendingDone = 0;
    return done;
  }

  @override
  Future<bool> isIdle() async {
    await timeline.poll();
    return _sealed && (_deviceWritten == 0 || _played >= _written);
  }
}
