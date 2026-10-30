import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/data/models/audio/audio_file_format.dart';
import 'package:phonolite_app/data/models/audio/audio_source_rejected.dart';
import 'package:phonolite_app/infrastructure/audio/decoding/audio_file_decoder.dart';
import 'package:phonolite_app/infrastructure/audio/engine/audio_engine.dart';

import '../support/streaming_test_helpers.dart' show MemoryPcmOutput, waitUntil;

const _deadline = Duration(seconds: 3);

class _PrecisePcmOutput extends MemoryPcmOutput {
  final samples = <int>[];
  int int16Writes = 0;

  @override
  Future<void> write(Int16List samples) async {
    int16Writes++;
    await super.write(samples);
  }

  @override
  Future<void> writePcm32(Int32List samples) async {
    await super.writePcm32(samples);
    this.samples.addAll(samples);
  }
}

class _BlockedPcmOutput extends _PrecisePcmOutput {
  final gate = Completer<void>();

  @override
  Future<void> writePcm32(Int32List samples) async {
    await gate.future;
    await super.writePcm32(samples);
  }

  @override
  Future<void> dispose() async {
    if (!gate.isCompleted) gate.complete();
    await super.dispose();
  }
}

void main() {
  test('Original fills the shared eight-second horizon while output is blocked and stops reading', () async {
    final decoder = _MemorySourceDecoder(Int32List(48000 * 20), sampleRate: 48000);
    final output = _BlockedPcmOutput();
    final session = AudioPlaybackHarness.original(
      decoderFactory: (_, __) => decoder,
      outputFactory: (_, __, ___) => output,
    );
    addTearDown(session.close);
    session.start();
    await waitUntil(() => decoder.readSamples >= 48000 * 8);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final decoded = decoder.readSamples;
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(decoded, inInclusiveRange(48000 * 8, 48000 * 9));
    expect(decoder.readSamples, decoded, reason: 'A full read-ahead buffer must stop requesting source bytes.');
    expect(output.samples, isEmpty);
  });

  for (final (baseUrl, quicPort, expectedUri) in [
    ('https://source.test/api', null, 'quic://source.test:444/track'),
    ('https://source.test/api', 7443, 'quic://source.test:7443/track'),
    ('http://localhost:3000/api', null, 'quic://127.0.0.1:3001/track'),
  ]) {
    test('Original selects $expectedUri and preserves PCM32 without an Opus stage', () async {
      final samples = Int32List.fromList([1, -1, 2147483647, -2147483648, 0x12345678, -0x12345678]);
      final output = _PrecisePcmOutput();
      Uri? requested;
      final session = AudioPlaybackHarness.original(
        baseUrl: baseUrl,
        quicPort: quicPort,
        decoderFactory: (uri, offset) {
          requested = uri;

          return _MemorySourceDecoder(samples);
        },
        outputFactory: (_, __, ___) => output,
      );
      addTearDown(session.close);
      session.start();
      await waitUntil(() => session.messages.any((event) => event['type'] == 'complete'));

      expect(requested.toString(), expectedUri);
      expect(output.samples, orderedEquals(samples));
      expect(output.int16Writes, 0);
      expect(session.cachedBytes, 0);
    });
  }

  final nativeLibrary = Platform.environment['PHONOLITE_LOCAL_AUDIO_LIBRARY'];
  final nativeSkip = nativeLibrary == null || nativeLibrary.isEmpty
      ? 'Set PHONOLITE_LOCAL_AUDIO_LIBRARY to the rebuilt native decoder library.'
      : false;
  final downloadFixtures = Platform.environment['PHONOLITE_DOWNLOAD_FIXTURES'];

  group('native file decoder isolate', () {
    late Directory fixtures;

    setUp(() async {
      fixtures = await Directory.systemTemp.createTemp('phonolite-file-decoder-test-');
      addTearDown(() => fixtures.delete(recursive: true));
    });

    Future<File> writeFlac(int bitDepth, List<int> samples) async {
      final source = File('${fixtures.path}/source-$bitDepth.flac');
      await source.writeAsBytes(_verbatimFlac(sampleRate: 192000, bitDepth: bitDepth, samples: samples));

      return source;
    }

    for (final bitrate in [64000, 96000, 128000, 192000]) {
      test(
        'server-generated $bitrate bps Opus downloads retain exact timing across the isolate',
        () async {
          final decoder = AudioFileDecoder.local(filePath: '$downloadFixtures/tone_$bitrate.opus');
          addTearDown(decoder.close);
          await decoder.initialize().timeout(_deadline);

          expect(decoder.format.sampleRate, 48000);
          expect(decoder.format.channels, 2);
          expect(decoder.format.bitDepth, 32);
          expect(decoder.format.playableFrames, 19200);
          expect(decoder.format.duration, const Duration(milliseconds: 400));

          final samples = await _readAllPcm32(decoder);
          expect(samples, hasLength(38400));
          expect(samples.any((sample) => sample.abs() > 1000000), isTrue);
          await decoder.seek(const Duration(milliseconds: 100)).timeout(_deadline);
          expect(await _readAllPcm32(decoder), orderedEquals(samples.skip(9600)));
        },
        skip: downloadFixtures == null || downloadFixtures.isEmpty
            ? 'Set PHONOLITE_DOWNLOAD_FIXTURES to server-generated Opus fixtures.'
            : false,
      );
    }

    for (final bitDepth in [24, 32]) {
      test('preserves 192 kHz and every $bitDepth-bit sample across isolate transfers', () async {
        final values = _sourceSamples(bitDepth);
        final source = await writeFlac(bitDepth, values);
        final decoder = AudioFileDecoder.local(filePath: source.path);
        addTearDown(decoder.close);

        final opening = decoder.initialize();
        expect(identical(opening, decoder.initialize()), isTrue);
        await opening.timeout(_deadline);

        expect(decoder.format.sampleRate, 192000);
        expect(decoder.format.bitDepth, bitDepth);
        expect(decoder.format.channels, 1);
        expect(decoder.format.duration, const Duration(milliseconds: 1));

        final first = await decoder.read32(7).timeout(_deadline);
        final remaining = await decoder.read32(300).timeout(_deadline);
        final actual = [...first, ...remaining];
        final expected = values.map((value) => value << (32 - bitDepth)).toList();

        expect(first, hasLength(7));
        expect(actual, orderedEquals(expected));
        expect(actual.first & 0xffff, isNonZero, reason: 'Detail below 16-bit precision must survive.');
        expect(await decoder.read32(16).timeout(_deadline), isEmpty);

        final closing = decoder.close();
        expect(identical(closing, decoder.close()), isTrue);
        await closing.timeout(_deadline);
        await expectLater(decoder.read32(1), throwsA(isA<StateError>()));

        // Release the fixture after the decoder acknowledges native shutdown.
        await source.delete();
      });

      test(
        'Original $bitDepth-bit sessions keep remote identity and source precision through paused seeking',
        () async {
          final values = _sourceSamples(bitDepth, count: 4096);
          final source = await writeFlac(bitDepth, values);
          final output = _PrecisePcmOutput();
          Uri? requestedUri;
          Duration? requestedOffset;
          final outputFormats = <(int, int, int)>[];
          final session = AudioPlaybackHarness.original(
            decoderFactory: (url, startOffset) {
              requestedUri = url;
              requestedOffset = startOffset;

              return AudioFileDecoder.local(filePath: source.path, startOffset: startOffset);
            },
            outputFactory: (sampleRate, channels, deviceId) {
              outputFormats.add((sampleRate, channels, deviceId));

              return output;
            },
            initialPaused: true,
          );
          addTearDown(session.close);
          session.start();

          await _waitForSession(
            session,
            () => session.messages.any((event) => event['type'] == 'stats'),
            'paused stats',
          );

          expect(requestedUri.toString(), 'quic://source.test:444/track');
          expect(requestedOffset, Duration.zero);
          expect(outputFormats, [(192000, 1, -1)]);
          expect(session.paused, isTrue);
          expect(output.samples, isEmpty);
          expect(session.cachedBytes, 0);
          final stats = session.messages.where((event) => event['type'] == 'stats');
          expect(stats, isNotEmpty);
          expect(stats.every((event) => event['local'] == false), isTrue);
          expect(stats.every((event) => event['bitrate_kbps'] == null), isTrue);
          expect(stats.every((event) => event['rtt_ms'] == null), isTrue);

          expect(
            await session.seek(const Duration(milliseconds: 5)).timeout(_deadline),
            isTrue,
            reason: 'Session events:\n${session.messages.join('\n')}',
          );
          expect(session.paused, isTrue);
          expect(output.samples, isEmpty);
          expect(output.flushes, 1);
          expect(outputFormats, hasLength(1));
          session.resume();

          await _waitForSession(
            session,
            () => session.messages.any((event) => event['type'] == 'complete'),
            'completion',
          );

          expect(output.samples, orderedEquals(values.skip(960).map((value) => value << (32 - bitDepth))));
          expect(output.int16Writes, 0);
          expect(session.cachedBytes, 0);
          expect(session.messages.where((event) => event['type'] == 'seek_failed'), isEmpty);
          expect(session.messages.where((event) => event['source_rejected'] == true), isEmpty);
        },
      );
    }

    test('Original source rejection stops the session before opening an output', () async {
      var outputOpens = 0;
      final session = AudioPlaybackHarness.original(
        decoderFactory: (url, startOffset) =>
            AudioFileDecoder.remote(url: url, token: '', serverPin: '', startOffset: startOffset),
        outputFactory: (_, __, ___) {
          outputOpens++;

          return _PrecisePcmOutput();
        },
      );
      addTearDown(session.close);
      session.start();

      await _waitForSession(
        session,
        () => session.messages.any((event) => event['type'] == 'state' && event['active'] == false),
        'source rejection',
      );

      final state = session.messages.lastWhere((event) => event['type'] == 'state');
      expect(state['source_rejected'], isTrue);
      expect(state['paused'], isFalse);
      expect(outputOpens, 0);
      expect(session.cachedBytes, 0);
      expect(session.messages.where((event) => event['type'] == 'started' || event['type'] == 'complete'), isEmpty);
    });

    test('seeks and starts at the requested source frame without reducing precision', () async {
      final values = _sourceSamples(24);
      final source = await writeFlac(24, values);
      final decoder = AudioFileDecoder.local(filePath: source.path);
      addTearDown(decoder.close);
      await decoder.initialize().timeout(_deadline);
      await decoder.read32(64).timeout(_deadline);

      expect(await decoder.seek(const Duration(milliseconds: 1)).timeout(_deadline), const Duration(milliseconds: 1));
      expect(await decoder.read32(64).timeout(_deadline), orderedEquals(values.skip(192).map((value) => value << 8)));
      expect(await decoder.read32(16).timeout(_deadline), isEmpty);

      expect(await decoder.seek(Duration.zero).timeout(_deadline), Duration.zero);
      expect(await decoder.read32(8).timeout(_deadline), orderedEquals(values.take(8).map((value) => value << 8)));
      await decoder.close().timeout(_deadline);

      final offsetDecoder = AudioFileDecoder.local(filePath: source.path, startOffset: const Duration(milliseconds: 1));
      addTearDown(offsetDecoder.close);
      await offsetDecoder.initialize().timeout(_deadline);

      expect(
        await offsetDecoder.read32(64).timeout(_deadline),
        orderedEquals(values.skip(192).map((value) => value << 8)),
      );
    });

    test('close during initialization drains startup and releases the source', () async {
      final source = await writeFlac(24, _sourceSamples(24));
      final decoder = AudioFileDecoder.local(filePath: source.path);
      addTearDown(decoder.close);

      final opening = decoder.initialize();
      final closing = decoder.close();
      await opening.timeout(_deadline);
      await closing.timeout(_deadline);

      await expectLater(decoder.read32(1), throwsA(isA<StateError>()));
      await source.delete();
    });

    for (final invalidPin in ['', 'invalid-server-pin']) {
      test(
        'invalid Original credentials survive the isolate as source rejection (${invalidPin.isEmpty ? 'missing' : 'malformed'} pin)',
        () async {
          final decoder = AudioFileDecoder.remote(
            url: Uri.parse('https://127.0.0.1:1/api/stream/source/original'),
            token: invalidPin.isEmpty ? '' : 'fixture-token',
            serverPin: invalidPin,
          );
          addTearDown(decoder.close);

          await expectLater(decoder.initialize().timeout(_deadline), throwsA(isA<AudioSourceRejected>()));
          await decoder.close().timeout(_deadline);
          await decoder.close().timeout(_deadline);
        },
      );
    }

    test('missing sources report initialization failure and still close promptly', () async {
      final decoder = AudioFileDecoder.local(filePath: '${fixtures.path}/missing.flac');
      addTearDown(decoder.close);

      await expectLater(decoder.initialize().timeout(_deadline), throwsA(isA<StateError>()));
      await decoder.close().timeout(_deadline);
      await decoder.close().timeout(_deadline);
      await expectLater(decoder.read32(1), throwsA(isA<StateError>()));
    });
  }, skip: nativeSkip);

  test('closing an unopened decoder prevents initialization without acquiring resources', () async {
    final decoder = AudioFileDecoder.local(filePath: 'unopened-source.flac');
    final closing = decoder.close();

    expect(identical(closing, decoder.close()), isTrue);
    await closing;
    await expectLater(decoder.initialize(), throwsA(isA<StateError>()));
    await expectLater(decoder.read32(1), throwsA(isA<StateError>()));
  });
}

