import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/infrastructure/audio/output/audio_output_factory.dart';
import 'package:phonolite_app/infrastructure/platform/audio/linux/pulse_audio_output.dart';
import 'package:phonolite_app/infrastructure/platform/audio/linux/pulse_audio_stream.dart';

void main() {
  late _FakeStream stream;
  late PulseAudioPlayer player;

  setUp(() {
    stream = _FakeStream();
    player = PulseAudioPlayer(sampleRate: 48000, channels: 2, deviceId: -1, createStream: () => stream);
  });

  tearDown(() async => player.dispose());

  test('Linux factory constructs an unopened PCM backend', () async {
    final output = createAudioPcmOutput(sampleRate: 48000, channels: 2, deviceId: -1);
    expect(output, isA<PulseAudioPlayer>());
    await output.dispose();
  }, skip: !Platform.isLinux);

  test('opening waits for readiness and applies earlier volume/pause commands', () async {
    stream.ready = false;
    player.setVolume(0.4);
    player.pause();
    final opening = player.initialize();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(stream.opened, isTrue);
    stream.ready = true;
    await opening;
    expect(stream.volume, 0.4);
    expect(stream.paused, isTrue);
    expect(identical(opening, player.initialize()), isTrue);
  });

  test('disposal cancels pending initialization and releases the stream once', () async {
    stream.ready = false;
    final opening = expectLater(player.initialize(), throwsStateError);
    await player.dispose();
    await opening;
    expect(stream.closes, 1);
    await player.dispose();
    expect(stream.closes, 1);
  });

  test('startup timeout closes the connection', () async {
    player = PulseAudioPlayer(
      sampleRate: 48000,
      channels: 2,
      deviceId: -1,
      createStream: () => stream,
      connectionTimeout: Duration.zero,
    );
    stream.ready = false;
    await expectLater(player.initialize(), throwsA(isA<TimeoutException>()));
    expect(stream.closes, 1);
  });

  test('stop after native readiness still cancels unfinished initialization', () async {
    final opening = expectLater(player.initialize(), throwsStateError);
    await player.dispose();
    await opening;
    expect(stream.closes, 1);
  });

  test('disposal before startup prevents any native open', () async {
    await player.dispose();
    await expectLater(player.initialize(), throwsStateError);
    expect(stream.opened, isFalse);
    expect(stream.closes, 0);
  });

  test('partial writes preserve byte offsets and wait for queue space', () async {
    await player.initialize();
    stream.capacity = 4;
    final samples = Int16List.fromList([99, 99, -32768, 32767, 42, -42, 99, 99]);
    final writing = player.write(Int16List.sublistView(samples, 2, 6));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(stream.bytes, samples.buffer.asUint8List(4, 4));
    stream.capacity = 4;
    await writing;
    expect(stream.bytes, samples.buffer.asUint8List(4, 8));
  });

  test('flush cancels blocked writes and starts a new playback clock', () async {
    await player.initialize();
    stream.capacity = 4;
    final writing = player.write(Int16List.fromList([1, 2, 3, 4]));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    stream.played = 2;
    expect(await player.collectDoneSamples(), 2);
    await player.flush();
    await writing;
    expect(stream.bytes, isEmpty);
    stream.capacity = 4;
    await player.write(Int16List.fromList([5, 6]));
    expect(stream.bytes, Int16List.fromList([5, 6]).buffer.asUint8List());
    stream.played = 2;
    expect(await player.collectDoneSamples(), 2);
    expect(await player.collectDoneSamples(), 0);
    expect(await player.isIdle(), isTrue);
  });

  test('disposal releases a full queue without waiting for hardware', () async {
    await player.initialize();
    stream.capacity = 0;
    final writing = player.write(Int16List(1920));
    await player.dispose();
    await writing;
    expect(stream.closes, 1);
    expect(await player.isIdle(), isTrue);
  });

  test('32-bit PCM preserves all source bits and rejects incomplete frames', () async {
    player = PulseAudioPlayer(
      sampleRate: 48000,
      channels: 2,
      deviceId: -1,
      bitsPerSample: 32,
      validBitsPerSample: 24,
      createStream: () => stream,
    );
    await player.initialize();
    final samples = Int32List.fromList([-2147483648, 2147483392]);
    await player.writePcm32(samples);
    expect(stream.bits, 32);
    expect(stream.bytes, samples.buffer.asUint8List());
    await expectLater(player.writePcm32(Int32List(1)), throwsArgumentError);
    await expectLater(player.write(Int16List(2)), throwsArgumentError);
  });

  test('server failure reaches the playback owner instead of stalling', () async {
    await player.initialize();
    stream.failure = StateError('Server disconnected');
    await expectLater(player.write(Int16List(2)), throwsStateError);
    await expectLater(player.collectDoneSamples(), throwsStateError);
  });
}

class _FakeStream implements PulseAudioStream {
  bool opened = false;
  bool ready = true;
  bool paused = false;
  double volume = 1;
  int bits = 16;
  int capacity = 1000000;
  int closes = 0;
  int played = 0;
  Object? failure;
  final List<int> bytes = [];

  @override
  int get playedSamples => played;

  @override
  bool get isIdle => played >= bytes.length ~/ (bits ~/ 8);

  @override
  void open({required int sampleRate, required int channels, required int bitsPerSample}) {
    opened = true;
    bits = bitsPerSample;
  }

  @override
  bool poll() {
    if (failure != null) throw failure!;
    return ready;
  }

  @override
  int write(Uint8List data) {
    final count = data.length.clamp(0, capacity);
    bytes.addAll(data.take(count));
    capacity -= count;
    return count;
  }

  @override
  void flush() {
    bytes.clear();
    played = 0;
  }

  @override
  void setVolume(double value) => volume = value;

  @override
  void setPaused(bool value) => paused = value;

  @override
  void close() => closes++;
}
