import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/infrastructure/audio/output/audio_pcm_output.dart';
import 'package:phonolite_app/infrastructure/platform/audio/windows/xaudio2_bindings.dart';
import 'package:phonolite_app/infrastructure/platform/audio/windows/xaudio2_output.dart';

void main() {
  late _MemoryXAudio2Bindings bindings;
  late XAudio2Player player;
  late int bindingCreations;

  setUp(() {
    bindings = _MemoryXAudio2Bindings();
    bindingCreations = 0;
    player = XAudio2Player(
      sampleRate: 48000,
      channels: 2,
      deviceId: kDefaultOutputDeviceId,
      bindingsFactory: () {
        bindingCreations++;
        return bindings;
      },
    );
  });

  tearDown(() => player.dispose());

  test('construction and unused disposal do not load native bindings', () async {
    player.setVolume(0.25);
    expect(bindingCreations, 0);
    expect(bindings.calls, isEmpty);

    await player.dispose();
    await player.dispose();
    player.setVolume(0.75);
    await player.write(Int16List.fromList([-1000, 1000]));

    expect(bindingCreations, 0);
    expect(bindings.calls, isEmpty);
  });

  test('initialization opens once and applies the latest saved volume', () async {
    player.setVolume(0.75);
    player.setVolume(0.25);
    await player.initialize();
    await player.initialize();

    expect(bindingCreations, 1);
    expect(bindings.openedConfiguration, (48000, 2, kDefaultOutputDeviceId));
    expect(bindings.calls, ['open', 'volume']);
    expect(bindings.volumes, [0.25]);
  });

  test('default volume initializes at unity gain', () async {
    await player.initialize();
    expect(bindings.volumes, [1.0]);
  });

  test('Original retains PCM32 precision and source rate across the native bridge', () async {
    final original = XAudio2Player(
      sampleRate: 192000,
      channels: 2,
      deviceId: kDefaultOutputDeviceId,
      bitsPerSample: 32,
      validBitsPerSample: 24,
      bindingsFactory: () => bindings,
    );
    addTearDown(original.dispose);
    final samples = Int32List.fromList([-2147483648, 2147483392, -256, 256]);

    await original.initialize();
    await original.writePcm32(samples);

    expect(bindings.openedFormat, (192000, 2, kDefaultOutputDeviceId, 32, 24));
    expect(bindings.pending.single, samples);
    await expectLater(original.write(Int16List(2)), throwsStateError);
  });

  test('fractional gain and mute keep queued PCM raw and update the native voice immediately', () async {
    final samples = Int16List.fromList([-32768, -1001, -1, 0, 1, 1001, 32767, 32766]);
    final original = List<int>.of(samples);

    await player.initialize();
    player.setVolume(0.5);
    await player.write(samples);
    final callsBeforeMute = bindings.calls.length;

    player.setVolume(0);

    expect(bindings.calls.skip(callsBeforeMute), ['volume']);
    expect(bindings.volumes, [1.0, 0.5, 0.0]);
    expect(bindings.pending.single, original);
    expect(samples, original);

    await player.write(samples);
    player.setVolume(0.5);

    expect(bindings.pending, [original, original]);
    expect(bindings.volumes.last, 0.5);
    expect(bindings.calls.where((call) => call == 'flush'), isEmpty);
    expect(bindings.calls.where((call) => call == 'open'), hasLength(1));
  });

  test('native gain is updated while a full queue blocks a write', () async {
    await player.initialize();
    bindings.queueFull = true;
    final samples = Int16List.fromList([-2000, 2000]);
    final writing = player.write(samples);
    await Future<void>.delayed(Duration.zero);
    expect(bindings.writeAttempts, greaterThan(0));
    expect(bindings.pending, isEmpty);

    player.setVolume(0);
    expect(bindings.volumes.last, 0.0);
    expect(bindings.calls.last, 'volume');

    bindings.queueFull = false;
    await writing.timeout(const Duration(seconds: 1));
    expect(bindings.pending.single, [-2000, 2000]);
  });

  test('gain changes while paused do not resume or rebuild the voice', () async {
    await player.initialize();
    await player.write(Int16List.fromList([-2000, 2000]));
    player.pause();
    final callsBeforeMute = bindings.calls.length;

    player.setVolume(0);

    expect(bindings.paused, isTrue);
    expect(bindings.calls.skip(callsBeforeMute), ['volume']);
    expect(bindings.pending.single, [-2000, 2000]);
    player.resume();
    expect(bindings.paused, isFalse);
    expect(bindings.volumes.last, 0.0);
  });

  test('volume is clamped without changing Windows mixer or queued samples', () async {
    await player.initialize();
    player.setVolume(-1);
    player.setVolume(2);
    expect(bindings.volumes, [1.0, 0.0, 1.0]);
    expect(bindings.calls, ['open', 'volume', 'volume', 'volume']);
  });

  test('flush invalidates a blocked write and permits fresh PCM afterward', () async {
    await player.initialize();
    bindings.queueFull = true;
    final blocked = player.write(Int16List.fromList([-2000, 2000]));
    await Future<void>.delayed(Duration.zero);
    final attemptsBeforeFlush = bindings.writeAttempts;

    await player.flush();
    bindings.queueFull = false;
    await blocked.timeout(const Duration(seconds: 1));

    expect(bindings.writeAttempts, attemptsBeforeFlush);
    expect(bindings.pending, isEmpty);
    await player.write(Int16List.fromList([-3000, 3000]));
    expect(bindings.pending.single, [-3000, 3000]);
  });

  test('disposal cancels a blocked write and releases the native voice once', () async {
    await player.initialize();
    bindings.queueFull = true;
    final blocked = player.write(Int16List.fromList([-2000, 2000]));
    await Future<void>.delayed(Duration.zero);
    final attemptsBeforeClose = bindings.writeAttempts;

    await player.dispose();
    await player.dispose();
    bindings.queueFull = false;
    await blocked.timeout(const Duration(seconds: 1));
    player.setVolume(0.5);

    expect(bindings.writeAttempts, attemptsBeforeClose);
    expect(bindings.calls.where((call) => call == 'close'), hasLength(1));
    expect(bindings.calls.last, 'close');
    expect(bindings.pending, isEmpty);
    expect(await player.isIdle(), isTrue);
  });

  test('native sample completion and idle status reach the playback session', () async {
    await player.initialize();
    await player.write(Int16List.fromList([-2000, 2000, -1000, 1000]));
    expect(await player.isIdle(), isFalse);

    bindings.completeQueuedAudio();

    expect(await player.collectDoneSamples(), 4);
    expect(await player.collectDoneSamples(), 0);
    expect(await player.isIdle(), isTrue);
  });

  test('empty PCM does not submit a native buffer', () async {
    await player.initialize();
    await player.write(Int16List(0));
    expect(bindings.writeAttempts, 0);
    expect(bindings.pending, isEmpty);
  });

  test('a native write failure is reported instead of retried indefinitely', () async {
    await player.initialize();
    bindings.writeError = -1;
    await expectLater(player.write(Int16List.fromList([-2000, 2000])), throwsStateError);
    expect(bindings.writeAttempts, 1);
  });

  test('a native volume failure is surfaced immediately', () async {
    await player.initialize();
    bindings.volumeError = -1;
    expect(() => player.setVolume(0), throwsStateError);
  });

  test('a failed native open is reported without treating a null handle as live', () async {
    bindings.failOpen = true;
    await expectLater(player.initialize(), throwsStateError);
    await player.dispose();
    expect(bindings.calls.where((call) => call == 'close'), isEmpty);
    expect(await player.isIdle(), isTrue);
  });
}