class _MemorySourceDecoder implements AudioFileDecoder {
  final Int32List samples;
  final int sampleRate;
  int _position = 0;
  int readSamples = 0;

  _MemorySourceDecoder(this.samples, {this.sampleRate = 192000});

  @override
  AudioFileFormat get format => AudioFileFormat(
    sampleRate: sampleRate,
    channels: 1,
    bitDepth: 32,
    duration: Duration(microseconds: samples.length * 1000000 ~/ sampleRate),
    playableFrames: samples.length,
  );

  @override
  Future<void> initialize() async {}

  @override
  void interruptRead() {}

  @override
  Future<Int32List> read32(int maxSamples) async {
    final end = (_position + maxSamples).clamp(0, samples.length);
    final chunk = Int32List.fromList(samples.sublist(_position, end));
    _position = end;
    readSamples += chunk.length;

    return chunk;
  }

  @override
  Future<Duration> seek(Duration position) async {
    _position = (position.inMicroseconds * sampleRate ~/ 1000000).clamp(0, samples.length);

    return position;
  }

  @override
  Future<void> close() async {}
}

Future<void> _waitForSession(AudioPlaybackHarness session, bool Function() predicate, String description) async {
  try {
    await waitUntil(predicate);
  } catch (error) {
    fail('Timed out waiting for $description: $error\nSession events:\n${session.messages.join('\n')}');
  }
}

