import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/infrastructure/audio/output/audio_pcm_output.dart';
import 'package:phonolite_app/infrastructure/platform/audio/windows/wave_out_bindings.dart';
import 'package:phonolite_app/infrastructure/platform/audio/windows/wave_out_output.dart';

void main() {
  late _MemoryWaveOutBindings bindings;
  late WaveOutPlayer player;
  late int bindingCreations;

  setUp(() {
    bindings = _MemoryWaveOutBindings();
    bindingCreations = 0;
    player = WaveOutPlayer(
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

  test('default volume preserves the full signed PCM range', () async {
    final samples = Int16List.fromList([-32768, -1001, -1, 0, 1, 1001, 32767]);

    await player.initialize();
    await player.write(samples);

    expect(bindings.submitted.single, samples);
    expect(await player.collectDoneSamples(), samples.length);
    expect(await player.isIdle(), isTrue);
    expect(bindingCreations, 1);
  });

  test('volume changes make no native calls before or after initialization', () async {
    player.setVolume(0.25);

    expect(bindingCreations, 0);
    expect(bindings.calls, isEmpty);

    await player.initialize();

    expect(bindings.calls, ['open']);
    await player.write(Int16List.fromList([-32768, 32764]));
    expect(bindings.submitted.single, [-8192, 8191]);
    final callsBeforeChange = List<String>.of(bindings.calls);

    player.setVolume(0.75);

    expect(bindings.calls, callsBeforeChange);
    expect(bindingCreations, 1);
  });

  test('fractional volume scales submitted PCM without changing source samples', () async {
    final samples = Int16List.fromList([-32768, -1001, -3, -1, 0, 1, 3, 1001, 32767]);
    final original = List<int>.of(samples);
    player.setVolume(0.5);

    await player.initialize();
    await player.write(samples);

    expect(bindings.submitted.single, [-16384, -501, -2, -1, 0, 1, 2, 501, 16384]);
    expect(samples, original);
  });

  for (final volume in [0.0, -0.5]) {
    test('volume $volume submits silence', () async {
      final samples = Int16List.fromList([-32768, -3, 0, 3, 32767]);
      final original = List<int>.of(samples);
      player.setVolume(volume);

      await player.initialize();
      await player.write(samples);

      expect(bindings.submitted.single, [0, 0, 0, 0, 0]);
      expect(samples, original);
    });
  }

  for (final volume in [1.0, 1.5]) {
    test('volume $volume preserves PCM without overflow', () async {
      final samples = Int16List.fromList([-32768, -3, 0, 3, 32767]);
      player.setVolume(volume);

      await player.initialize();
      await player.write(samples);

      expect(bindings.submitted.single, samples);
    });
  }

  test('each new buffer uses the latest volume without compounding previous gain', () async {
    final samples = Int16List.fromList([-2000, 2000]);

    await player.initialize();
    player.setVolume(0.5);
    await player.write(samples);
    player.setVolume(0.25);
    await player.write(samples);
    player.setVolume(1);
    await player.write(samples);

    expect(bindings.submitted, [
      [-1000, 1000],
      [-500, 500],
      [-2000, 2000],
    ]);
    expect(samples, [-2000, 2000]);
    expect(bindingCreations, 1);
  });

  test('changing volume leaves a submitted native buffer untouched', () async {
    bindings.completeImmediately = false;
    final samples = Int16List.fromList([-2000, 2000]);

    await player.initialize();
    player.setVolume(0.5);
    await player.write(samples);
    final queued = bindings.pending.single;

    player.setVolume(0);

    expect(_readSamples(queued), [-1000, 1000]);
    await player.write(samples);
    expect(bindings.submitted.last, [0, 0]);
    expect(_readSamples(queued), [-1000, 1000]);
    expect(await player.isIdle(), isFalse);

    await player.flush();

    expect(bindings.pending, isEmpty);
    expect(await player.isIdle(), isTrue);
  });
}

List<int> _readSamples(ffi.Pointer<WAVEHDR> header) =>
    List<int>.of(header.ref.lpData.cast<ffi.Int16>().asTypedList(header.ref.dwBufferLength ~/ 2));

class _MemoryWaveOutBindings implements WaveOutBindings {
  final List<String> calls = [];
  final List<List<int>> submitted = [];
  final List<ffi.Pointer<WAVEHDR>> pending = [];
  bool completeImmediately = true;

  @override
  WaveOutOpenDart get waveOutOpen => (handle, deviceId, format, callback, instance, flags) {
    calls.add('open');
    handle.value = ffi.Pointer<ffi.Void>.fromAddress(1);

    return MMSYSERR_NOERROR;
  };

  @override
  WaveOutPrepareHeaderDart get waveOutPrepareHeader => (handle, header, size) {
    calls.add('prepare');

    return MMSYSERR_NOERROR;
  };

  @override
  WaveOutWriteDart get waveOutWrite => (handle, header, size) {
    calls.add('write');
    submitted.add(_readSamples(header));

    if (completeImmediately) {
      header.ref.dwFlags |= WHDR_DONE;
    } else {
      pending.add(header);
    }

    return MMSYSERR_NOERROR;
  };

  @override
  WaveOutUnprepareHeaderDart get waveOutUnprepareHeader => (handle, header, size) {
    calls.add('unprepare');
    pending.remove(header);

    return MMSYSERR_NOERROR;
  };

  @override
  WaveOutResetDart get waveOutReset => (handle) {
    calls.add('reset');

    return MMSYSERR_NOERROR;
  };

  @override
  WaveOutCloseDart get waveOutClose => (handle) {
    calls.add('close');

    return MMSYSERR_NOERROR;
  };

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected native binding call: ${invocation.memberName}');
}
