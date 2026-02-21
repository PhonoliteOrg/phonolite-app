library phonolite_quic;

import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

class QuicException implements Exception {
  QuicException(this.message);

  final String message;

  @override
  String toString() => 'QuicException: $message';
}

class QuicClient {
  QuicClient._(this._bindings, this._handle);

  static QuicClient connect({
    required String host,
    required int port,
    required String token,
  }) {
    final bindings = _Bindings(_loadLibrary());
    final hostPtr = host.toNativeUtf8();
    final tokenPtr = token.toNativeUtf8();
    final handle = bindings.connect(hostPtr, port, tokenPtr);
    calloc.free(hostPtr);
    calloc.free(tokenPtr);
    if (handle == ffi.nullptr) {
      throw QuicException('failed to connect QUIC client');
    }
    return QuicClient._(bindings, handle);
  }

  final _Bindings _bindings;
  ffi.Pointer<_QuicHandle> _handle;
  bool _closed = false;

  void openTrack({
    required String trackId,
    String? mode,
    String? quality,
    int frameMs = 20,
    List<String> queue = const [],
  }) {
    _ensureActive();
    final trackPtr = trackId.toNativeUtf8();
    final modePtr = (mode ?? '').toNativeUtf8();
    final qualityPtr = (quality ?? '').toNativeUtf8();
    final queueJson = queue.isEmpty ? '' : _encodeJsonArray(queue);
    final queuePtr = queueJson.toNativeUtf8();
    final result = _bindings.openTrack(
      _handle,
      trackPtr,
      modePtr,
      qualityPtr,
      frameMs,
      queuePtr,
    );
    calloc.free(trackPtr);
    calloc.free(modePtr);
    calloc.free(qualityPtr);
    calloc.free(queuePtr);
    if (result != 0) {
      throw QuicException('failed to open track (code $result)');
    }
  }

  int read(Uint8List buffer) {
    _ensureActive();
    final ptr = calloc<ffi.Uint8>(buffer.length);
    final read = _bindings.read(_handle, ptr, buffer.length);
    if (read > 0) {
      buffer.setRange(0, read, ptr.asTypedList(read));
    }
    calloc.free(ptr);
    return read;
  }

  void sendBufferStats({required int bufferMs, int? targetMs}) {
    _ensureActive();
    final target = targetMs ?? 0;
    _bindings.sendBuffer(_handle, bufferMs, target);
  }

  void sendPlayback({
    required String trackId,
    required int positionMs,
    required bool playing,
  }) {
    _ensureActive();
    final trackPtr = trackId.toNativeUtf8();
    final result =
        _bindings.sendPlayback(_handle, trackPtr, positionMs, playing ? 1 : 0);
    calloc.free(trackPtr);
    if (result != 0) {
      throw QuicException('failed to send playback stats (code $result)');
    }
  }

  void seek({required String trackId, required int positionMs}) {
    _ensureActive();
    final trackPtr = trackId.toNativeUtf8();
    final result = _bindings.seek(_handle, trackPtr, positionMs);
    calloc.free(trackPtr);
    if (result != 0) {
      throw QuicException('failed to seek track (code $result)');
    }
  }

  void advance() {
    _ensureActive();
    _bindings.advance(_handle);
  }

  String? lastError() {
    _ensureActive();
    final ptr = _bindings.lastError(_handle);
    if (ptr == ffi.nullptr) {
      return null;
    }
    final msg = ptr.cast<Utf8>().toDartString();
    _bindings.freeString(ptr);
    return msg.isEmpty ? null : msg;
  }

  String? pollStats() {
    _ensureActive();
    final ptr = _bindings.pollStats(_handle);
    if (ptr == ffi.nullptr) {
      return null;
    }
    final msg = ptr.cast<Utf8>().toDartString();
    _bindings.freeString(ptr);
    return msg.isEmpty ? null : msg;
  }

  int? pollRttMs() {
    _ensureActive();
    final value = _bindings.pollRttMs(_handle);
    if (value < 0) {
      return null;
    }
    return value;
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
      throw QuicException('QUIC client is closed');
    }
  }
}

ffi.DynamicLibrary _loadLibrary() {
  if (Platform.isIOS || Platform.isMacOS) {
    final exec = File(Platform.resolvedExecutable);
    final frameworkPath = Platform.isMacOS
        ? '${exec.parent.parent.path}/Frameworks/phonolite_quic.framework/phonolite_quic'
        : '${exec.parent.path}/Frameworks/phonolite_quic.framework/phonolite_quic';
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
    return ffi.DynamicLibrary.open('libphonolite_quic.so');
  }
  if (Platform.isWindows) {
    return ffi.DynamicLibrary.open('phonolite_quic.dll');
  }
  if (Platform.isLinux) {
    return ffi.DynamicLibrary.open('libphonolite_quic.so');
  }
  throw QuicException('unsupported platform');
}

String _encodeJsonArray(List<String> items) {
  final escaped = items.map(_escapeJsonString).join(',');
  return '[$escaped]';
}

String _escapeJsonString(String value) {
  final escaped = value
      .replaceAll('\\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r')
      .replaceAll('\t', r'\t');
  return '"$escaped"';
}

final class _QuicHandle extends ffi.Opaque {}

typedef _ConnectNative = ffi.Pointer<_QuicHandle> Function(
  ffi.Pointer<Utf8>,
  ffi.Uint16,
  ffi.Pointer<Utf8>,
);
typedef _ConnectDart = ffi.Pointer<_QuicHandle> Function(
  ffi.Pointer<Utf8>,
  int,
  ffi.Pointer<Utf8>,
);

