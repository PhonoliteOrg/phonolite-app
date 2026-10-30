import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/data/structures/audio/pcm_stream_converter.dart';

PcmStreamConverter converter({
  int inputRate = 44100,
  int outputRate = 48000,
  int inputChannels = 1,
  int outputChannels = 1,
  int inputBits = 32,
  int outputBits = 32,
}) => PcmStreamConverter(
  inputRate: inputRate,
  inputChannels: inputChannels,
  outputRate: outputRate,
  outputChannels: outputChannels,
  inputBits: inputBits,
  outputBits: outputBits,
);

void main() {
  test('unity PCM32 preserves all signed bits including extreme samples', () {
    final source = Int32List.fromList(<int>[-2147483648, -2147483647, -1, 0, 1, 2147483646, 2147483647]);
    final result = converter(inputRate: 48000).process(source, endOfInput: true);
    expect(result, isA<Int32List>());
    expect(result, orderedEquals(source));
  });

  test('arbitrary chunk boundaries preserve sample values and exact duration', () {
    final source = Int32List.fromList(List<int>.generate(4417, (n) => (math.sin(n * 0.071) * 1000000000).round()));
    final expected = converter().process(source, endOfInput: true);
    final stream = converter();
    final actual = <int>[];
    for (var offset = 0; offset < source.length; offset += 17) {
      actual.addAll(stream.process(source.sublist(offset, math.min(offset + 17, source.length))));
    }
    actual.addAll(stream.process(const <int>[], endOfInput: true));
    expect(actual, orderedEquals(expected));
    expect(actual.length, (source.length * 48000 + 22050) ~/ 44100);
  });

  test('downsampling rejects aliases and keeps the audio passband', () {
    double energyAt(int frequency) {
      final source = Int32List.fromList(
        List<int>.generate(9600, (n) => (math.sin(n * 2 * math.pi * frequency / 96000) * 1000000000).round()),
      );
      final output = converter(inputRate: 96000).process(source, endOfInput: true);
      final interior = output.sublist(100, output.length - 100);
      return math.sqrt(interior.fold<double>(0.0, (sum, n) => sum + n * n) / interior.length);
    }

    expect(energyAt(36000), lessThan(1000000));
    expect(energyAt(18000), closeTo(1000000000 / math.sqrt2, 2000000));
  });

  test('short tails keep DC and emit rounded duration without padding', () {
    final stream = converter();
    expect(stream.process(Int32List.fromList(List<int>.filled(7, 123456789))), isEmpty);
    expect(stream.process(const <int>[], endOfInput: true), orderedEquals(List<int>.filled(8, 123456789)));
    expect(converter().process(const <int>[], endOfInput: true), isEmpty);
    expect(converter().process(const <int>[12345], endOfInput: true), <int>[12345]);
  });

  test('mono and stereo mappings and PCM container conversion are explicit', () {
    expect(
      converter(
        inputRate: 48000,
        outputChannels: 2,
        inputBits: 16,
      ).process(Int16List.fromList(<int>[-32768, 123, 32767]), endOfInput: true),
      orderedEquals(<int>[-2147483648, -2147483648, 123 << 16, 123 << 16, 32767 << 16, 32767 << 16]),
    );
    final mono = converter(
      inputRate: 48000,
      inputChannels: 2,
      outputBits: 16,
    ).process(Int32List.fromList(<int>[-2147483648, -2147483648, 0, 0, 2147483647, 2147483647]), endOfInput: true);
    expect(mono, isA<Int16List>());
    expect(mono, orderedEquals(<int>[-32768, 0, 32767]));
  });

  test('stereo resampling preserves frame alignment and channel identity', () {
    final source = Int32List.fromList(List<int>.generate(441 * 2, (index) => index.isEven ? 1000000000 : -1000000000));
    final result = converter(inputChannels: 2, outputChannels: 2).process(source, endOfInput: true);
    expect(result.length, 480 * 2);
    for (var n = 0; n < result.length; n += 2) {
      expect(result[n], 1000000000);
      expect(result[n + 1], -1000000000);
    }
  });

  test('invalid formats, partial frames and input after EOF are rejected', () {
    expect(() => converter(inputRate: 0), throwsArgumentError);
    expect(() => converter(inputChannels: 3), throwsArgumentError);
    expect(() => converter(outputBits: 24), throwsArgumentError);
    expect(() => converter(inputChannels: 2).process(const <int>[1]), throwsArgumentError);
    final stream = converter();
    stream.process(const <int>[], endOfInput: true);
    expect(() => stream.process(const <int>[1]), throwsStateError);
  });
}
