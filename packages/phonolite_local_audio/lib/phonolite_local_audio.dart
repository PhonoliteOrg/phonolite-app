import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

class LocalAudioException implements Exception {
  LocalAudioException(this.message, {this.code});

  final String message;
  final int? code;

  @override
  String toString() {
    if (code == null) {
      return 'LocalAudioException: $message';
    }
    return 'LocalAudioException($code): $message';
  }
}

class LocalAudioDecoder {
  LocalAudioDecoder._(
    this._bindings,
    this._handle, {
    required this.sampleRate,
    required this.channels,
    required this.duration,
  });

  factory LocalAudioDecoder.open(
    String filePath, {
    Duration startOffset = Duration.zero,
  }) {
    final bindings = _Bindings(_loadLibrary());
    final pathBytes = utf8.encode(filePath);
    if (pathBytes.isEmpty) {
      throw LocalAudioException('empty file path');
    }
    final pathPtr = calloc<ffi.Uint8>(pathBytes.length);
    pathPtr.asTypedList(pathBytes.length).setAll(0, pathBytes);
    final handle = bindings.open(
      pathPtr,
      pathBytes.length,
      startOffset.inMilliseconds,
    );
    calloc.free(pathPtr);

    if (handle == ffi.nullptr) {
      throw LocalAudioException(
        _lastError(bindings, ffi.nullptr) ?? 'failed to open local audio file',
      );
    }

    final sampleRate = bindings.sampleRate(handle);
    final channels = bindings.channels(handle);
    final durationMs = bindings.durationMs(handle);
    if (sampleRate <= 0 || channels <= 0) {
      final error = _lastError(bindings, handle) ?? 'invalid audio metadata';
      bindings.close(handle);
      throw LocalAudioException(error);
    }

    return LocalAudioDecoder._(
      bindings,
      handle,
      sampleRate: sampleRate,
      channels: channels,
      duration: Duration(milliseconds: durationMs < 0 ? 0 : durationMs),
    );
  }

  final _Bindings _bindings;
  ffi.Pointer<_LocalAudioHandle> _handle;
  bool _closed = false;

  final int sampleRate;
  final int channels;
  final Duration duration;

  Duration get position {
    _ensureActive();
    final ms = _bindings.positionMs(_handle);
    return Duration(milliseconds: ms < 0 ? 0 : ms);
  }

  int readInto(Int16List buffer) {
    _ensureActive();
    if (buffer.isEmpty) {
      return 0;
    }
    final alignedLength = buffer.length - (buffer.length % channels);
    if (alignedLength <= 0) {
      return 0;
    }
    final outPtr = calloc<ffi.Int16>(alignedLength);
    final read = _bindings.read(_handle, outPtr, alignedLength);
    if (read < 0) {
      calloc.free(outPtr);
      throw LocalAudioException(
        _lastError(_bindings, _handle) ?? 'local audio read failed',
        code: read,
      );
    }
    if (read > 0) {
      buffer.setRange(0, read, outPtr.asTypedList(read));
    }
    calloc.free(outPtr);
    return read;
  }

  Int16List read(int maxSamples) {
    if (maxSamples <= 0) {
      return Int16List(0);
    }
    final buffer = Int16List(maxSamples);
    final read = readInto(buffer);
    if (read <= 0) {
      return Int16List(0);
    }
    return Int16List.fromList(buffer.sublist(0, read));
  }

  Duration seek(Duration position) {
    _ensureActive();
    final targetMs = position.inMilliseconds < 0 ? 0 : position.inMilliseconds;
    final actualMs = _bindings.seek(_handle, targetMs);
    if (actualMs < 0) {
      throw LocalAudioException(
        _lastError(_bindings, _handle) ?? 'local audio seek failed',
        code: actualMs,
      );
    }
    return Duration(milliseconds: actualMs);
  }

  String? lastError() {
    _ensureActive();
    return _lastError(_bindings, _handle);
  }

  void close() {
    if (_closed) {
      return;
    }
    _bindings.close(_handle);
    _handle = ffi.nullptr;
    _closed = true;
  }

  void _ensureActive() {
    if (_closed || _handle == ffi.nullptr) {
      throw LocalAudioException('local audio decoder is closed');
    }
  }
}

ffi.DynamicLibrary _loadLibrary() {
  if (Platform.isIOS || Platform.isMacOS) {
    final exec = File(Platform.resolvedExecutable);
    final frameworkPath = Platform.isMacOS
        ? '${exec.parent.parent.path}/Frameworks/phonolite_local_audio.framework/phonolite_local_audio'
        : '${exec.parent.path}/Frameworks/phonolite_local_audio.framework/phonolite_local_audio';
    try {
      if (File(frameworkPath).existsSync()) {
        return ffi.DynamicLibrary.open(frameworkPath);
      }
    } catch (_) {
      // Fall back to process lookup below.
    }
    return ffi.DynamicLibrary.process();
  }
  if (Platform.isAndroid) {
    return ffi.DynamicLibrary.open('libphonolite_local_audio.so');
  }
  if (Platform.isWindows) {
    return ffi.DynamicLibrary.open('phonolite_local_audio.dll');
  }
  if (Platform.isLinux) {
    return ffi.DynamicLibrary.open('libphonolite_local_audio.so');
  }
  throw LocalAudioException('unsupported platform');
}

