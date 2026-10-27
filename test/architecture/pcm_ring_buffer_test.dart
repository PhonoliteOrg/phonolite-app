import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/data/structures/audio/pcm_ring_buffer.dart';

void main() {
  test('32-bit PCM retains low bits through wrapping and growth', () {
    final buffer = PcmRingBuffer(4, bitsPerSample: 32);
    final samples = Int32List.fromList([-2147483648, -65537, -1, 1, 65537, 2147483647]);

    expect(buffer.write(samples, 0), 4);
    expect(buffer.read(3), samples.sublist(0, 3));
    expect(buffer.write(samples, 4), 2);
    buffer.ensureCapacity(8);

    final result = buffer.read(8);

    expect(result, isA<Int32List>());
    expect(result, [1, 65537, 2147483647]);
  });

  test('growth preserves wrapped samples and pending producer reference', () {
    final buffer = PcmRingBuffer(6);
    final producer = buffer;
    expect(buffer.write(Int16List.fromList([1, 2, 3, 4, 5]), 0), 5);
    expect(buffer.read(4), [1, 2, 3, 4]);
    expect(buffer.write(Int16List.fromList([6, 7, 8, 9]), 0), 4);

    buffer.ensureCapacity(12);

    expect(producer, same(buffer));
    expect(buffer.capacity, 12);
    expect(buffer.length, 5);
    expect(buffer.free, 7);
    expect(producer.write(Int16List.fromList([10, 11, 12]), 0), 3);
    expect(buffer.read(20), [5, 6, 7, 8, 9, 10, 11, 12]);
    expect(buffer.length, 0);
  });

  test('growing a full queue allows refill past the former capacity', () {
    final buffer = PcmRingBuffer(4);
    expect(buffer.write(Int16List.fromList([1, 2, 3, 4, 5, 6]), 0), 4);
    expect(buffer.free, 0);

    buffer.ensureCapacity(8);

    expect(buffer.write(Int16List.fromList([5, 6, 7, 8]), 0), 4);
    expect(buffer.read(8), [1, 2, 3, 4, 5, 6, 7, 8]);
    expect(buffer.write(Int16List.fromList([9, 10]), 0), 2);
    expect(buffer.read(8), [9, 10]);
  });

  test('smaller capacity requests leave queued audio untouched', () {
    final buffer = PcmRingBuffer(8);
    buffer.write(Int16List.fromList([4, 5, 6]), 0);

    buffer.ensureCapacity(2);
    buffer.ensureCapacity(8);

    expect(buffer.capacity, 8);
    expect(buffer.length, 3);
    expect(buffer.read(8), [4, 5, 6]);
  });

  test('an empty queue can grow then accept a full new buffer', () {
    final buffer = PcmRingBuffer(3);
    buffer.write(Int16List.fromList([1, 2, 3]), 0);
    expect(buffer.read(3), [1, 2, 3]);
    buffer.ensureCapacity(6);
    expect(buffer.free, 6);
    expect(buffer.write(Int16List.fromList([4, 5, 6, 7, 8, 9]), 0), 6);
    expect(buffer.read(6), [4, 5, 6, 7, 8, 9]);
  });
}
