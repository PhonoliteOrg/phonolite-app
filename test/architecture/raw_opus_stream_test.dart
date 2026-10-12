import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/entities/raw_opus_stream.dart';

import '../support/streaming_test_helpers.dart';

void main() {
  test('fragmented marker header packet and EOS preserve exact framing', () {
    final marker = Uint8List.fromList([255, 255, 42, 0, 0, 0]);
    final packet = [255, 255, ...'OPUSR01\u0000'.codeUnits];
    final bytes = [
      ...marker,
      ...rawHeader(),
      packet.length,
      0,
      ...packet,
      0,
      0,
    ];
    final reader = RawOpusStreamReader();
    final events = <RawOpusEvent>[];
    for (final byte in bytes) {
      events.addAll(reader.add(Uint8List.fromList([byte])));
    }
    expect(events, hasLength(4));
    expect((events[0] as RawOpusSeekMarker).seekId, 42);
    expect((events[1] as RawOpusStreamHeader).header.preSkip, 312);
    expect((events[2] as RawOpusPacket).bytes, packet);
    expect(events[3], isA<RawOpusEnd>());
  });

  test(
    'reset drops an incomplete obsolete packet before the next generation',
    () {
      final reader = RawOpusStreamReader();
      reader.add(Uint8List.fromList([...rawHeader(), 4, 0, 1]));
      reader.reset();
      final events = reader.add(
        Uint8List.fromList([255, 255, 7, 0, 0, 0, ...rawHeader(), 1, 0, 9]),
      );
      expect(events, hasLength(3));
      expect((events.last as RawOpusPacket).bytes, [9]);
    },
  );

  test(
    'invalid boundary and undersized header are errors, not endless resync',
    () {
      expect(
        () => RawOpusStreamReader().add(Uint8List(12)),
        throwsFormatException,
      );
      final invalid = rawHeader();
      ByteData.sublistView(invalid).setUint16(10, 12, Endian.little);
      expect(() => RawOpusStreamReader().add(invalid), throwsFormatException);
    },
  );
}
