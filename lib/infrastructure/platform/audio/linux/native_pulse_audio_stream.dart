import 'dart:ffi';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:phonolite_app/infrastructure/platform/audio/linux/pulse_audio_bindings.dart';
import 'package:phonolite_app/infrastructure/platform/audio/linux/pulse_audio_operation.dart';
import 'package:phonolite_app/infrastructure/platform/audio/linux/pulse_audio_stream.dart';

/// Owns a libpulse mainloop, connection and stream on one Dart isolate.
/// All protocol dispatch is nonblocking; no native callback enters another isolate.
class NativePulseAudioStream implements PulseAudioStream {
  final DynamicLibrary? library;
  late final PulseAudioBindings _api;
  Pointer<Void> _mainloop = nullptr;
  Pointer<Void> _context = nullptr;
  Pointer<Void> _stream = nullptr;
  PulseAudioOperation? _flushOperation;
  PulseAudioOperation? _drainOperation;
  int _drainingFrames = 0;
  int _rate = 0;
  int _channels = 0;
  int _bits = 0;
  int _writtenFrames = 0;
  int _playedFrames = 0;
  double _volume = 1;
  bool _paused = false;
  bool _ready = false;

  NativePulseAudioStream({this.library});

  @override
  int get playedSamples {
    if (!_ready || _flushOperation != null || _writtenFrames == 0) {
      return _playedFrames * _channels;
    }

    final latency = calloc<Uint64>();
    final negative = calloc<Int32>();

    try {
      if (_api.streamLatency(_stream, latency, negative) < 0) {
        // Timing arrives asynchronously shortly after connection/flush.
        if (_api.contextError(_context) == 16) {
          return _playedFrames * _channels;
        }
        throw _error('Read playback latency');
      }

      final pendingFrames = negative.value != 0 ? 0 : (latency.value * _rate / 1000000).ceil();
      _playedFrames = math.max(_playedFrames, (_writtenFrames - pendingFrames).clamp(0, _writtenFrames));

      return _playedFrames * _channels;
    } finally {
      calloc.free(latency);
      calloc.free(negative);
    }
  }

  @override
  bool get isIdle {
    if (playedSamples >= _writtenFrames * _channels) {
      return true;
    }

    // The caller probes idle only after its producer has finished this queue.
    // A drain during continuous writes waits for silence and can time out.
    _ensureDrain();

    return false;
  }

  @override
  void open({required int sampleRate, required int channels, required int bitsPerSample}) {
    _api = PulseAudioBindings(library ?? DynamicLibrary.open('libpulse.so.0'));
    _rate = sampleRate;
    _channels = channels;
    _bits = bitsPerSample;
    _mainloop = _api.mainloopNew();

    if (_mainloop == nullptr) {
      throw StateError('Could not allocate the Linux audio mainloop.');
    }

    final name = 'Phonolite'.toNativeUtf8();
    try {
      _context = _api.contextNew(_api.mainloopApi(_mainloop), name);
    } finally {
      calloc.free(name);
    }

    if (_context == nullptr) {
      throw StateError('Could not create the Linux audio connection.');
    }
    // PA_CONTEXT_NOAUTOSPAWN: connect to the desktop's existing service.
    if (_api.contextConnect(_context, nullptr, 1, nullptr) < 0) {
      throw _error('Connect to the desktop audio service');
    }
  }

  @override
  bool poll() {
    if (_mainloop == nullptr) {
      throw StateError('Linux audio connection is closed.');
    }

    // Bound dispatch work so a busy server cannot starve worker cancellation.
    for (var i = 0; i < 16; i++) {
      final dispatched = _api.mainloopIterate(_mainloop, 0, nullptr);
      if (dispatched < 0) {
        throw _error('Dispatch audio messages');
      }
      if (dispatched == 0) {
        break;
      }
    }

    final contextState = _api.contextState(_context);
    if (contextState >= 5) {
      throw _error('Desktop audio service disconnected');
    }
    if (contextState != 4) {
      return false;
    }
    if (_stream == nullptr) {
      _connectStream();
    }

    final streamState = _api.streamState(_stream);
    if (streamState >= 3) {
      throw _error('Audio stream disconnected');
    }
    if (streamState != 2) {
      return false;
    }
    if (!_ready) {
      _ready = true;
      setVolume(_volume);
      setPaused(_paused);
    }

    if (_flushOperation != null) {
      final succeeded = _flushOperation!.poll();
      if (succeeded == null) {
        return false;
      }

      _flushOperation!.dispose();
      _flushOperation = null;
      if (!succeeded) {
        throw _error('Flush audio');
      }
      _writtenFrames = 0;
      _playedFrames = 0;
    }

    final drain = _drainOperation;
    if (drain != null) {
      final succeeded = drain.poll();
      if (succeeded != null) {
        _releaseDrain();
        if (!succeeded) {
          throw _error('Drain audio');
        }
        // The acknowledgement only covers the writes present when requested.
        // Newer writes must get their own timing or completion confirmation.
        _playedFrames = math.max(_playedFrames, _drainingFrames);
      }
    }

    return true;
  }

