import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:phonolite_app/infrastructure/audio/output/audio_pcm_output.dart';
import 'package:phonolite_app/infrastructure/platform/audio/windows/xaudio2_bindings.dart';

/// Queues unscaled PCM; the native source voice applies volume while rendering.
class XAudio2Player implements AudioPcmOutput, AudioPcm32Output {
  final int _sampleRate;
  final int _channels;
  final int _deviceId;
  final int _bitsPerSample;
  final int _validBitsPerSample;
  final XAudio2Bindings Function() _bindingsFactory;
  late final XAudio2Bindings _bindings = _bindingsFactory();
  ffi.Pointer<ffi.Void> _handle = ffi.nullptr;
  double _volume = 1.0;
  bool _paused = false;
  int _writeEpoch = 0;
  Future<void>? _initialization;
  Future<void>? _shutdown;

  XAudio2Player({
    required int sampleRate,
    required int channels,
    required int deviceId,
    int bitsPerSample = 16,
    int validBitsPerSample = 16,
    XAudio2Bindings Function()? bindingsFactory,
  }) : _sampleRate = sampleRate,
       _channels = channels,
       _deviceId = deviceId,
       _bitsPerSample = bitsPerSample,
       _validBitsPerSample = validBitsPerSample,
       _bindingsFactory = bindingsFactory ?? XAudio2Bindings.new;

  @override
  Future<void> initialize() => _initialization ??= Future<void>.sync(() {
    if (_shutdown != null) {
      throw StateError('Audio output is closed.');
    }

    final handle = _bitsPerSample == 16
        ? _bindings.open(_sampleRate, _channels, _deviceId)
        : _bindings.openFormat(_sampleRate, _channels, _deviceId, _bitsPerSample, _validBitsPerSample);

    if (handle == ffi.nullptr) {
      throw StateError('XAudio2 could not open the audio output.');
    }

    try {
      _check(_bindings.setVolume(handle, _volume), 'set volume');
      if (_paused) {
        _check(_bindings.pause(handle), 'pause');
      }
    } catch (_) {
      _bindings.close(handle);
      rethrow;
    }

    _handle = handle;
  });

  @override
  Future<void> dispose() => _shutdown ??= Future<void>.sync(() {
    _writeEpoch++;
    final handle = _handle;
    _handle = ffi.nullptr;
    if (handle != ffi.nullptr) {
      _bindings.close(handle);
    }
  });

  @override
  Future<void> write(Int16List samples) => _writePcm(samples, 16);

  @override
  Future<void> writePcm32(Int32List samples) => _writePcm(samples, 32);

  @override
  Future<void> flush() async {
    _writeEpoch++;
    final handle = _handle;
    if (handle != ffi.nullptr) {
      _check(_bindings.flush(handle), 'flush');
    }
  }

  @override
  void setVolume(double value) {
    _volume = value.clamp(0.0, 1.0);
    final handle = _handle;
    if (handle != ffi.nullptr) {
      _check(_bindings.setVolume(handle, _volume), 'set volume');
    }
  }

  @override
  void pause() {
    _paused = true;
    final handle = _handle;
    if (handle != ffi.nullptr) {
      _check(_bindings.pause(handle), 'pause');
    }
  }

  @override
  void resume() {
    _paused = false;
    final handle = _handle;
    if (handle != ffi.nullptr) {
      _check(_bindings.resume(handle), 'resume');
    }
  }

  @override
  Future<int> collectDoneSamples() async {
    final handle = _handle;
    if (handle == ffi.nullptr) {
      return 0;
    }
    final samples = _bindings.collectDoneSamples(handle);
    if (samples < 0) {
      throw StateError('XAudio2 sample collection failed: $samples');
    }
    return samples;
  }

  @override
  Future<bool> isIdle() async {
    final handle = _handle;
    if (handle == ffi.nullptr) {
      return true;
    }
    final result = _bindings.isIdle(handle);
    if (result < 0) {
      throw StateError('XAudio2 idle check failed: $result');
    }
    return result != 0;
  }

  Future<void> _writePcm(TypedData samples, int bitsPerSample) async {
    if (_bitsPerSample != bitsPerSample) {
      throw StateError('The PCM precision does not match the configured XAudio2 output.');
    }

    final handle = _handle;
    final epoch = _writeEpoch;
    final sampleCount = samples.lengthInBytes ~/ (bitsPerSample ~/ 8);

    if (handle == ffi.nullptr || sampleCount == 0) {
      return;
    }

    final data = calloc<ffi.Uint8>(samples.lengthInBytes);

    try {
      data
          .asTypedList(samples.lengthInBytes)
          .setAll(0, samples.buffer.asUint8List(samples.offsetInBytes, samples.lengthInBytes));

      while (_handle == handle && epoch == _writeEpoch) {
        final result = bitsPerSample == 32
            ? _bindings.write32(handle, data.cast<ffi.Int32>(), sampleCount)
            : _bindings.write(handle, data.cast<ffi.Int16>(), sampleCount);
        if (result == xaudio2Ok) {
          return;
        }
        if (result != xaudio2QueueFull) {
          _check(result, 'write');
        }

        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
    } finally {
      calloc.free(data);
    }
  }

  void _check(int result, String operation) {
    if (result != xaudio2Ok) {
      throw StateError('XAudio2 $operation failed: $result');
    }
  }
}
