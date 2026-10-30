import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_local_audio/phonolite_local_audio.dart';

void main() {
  final libraryPath = Platform.environment['PHONOLITE_LOCAL_AUDIO_LIBRARY'];
  final skip = libraryPath == null || !File(libraryPath).existsSync()
      ? 'Requires a compiled decoder library with the native QUIC source entry point.'
      : false;

  test('native source descriptor preserves PCM24/PCM32 samples and seek, and owns close exactly once', () {
    for (final bits in [24, 32]) {
      final values = List<int>.generate(4096, (index) => index * 131 - 200001);
      final source = _MemoryNativeSource(_wav(bits, values));
      LocalAudioDecoder? decoder;

      try {
        decoder = LocalAudioDecoder.openRemoteQuic(
          sourceHandle: source.handle.address,
          readRangeAddress: source.readRange.nativeFunction.address,
          errorCodeAddress: source.errorCode.nativeFunction.address,
          errorAddress: source.error.nativeFunction.address,
          closeAddress: source.close.nativeFunction.address,
        );
        expect(decoder.sampleRate, 192000);
        expect(decoder.channels, 1);
        expect(decoder.bitDepth, bits);
        final expected = values.map((sample) => sample << (32 - bits)).toList();
        expect(_decodeAll(decoder), orderedEquals(expected));
        expect(decoder.seek(const Duration(milliseconds: 5)), const Duration(milliseconds: 5));
        expect(_decodeAll(decoder), orderedEquals(expected.sublist(960)));
        decoder.close();
        decoder.close();
        expect(source.closed, 1);
        expect(source.requests, isNotEmpty);
        expect(source.requests.every((length) => length <= 256 * 1024), isTrue);
      } finally {
        decoder?.close();
        source.dispose();
      }
    }
  }, skip: skip);

  test('continuous source crosses many decoder windows and restarts only for uncached seeks', () {
    for (final bits in [24, 32]) {
      final values = List<int>.generate(327803, (index) {
        final value = (index * 131) % 16000001 - 8000000;

        return bits == 24 ? value : value * 256 + (index & 255);
      });
      final source = _MemoryNativeSource(_wav(bits, values));
      LocalAudioDecoder? decoder;

      try {
        decoder = LocalAudioDecoder.openRemoteQuic(
          sourceHandle: source.handle.address,
          readRangeAddress: source.readRange.nativeFunction.address,
          errorCodeAddress: source.errorCode.nativeFunction.address,
          errorAddress: source.error.nativeFunction.address,
          closeAddress: source.close.nativeFunction.address,
        );
        final expected = values.map((sample) => sample << (32 - bits)).toList();
        expect(_decodeAll(decoder), orderedEquals(expected));
        expect(source.spans, [0], reason: 'Sequential cache windows consume one continuous span.');
        expect(source.requests.length, greaterThanOrEqualTo(4));
        expect(source.requests.first, 16 * 1024, reason: 'Startup should not wait for a 256 KiB fill.');
        expect(source.requests.every((length) => length > 0 && length <= 256 * 1024), isTrue);
        expect(source.returned.fold<int>(0, (sum, length) => sum + length), source.bytes.length);

        for (final milliseconds in [800, 1200, 5]) {
          final beforeSeek = source.spans.length;
          expect(decoder.seek(Duration(milliseconds: milliseconds)), Duration(milliseconds: milliseconds));
          expect(_decodeAll(decoder), orderedEquals(expected.sublist(milliseconds * 192)));
          expect(source.spans.length, beforeSeek + 1, reason: 'An uncached seek starts one new span.');
        }

        decoder.close();
        expect(source.closed, 1);
        expect(source.deadlines.every((timeout) => timeout > 0 && timeout <= 5000), isTrue);
      } finally {
        decoder?.close();
        source.dispose();
      }
    }
  }, skip: skip);

  test('positive short native source fills preserve decoded samples and seeking', () {
    for (final bits in [24, 32]) {
      final values = List<int>.generate(4096, (index) => index * 131 - 200001);
      final source = _MemoryNativeSource(_wav(bits, values), maximumFill: 97);
      LocalAudioDecoder? decoder;

      try {
        decoder = LocalAudioDecoder.openRemoteQuic(
          sourceHandle: source.handle.address,
          readRangeAddress: source.readRange.nativeFunction.address,
          errorCodeAddress: source.errorCode.nativeFunction.address,
          errorAddress: source.error.nativeFunction.address,
          closeAddress: source.close.nativeFunction.address,
        );
        final expected = values.map((sample) => sample << (32 - bits)).toList();
        expect(_decodeAll(decoder), orderedEquals(expected));
        expect(source.spans, [0]);
        expect(source.returned.every((length) => length > 0 && length <= 97), isTrue);
        expect(decoder.seek(const Duration(milliseconds: 5)), const Duration(milliseconds: 5));
        expect(_decodeAll(decoder), orderedEquals(expected.sublist(960)));
        decoder.close();
        expect(source.closed, 1);
      } finally {
        decoder?.close();
        source.dispose();
      }
    }
  }, skip: skip);

  test('invalid callback descriptor releases the transferred source before native opening', () {
    final source = _MemoryNativeSource(Uint8List(0));

    try {
      expect(
        () => LocalAudioDecoder.openRemoteQuic(
          sourceHandle: source.handle.address,
          readRangeAddress: 0,
          errorCodeAddress: source.errorCode.nativeFunction.address,
          errorAddress: source.error.nativeFunction.address,
          closeAddress: source.close.nativeFunction.address,
        ),
        throwsA(isA<LocalAudioException>()),
      );
      expect(source.closed, 1);
    } finally {
      source.dispose();
    }
  });
}

