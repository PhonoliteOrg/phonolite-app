import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

class OpusException implements Exception {
  OpusException(this.message, {this.code});

  final String message;
  final int? code;

  @override
  String toString() {
    if (code == null) {
      return 'OpusException: $message';
    }
    return 'OpusException($code): $message';
  }
}

class RawOpusHeader {
  RawOpusHeader({
    required this.sampleRate,
    required this.channels,
    required this.frameMs,
    required this.bitrateBps,
    required this.durationMs,
    required this.preSkip,
    this.playableFrames,
  });

  final int sampleRate;
  final int channels;
  final int frameMs;
  final int bitrateBps;
  final int durationMs;
  final int preSkip;

  /// Exact audible frames in this range, excluding pre-skip and final padding.
  /// Null for legacy servers. Frame counts are per channel.
  final int? playableFrames;

  static RawOpusHeader parse(Uint8List data) {
    if (data.length < 12) {
      throw OpusException('invalid opus raw header');
    }
    final prefix = data.sublist(0, 12);
    final magic = String.fromCharCodes(prefix.sublist(0, 8));
    if (magic != 'OPUSR01\u0000') {
      throw OpusException('invalid opus raw header');
    }
    if (prefix[8] != 1) {
      throw OpusException('unsupported opus raw header version');
    }
    final headerLen = _readU16(prefix, 10);
    if (headerLen < 40) {
      throw OpusException('invalid opus raw header length');
    }
    if (data.length < headerLen) {
      throw OpusException('invalid opus raw header length');
    }

    var idx = 12;
    final sampleRate = _readU32(data, idx);
    idx += 4;
    final channels = _readU8(data, idx);
    idx += 1;
    if (channels == 0) {
      throw OpusException('invalid opus raw header channel count');
    }
    final frameMs = _readU8(data, idx);
    idx += 1;
    final bitrateBps = _readU32(data, idx);
    idx += 4;
    final durationMs = _readU32(data, idx);
    idx += 4;
    final preSkip = _readU16(data, idx);
    idx += 2;
    final trackIdLen = _readU16(data, idx);
    idx += 2;
    final titleLen = _readU16(data, idx);
    idx += 2;
    final artistLen = _readU16(data, idx);
    idx += 2;
    final albumLen = _readU16(data, idx);
    idx += 2;
    final codecLen = _readU16(data, idx);
    idx += 2;
    final containerLen = _readU16(data, idx);
    idx += 2;

    final totalLen =
        trackIdLen + titleLen + artistLen + albumLen + codecLen + containerLen;
    if (idx + totalLen > headerLen) {
      throw OpusException('invalid opus raw header lengths');
    }
    int? playableFrames;
    if ((data[9] & 1) != 0) {
      final extension = idx + totalLen;
      if (extension + 8 != headerLen)
        throw OpusException('invalid exact frame extension');
      playableFrames = ByteData.sublistView(
        data,
      ).getUint64(extension, Endian.little);
      if (playableFrames < 0 || playableFrames > 0x1fffffffffffff)
        throw OpusException('invalid exact frame count');
    }

    return RawOpusHeader(
      sampleRate: sampleRate,
      channels: channels,
      frameMs: frameMs,
      bitrateBps: bitrateBps,
      durationMs: durationMs,
      preSkip: preSkip,
      playableFrames: playableFrames,
    );
  }
}

class OpusDecoder {
  OpusDecoder._(this.sampleRate, this.channels, this._bindings, this._handle);

  factory OpusDecoder({required int sampleRate, required int channels}) {
    if (!_isSupportedRate(sampleRate)) {
      throw OpusException('unsupported sample rate');
    }
    if (channels <= 0) {
      throw OpusException('invalid channel count');
    }
    final bindings = _Bindings(_loadLibrary());
    final errorOut = calloc<ffi.Int32>();
    final handle = bindings.decoderCreate(sampleRate, channels, errorOut);
    final error = errorOut.value;
    calloc.free(errorOut);

    if (handle == ffi.nullptr) {
      throw OpusException(_errorMessage(error), code: error);
    }
    return OpusDecoder._(sampleRate, channels, bindings, handle);
  }

  final int sampleRate;
  final int channels;
  final _Bindings _bindings;
  ffi.Pointer<_OpusDecoderHandle> _handle;
  bool _disposed = false;
  ffi.Pointer<ffi.Uint8> _packetBuffer = ffi.nullptr;
  int _packetCapacity = 0;
  ffi.Pointer<ffi.Int16> _outputBuffer = ffi.nullptr;
  int _outputCapacity = 0;

  int get maxFrameSize => _bindings.maxFrameSize();

  Int16List decode(Uint8List packet, {int? frameSize}) {
    _ensureActive();
    if (packet.isEmpty) {
      throw OpusException('invalid input');
    }

    final effectiveFrameSize = frameSize ?? maxFrameSize;
    if (effectiveFrameSize <= 0 || effectiveFrameSize > maxFrameSize) {
      throw OpusException('invalid frame size');
    }

    if (packet.length > _packetCapacity) {
      if (_packetBuffer != ffi.nullptr) calloc.free(_packetBuffer);
      _packetCapacity = packet.length;
      _packetBuffer = calloc<ffi.Uint8>(_packetCapacity);
    }
    _packetBuffer.asTypedList(packet.length).setAll(0, packet);

    final outputSamples = effectiveFrameSize * channels;
    if (outputSamples > _outputCapacity) {
      if (_outputBuffer != ffi.nullptr) calloc.free(_outputBuffer);
      _outputCapacity = outputSamples;
      _outputBuffer = calloc<ffi.Int16>(_outputCapacity);
    }
    final decodedFrames = _bindings.decode(
      _handle,
      _packetBuffer,
      packet.length,
      _outputBuffer,
      effectiveFrameSize,
    );

    if (decodedFrames < 0) {
      throw OpusException(_errorMessage(decodedFrames), code: decodedFrames);
    }

    final decodedSamples = decodedFrames * channels;
    final samples = Int16List.fromList(
      _outputBuffer.asTypedList(decodedSamples),
    );
    return samples;
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _bindings.decoderDestroy(_handle);
    if (_packetBuffer != ffi.nullptr) calloc.free(_packetBuffer);
    if (_outputBuffer != ffi.nullptr) calloc.free(_outputBuffer);
    _packetBuffer = ffi.nullptr;
    _outputBuffer = ffi.nullptr;
    _handle = ffi.nullptr;
    _disposed = true;
  }