class _MemoryXAudio2Bindings implements XAudio2Bindings {
  final List<String> calls = [];
  final List<double> volumes = [];
  final List<List<int>> pending = [];
  (int, int, int)? openedConfiguration;
  (int, int, int, int, int)? openedFormat;
  bool queueFull = false;
  bool paused = false;
  bool failOpen = false;
  int writeAttempts = 0;
  int writeError = 0;
  int volumeError = 0;
  int completedSamples = 0;

  @override
  ffi.Pointer<ffi.Void> Function(int, int, int) get open => (sampleRate, channels, deviceId) {
    calls.add('open');
    openedConfiguration = (sampleRate, channels, deviceId);
    return failOpen ? ffi.nullptr : ffi.Pointer<ffi.Void>.fromAddress(1);
  };

  @override
  XAudio2OpenFormatDart get openFormat => (sampleRate, channels, deviceId, bitsPerSample, validBitsPerSample) {
    openedFormat = (sampleRate, channels, deviceId, bitsPerSample, validBitsPerSample);
    return open(sampleRate, channels, deviceId);
  };

  @override
  void Function(ffi.Pointer<ffi.Void>) get close => (handle) {
    calls.add('close');
    pending.clear();
  };

  @override
  int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Int16>, int) get write => (handle, samples, sampleCount) {
    calls.add('write');
    writeAttempts++;
    if (writeError != 0) return writeError;
    if (queueFull) return xaudio2QueueFull;
    pending.add(List<int>.of(samples.asTypedList(sampleCount)));
    return xaudio2Ok;
  };

  @override
  XAudio2Write32Dart get write32 => (handle, samples, sampleCount) {
    pending.add(List<int>.of(samples.asTypedList(sampleCount)));
    return xaudio2Ok;
  };

  @override
  int Function(ffi.Pointer<ffi.Void>) get flush => (handle) {
    calls.add('flush');
    pending.clear();
    completedSamples = 0;
    return xaudio2Ok;
  };

  @override
  int Function(ffi.Pointer<ffi.Void>, double) get setVolume => (handle, volume) {
    calls.add('volume');
    volumes.add(volume);
    return volumeError;
  };

  @override
  int Function(ffi.Pointer<ffi.Void>) get pause => (handle) {
    calls.add('pause');
    paused = true;
    return xaudio2Ok;
  };

  @override
  int Function(ffi.Pointer<ffi.Void>) get resume => (handle) {
    calls.add('resume');
    paused = false;
    return xaudio2Ok;
  };

  @override
  int Function(ffi.Pointer<ffi.Void>) get collectDoneSamples => (handle) {
    final samples = completedSamples;
    completedSamples = 0;
    return samples;
  };

  @override
  int Function(ffi.Pointer<ffi.Void>) get isIdle =>
      (handle) => pending.isEmpty ? 1 : 0;

  void completeQueuedAudio() {
    completedSamples += pending.fold<int>(0, (total, samples) => total + samples.length);
    pending.clear();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected native binding call: ${invocation.memberName}');
}
