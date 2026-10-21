import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:phonolite_app/infrastructure/audio/output/audio_pcm_output.dart';
import 'package:phonolite_app/infrastructure/platform/audio/apple/core_audio_bindings.dart';

class CoreAudioPlayer implements AudioPcmOutput {
  final int _sampleRate;
  final int _channels;
  final int _deviceId;
  late final CoreAudioBindings _bindings;
  ffi.Pointer<ffi.Void> _handle = ffi.nullptr;
  int _writeEpoch = 0;
  Future<void>? _initialization;
  Future<void>? _shutdown;

  CoreAudioPlayer({required int sampleRate, required int channels, required int deviceId})
    : _sampleRate = sampleRate,
      _channels = channels,
      _deviceId = deviceId;

  @override
  Future<void> initialize() => _initialization ??= Future<void>.sync(() {
    if (_shutdown != null) {
      throw StateError('Audio output is closed.');
    }

    _bindings = CoreAudioBindings();
    _open();
  });

  @override
  Future<void> dispose() => _shutdown ??= Future<void>.sync(_close);

  void _close() {
    _writeEpoch++;

    final handle = _handle;

    _handle = ffi.nullptr;

    if (handle == ffi.nullptr) {
      return;
    }

    _bindings.close(handle);
  }

  @override
  Future<void> write(Int16List samples) async {
    if (samples.isEmpty) {
      return;
    }

    final epoch = _writeEpoch;
    final dataPtr = calloc<ffi.Int16>(samples.length);

    try {
      dataPtr.asTypedList(samples.length).setAll(0, samples);

      while (true) {
        if (epoch != _writeEpoch) {
          return;
        }

        final handle = _handle;

        if (handle == ffi.nullptr) {
          return;
        }

        final result = _bindings.write(handle, dataPtr, samples.length);

        if (result == 0) {
          break;
        }

        if (result == coreAudioQueueFull) {
          await Future<void>.delayed(const Duration(milliseconds: 2));
          continue;
        }

        throw Exception('CoreAudio write failed: $result');
      }
    } finally {
      calloc.free(dataPtr);
    }
  }

  @override
  Future<void> flush() async {
    _writeEpoch++;

    final handle = _handle;

    if (handle == ffi.nullptr) {
      return;
    }

    final result = _bindings.flush(handle);

    if (result != 0) {
      throw Exception('CoreAudio reset failed: $result');
    }
  }

  @override
  void setVolume(double value) {
    final handle = _handle;

    if (handle == ffi.nullptr) {
      return;
    }

    _bindings.setVolume(handle, value);
  }

  @override
  void pause() {
    final handle = _handle;

    if (handle == ffi.nullptr) {
      return;
    }

    _bindings.pause(handle);
  }

  @override
  void resume() {
    final handle = _handle;

    if (handle == ffi.nullptr) {
      return;
    }

    _bindings.resume(handle);
  }

  @override
  Future<int> collectDoneSamples() async {
    final handle = _handle;

    if (handle == ffi.nullptr) {
      return 0;
    }

    return _bindings.collectDoneSamples(handle);
  }

  @override
  Future<bool> isIdle() async {
    final handle = _handle;

    if (handle == ffi.nullptr) {
      return true;
    }

    return _bindings.isIdle(handle) != 0;
  }

  void _open() {
    final handle = _bindings.open(_sampleRate, _channels, _deviceId);

    if (handle == ffi.nullptr) {
      throw Exception('CoreAudio open failed.');
    }

    _handle = handle;
  }
}