List<int> _decodeAll(LocalAudioDecoder decoder) {
  final output = <int>[];

  while (true) {
    final samples = decoder.read32(137);
    if (samples.isEmpty) return output;
    output.addAll(samples);
  }
}

Uint8List _wav(int bits, List<int> samples) {
  final width = bits ~/ 8;
  final bytes = Uint8List(44 + samples.length * width);
  final data = ByteData.sublistView(bytes);
  bytes.setAll(0, 'RIFF'.codeUnits);
  data.setUint32(4, bytes.length - 8, Endian.little);
  bytes.setAll(8, 'WAVEfmt '.codeUnits);
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 192000, Endian.little);
  data.setUint32(28, 192000 * width, Endian.little);
  data.setUint16(32, width, Endian.little);
  data.setUint16(34, bits, Endian.little);
  bytes.setAll(36, 'data'.codeUnits);
  data.setUint32(40, samples.length * width, Endian.little);

  for (var index = 0; index < samples.length; index++) {
    for (var byte = 0; byte < width; byte++) {
      bytes[44 + index * width + byte] = (samples[index] >> (byte * 8)) & 0xff;
    }
  }

  return bytes;
}

typedef _ReadRangeNative =
    ffi.Int64 Function(
      ffi.Pointer<ffi.Void>,
      ffi.Uint64,
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Uint32,
      ffi.Pointer<ffi.Uint64>,
    );
typedef _ErrorCodeNative = ffi.Int32 Function(ffi.Pointer<ffi.Void>);
typedef _ErrorNative = ffi.Size Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint8>, ffi.Size);
typedef _CloseNative = ffi.Void Function(ffi.Pointer<ffi.Void>);

class _MemoryNativeSource {
  final Uint8List bytes;
  final int? maximumFill;
  final ffi.Pointer<ffi.Void> handle = calloc<ffi.Uint8>(1).cast();
  final requests = <int>[];
  final returned = <int>[];
  final deadlines = <int>[];
  final spans = <int>[0];
  late final ffi.NativeCallable<_ReadRangeNative> readRange;
  late final ffi.NativeCallable<_ErrorCodeNative> errorCode;
  late final ffi.NativeCallable<_ErrorNative> error;
  late final ffi.NativeCallable<_CloseNative> close;
  int closed = 0;
  int _streamCursor = 0;

  _MemoryNativeSource(this.bytes, {this.maximumFill}) {
    readRange = ffi.NativeCallable<_ReadRangeNative>.isolateLocal((
      ffi.Pointer<ffi.Void> handle,
      int offset,
      ffi.Pointer<ffi.Uint8> output,
      int capacity,
      int timeout,
      ffi.Pointer<ffi.Uint64> total,
    ) {
      requests.add(capacity);
      deadlines.add(timeout);
      total.value = bytes.length;
      final start = offset.clamp(0, bytes.length).toInt();
      final length = (bytes.length - start).clamp(0, capacity).clamp(0, maximumFill ?? capacity).toInt();
      if (offset != _streamCursor) spans.add(offset);
      output.asTypedList(length).setAll(0, bytes.sublist(start, start + length));
      _streamCursor = start + length;
      returned.add(length);

      return length;
    }, exceptionalReturn: -102);
    errorCode = ffi.NativeCallable<_ErrorCodeNative>.isolateLocal(
      (ffi.Pointer<ffi.Void> _) => 0,
      exceptionalReturn: -102,
    );
    error = ffi.NativeCallable<_ErrorNative>.isolateLocal(
      (ffi.Pointer<ffi.Void> _, ffi.Pointer<ffi.Uint8> __, int ___) => 0,
      exceptionalReturn: 0,
    );
    close = ffi.NativeCallable<_CloseNative>.isolateLocal((ffi.Pointer<ffi.Void> _) {
      closed++;
      calloc.free(handle);
    });
  }

  void dispose() {
    readRange.close();
    errorCode.close();
    error.close();
    close.close();
    if (closed == 0) calloc.free(handle);
  }
}
