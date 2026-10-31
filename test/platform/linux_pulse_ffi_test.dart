import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/data/models/audio/audio_file_format.dart';
import 'package:phonolite_app/infrastructure/audio/decoding/audio_file_decoder.dart';
import 'package:phonolite_app/infrastructure/audio/engine/audio_engine.dart';
import 'package:phonolite_app/infrastructure/platform/audio/linux/native_pulse_audio_stream.dart';
import 'package:phonolite_app/infrastructure/platform/audio/linux/pulse_audio_output.dart';

void main() {
  final fixturePath = Platform.environment['PHONOLITE_PULSE_TEST_LIBRARY'];

  group('PulseAudio public ABI', () {
    late DynamicLibrary library;
    late PulseAudioPlayer player;
    late int Function(int) value;
    late void Function(int) latency;
    late void Function(int) error;

    setUp(() {
      library = DynamicLibrary.open(fixturePath!);
      library.lookupFunction<Void Function(), void Function()>('pulse_test_reset')();
      value = library.lookupFunction<Int32 Function(Int32), int Function(int)>('pulse_test_value');
      latency = library.lookupFunction<Void Function(Uint64), void Function(int)>('pulse_test_latency');
      error = library.lookupFunction<Void Function(Int32), void Function(int)>('pulse_test_error');
      player = PulseAudioPlayer(
        sampleRate: 48000,
        channels: 2,
        deviceId: -1,
        createStream: () => NativePulseAudioStream(library: library),
      );
    });

    tearDown(() async {
      await player.dispose();
      expect(value(0), 0, reason: 'Every mainloop, context, stream and operation must be released.');
    });

    test('uses native PCM format, bounded buffering and server playback latency', () async {
      await player.initialize();
      expect([value(1), value(2), value(3)], [3, 48000, 2]);
      expect(value(4), 1, reason: 'Never auto-spawn a PulseAudio daemon.');
      expect(value(5), 0x000b);
      expect(value(9), 38400);
      expect(value(10), 4, reason: 'Underrun recovery waits for one complete frame, including very short tracks.');
      final samples = Int16List(1920)..[0] = -32768;
      await player.write(samples);
      expect(value(8), 3840);
      final byte = library.lookupFunction<Int32 Function(Int32), int Function(int)>('pulse_test_byte');
      expect([byte(0), byte(1)], [0, 128]);
      latency(10000);
      expect(await player.collectDoneSamples(), 960);
      expect(await player.collectDoneSamples(), 0);
      expect(await player.isIdle(), isFalse);
      latency(0);
      expect(await player.collectDoneSamples(), 960);
      expect(await player.isIdle(), isTrue);
    });

    test('pause, resume, linear volume and acknowledged flush reach libpulse', () async {
      await player.initialize();
      player.pause();
      expect(value(6), 1);
      player.resume();
      expect(value(6), 0);
      player.setVolume(0.125);
      expect(value(7), 32768);
      await player.write(Int16List(1920));
      await player.flush();
      expect(value(8), 0);
      expect(await player.collectDoneSamples(), 0);
      await player.write(Int16List(960));
      expect(await player.collectDoneSamples(), 960);
    });

    test('32-bit PCM stays left aligned', () async {
      player = PulseAudioPlayer(
        sampleRate: 96000,
        channels: 2,
        deviceId: -1,
        bitsPerSample: 32,
        validBitsPerSample: 24,
        createStream: () => NativePulseAudioStream(library: library),
      );
      await player.initialize();
      expect([value(1), value(2), value(3)], [7, 96000, 2]);
      await player.writePcm32(Int32List.fromList([-2147483648, 2147483392]));
      final byte = library.lookupFunction<Int32 Function(Int32), int Function(int)>('pulse_test_byte');
      expect(List.generate(8, byte), [0, 0, 0, 128, 0, 255, 255, 127]);
    });

    test('missing timing does not count queued samples as played', () async {
      await player.initialize();
      await player.write(Int16List(1920));
      error(16);
      expect(await player.collectDoneSamples(), 0);
      error(0);
      expect(await player.collectDoneSamples(), 1920);
    });

    test('server and flush failures propagate and remain disposable', () async {
      await player.initialize();
      library.lookupFunction<Void Function(Int32), void Function(int)>('pulse_test_flush_success')(0);
      await expectLater(player.flush(), throwsStateError);
      error(6);
      await expectLater(player.write(Int16List(2)), throwsStateError);
    });

    test('disposal cancels an unacknowledged flush and releases its callback', () async {
      await player.initialize();
      library.lookupFunction<Void Function(Int32), void Function(int)>('pulse_test_flush_ready')(0);
      final flushing = expectLater(player.flush(), throwsStateError);
      await player.dispose();
      await flushing;
      expect(value(0), 0);
    });

    test('server drain confirms the final frame when reported latency never reaches zero', () async {
      await player.initialize();
      await player.write(Int16List(1920));
      latency(1);
      expect(await player.collectDoneSamples(), 1918);
      expect(await player.isIdle(), isFalse);

      library.lookupFunction<Void Function(Int32), void Function(int)>('pulse_test_drain_ready')(1);
      var tail = 0;
      for (var i = 0; i < 20 && tail == 0; i++) {
        tail += await player.collectDoneSamples();
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      expect(tail, 2, reason: 'A residual latency estimate must not strand the last stereo frame.');
      expect(await player.isIdle(), isTrue);
      expect(await player.collectDoneSamples(), 0);
    });

    test('continuous playback passes the server operation deadline without starting a drain', () async {
      await player.initialize();
      latency(1);
      final advanceTime = library.lookupFunction<Void Function(Uint64), void Function(int)>('pulse_test_advance_time');

      for (var second = 0; second < 40; second++) {
        await player.write(Int16List(1920));
        await player.collectDoneSamples();
        advanceTime(1000);
      }

      expect(value(12), 0, reason: 'Progress polling during playback must not ask the server to drain.');
      expect(await player.isIdle(), isFalse);
      expect(value(12), 1, reason: 'Only an explicit end-of-queue idle check requests a drain.');
    });

    test('the production worker streams beyond 30 seconds without speculative completion or restarts', () async {
      latency(1);
      library.lookupFunction<Void Function(Int32), void Function(int)>('pulse_test_clocked_playback')(1);
      final advanceTime = library.lookupFunction<Void Function(Uint64), void Function(int)>('pulse_test_advance_time');
      final decoder = _MemoryDecoder(samples: 48000 * 2 * 45);
      final harness = GaplessPlaybackHarness(
        fileDecoderFactory: (id, uri, offset) => decoder,
        outputFactory: (rate, channels, device, bits, validBits) => PulseAudioPlayer(
          sampleRate: rate,
          channels: channels,
          deviceId: device,
          bitsPerSample: bits,
          validBitsPerSample: validBits,
          createStream: () => NativePulseAudioStream(library: library),
        ),
      );

      try {
        await harness.playOriginal('long-track');
        final startup = Stopwatch()..start();
        while (value(8) == 0 && startup.elapsed < const Duration(seconds: 2)) {
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
        expect(value(8), greaterThan(0));

        final playback = Stopwatch()..start();
        const tickBytes = 48000 * 2 * 4 ~/ 10;
        for (var tick = 0; tick < 400; tick++) {
          // Let the real worker replenish the queue before advancing the
          // simulated server clock. Host scheduling must not cause underruns.
          while (value(8) - value(13) < tickBytes && playback.elapsed < const Duration(seconds: 10)) {
            await Future<void>.delayed(const Duration(milliseconds: 2));
          }
          expect(value(8) - value(13), greaterThanOrEqualTo(tickBytes), reason: 'Tick $tick needs queued audio.');
          advanceTime(100);
        }

        expect(value(13), greaterThan(48000 * 2 * 4 * 35), reason: 'Over 35 seconds of PCM was consumed.');
        expect(value(12), 0, reason: 'An active source must not ask for end-of-stream completion.');
        expect(harness.messages.where((message) => message['type'] == 'complete'), isEmpty);
        expect(harness.messages.where((message) => message['type'] == 'state' && message['active'] == false), isEmpty);
      } finally {
        await harness.close();
      }

      expect(decoder.closed, isTrue);
      expect(value(0), 0);
    });

    test('new writes cancel a pending tail probe without inheriting its timeout or credit', () async {
      await player.initialize();
      latency(20000);
      await player.write(Int16List(960));
      expect(await player.collectDoneSamples(), 0);
      expect(await player.isIdle(), isFalse);
      expect(value(11), 1);
      await player.write(Int16List(960));
      expect(value(11), 0);

      final ready = library.lookupFunction<Void Function(Int32), void Function(int)>('pulse_test_drain_ready');
      ready(1);
      library.lookupFunction<Void Function(Uint64), void Function(int)>('pulse_test_advance_time')(40000);
      expect(await player.collectDoneSamples(), 0);
      expect(await player.isIdle(), isFalse);
      expect(await player.collectDoneSamples(), 1920);
      expect(await player.isIdle(), isTrue);
    });

    test('hardware latency beyond the scheduling horizon cannot starve the native queue', () async {
      latency(200000);
      library.lookupFunction<Void Function(Int32), void Function(int)>('pulse_test_clocked_playback')(1);
      final advanceTime = library.lookupFunction<Void Function(Uint64), void Function(int)>('pulse_test_advance_time');
      final decoder = _MemoryDecoder(samples: 44100 * 2 * 2, rate: 44100);
      final harness = GaplessPlaybackHarness(
        outputProgressTimeout: const Duration(milliseconds: 500),
        fileDecoderFactory: (id, uri, offset) => decoder,
        outputFactory: (rate, channels, device, bits, validBits) => PulseAudioPlayer(
          sampleRate: rate,
          channels: channels,
          deviceId: device,
          bitsPerSample: bits,
          validBitsPerSample: validBits,
          createStream: () => NativePulseAudioStream(library: library),
        ),
      );

      try {
        await harness.playOriginal('high-latency-track');
        const tickBytes = 44100 * 2 * 4 ~/ 10;
        final deadline = Stopwatch()..start();
        for (var tick = 0; tick < 10; tick++) {
          while (value(8) - value(13) < tickBytes && deadline.elapsed < const Duration(seconds: 2)) {
            await Future<void>.delayed(const Duration(milliseconds: 2));
          }
          expect(value(8) - value(13), greaterThanOrEqualTo(tickBytes), reason: 'Native refill stalled at tick $tick.');
          advanceTime(100);
        }

        expect(value(13), 44100 * 2 * 4);
        expect(value(12), 0, reason: 'Continuous playback must not request a drain.');
        expect(harness.messages.where((event) => event['type'] == 'state' && event['active'] == false), isEmpty);
      } finally {
        await harness.close();
      }
    });

    test('a genuinely blocked native queue still fails within the output progress deadline', () async {
      latency(200000);
      library.lookupFunction<Void Function(Int32), void Function(int)>('pulse_test_clocked_playback')(1);
      final decoder = _MemoryDecoder(samples: 48000 * 2 * 2);
      final harness = GaplessPlaybackHarness(
        outputProgressTimeout: const Duration(milliseconds: 100),
        fileDecoderFactory: (id, uri, offset) => decoder,
        outputFactory: (rate, channels, device, bits, validBits) => PulseAudioPlayer(
          sampleRate: rate,
          channels: channels,
          deviceId: device,
          bitsPerSample: bits,
          validBitsPerSample: validBits,
          createStream: () => NativePulseAudioStream(library: library),
        ),
      );

      try {
        await harness.playOriginal('blocked-output');
        final filling = Stopwatch()..start();
        while (value(8) < value(9) && filling.elapsed < const Duration(seconds: 1)) {
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
        expect(value(8), value(9), reason: 'The native write must be waiting on a full queue.');
        await harness.pause();
        await Future<void>.delayed(const Duration(milliseconds: 250));
        expect(
          harness.messages.where((event) => event['type'] == 'state' && event['active'] == false),
          isEmpty,
          reason: 'User pause suspends the progress deadline even during a blocked write.',
        );
        harness.resume();

        final deadline = Stopwatch()..start();
        while (!harness.messages.any((event) => event['type'] == 'state' && event['active'] == false) &&
            deadline.elapsed < const Duration(seconds: 2)) {
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }

        expect(harness.messages.where((event) => event['type'] == 'state' && event['active'] == false), isNotEmpty);
        expect(
          harness.messages.any((event) => '${event['text']}'.contains('Audio output stopped making progress')),
          isTrue,
        );
        expect(decoder.closed, isTrue);
        expect(value(0), 0);
      } finally {
        await harness.close();
      }
    });

    test('a failed drain cannot turn an output failure into track completion', () async {
      await player.initialize();
      latency(1);
      await player.write(Int16List(960));
      expect(await player.collectDoneSamples(), 958);
      expect(await player.isIdle(), isFalse);
      library.lookupFunction<Void Function(Int32), void Function(int)>('pulse_test_drain_ready')(1);
      library.lookupFunction<Void Function(Int32), void Function(int)>('pulse_test_drain_success')(0);

      await expectLater(player.collectDoneSamples(), throwsStateError);
      expect(value(11), 0);
    });

    test('pause suspends pending completion and flush retires its old callback', () async {
      await player.initialize();
      latency(1);
      await player.write(Int16List(960));
      expect(await player.collectDoneSamples(), 958);
      expect(await player.isIdle(), isFalse);
      final ready = library.lookupFunction<Void Function(Int32), void Function(int)>('pulse_test_drain_ready');
      ready(1);
      player.pause();
      expect(value(11), 0);
      library.lookupFunction<Void Function(Uint64), void Function(int)>('pulse_test_advance_time')(40000);
      expect(await player.collectDoneSamples(), 0);
      expect(await player.isIdle(), isFalse);
      player.resume();
      expect(await player.isIdle(), isFalse);
      expect(await player.collectDoneSamples(), 2);

      ready(0);
      await player.write(Int16List(960));
      await player.collectDoneSamples();
      expect(await player.isIdle(), isFalse);
      expect(value(11), 1);
      await player.flush();
      expect(value(11), 0);
      await player.write(Int16List(2));
      expect(await player.collectDoneSamples(), 0);
      expect(await player.isIdle(), isFalse);
      ready(1);
      expect(await player.collectDoneSamples(), 2);
    });

    test('native Linux progress crosses prepared track boundaries and completes without a latency zero', () async {
      latency(1);
      final decoders = <String, _MemoryDecoder>{};
      var outputs = 0;
      final harness = GaplessPlaybackHarness(
        outputProgressTimeout: const Duration(milliseconds: 300),
        fileDecoderFactory: (id, uri, offset) => decoders.putIfAbsent(id, _MemoryDecoder.new),
        outputFactory: (rate, channels, device, bits, validBits) {
          outputs++;
          return PulseAudioPlayer(
            sampleRate: rate,
            channels: channels,
            deviceId: device,
            bitsPerSample: bits,
            validBitsPerSample: validBits,
            createStream: () => NativePulseAudioStream(library: library),
          );
        },
      );

      try {
        await harness.playOriginal('current');
        await harness.prepareOriginal('next', 21);
        await harness.prepareOriginal('following', 22, afterPreparationId: 21);
        library.lookupFunction<Void Function(Int32), void Function(int)>('pulse_test_drain_ready')(1);
        final deadline = Stopwatch()..start();
        while (!harness.messages.any((message) => message['type'] == 'complete') &&
            deadline.elapsed < const Duration(seconds: 2)) {
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }

        expect(
          harness.messages
              .where((message) => message['type'] == 'gapless_transition')
              .map((event) => event['preparation_id']),
          [21, 22],
        );
        expect(harness.messages.where((message) => message['type'] == 'complete'), hasLength(1));
        expect(harness.messages.where((message) => message['type'] == 'state' && message['active'] == false), isEmpty);
        expect(outputs, 1, reason: 'Prepared successors share the same native output.');
      } finally {
        await harness.close();
      }

      expect(decoders.values.every((decoder) => decoder.closed), isTrue);
      expect(value(0), 0);
    });
  }, skip: fixturePath == null ? 'Set PHONOLITE_PULSE_TEST_LIBRARY to the headless CMake fixture.' : false);
}

class _MemoryDecoder extends Fake implements AudioFileDecoder {
  final int samples;
  final int rate;
  late int _remaining = samples;
  bool closed = false;

  _MemoryDecoder({this.samples = 1920, this.rate = 48000});

  @override
  AudioFileFormat get format => AudioFileFormat(
    sampleRate: rate,
    channels: 2,
    bitDepth: 32,
    duration: Duration(microseconds: samples * 1000000 ~/ (rate * 2)),
    playableFrames: samples ~/ 2,
  );

  @override
  Future<void> initialize() async {}

  @override
  Future<Int32List> read32(int maxSamples) async {
    final count = _remaining.clamp(0, maxSamples);
    _remaining -= count;

    return Int32List(count);
  }

  @override
  void interruptRead() {}

  @override
  Future<void> close() async => closed = true;
}
