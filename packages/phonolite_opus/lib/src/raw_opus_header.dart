import 'dart:typed_data';

import 'package:phonolite_opus/src/opus_exception.dart';

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
      if (extension + 8 != headerLen) {
        throw OpusException('invalid exact frame extension');
      }
      playableFrames = ByteData.sublistView(
        data,
      ).getUint64(extension, Endian.little);
      if (playableFrames < 0 || playableFrames > 0x1fffffffffffff) {
        throw OpusException('invalid exact frame count');
      }
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