Future<List<int>> _readAllPcm32(AudioFileDecoder decoder) async {
  final output = <int>[];

  while (true) {
    final chunk = await decoder.read32(4096).timeout(_deadline);

    if (chunk.isEmpty) {
      return output;
    }

    output.addAll(chunk);
  }
}

List<int> _sourceSamples(int bitDepth, {int count = 256}) {
  final maximum = (1 << (bitDepth - 1)) - 1;
  final minimum = -(1 << (bitDepth - 1));
  final initial = [1, -1, maximum, minimum, 0x123456, -0x123456, 255, -255];

  return [
    ...initial,
    for (var index = initial.length; index < count; index++) (index.isEven ? 1 : -1) * (index * 31 + 1),
  ];
}

/// A single verbatim FLAC frame keeps the expected source samples independent
/// of any encoder, external tool or audio device used by the test host.
Uint8List _verbatimFlac({required int sampleRate, required int bitDepth, required List<int> samples}) {
  final output = BytesBuilder(copy: false);
  final blockSize = samples.length;
  final streamInfo = ByteData(34)
    ..setUint16(0, blockSize, Endian.big)
    ..setUint16(2, blockSize, Endian.big)
    ..setUint64(10, (sampleRate << 44) | ((bitDepth - 1) << 36) | blockSize, Endian.big);

  output.add([0x66, 0x4c, 0x61, 0x43, 0x80, 0, 0, streamInfo.lengthInBytes]);
  output.add(streamInfo.buffer.asUint8List());

  final frame = <int>[0xff, 0xf8, blockSize <= 256 ? 0x60 : 0x70, 0, 0];

  if (blockSize <= 256) {
    frame.add(blockSize - 1);
  } else {
    frame.addAll([(blockSize - 1) >> 8, (blockSize - 1) & 0xff]);
  }

  frame.add(_crc(frame, width: 8, polynomial: 0x07));
  frame.add(0x02);

  for (final sample in samples) {
    final encoded = ByteData(4)..setInt32(0, sample, Endian.big);
    frame.addAll(encoded.buffer.asUint8List(4 - bitDepth ~/ 8));
  }

  final checksum = _crc(frame, width: 16, polynomial: 0x8005);
  output.add(frame);
  output.add([checksum >> 8, checksum & 0xff]);

  return output.takeBytes();
}

int _crc(List<int> bytes, {required int width, required int polynomial}) {
  final topBit = 1 << (width - 1);
  final mask = (1 << width) - 1;
  var checksum = 0;

  for (final byte in bytes) {
    checksum ^= byte << (width - 8);

    for (var bit = 0; bit < 8; bit++) {
      checksum = ((checksum << 1) ^ (checksum & topBit != 0 ? polynomial : 0)) & mask;
    }
  }

  return checksum;
}
