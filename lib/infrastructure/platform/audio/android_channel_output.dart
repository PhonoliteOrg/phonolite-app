import 'dart:async';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'package:phonolite_app/infrastructure/audio/output/audio_pcm_output.dart';
import 'package:phonolite_app/infrastructure/audio/output/pcm_queue_writer.dart';
import 'package:phonolite_app/infrastructure/platform/audio/apple/core_audio_bindings.dart';

const MethodChannel androidAudioOutputChannel = MethodChannel('phonolite/audio_output');

/// Each retry resends the chunk over the platform channel. The native side
/// holds about a second of audio, so a coarse wait loses nothing and keeps the
/// shared UI/platform thread free for rendering.
const Duration _queueFullRetryDelay = Duration(milliseconds: 20);

/// Writes wait for native queue capacity (`-3` retries), and flush or disposal
/// cancels a waiting write through [_writes], satisfying the bounded contract.
/// Without it the gapless timeline caps Android at ~125 ms in flight.
class AndroidChannelPlayer implements BoundedAudioPcmOutput, AudioPcm32Output {
  final int _sampleRate;
  final int _channels;
  final int _deviceId;
  final int _bitsPerSample;
  final int _validBitsPerSample;
  int? _handleId;
  Future<void>? _openFuture;
  Future<void>? _shutdown;
  double _pendingVolume = 1.0;
  bool _pendingPaused = false;
  bool _disposed = false;
  final PcmQueueWriter _writes = PcmQueueWriter(retryDelay: _queueFullRetryDelay);

  AndroidChannelPlayer({
    required this._sampleRate,
    required this._channels,
    required this._deviceId,
    this._bitsPerSample = 16,
    this._validBitsPerSample = 16,
  });

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
    _writes.cancelPending();
    _disposed = true;

    try {
      // Wait for startup to hand over any late native handle before closing it.
      await _openFuture;
    } on Object catch (_) {
      // The initialization caller owns the startup failure.
    }

    final handle = _handleId;

    _handleId = null;

    if (handle != null) {
      await androidAudioOutputChannel.invokeMethod<void>('close', {'id': handle});
    }
  }

  @override
  Future<void> write(Int16List samples) => _writePcm(samples, 16);

  @override
  Future<void> writePcm32(Int32List samples) => _writePcm(samples, 32);

  @override
  Future<void> flush() async {
    _writes.cancelPending();

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

    _sendControl('setVolume', {'id': handle, 'value': _pendingVolume});
  }

  @override
  void pause() {
    _pendingPaused = true;

    final handle = _handleId;
    if (handle == null) {
      return;
    }

    _sendControl('pause', {'id': handle});
  }

  @override
  void resume() {
    _pendingPaused = false;

    final handle = _handleId;
    if (handle == null) {
      return;
    }

    _sendControl('resume', {'id': handle});
  }

  /// Volume, pause and resume are fire-and-forget. A native failure (for example
  /// AudioTrack.play on an invalidated track) is logged rather than left as an uncaught
  /// error, which would kill the audio worker isolate; the next write reports a dead track.
  void _sendControl(String method, Map<String, Object?> arguments) {
    unawaited(
      androidAudioOutputChannel.invokeMethod<void>(method, arguments).catchError((Object error) {
        developer.log('Android audio $method failed: $error', name: 'AndroidChannelPlayer');
      }),
    );
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

  Future<void> _writePcm(TypedData samples, int bitsPerSample) async {
    if (_bitsPerSample != bitsPerSample) {
      throw StateError('The PCM precision does not match the configured Android output.');
    }

    if (samples.lengthInBytes == 0) {
      return;
    }

    final write = _writes.begin();

    final handle = await _handle();
    if (handle == null) {
      return;
    }

    final bytes = Uint8List.view(samples.buffer, samples.offsetInBytes, samples.lengthInBytes);

    await _writes.queue(
      write,
      targetIsOpen: () => !_disposed && handle == _handleId,
      attempt: () async {
        final result = await androidAudioOutputChannel.invokeMethod<int>('write', {'id': handle, 'pcm': bytes});

        if (result == null || result == 0) {
          return PcmQueueStatus.queued;
        }

        if (result == coreAudioQueueFull) {
          return PcmQueueStatus.full;
        }

        throw Exception('Android audio write failed: $result');
      },
    );
  }

  Future<void> _open() async {
    final handle = await androidAudioOutputChannel.invokeMethod<int>('open', {
      'sampleRate': _sampleRate,
      'channels': _channels,
      'deviceId': _deviceId,
      'bitsPerSample': _bitsPerSample,
      'validBitsPerSample': _validBitsPerSample,
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