  void _ensureActive() {
    if (_disposed || _handle == ffi.nullptr) {
      throw OpusException('decoder is disposed');
    }
  }
}

bool _isSupportedRate(int sampleRate) {
  return sampleRate == 8000 ||
      sampleRate == 12000 ||
      sampleRate == 16000 ||
      sampleRate == 24000 ||
      sampleRate == 48000;
}

int _readU8(Uint8List data, int offset) {
  if (offset >= data.length) {
    throw OpusException('unexpected end of opus raw header');
  }
  return data[offset];
}

int _readU16(Uint8List data, int offset) {
  if (offset + 1 >= data.length) {
    throw OpusException('unexpected end of opus raw header');
  }
  return data[offset] | (data[offset + 1] << 8);
}

int _readU32(Uint8List data, int offset) {
  if (offset + 3 >= data.length) {
    throw OpusException('unexpected end of opus raw header');
  }
  return data[offset] |
      (data[offset + 1] << 8) |
      (data[offset + 2] << 16) |
      (data[offset + 3] << 24);
}

ffi.DynamicLibrary _loadLibrary() {
  if (Platform.isIOS || Platform.isMacOS) {
    final exec = File(Platform.resolvedExecutable);
    final frameworkPath = Platform.isMacOS
        ? '${exec.parent.parent.path}/Frameworks/phonolite_opus.framework/phonolite_opus'
        : '${exec.parent.path}/Frameworks/phonolite_opus.framework/phonolite_opus';
    try {
      if (File(frameworkPath).existsSync()) {
        return ffi.DynamicLibrary.open(frameworkPath);
      }
    } catch (_) {
      // Fall back to process lookup below.
    }
    return ffi.DynamicLibrary.process();
  }
  if (Platform.isAndroid || Platform.isLinux) {
    return ffi.DynamicLibrary.open('libphonolite_opus.so');
  }
  if (Platform.isWindows) {
    return ffi.DynamicLibrary.open('phonolite_opus.dll');
  }
  throw OpusException('unsupported platform');
}

String _errorMessage(int code) {
  switch (code) {
    case -1:
      return 'invalid argument';
    case -2:
      return 'buffer too small';
    case -3:
      return 'internal error';
    case -4:
      return 'invalid packet';
    case -5:
      return 'unimplemented';
    case -6:
      return 'invalid state';
    case -7:
      return 'alloc failed';
    default:
      return 'opus error';
  }
}

class _Bindings {
  _Bindings(ffi.DynamicLibrary library)
    : decoderCreate = library
          .lookup<ffi.NativeFunction<_DecoderCreateNative>>(
            'phonolite_opus_decoder_create',
          )
          .asFunction(),
      decoderDestroy = library
          .lookup<ffi.NativeFunction<_DecoderDestroyNative>>(
            'phonolite_opus_decoder_destroy',
          )
          .asFunction(),
      decode = library
          .lookup<ffi.NativeFunction<_DecodeNative>>('phonolite_opus_decode')
          .asFunction(),
      maxFrameSize = library
          .lookup<ffi.NativeFunction<_MaxFrameSizeNative>>(
            'phonolite_opus_max_frame_size',
          )
          .asFunction();

  final _DecoderCreateDart decoderCreate;
  final _DecoderDestroyDart decoderDestroy;
  final _DecodeDart decode;
  final _MaxFrameSizeDart maxFrameSize;
}

final class _OpusDecoderHandle extends ffi.Opaque {}

typedef _DecoderCreateNative =
    ffi.Pointer<_OpusDecoderHandle> Function(
      ffi.Int32 sampleRate,
      ffi.Int32 channels,
      ffi.Pointer<ffi.Int32> errorOut,
    );
typedef _DecoderCreateDart =
    ffi.Pointer<_OpusDecoderHandle> Function(
      int sampleRate,
      int channels,
      ffi.Pointer<ffi.Int32> errorOut,
    );

typedef _DecoderDestroyNative =
    ffi.Void Function(ffi.Pointer<_OpusDecoderHandle> decoder);
typedef _DecoderDestroyDart =
    void Function(ffi.Pointer<_OpusDecoderHandle> decoder);

typedef _DecodeNative =
    ffi.Int32 Function(
      ffi.Pointer<_OpusDecoderHandle> decoder,
      ffi.Pointer<ffi.Uint8> data,
      ffi.Int32 len,
      ffi.Pointer<ffi.Int16> pcm,
      ffi.Int32 frameSize,
    );
typedef _DecodeDart =
    int Function(
      ffi.Pointer<_OpusDecoderHandle> decoder,
      ffi.Pointer<ffi.Uint8> data,
      int len,
      ffi.Pointer<ffi.Int16> pcm,
      int frameSize,
    );

typedef _MaxFrameSizeNative = ffi.Int32 Function();
typedef _MaxFrameSizeDart = int Function();