String? _lastError(_Bindings bindings, ffi.Pointer<_LocalAudioHandle> handle) {
  const bufferLength = 1024;
  final buffer = calloc<ffi.Uint8>(bufferLength);
  final copied = bindings.lastError(handle, buffer, bufferLength);
  if (copied <= 0) {
    calloc.free(buffer);
    return null;
  }
  final bytes = buffer.asTypedList(copied);
  final message = utf8.decode(bytes, allowMalformed: true);
  calloc.free(buffer);
  return message.isEmpty ? null : message;
}

final class _LocalAudioHandle extends ffi.Opaque {}

typedef _OpenNative =
    ffi.Pointer<_LocalAudioHandle> Function(
      ffi.Pointer<ffi.Uint8>,
      ffi.Uint64,
      ffi.Int64,
    );
typedef _OpenDart =
    ffi.Pointer<_LocalAudioHandle> Function(ffi.Pointer<ffi.Uint8>, int, int);

typedef _ReadNative =
    ffi.Int64 Function(
      ffi.Pointer<_LocalAudioHandle>,
      ffi.Pointer<ffi.Int16>,
      ffi.Uint64,
    );
typedef _ReadDart =
    int Function(ffi.Pointer<_LocalAudioHandle>, ffi.Pointer<ffi.Int16>, int);

typedef _SeekNative =
    ffi.Int64 Function(ffi.Pointer<_LocalAudioHandle>, ffi.Int64);
typedef _SeekDart = int Function(ffi.Pointer<_LocalAudioHandle>, int);

typedef _IntGetterNative = ffi.Int32 Function(ffi.Pointer<_LocalAudioHandle>);
typedef _IntGetterDart = int Function(ffi.Pointer<_LocalAudioHandle>);

typedef _LongGetterNative = ffi.Int64 Function(ffi.Pointer<_LocalAudioHandle>);
typedef _LongGetterDart = int Function(ffi.Pointer<_LocalAudioHandle>);

typedef _LastErrorNative =
    ffi.Uint64 Function(
      ffi.Pointer<_LocalAudioHandle>,
      ffi.Pointer<ffi.Uint8>,
      ffi.Uint64,
    );
typedef _LastErrorDart =
    int Function(ffi.Pointer<_LocalAudioHandle>, ffi.Pointer<ffi.Uint8>, int);

typedef _CloseNative = ffi.Void Function(ffi.Pointer<_LocalAudioHandle>);
typedef _CloseDart = void Function(ffi.Pointer<_LocalAudioHandle>);

class _Bindings {
  _Bindings(ffi.DynamicLibrary library)
    : open = library
          .lookup<ffi.NativeFunction<_OpenNative>>('phonolite_local_audio_open')
          .asFunction(),
      read = library
          .lookup<ffi.NativeFunction<_ReadNative>>('phonolite_local_audio_read')
          .asFunction(),
      seek = library
          .lookup<ffi.NativeFunction<_SeekNative>>('phonolite_local_audio_seek')
          .asFunction(),
      sampleRate = library
          .lookup<ffi.NativeFunction<_IntGetterNative>>(
            'phonolite_local_audio_sample_rate',
          )
          .asFunction(),
      channels = library
          .lookup<ffi.NativeFunction<_IntGetterNative>>(
            'phonolite_local_audio_channels',
          )
          .asFunction(),
      durationMs = library
          .lookup<ffi.NativeFunction<_LongGetterNative>>(
            'phonolite_local_audio_duration_ms',
          )
          .asFunction(),
      positionMs = library
          .lookup<ffi.NativeFunction<_LongGetterNative>>(
            'phonolite_local_audio_position_ms',
          )
          .asFunction(),
      lastError = library
          .lookup<ffi.NativeFunction<_LastErrorNative>>(
            'phonolite_local_audio_last_error',
          )
          .asFunction(),
      close = library
          .lookup<ffi.NativeFunction<_CloseNative>>(
            'phonolite_local_audio_close',
          )
          .asFunction();

  final _OpenDart open;
  final _ReadDart read;
  final _SeekDart seek;
  final _IntGetterDart sampleRate;
  final _IntGetterDart channels;
  final _LongGetterDart durationMs;
  final _LongGetterDart positionMs;
  final _LastErrorDart lastError;
  final _CloseDart close;
}
