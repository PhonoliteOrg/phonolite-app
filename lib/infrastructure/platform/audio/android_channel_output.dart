import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'package:phonolite_app/infrastructure/audio/output/audio_pcm_output.dart';
import 'package:phonolite_app/infrastructure/platform/audio/apple/core_audio_bindings.dart';

const MethodChannel androidAudioOutputChannel = MethodChannel('phonolite/audio_output');

class AndroidChannelPlayer implements AudioPcmOutput {
  final int _sampleRate;
  final int _channels;
  final int _deviceId;
  int? _handleId;
  Future<void>? _openFuture;
  Future<void>? _shutdown;
  double _pendingVolume = 1.0;
  bool _pendingPaused = false;
  bool _disposed = false;
  int _writeEpoch = 0;

  AndroidChannelPlayer({required int sampleRate, required int channels, required int deviceId})
    : _sampleRate = sampleRate,
      _channels = channels,
      _deviceId = deviceId;

  @override
  Future<void> initialize() {
    if (_disposed) {
      return Future<void>.error(StateError('Audio output is closed.'));
    }

    return _openFuture ??= _open();
  }

  @override
  Future<void> dispose() => _shutdown ??= _close();

  Future<void> _close() async {
    _writeEpoch++;
    _disposed = true;

    try {
      // Wait for startup to hand over any late native handle before closing it.
      await _openFuture;
    } catch (_) {
      // The initialization caller owns the startup failure.
    }

    final handle = _handleId;

    _handleId = null;

    if (handle != null) {
      await androidAudioOutputChannel.invokeMethod<void>('close', {'id': handle});
    }
  }

  @override
  Future<void> write(Int16List samples) async {
    if (samples.isEmpty) {
      return;
    }

    final epoch = _writeEpoch;

    final handle = await _handle();
    if (handle == null) {
      return;
    }

    final bytes = Uint8List.view(samples.buffer, samples.offsetInBytes, samples.lengthInBytes);

    while (true) {
      if (_disposed || epoch != _writeEpoch || handle != _handleId) {
        return;
      }

      final result = await androidAudioOutputChannel.invokeMethod<int>('write', {'id': handle, 'pcm': bytes});

      if (_disposed || epoch != _writeEpoch || handle != _handleId) {
        return;
      }

      if (result == null || result == 0) {
        return;
      }

      if (result == coreAudioQueueFull) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
        continue;
      }

      throw Exception('Android audio write failed: $result');
    }
  }

  @override
  Future<void> flush() async {
    _writeEpoch++;

    final handle = await _handle();
    if (handle == null) {
      return;
    }

    await androidAudioOutputChannel.invokeMethod<void>('flush', {'id': handle});
  }

  @override
  void setVolume(double value) {
    _pendingVolume = value.clamp(0.0, 1.0);

    final handle = _handleId;
    if (handle == null) {
      return;
    }

    androidAudioOutputChannel.invokeMethod<void>('setVolume', {'id': handle, 'value': _pendingVolume});
  }

  @override
  void pause() {
    _pendingPaused = true;

    final handle = _handleId;
    if (handle == null) {
      return;
    }

    androidAudioOutputChannel.invokeMethod<void>('pause', {'id': handle});
  }

  @override
  void resume() {
    _pendingPaused = false;

    final handle = _handleId;
    if (handle == null) {
      return;
    }

    androidAudioOutputChannel.invokeMethod<void>('resume', {'id': handle});
  }

  @override
  Future<int> collectDoneSamples() async {
    final handle = _handleId;
    if (handle == null) {
      return 0;
    }

    final result = await androidAudioOutputChannel.invokeMethod<int>('collectDoneSamples', {'id': handle});

    return result ?? 0;
  }

  @override
  Future<bool> isIdle() async {
    final handle = _handleId;
    if (handle == null) {
      return true;
    }

    final result = await androidAudioOutputChannel.invokeMethod<bool>('isIdle', {'id': handle});

    return result ?? true;
  }

  Future<void> _open() async {
    final handle = await androidAudioOutputChannel.invokeMethod<int>('open', {
      'sampleRate': _sampleRate,
      'channels': _channels,
      'deviceId': _deviceId,
    });

    if (handle == null || handle <= 0) {
      throw Exception('Android audio output open failed.');
    }

    _handleId = handle;

    if (_disposed) {
      // The awaitable shutdown owns release, including a handle opened late.
      return;
    }

    await androidAudioOutputChannel.invokeMethod<void>('setVolume', {'id': handle, 'value': _pendingVolume});

    if (_pendingPaused) {
      await androidAudioOutputChannel.invokeMethod<void>('pause', {'id': handle});
    }
  }

  Future<int?> _handle() async {
    if (_disposed) {
      return null;
    }

    await initialize();

    return _handleId;
  }
}
