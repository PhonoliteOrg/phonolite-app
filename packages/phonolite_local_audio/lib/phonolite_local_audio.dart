import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

class LocalAudioException implements Exception {
  final String message;
  final int? code;

  LocalAudioException(this.message, {this.code});

  /// Terminal source/authentication failures should not enter reconnect loops.
  bool get isSourceRejected {
    final value = code;

    return value == -100 ||
        value == -101 ||
        value == -102 ||
        (value != null &&
            value >= 400 &&
            value < 500 &&
            value != 408 &&
            value != 429);
  }

  @override
  String toString() {
    if (code == null) {
      return 'LocalAudioException: $message';
    }

    return 'LocalAudioException($code): $message';
  }
}

class LocalAudioDecoder {
  final int sampleRate;
  final int channels;

  /// Source PCM precision; lossy sources use the decoder's 32-bit precision.
  final int bitDepth;
  final Duration duration;

  /// Exact audible frames per channel, or null for unknown/estimated lengths.
  final int? playableFrames;
  final _Bindings _bindings;
  ffi.Pointer<_LocalAudioHandle> _handle;
  bool _closed = false;

  LocalAudioDecoder._(
    this._bindings,
    this._handle, {
    required this.sampleRate,
    required this.channels,
    required this.bitDepth,
    required this.duration,
    required this.playableFrames,
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

    try {
      final handle = bindings.open(
        pathPtr,
        pathBytes.length,
        startOffset.inMilliseconds,
      );

      return LocalAudioDecoder._opened(bindings, handle);
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// Opens a seekable, authenticated HTTPS source with a bounded byte cache.
  ///
  /// Calls perform synchronous native I/O and belong in an owned decoder
  /// isolate. Opening has a fifteen-second network budget; subsequent range
  /// requests have five-second deadlines. Redirects and
  /// changes to the pinned server key or source file are rejected.
  factory LocalAudioDecoder.openRemote(
    String url, {
    required String token,
    required String serverPin,
    Duration startOffset = Duration.zero,
  }) {
    final bindings = _Bindings(_loadLibrary());
    final urlBytes = utf8.encode(url);
    final tokenBytes = utf8.encode(token);
    final pinBytes = utf8.encode(serverPin);

    if (urlBytes.isEmpty || tokenBytes.isEmpty || pinBytes.isEmpty) {
      throw LocalAudioException(
        'Original playback requires an authenticated server',
        code: -100,
      );
    }

    final urlPtr = calloc<ffi.Uint8>(urlBytes.length);
    final tokenPtr = calloc<ffi.Uint8>(tokenBytes.length);
    final pinPtr = calloc<ffi.Uint8>(pinBytes.length);

    try {
      urlPtr.asTypedList(urlBytes.length).setAll(0, urlBytes);
      tokenPtr.asTypedList(tokenBytes.length).setAll(0, tokenBytes);
      pinPtr.asTypedList(pinBytes.length).setAll(0, pinBytes);
      final handle = bindings.openRemote(
        urlPtr,
        urlBytes.length,
        tokenPtr,
        tokenBytes.length,
        pinPtr,
        pinBytes.length,
        startOffset.inMilliseconds,
      );

      return LocalAudioDecoder._opened(bindings, handle);
    } finally {
      tokenPtr
          .asTypedList(tokenBytes.length)
          .fillRange(0, tokenBytes.length, 0);
      calloc.free(urlPtr);
      calloc.free(tokenPtr);
      calloc.free(pinPtr);
    }
  }

  /// Consumes a source-file transport from the existing native QUIC library.
  ///
  /// The handle and function addresses must describe one live source. They are
  /// consumed even when opening fails; callers must not close the handle again.
  /// Synchronous I/O belongs in the same owned decoder isolate as read/seek.
  factory LocalAudioDecoder.openRemoteQuic({
    required int sourceHandle,
    required int readRangeAddress,
    required int errorCodeAddress,
    required int errorAddress,
    required int closeAddress,
    Duration startOffset = Duration.zero,
  }) {
    if (sourceHandle <= 0 || closeAddress <= 0) {
      throw LocalAudioException(
        'invalid native QUIC source descriptor',
        code: -100,
      );
    }
    final source = ffi.Pointer<ffi.Void>.fromAddress(sourceHandle);
    final close = ffi.Pointer<ffi.NativeFunction<_QuicCloseNative>>.fromAddress(
      closeAddress,
    );
    var transferred = false;

    try {
      if (readRangeAddress <= 0 || errorCodeAddress <= 0 || errorAddress <= 0) {
        throw LocalAudioException(
          'invalid native QUIC source descriptor',
          code: -100,
        );
      }
      final bindings = _Bindings(_loadLibrary());
      final openQuic = bindings.openQuic;
      transferred = true;
      final handle = openQuic(
        source,
        ffi.Pointer<ffi.NativeFunction<_QuicReadRangeNative>>.fromAddress(
          readRangeAddress,
        ),
        ffi.Pointer<ffi.NativeFunction<_QuicErrorCodeNative>>.fromAddress(
          errorCodeAddress,
        ),
        ffi.Pointer<ffi.NativeFunction<_QuicCopyErrorNative>>.fromAddress(
          errorAddress,
        ),
        close,
        startOffset.inMilliseconds,
      );

      return LocalAudioDecoder._opened(bindings, handle);
    } finally {
      if (!transferred)
        close.asFunction<void Function(ffi.Pointer<ffi.Void>)>()(source);
    }
  }

  Duration get position {
    _ensureActive();
    final ms = _bindings.positionMs(_handle);

    return Duration(milliseconds: ms < 0 ? 0 : ms);
  }

  void close() {
    if (_closed) {
      return;
    }

    _bindings.close(_handle);
    _handle = ffi.nullptr;
    _closed = true;
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

    try {
      final read = _bindings.read(_handle, outPtr, alignedLength);
      _checkRead(read, alignedLength);
      if (read > 0) {
        buffer.setRange(0, read, outPtr.asTypedList(read));
      }

      return read;
    } finally {
      calloc.free(outPtr);
    }
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

  /// Reads interleaved signed PCM32 with source samples left-aligned.
  ///
  /// A 24-bit value is shifted left eight bits, retaining every source bit.
  /// No sample-rate conversion or intermediate 16-bit quantization occurs.
  int readInto32(Int32List buffer) {
    _ensureActive();
    final alignedLength = buffer.length - (buffer.length % channels);

    if (alignedLength <= 0) {
      return 0;
    }

    final outPtr = calloc<ffi.Int32>(alignedLength);

    try {
      final read = _bindings.read32(_handle, outPtr, alignedLength);
      _checkRead(read, alignedLength);
      if (read > 0) {
        buffer.setRange(0, read, outPtr.asTypedList(read));
      }

      return read;
    } finally {
      calloc.free(outPtr);
    }
  }

  Int32List read32(int maxSamples) {
    if (maxSamples <= 0) {
      return Int32List(0);
    }

    final buffer = Int32List(maxSamples);
    final count = readInto32(buffer);

    return Int32List.sublistView(buffer, 0, count);
  }

  Duration seek(Duration position) {
    _ensureActive();
    final targetMs = position.inMilliseconds < 0 ? 0 : position.inMilliseconds;
    final actualMs = _bindings.seek(_handle, targetMs);
    if (actualMs < 0) {
      throw LocalAudioException(
        _lastError(_bindings, _handle) ?? 'local audio seek failed',
        code: _bindings.errorCode(_handle),
      );
    }

    return Duration(milliseconds: actualMs);
  }

  String? lastError() {
    _ensureActive();
    return _lastError(_bindings, _handle);
  }

  static LocalAudioDecoder _opened(
    _Bindings bindings,
    ffi.Pointer<_LocalAudioHandle> handle,
  ) {
    if (handle == ffi.nullptr) {
      throw LocalAudioException(
        _lastError(bindings, handle) ?? 'failed to open audio source',
        code: bindings.errorCode(handle),
      );
    }

    final sampleRate = bindings.sampleRate(handle);
    final channels = bindings.channels(handle);
    final bitDepth = bindings.bitDepth(handle);
    final durationMs = bindings.durationMs(handle);
    final playableFrames = bindings.playableFrames?.call(handle);

    if (sampleRate <= 0 || channels <= 0 || bitDepth <= 0 || bitDepth > 32) {
      final error = _lastError(bindings, handle) ?? 'invalid audio metadata';
      bindings.close(handle);
      throw LocalAudioException(error, code: -101);
    }

    return LocalAudioDecoder._(
      bindings,
      handle,
      sampleRate: sampleRate,
      channels: channels,
      bitDepth: bitDepth,
      duration: Duration(milliseconds: durationMs < 0 ? 0 : durationMs),
      playableFrames: playableFrames != null && playableFrames >= 0
          ? playableFrames
          : null,
    );
  }

  void _ensureActive() {
    if (_closed || _handle == ffi.nullptr) {
      throw LocalAudioException('local audio decoder is closed');
    }
  }

  void _checkRead(int count, int capacity) {
    if (count < 0) {
      throw LocalAudioException(
        _lastError(_bindings, _handle) ?? 'audio read failed',
        code: _bindings.errorCode(_handle),
      );
    }

    if (count > capacity || count % channels != 0) {
      throw LocalAudioException('invalid native audio read size');
    }
  }
}

ffi.DynamicLibrary _loadLibrary() {
  final configuredLibrary =
      Platform.environment['PHONOLITE_LOCAL_AUDIO_LIBRARY'];

  if (configuredLibrary != null && configuredLibrary.isNotEmpty) {
    return ffi.DynamicLibrary.open(configuredLibrary);
  }

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

typedef _OpenRemoteNative =
    ffi.Pointer<_LocalAudioHandle> Function(
      ffi.Pointer<ffi.Uint8>,
      ffi.Uint64,
      ffi.Pointer<ffi.Uint8>,
      ffi.Uint64,
      ffi.Pointer<ffi.Uint8>,
      ffi.Uint64,
      ffi.Int64,
    );
typedef _OpenRemoteDart =
    ffi.Pointer<_LocalAudioHandle> Function(
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<ffi.Uint8>,
      int,
      int,
    );
typedef _Read32Native =
    ffi.Int64 Function(
      ffi.Pointer<_LocalAudioHandle>,
      ffi.Pointer<ffi.Int32>,
      ffi.Uint64,
    );
typedef _Read32Dart =
    int Function(ffi.Pointer<_LocalAudioHandle>, ffi.Pointer<ffi.Int32>, int);

typedef _QuicReadRangeNative =
    ffi.Int64 Function(
      ffi.Pointer<ffi.Void>,
      ffi.Uint64,
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Uint32,
      ffi.Pointer<ffi.Uint64>,
    );
typedef _QuicErrorCodeNative = ffi.Int32 Function(ffi.Pointer<ffi.Void>);
typedef _QuicCopyErrorNative =
    ffi.Size Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint8>, ffi.Size);
typedef _QuicCloseNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _OpenQuicNative =
    ffi.Pointer<_LocalAudioHandle> Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.NativeFunction<_QuicReadRangeNative>>,
      ffi.Pointer<ffi.NativeFunction<_QuicErrorCodeNative>>,
      ffi.Pointer<ffi.NativeFunction<_QuicCopyErrorNative>>,
      ffi.Pointer<ffi.NativeFunction<_QuicCloseNative>>,
      ffi.Int64,
    );
typedef _OpenQuicDart =
    ffi.Pointer<_LocalAudioHandle> Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.NativeFunction<_QuicReadRangeNative>>,
      ffi.Pointer<ffi.NativeFunction<_QuicErrorCodeNative>>,
      ffi.Pointer<ffi.NativeFunction<_QuicCopyErrorNative>>,
      ffi.Pointer<ffi.NativeFunction<_QuicCloseNative>>,
      int,
    );

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
  final ffi.DynamicLibrary _library;
  late final _OpenQuicDart openQuic = _library
      .lookupFunction<_OpenQuicNative, _OpenQuicDart>(
        'phonolite_local_audio_open_quic',
      );
  final _OpenDart open;
  final _OpenRemoteDart openRemote;
  final _ReadDart read;
  final _Read32Dart read32;
  final _SeekDart seek;
  final _IntGetterDart sampleRate;
  final _IntGetterDart channels;
  final _IntGetterDart bitDepth;
  final _IntGetterDart errorCode;
  final _LongGetterDart durationMs;
  final _LongGetterDart? playableFrames;
  final _LongGetterDart positionMs;
  final _LastErrorDart lastError;
  final _CloseDart close;

  _Bindings(ffi.DynamicLibrary library)
    : _library = library,
      open = library
          .lookup<ffi.NativeFunction<_OpenNative>>('phonolite_local_audio_open')
          .asFunction(),
      read = library
          .lookup<ffi.NativeFunction<_ReadNative>>('phonolite_local_audio_read')
          .asFunction(),
      openRemote = library.lookupFunction<_OpenRemoteNative, _OpenRemoteDart>(
        'phonolite_local_audio_open_remote',
      ),
      read32 = library.lookupFunction<_Read32Native, _Read32Dart>(
        'phonolite_local_audio_read32',
      ),
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
      bitDepth = library.lookupFunction<_IntGetterNative, _IntGetterDart>(
        'phonolite_local_audio_bit_depth',
      ),
      errorCode = library.lookupFunction<_IntGetterNative, _IntGetterDart>(
        'phonolite_local_audio_error_code',
      ),
      durationMs = library
          .lookup<ffi.NativeFunction<_LongGetterNative>>(
            'phonolite_local_audio_duration_ms',
          )
          .asFunction(),
      playableFrames = _optionalPlayableFrames(library),
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

  static _LongGetterDart? _optionalPlayableFrames(ffi.DynamicLibrary library) {
    // Older native bundles remain usable; do not infer exact frames from ms.
    try {
      return library.lookupFunction<_LongGetterNative, _LongGetterDart>(
        'phonolite_local_audio_playable_frames',
      );
    } on ArgumentError {
      return null;
    }
  }
}
