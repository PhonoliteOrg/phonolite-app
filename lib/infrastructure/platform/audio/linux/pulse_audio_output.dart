import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:phonolite_app/infrastructure/audio/output/audio_pcm_output.dart';
import 'package:phonolite_app/infrastructure/platform/audio/linux/native_pulse_audio_stream.dart';
import 'package:phonolite_app/infrastructure/platform/audio/linux/pulse_audio_stream.dart';

/// Sends PCM to PulseAudio, including PipeWire's PulseAudio compatibility service.
class PulseAudioPlayer implements BoundedAudioPcmOutput, AudioPcm32Output {
  final int _sampleRate;
  final int _channels;
  final int _bitsPerSample;
  final PulseAudioStream Function() _createStream;
  final Duration connectionTimeout;
  PulseAudioStream? _stream;
  Future<void>? _initialization;
  Future<void>? _shutdown;
  bool _closed = false;
  bool _paused = false;
  double _volume = 1;
  int _writeEpoch = 0;
  int _collectedSamples = 0;
  Future<void>? _flushing;

  PulseAudioPlayer({
    required int sampleRate,
    required int channels,
    required int deviceId,
    int bitsPerSample = 16,
    int validBitsPerSample = 16,
    PulseAudioStream Function()? createStream,
    this.connectionTimeout = const Duration(seconds: 10),
  }) : _sampleRate = sampleRate,
       _channels = channels,
       _bitsPerSample = bitsPerSample,
       _createStream = createStream ?? NativePulseAudioStream.new {
    if (sampleRate <= 0 || sampleRate > 384000 || channels <= 0 || channels > 8) {
      throw ArgumentError('Unsupported Linux audio format.');
    }
    if ((bitsPerSample != 16 && bitsPerSample != 32) || validBitsPerSample <= 0 || validBitsPerSample > bitsPerSample) {
      throw ArgumentError('Unsupported PCM precision.');
    }
    if (deviceId != kDefaultOutputDeviceId) {
      throw ArgumentError('Linux audio currently uses the system default output device.');
    }
  }

  @override
  Future<void> initialize() => _initialization ??= _open();

  @override
  Future<void> dispose() => _shutdown ??= _close();

  Future<void> _close() async {
    _closed = true;
    _writeEpoch++;
    _stream?.close();
    _stream = null;
    try {
      await _initialization;
    } catch (_) {
      // Startup failure/cancellation still releases every native resource.
    }
  }

  @override
  Future<void> write(Int16List samples) => _write(samples, 16);

  @override
  Future<void> writePcm32(Int32List samples) => _write(samples, 32);

  @override
  Future<void> flush() {
    _writeEpoch++;

    return _flushing ??= _flush().whenComplete(() => _flushing = null);
  }

  @override
  void setVolume(double value) {
    _volume = value.isFinite ? value.clamp(0.0, 1.0) : 0;
    _stream?.setVolume(_volume);
  }

  @override
  void pause() {
    _paused = true;
    _stream?.setPaused(true);
  }

  @override
  void resume() {
    _paused = false;
    _stream?.setPaused(false);
  }

  @override
  Future<int> collectDoneSamples() async {
    final stream = _stream;
    if (stream == null || _flushing != null || !stream.poll()) {
      return 0;
    }

    final played = stream.playedSamples;
    final done = math.max(0, played - _collectedSamples);
    _collectedSamples = played;

    return done;
  }

  @override
  Future<bool> isIdle() async {
    final stream = _stream;

    return stream == null || (_flushing == null && stream.poll() && stream.isIdle);
  }

  Future<void> _open() async {
    if (_closed) {
      throw StateError('Audio output is closed.');
    }

    final stream = _createStream();
    _stream = stream;

    try {
      stream.open(sampleRate: _sampleRate, channels: _channels, bitsPerSample: _bitsPerSample);
      await _waitUntilReady(stream);
      if (_closed || !identical(_stream, stream)) {
        throw StateError('Audio output is closed.');
      }
      stream.setVolume(_volume);
      stream.setPaused(_paused);
    } catch (_) {
      if (identical(_stream, stream)) {
        _stream = null;
        stream.close();
      }
      rethrow;
    }
  }

  Future<void> _waitUntilReady(PulseAudioStream stream) async {
    final deadline = Stopwatch()..start();

    while (identical(_stream, stream) && !_closed) {
      if (stream.poll()) {
        return;
      }
      if (deadline.elapsed >= connectionTimeout) {
        throw TimeoutException('Linux audio server did not respond. Check your desktop audio service.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }

    throw StateError('Audio output is closed.');
  }

  Future<void> _flush() async {
    final stream = _stream;
    if (stream == null) {
      return;
    }

    stream.flush();
    await _waitUntilReady(stream);
    _collectedSamples = 0;
  }

  Future<void> _write(TypedData samples, int bitsPerSample) async {
    if (_bitsPerSample != bitsPerSample || samples.lengthInBytes % (_channels * (bitsPerSample ~/ 8)) != 0) {
      throw ArgumentError('PCM data must match the configured precision and contain complete frames.');
    }

    final epoch = _writeEpoch;
    final bytes = samples.buffer.asUint8List(samples.offsetInBytes, samples.lengthInBytes);
    final chunkBytes = math.max(1, _sampleRate ~/ 50) * _channels * (bitsPerSample ~/ 8);
    var offset = 0;

    while (offset < bytes.length && epoch == _writeEpoch && !_closed) {
      final stream = _stream;
      if (stream == null) {
        throw StateError('Initialize Linux audio output before writing.');
      }

      if (_flushing != null || !stream.poll()) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
        continue;
      }

      final end = math.min(bytes.length, offset + chunkBytes);
      final written = stream.write(Uint8List.sublistView(bytes, offset, end));
      offset += written;

      if (written == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
    }
  }
}