  @override
  int write(Uint8List bytes) {
    final writable = _api.streamWritable(_stream);
    if (writable < 0 || writable > 0x7fffffff) {
      throw _error('Query audio queue');
    }

    final frameSize = _channels * (_bits ~/ 8);
    final count = math.min(bytes.length, writable) ~/ frameSize * frameSize;
    if (count == 0) {
      return 0;
    }

    // A late successor can resume writes after an end-of-queue probe. Its data
    // must neither inherit that acknowledgement nor its operation deadline.
    _releaseDrain();
    final data = calloc<Uint8>(count);
    try {
      data.asTypedList(count).setRange(0, count, bytes);
      // A null free callback instructs libpulse to copy the bytes before return.
      if (_api.streamWrite(_stream, data, count, nullptr, 0, 0) < 0) {
        throw _error('Write audio');
      }
      _writtenFrames += count ~/ frameSize;
    } finally {
      calloc.free(data);
    }

    return count;
  }

  @override
  void flush() {
    if (!_ready || _flushOperation != null) {
      return;
    }

    _releaseDrain();
    _flushOperation = PulseAudioOperation(_api, start: (callback) => _api.streamFlush(_stream, callback, nullptr));
  }

  @override
  void setVolume(double value) {
    _volume = value;
    if (!_ready) {
      return;
    }

    final volume = calloc<PulseVolume>();
    try {
      volume.ref.channels = _channels;
      // PulseAudio's volume scale is cubic; convert the app's linear gain.
      final level = (math.pow(value, 1 / 3) * 65536).round();
      for (var i = 0; i < _channels; i++) {
        volume.ref.values[i] = level;
      }
      _releaseCommand(_api.setVolume(_context, _api.streamIndex(_stream), volume, nullptr, nullptr));
    } finally {
      calloc.free(volume);
    }
  }

  @override
  void setPaused(bool paused) {
    _paused = paused;
    if (paused) {
      _releaseDrain();
    }

    if (_ready) {
      _releaseCommand(_api.streamCork(_stream, paused ? 1 : 0, nullptr, nullptr));
    }
  }

  @override
  void close() {
    _ready = false;
    _releaseDrain();
    _flushOperation?.dispose();
    _flushOperation = null;
    if (_stream != nullptr) {
      _api.streamDisconnect(_stream);
      _api.streamUnref(_stream);
      _stream = nullptr;
    }
    if (_context != nullptr) {
      _api.contextDisconnect(_context);
      _api.contextUnref(_context);
      _context = nullptr;
    }
    if (_mainloop != nullptr) {
      _api.mainloopFree(_mainloop);
      _mainloop = nullptr;
    }
  }

  void _connectStream() {
    final spec = calloc<PulseSampleSpec>();
    final attributes = calloc<PulseBufferAttributes>();
    final name = 'Music'.toNativeUtf8();

    try {
      spec.ref
        ..format = _bits == 32
            ? 7
            : 3 // PA_SAMPLE_S32LE / PA_SAMPLE_S16LE.
        ..rate = _rate
        ..channels = _channels;
      _stream = _api.streamNew(_context, name, spec, nullptr);
      if (_stream == nullptr) {
        throw _error('Create audio stream');
      }

      final queueBytes = (_rate ~/ 5) * _channels * (_bits ~/ 8);
      attributes.ref
        ..maximumLength = queueBytes
        ..targetLength = queueBytes
        // One frame also lets very short tracks play. Automatic prebuffering
        // prevents the read index overtaking writes during a source underrun.
        ..prebuffer = _channels * (_bits ~/ 8)
        ..minimumRequest = 0xffffffff
        ..fragmentSize = 0xffffffff;
      // Start corked; interpolate server timing and request automatic updates.
      if (_api.streamConnect(_stream, nullptr, attributes, 0x0001 | 0x0002 | 0x0008, nullptr, nullptr) < 0) {
        throw _error('Open default audio output');
      }
    } finally {
      calloc.free(spec);
      calloc.free(attributes);
      calloc.free(name);
    }
  }

  void _releaseCommand(Pointer<Void> operation) {
    if (operation == nullptr) {
      throw _error('Configure audio stream');
    }
    _api.operationUnref(operation);
  }

  void _ensureDrain() {
    if (!_ready || _paused || _flushOperation != null || _playedFrames >= _writtenFrames || _drainOperation != null) {
      return;
    }

    // Interpolated latency can retain a final frame after the server has played
    // it. Drain acknowledgements bound that estimate without guessing or
    // counting queued samples as audible. Only one drain can be outstanding.
    _drainingFrames = _writtenFrames;
    _drainOperation = PulseAudioOperation(_api, start: (callback) => _api.streamDrain(_stream, callback, nullptr));
  }

  void _releaseDrain() {
    _drainOperation?.dispose();
    _drainOperation = null;
  }

  StateError _error(String operation) {
    final message = _api.errorString(_api.contextError(_context)).toDartString();

    return StateError('$operation: $message. Check your PipeWire/PulseAudio output settings.');
  }
}