typedef _OpenTrackNative = ffi.Int32 Function(
  ffi.Pointer<_QuicHandle>,
  ffi.Pointer<Utf8>,
  ffi.Pointer<Utf8>,
  ffi.Pointer<Utf8>,
  ffi.Uint32,
  ffi.Pointer<Utf8>,
);
typedef _OpenTrackDart = int Function(
  ffi.Pointer<_QuicHandle>,
  ffi.Pointer<Utf8>,
  ffi.Pointer<Utf8>,
  ffi.Pointer<Utf8>,
  int,
  ffi.Pointer<Utf8>,
);

typedef _ReadNative = ffi.Int32 Function(
  ffi.Pointer<_QuicHandle>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Uint64,
);
typedef _ReadDart = int Function(
  ffi.Pointer<_QuicHandle>,
  ffi.Pointer<ffi.Uint8>,
  int,
);

typedef _SendBufferNative = ffi.Int32 Function(
  ffi.Pointer<_QuicHandle>,
  ffi.Uint32,
  ffi.Uint32,
);
typedef _SendBufferDart = int Function(
  ffi.Pointer<_QuicHandle>,
  int,
  int,
);

typedef _SendPlaybackNative = ffi.Int32 Function(
  ffi.Pointer<_QuicHandle>,
  ffi.Pointer<Utf8>,
  ffi.Uint32,
  ffi.Int32,
);
typedef _SendPlaybackDart = int Function(
  ffi.Pointer<_QuicHandle>,
  ffi.Pointer<Utf8>,
  int,
  int,
);

typedef _SeekNative = ffi.Int32 Function(
  ffi.Pointer<_QuicHandle>,
  ffi.Pointer<Utf8>,
  ffi.Uint32,
);
typedef _SeekDart = int Function(
  ffi.Pointer<_QuicHandle>,
  ffi.Pointer<Utf8>,
  int,
);

typedef _AdvanceNative = ffi.Int32 Function(ffi.Pointer<_QuicHandle>);
typedef _AdvanceDart = int Function(ffi.Pointer<_QuicHandle>);

typedef _LastErrorNative = ffi.Pointer<Utf8> Function(ffi.Pointer<_QuicHandle>);
typedef _LastErrorDart = ffi.Pointer<Utf8> Function(ffi.Pointer<_QuicHandle>);

typedef _PollStatsNative = ffi.Pointer<Utf8> Function(ffi.Pointer<_QuicHandle>);
typedef _PollStatsDart = ffi.Pointer<Utf8> Function(ffi.Pointer<_QuicHandle>);

typedef _PollRttNative = ffi.Int64 Function(ffi.Pointer<_QuicHandle>);
typedef _PollRttDart = int Function(ffi.Pointer<_QuicHandle>);

typedef _FreeStringNative = ffi.Void Function(ffi.Pointer<Utf8>);
typedef _FreeStringDart = void Function(ffi.Pointer<Utf8>);

typedef _CloseNative = ffi.Void Function(ffi.Pointer<_QuicHandle>);
typedef _CloseDart = void Function(ffi.Pointer<_QuicHandle>);

class _Bindings {
  _Bindings(ffi.DynamicLibrary library)
      : connect = library
            .lookup<ffi.NativeFunction<_ConnectNative>>(
              'phonolite_quic_connect',
            )
            .asFunction(),
        openTrack = library
            .lookup<ffi.NativeFunction<_OpenTrackNative>>(
              'phonolite_quic_open_track',
            )
            .asFunction(),
        read = library
            .lookup<ffi.NativeFunction<_ReadNative>>(
              'phonolite_quic_read',
            )
            .asFunction(),
        sendBuffer = library
            .lookup<ffi.NativeFunction<_SendBufferNative>>(
              'phonolite_quic_send_buffer',
            )
            .asFunction(),
        sendPlayback = library
            .lookup<ffi.NativeFunction<_SendPlaybackNative>>(
              'phonolite_quic_send_playback',
            )
            .asFunction(),
        seek = library
            .lookup<ffi.NativeFunction<_SeekNative>>(
              'phonolite_quic_seek',
            )
            .asFunction(),
        advance = library
            .lookup<ffi.NativeFunction<_AdvanceNative>>(
              'phonolite_quic_advance',
            )
            .asFunction(),
        lastError = library
            .lookup<ffi.NativeFunction<_LastErrorNative>>(
              'phonolite_quic_last_error',
            )
            .asFunction(),
        pollStats = library
            .lookup<ffi.NativeFunction<_PollStatsNative>>(
              'phonolite_quic_poll_stats',
            )
            .asFunction(),
        pollRttMs = library
            .lookup<ffi.NativeFunction<_PollRttNative>>(
              'phonolite_quic_poll_rtt_ms',
            )
            .asFunction(),
        freeString = library
            .lookup<ffi.NativeFunction<_FreeStringNative>>(
              'phonolite_quic_free_string',
            )
            .asFunction(),
        close = library
            .lookup<ffi.NativeFunction<_CloseNative>>(
              'phonolite_quic_close',
            )
            .asFunction();

  final _ConnectDart connect;
  final _OpenTrackDart openTrack;
  final _ReadDart read;
  final _SendBufferDart sendBuffer;
  final _SendPlaybackDart sendPlayback;
  final _SeekDart seek;
  final _AdvanceDart advance;
  final _LastErrorDart lastError;
  final _PollStatsDart pollStats;
  final _PollRttDart pollRttMs;
  final _FreeStringDart freeString;
  final _CloseDart close;
}
