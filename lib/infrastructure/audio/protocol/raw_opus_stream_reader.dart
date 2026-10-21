import 'dart:typed_data';

import 'package:phonolite_opus/phonolite_opus.dart';

import 'package:phonolite_app/data/models/audio/raw_opus_event.dart';

export 'package:phonolite_app/data/models/audio/raw_opus_event.dart';

/// Incremental framing only. It never waits for PCM space or native output.
class RawOpusStreamReader {
  static final Uint8List _magic = Uint8List.fromList('OPUSR01\u0000'.codeUnits);

  Uint8List _bytes = Uint8List(0);
  int _offset = 0;
  bool _hasHeader = false;

  void reset() {
    _bytes = Uint8List(0);
    _offset = 0;
    _hasHeader = false;
  }

  List<RawOpusEvent> add(Uint8List data) {
    final remaining = _bytes.length - _offset;
    final next = Uint8List(remaining + data.length);
    next.setRange(0, remaining, _bytes, _offset);
    next.setRange(remaining, next.length, data);

    _bytes = next;
    _offset = 0;

    final events = <RawOpusEvent>[];

    while (_bytes.length - _offset >= 2) {
      final length = _bytes[_offset] | (_bytes[_offset + 1] << 8);

      if (length == 0xffff) {
        if (_bytes.length - _offset < 6) {
          break;
        }

        final marker = ByteData.sublistView(_bytes, _offset + 2, _offset + 6).getUint32(0, Endian.little);

        _offset += 6;
        _hasHeader = false;
        events.add(RawOpusSeekMarker(marker));
        continue;
      }

      if (!_hasHeader) {
        if (_bytes.length - _offset < 12) {
          break;
        }

        for (var i = 0; i < _magic.length; i++) {
          if (_bytes[_offset + i] != _magic[i]) {
            throw const FormatException('Invalid raw Opus stream boundary');
          }
        }

        final headerLength = _bytes[_offset + 10] | (_bytes[_offset + 11] << 8);

        if (headerLength < 40) {
          throw const FormatException('Invalid raw Opus header length');
        }

        if (_bytes.length - _offset < headerLength) {
          break;
        }

        final headerBytes = Uint8List.fromList(_bytes.sublist(_offset, _offset + headerLength));

        _offset += headerLength;
        _hasHeader = true;
        events.add(RawOpusStreamHeader(headerBytes, RawOpusHeader.parse(headerBytes)));
        continue;
      }

      if (length == 0) {
        _offset += 2;
        _hasHeader = false;
        events.add(RawOpusEnd());
        continue;
      }

      if (_bytes.length - _offset < length + 2) {
        break;
      }

      _offset += 2;
      final packet = Uint8List.fromList(_bytes.sublist(_offset, _offset + length));

      _offset += length;
      events.add(RawOpusPacket(packet));
    }

    if (_offset == _bytes.length) {
      _bytes = Uint8List(0);
      _offset = 0;
    }

    return events;
  }
}
