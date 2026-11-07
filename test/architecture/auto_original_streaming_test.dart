import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_opus/phonolite_opus.dart';

import 'package:phonolite_app/data/models/audio/audio_file_format.dart';
import 'package:phonolite_app/data/structures/audio/audio_auto_quality_history.dart';
import 'package:phonolite_app/data/structures/audio/pcm_stream_converter.dart';
import 'package:phonolite_app/infrastructure/audio/decoding/audio_file_decoder.dart';
import 'package:phonolite_app/infrastructure/audio/engine/audio_engine.dart';

import '../support/streaming_test_helpers.dart';

class _Original extends AudioFileDecoder {
  final Duration start;
  final bool mismatch;
  late int _frame = start.inMilliseconds * 44100 ~/ 1000;
  bool blocked = false;
  bool closed = false;
  final seekPositions = <Duration>[];
  Completer<Int32List>? _pending;
  PcmStreamConverter? _converter;
  bool _ended = false;

  _Original(this.start, {this.mismatch = false}) : super.local(filePath: 'unused');

  @override
  AudioFileFormat get format =>
      const AudioFileFormat(sampleRate: 44100, channels: 2, bitDepth: 24, duration: Duration(seconds: 30));

  @override
  Map<String, dynamic> get sourceMetadata => {
    'source_version': mismatch ? 'changed-file' : 'pinned-file',
    'total_length': 1000000,
  };

  @override
  Future<void> initialize() async {}

  @override
  Future<Duration> seek(Duration position) async {
    seekPositions.add(position);
    _frame = position.inMilliseconds * format.sampleRate ~/ 1000;
    _converter = null;
    _ended = false;
    return position;
  }

  @override
  Future<Int32List> read32(int maxSamples) async {
    if (blocked) {
      _pending = Completer<Int32List>();
      return _pending!.future;
    }
    final frames = math.min(maxSamples ~/ 2, 30 * 44100 - _frame);
    _frame += frames;
    return Int32List(frames * 2)..fillRange(0, frames * 2, 70000);
  }

  @override
  Future<Int32List> readNormalized32({required int outputRate, required int outputChannels}) async {
    if (_ended) {
      return Int32List(0);
    }
    _converter ??= PcmStreamConverter(
      inputRate: format.sampleRate,
      inputChannels: format.channels,
      outputRate: outputRate,
      outputChannels: outputChannels,
    );
    final samples = await read32(format.sampleRate * format.channels ~/ 5);
    _ended = samples.isEmpty;
    return _converter!.process(samples, endOfInput: _ended) as Int32List;
  }

  @override
  void reportPlayableMilliseconds(int milliseconds) {}

  @override
  void interruptRead() {
    final pending = _pending;
    if (pending != null && !pending.isCompleted) pending.completeError(StateError('interrupted'));
  }

  @override
  Future<void> close() async {
    closed = true;
    interruptRead();
  }
}

class _Output extends MemoryPcmOutput {
  final int channels;
  final samples = <int>[];
  int played = 0;
  int _pendingDone = 0;

  _Output({this.channels = 2});

  void advance() {
    final count = math.min(4800 * channels, samples.length - played);
    played += count;
    _pendingDone += count;
  }

  @override
  Future<void> writePcm32(Int32List values) async {
    final generation = epoch;
    while (samples.length - played >= 48000 * channels ~/ 8 && !disposed && generation == epoch) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    if (disposed || generation != epoch) {
      return;
    }
    samples.addAll(values);
    await super.writePcm32(values);
  }

  @override
  Future<int> collectDoneSamples() async {
    final result = _pendingDone;
    _pendingDone = 0;
    return result;
  }

  @override
  Future<void> flush() async {
    await super.flush();
    samples.clear();
    played = 0;
    _pendingDone = 0;
  }

  @override
  Future<bool> isIdle() async => played == samples.length;
}

MemoryQuic _transport({bool original = true}) {
  final transport = MemoryQuic();
  transport.onRequest = (start, seekId) {
    transport.deliverRange(
      startMs: start,
      endMs: math.min(30000, start + 5000),
      durationMs: 30000,
      seekId: seekId,
      bitrateBps: 160000,
      adaptiveRanges: true,
      endOfTrack: start >= 25000,
    );
    if (original) {
      transport.events.last['original'] = {
        'source_version': 'pinned-file',
        'total_length': 1000000,
        'duration_ms': 30000,
      };
    }
  };
  return transport;
}

Future<void> _play(AudioPlaybackHarness harness, _Output output, FutureOr<void> Function(int) tick) async {
  for (var step = 0; step < 4000; step++) {
    await tick(step);
    output.advance();
    await harness.collectStats();
    if (harness.messages.any((event) => event['type'] == 'complete')) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 3));
  }
  fail('Playback did not complete: ${harness.messages.where((e) => e['type'] == 'message').toList()}');
}

void main() {
  final opusLibrary = Platform.environment['PHONOLITE_OPUS_LIBRARY'];
  final localLibrary = Platform.environment['PHONOLITE_LOCAL_AUDIO_LIBRARY'];
  final native =
      opusLibrary != null && localLibrary != null && File(opusLibrary).existsSync() && File(localLibrary).existsSync();
  if (native) ffi.DynamicLibrary.open(opusLibrary);

  test('audible OG carries to the first samples of the next track without flushing', () async {
    var now = Duration.zero;
    final history = AudioAutoQualityHistory(now: () => now);
    final firstOutput = _Output();
    final first = AudioPlaybackHarness(
      transport: _transport(),
      settings: const StreamSettings(mode: 'auto', quality: 'high'),
      autoQualityHistory: history,
      autoOriginalNow: () => now,
      decoderFactory: MemoryOpusDecoder.new,
      originalDecoderFactory: (_, start) => _Original(start),
      outputFactory: (_, __, ___) => firstOutput,
    );
    addTearDown(first.close);
    first.start();
    for (var step = 0; step < 1500; step++) {
      now += const Duration(milliseconds: 100);
      firstOutput.advance();
      await first.collectStats();
      if (first.messages.any((event) => event['stream_quality'] == 'original')) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 3));
    }
    expect(first.messages.any((event) => event['stream_quality'] == 'original'), isTrue);
    first.notifyNetworkChange(1);
    await first.collectStats();
    expect(
      history.mayWarmOriginal(
        AudioAutoQualityHistory.scope(
          endpoint: 'http://test.local:3000|null',
          token: '',
          serverPin: '',
          routeGeneration: 1,
        ),
      ),
      isFalse,
      reason: 'Queued Original from the previous route cannot validate the new network.',
    );
    await first.close();

    final secondOutput = _Output();
    _Original? nextOriginal;
    final second = AudioPlaybackHarness(
      transport: _transport(),
      settings: const StreamSettings(mode: 'auto', quality: 'high'),
      autoQualityHistory: history,
      autoOriginalNow: () => now,
      decoderFactory: MemoryOpusDecoder.new,
      originalDecoderFactory: (_, start) => nextOriginal = _Original(start),
      outputFactory: (_, __, ___) => secondOutput,
    );
    addTearDown(second.close);
    second.start();
    await waitUntil(() => secondOutput.samples.isNotEmpty);
    expect(nextOriginal!.start, Duration.zero);
    final transitions = second.messages.where(
      (event) => event['text']?.toString().contains('Auto Original transition: OG at_frame=0 ') == true,
    );
    expect(transitions, hasLength(1));
    expect(secondOutput.flushes, 0);
    await second.close();
  });

  test('a slow new Original file cannot hold a remembered-quality startup beyond its budget', () async {
    final history = AudioAutoQualityHistory();
    history.rememberOriginal(
      AudioAutoQualityHistory.scope(
        endpoint: 'http://test.local:3000|null',
        token: '',
        serverPin: '',
        routeGeneration: 0,
      ),
    );
    final output = _Output();
    final original = _PendingOriginal(Duration.zero);
    final harness = AudioPlaybackHarness(
      transport: _transport(),
      settings: const StreamSettings(mode: 'auto', quality: 'high'),
      autoQualityHistory: history,
      decoderFactory: MemoryOpusDecoder.new,
      originalDecoderFactory: (_, __) => original,
      outputFactory: (_, __, ___) => output,
    );
    addTearDown(harness.close);
    final elapsed = Stopwatch()..start();
    harness.start();
    await waitUntil(() => output.samples.isNotEmpty);
    expect(elapsed.elapsed, lessThan(const Duration(seconds: 2)));
    expect(original.ready.isCompleted, isFalse);
    expect(
      harness.messages.any((event) => event['text']?.toString().contains('Auto Original transition: OG') == true),
      isFalse,
    );
    original.ready.complete();
    await harness.close();
  });

  test('stop cancels a remembered Original startup before any PCM is accepted', () async {
    final history = AudioAutoQualityHistory();
    history.rememberOriginal(
      AudioAutoQualityHistory.scope(
        endpoint: 'http://test.local:3000|null',
        token: '',
        serverPin: '',
        routeGeneration: 0,
      ),
    );
    final output = _Output();
    _PendingOriginal? original;
    final harness = AudioPlaybackHarness(
      transport: _transport(),
      settings: const StreamSettings(mode: 'auto', quality: 'high'),
      autoQualityHistory: history,
      decoderFactory: MemoryOpusDecoder.new,
      originalDecoderFactory: (_, start) => original = _PendingOriginal(start),
      outputFactory: (_, __, ___) => output,
    );
    addTearDown(harness.close);
    harness.start();
    await waitUntil(() => original != null);
    await harness.requestStop();
    expect(original!.closed, isTrue);
    expect(output.samples, isEmpty);
  });

  test('decoder-worker conversion drains exact EOF frames and resets on seek', () async {
    final fixture = {
      'original_sample_rate': 44100,
      'duration_ms': 1200,
      'angular_frequency': 0.0576,
      'amplitude': 10000,
    };
    final directory = await Directory.systemTemp.createTemp('phonolite-normalized-decoder-');
    addTearDown(() => directory.delete(recursive: true));
    final wave = _wave(fixture);
    final path = '${directory.path}/original.wav';
    await File(path).writeAsBytes(wave);
    final decoder = AudioFileDecoder.local(filePath: path);
    addTearDown(decoder.close);
    await decoder.initialize();
    var frames = 0;
    while (true) {
      final samples = await decoder.readNormalized32(outputRate: 48000, outputChannels: 1);
      if (samples.isEmpty) {
        break;
      }
      frames += samples.length;
    }
    expect(frames, 57600);
    expect(await decoder.readNormalized32(outputRate: 48000, outputChannels: 1), isEmpty);
    await expectLater(decoder.read32(1), throwsStateError);
    await decoder.seek(const Duration(milliseconds: 500));
    final expected = ByteData.sublistView(wave).getInt16(44 + 22050 * 2, Endian.little) << 16;
    expect(await decoder.read32(1), [expected]);
  }, skip: native ? false : 'Set PHONOLITE_OPUS_LIBRARY and PHONOLITE_LOCAL_AUDIO_LIBRARY.');

  test('an output without PCM32 support retains the live gapless lease on compressed Auto', () async {
    final formats = <int>[];
    final output = MemoryPcmOutput();
    final harness = GaplessPlaybackHarness(
      outputFactory: (_, __, ___, bits, ____) {
        formats.add(bits);
        return bits == 32 ? _UnsupportedOutput() : output;
      },
      decoderFactory: MemoryOpusDecoder.new,
      transportFactory: (_) => _transport(original: false),
    );
    addTearDown(harness.close);
    await harness.playOpus('track', mode: 'auto');
    await waitUntil(() => harness.messages.any((e) => e['type'] == 'complete'));
    expect(formats, [32, 16]);
    expect(output.samplesWritten, 30 * 48000 * 2);
    expect(harness.messages.any((e) => e['text']?.toString().contains('Playback failed:') == true), isFalse);
  });

  test('real Opus and Original decoders share exact frames across both handoffs', () async {
    final fixture = jsonDecode(File('test/fixtures/audio/auto_original_ranges.json').readAsStringSync()) as Map;
    final directory = await Directory.systemTemp.createTemp('phonolite-auto-original-');
    addTearDown(() => directory.delete(recursive: true));
    final wave = _wave(fixture);
    final path = '${directory.path}/original.wav';
    await File(path).writeAsBytes(wave);
    final descriptor = {
      'source_version': 'pinned-file',
      'total_length': wave.length,
      'duration_ms': fixture['duration_ms'],
    };
    final transport = MemoryQuic();
    final ranges = (fixture['ranges'] as List).cast<Map>();
    final delayed = <Uint8List>[];
    transport.onRequest = (start, seekId) {
      final range = ranges.singleWhere((range) => range['start_ms'] == start);
      transport.events.add({
        'type': 'stream',
        'request_id': transport.requestId,
        'position_ms': start,
        'range_end_ms': range['end_ms'],
        'end_of_track': range['end_ms'] == fixture['duration_ms'],
        'source_version': 'opus-file',
        'adaptive_ranges': true,
        'original': descriptor,
      });
      if (seekId != null) {
        final marker = Uint8List(6)..setAll(0, [255, 255]);
        ByteData.sublistView(marker).setUint32(2, seekId, Endian.little);
        transport.chunks.add(marker);
      }
      final payload = base64Decode(range['payload'] as String);
      if (start == 15000) {
        delayed.add(payload);
      } else {
        transport.chunks.add(payload);
      }
    };
    final output = _Output(channels: 1);
    _NativeOriginal? original;
    var now = Duration.zero;
    var opened = 0;
    final harness = AudioPlaybackHarness(
      transport: transport,
      settings: const StreamSettings(mode: 'auto', quality: 'high'),
      decoderFactory: (rate, channels) => OpusDecoder(sampleRate: rate, channels: channels),
      originalDecoderFactory: (_, start) => original = _NativeOriginal(path, start, descriptor),
      autoOriginalNow: () => now,
      outputFactory: (_, __, ___) {
        opened++;
        return output;
      },
    );
    addTearDown(harness.close);
    harness.start();
    var waited = false;
    var starved = false;
    await _play(harness, output, (_) async {
      now = Duration(milliseconds: output.played * 1000 ~/ 48000);
      if (output.played >= 16000 * 48 && delayed.isNotEmpty) {
        transport.chunks.addAll(delayed);
        delayed.clear();
      }
      if (original != null && !waited) {
        waited = true;
        // Hold the simulated device clock while the real worker starts and
        // fills its ahead buffer; no real device or network is started.
        await waitUntil(() => original!.delivered >= 6 * 44100);
      }
      if (!starved &&
          harness.messages.any((e) => e['text']?.toString().startsWith('Auto Original transition: OG') == true)) {
        starved = true;
        original!.blocked = true;
      }
    });
    final transitions = harness.messages
        .where((e) => e['text']?.toString().startsWith('Auto Original transition:') == true)
        .toList();
    expect(transitions, hasLength(2));
    expect(output.samples, hasLength(20 * 48000));
    expect(opened, 1);
    expect(output.flushes, 0);
    for (final transition in transitions) {
      final center = int.parse(RegExp(r'at_frame=(\d+)').firstMatch(transition['text'] as String)!.group(1)!);
      var error = 0.0;
      var energy = 0.0;
      for (var index = center - 240; index < center + 720; index++) {
        final expected = math.sin(index * (fixture['angular_frequency'] as num)) * (fixture['amplitude'] as num);
        error += math.pow((output.samples[index] >> 16) - expected, 2);
        energy += expected * expected;
      }
      expect(error / energy, lessThan(0.05), reason: transition['text'] as String);
    }
    expect(original!.closed, isTrue);
    expect(harness.messages.any((e) => e['text']?.toString().startsWith('Buffer low:') == true), isFalse);
  }, skip: native ? false : 'Set PHONOLITE_OPUS_LIBRARY and PHONOLITE_LOCAL_AUDIO_LIBRARY.');

  for (final seeking in [false, true]) {
    test('${seeking ? 'seek' : 'stop'} cancels pending Original preparation before releasing the session', () async {
      final output = _Output();
      _PendingOriginal? original;
      var now = Duration.zero;
      final harness = AudioPlaybackHarness(
        transport: _transport(),
        settings: const StreamSettings(mode: 'auto', quality: 'high'),
        decoderFactory: MemoryOpusDecoder.new,
        originalDecoderFactory: (_, start) => original = _PendingOriginal(start),
        autoOriginalNow: () => now,
        outputFactory: (_, __, ___) => output,
      );
      addTearDown(harness.close);
      harness.start();
      for (var step = 0; step < 200 && original == null; step++) {
        now = Duration(milliseconds: output.played * 1000 ~/ 96000);
        output.advance();
        await harness.collectStats();
        await Future<void>.delayed(const Duration(milliseconds: 3));
      }
      expect(original, isNotNull);
      if (seeking) {
        expect(await harness.seek(const Duration(seconds: 18)), isTrue);
        expect(output.flushes, 1);
        expect(output.samples.take(500).every((sample) => sample == 65536), isTrue);
      } else {
        await harness.requestStop().timeout(const Duration(seconds: 1));
      }
      expect(original!.closed, isTrue);
      expect(harness.messages.any((e) => e['type'] == 'stats' && e['stream_quality'] == 'original'), isFalse);
    });
  }

  test('slow Original initialization retargets ahead while compressed playback continues', () async {
    final output = _Output();
    _PendingOriginal? original;
    var now = Duration.zero;
    final harness = AudioPlaybackHarness(
      transport: _transport(),
      settings: const StreamSettings(mode: 'auto', quality: 'high'),
      decoderFactory: MemoryOpusDecoder.new,
      originalDecoderFactory: (_, start) => original = _PendingOriginal(start),
      autoOriginalNow: () => now,
      outputFactory: (_, __, ___) => output,
    );
    addTearDown(harness.close);
    harness.start();
    await _play(harness, output, (_) {
      now = Duration(milliseconds: output.played * 1000 ~/ 96000);
      final source = original;
      if (source != null && !source.ready.isCompleted && now >= source.start + const Duration(seconds: 3)) {
        source.ready.complete();
      }
    });
    expect(original, isNotNull);
    expect(original!.seekPositions.single, greaterThan(original!.start));
    expect(harness.messages.any((e) => e['type'] == 'stats' && e['stream_quality'] == 'original'), isTrue);
    expect(output.samples, hasLength(30 * 48000 * 2));
    expect(output.flushes, 0);
    expect(harness.messages.any((e) => e['text']?.toString().startsWith('Buffer low:') == true), isFalse);
  });

  test('Original reaches track end while the final compressed range is unavailable', () async {
    final output = _Output();
    final transport = _transport();
    final request = transport.onRequest!;
    transport.onRequest = (start, seekId) {
      if (start != 25000) request(start, seekId);
    };
    var now = Duration.zero;
    final harness = AudioPlaybackHarness(
      transport: transport,
      settings: const StreamSettings(mode: 'auto', quality: 'high'),
      decoderFactory: MemoryOpusDecoder.new,
      originalDecoderFactory: (_, start) => _Original(start),
      autoOriginalNow: () => now,
      outputFactory: (_, __, ___) => output,
    );
    addTearDown(harness.close);
    harness.start();
    await _play(harness, output, (_) => now = Duration(milliseconds: output.played * 1000 ~/ 96000));
    expect(transport.requestedPositions, contains(25000));
    expect(output.samples, hasLength(30 * 48000 * 2));
    expect(harness.messages.lastWhere((e) => e['type'] == 'stats')['stream_quality'], 'original');
    expect(harness.messages.where((e) => e['type'] == 'complete'), hasLength(1));
    expect(harness.messages.any((e) => e['text']?.toString().startsWith('Buffer low:') == true), isFalse);
  });

  test('Auto changes to Original mid-track and falls back without reopening or losing frames', () async {
    final output = _Output();
    final originals = <_Original>[];
    var now = Duration.zero;
    var opens = 0;
    final harness = AudioPlaybackHarness(
      transport: _transport(),
      settings: const StreamSettings(mode: 'auto', quality: 'high'),
      decoderFactory: MemoryOpusDecoder.new,
      originalDecoderFactory: (_, start) {
        final source = _Original(start);
        originals.add(source);
        return source;
      },
      autoOriginalNow: () => now,
      outputFactory: (_, __, ___) {
        opens++;
        return output;
      },
    );
    addTearDown(harness.close);
    harness.start();
    var starved = false;
    var maximumOriginalReserve = 0;
    await _play(harness, output, (step) {
      now = Duration(milliseconds: output.played * 1000 ~/ (48000 * 2));
      maximumOriginalReserve = math.max(maximumOriginalReserve, harness.originalReserveMilliseconds);
      if (!starved &&
          harness.messages.any((e) => e['text']?.toString().startsWith('Auto Original transition: OG') == true)) {
        starved = true;
        originals.last.blocked = true;
      }
    });
    final transitions = harness.messages
        .where((e) => e['text']?.toString().startsWith('Auto Original transition:') == true)
        .toList();
    expect(transitions.length, greaterThanOrEqualTo(2));
    expect(transitions.first['text'], contains('OG'));
    expect(transitions[1]['text'], contains('high'));
    expect(
      maximumOriginalReserve,
      greaterThan(2000),
      reason: 'Prepared Original reserve remains observable after rendering.',
    );
    expect(opens, 1);
    expect(output.flushes, 0);
    expect(output.samples, hasLength(30 * 48000 * 2));
    expect(
      output.samples.any((value) => value == 70000),
      isTrue,
      reason: 'Original precision survives resampling and output.',
    );
    expect(output.samples.every((value) => value >= 65536 && value <= 70000), isTrue);
    expect(harness.messages.where((e) => e['type'] == 'started'), hasLength(1));
    expect(harness.messages.any((e) => e['type'] == 'stats' && e['stream_quality'] == 'original'), isTrue);
    expect(harness.messages.lastWhere((e) => e['type'] == 'stats')['stream_quality'], 'high');
    expect(originals.every((source) => source.closed), isTrue);
  });

  for (final failure in ['identity', 'missing', 'factory']) {
    final missing = failure == 'missing';
    test('Original $failure retains compressed playback', () async {
      final output = _Output();
      var now = Duration.zero;
      var probes = 0;
      final harness = AudioPlaybackHarness(
        transport: _transport(original: !missing),
        settings: const StreamSettings(mode: 'auto', quality: 'high'),
        decoderFactory: MemoryOpusDecoder.new,
        originalDecoderFactory: (_, start) {
          probes++;
          if (failure == 'factory') {
            throw StateError('Original unavailable');
          }
          return _Original(start, mismatch: true);
        },
        autoOriginalNow: () => now,
        outputFactory: (_, __, ___) => output,
      );
      addTearDown(harness.close);
      harness.start();
      await _play(harness, output, (step) => now = Duration(milliseconds: output.played * 1000 ~/ (48000 * 2)));
      expect(probes, missing ? 0 : greaterThan(0));
      expect(output.samples, hasLength(30 * 48000 * 2));
      expect(output.samples.every((value) => value == 65536), isTrue);
      expect(harness.messages.any((e) => e['type'] == 'stats' && e['stream_quality'] == 'original'), isFalse);
    });
  }
}

class _NativeOriginal extends AudioFileDecoder {
  final AudioFileDecoder decoder;
  final Map<String, dynamic> descriptor;
  bool blocked = false, closed = false;
  int delivered = 0;
  Completer<Int32List>? _pending;

  _NativeOriginal(String path, Duration start, this.descriptor)
    : decoder = AudioFileDecoder.local(filePath: path, startOffset: start),
      super.local(filePath: 'unused');

  @override
  AudioFileFormat get format => decoder.format;
  @override
  Map<String, dynamic> get sourceMetadata => descriptor;
  @override
  Future<void> initialize() => decoder.initialize();
  @override
  Future<Duration> seek(Duration position) => decoder.seek(position);
  @override
  void reportPlayableMilliseconds(int milliseconds) {}
  @override
  Future<Int32List> read32(int maxSamples) async {
    if (blocked) {
      _pending = Completer<Int32List>();
      return _pending!.future;
    }
    final samples = await decoder.read32(maxSamples);
    delivered += samples.length ~/ format.channels;
    return samples;
  }

  @override
  Future<Int32List> readNormalized32({required int outputRate, required int outputChannels}) async {
    if (blocked) {
      _pending = Completer<Int32List>();
      return _pending!.future;
    }
    final samples = await decoder.readNormalized32(outputRate: outputRate, outputChannels: outputChannels);
    delivered += samples.length ~/ outputChannels * format.sampleRate ~/ outputRate;
    return samples;
  }

  @override
  void interruptRead() {
    final pending = _pending;
    if (pending != null && !pending.isCompleted) pending.completeError(StateError('interrupted'));
    decoder.interruptRead();
  }

  @override
  Future<void> close() async {
    closed = true;
    interruptRead();
    await decoder.close();
  }
}

class _PendingOriginal extends _Original {
  final Completer<void> ready = Completer<void>();

  _PendingOriginal(super.start);

  @override
  Future<void> initialize() => ready.future;

  @override
  Future<void> close() async {
    if (!ready.isCompleted) ready.completeError(StateError('cancelled initialization'));
    await super.close();
  }
}

class _UnsupportedOutput extends MemoryPcmOutput {
  @override
  Future<void> initialize() async => throw StateError('PCM32 unavailable');
}

Uint8List _wave(Map fixture) {
  final rate = fixture['original_sample_rate'] as int;
  final frames = rate * (fixture['duration_ms'] as int) ~/ 1000;
  final wave = Uint8List(44 + frames * 2);
  wave.setAll(0, 'RIFF'.codeUnits);
  wave.setAll(8, 'WAVEfmt '.codeUnits);
  wave.setAll(36, 'data'.codeUnits);
  final view = ByteData.sublistView(wave);
  view.setUint32(4, wave.length - 8, Endian.little);
  view.setUint32(16, 16, Endian.little);
  view.setUint16(20, 1, Endian.little);
  view.setUint16(22, 1, Endian.little);
  view.setUint32(24, rate, Endian.little);
  view.setUint32(28, rate * 2, Endian.little);
  view.setUint16(32, 2, Endian.little);
  view.setUint16(34, 16, Endian.little);
  view.setUint32(40, frames * 2, Endian.little);
  for (var frame = 0; frame < frames; frame++) {
    final sample =
        (math.sin(frame * (fixture['angular_frequency'] as num) * 48000 / rate) * (fixture['amplitude'] as num))
            .toInt();
    view.setInt16(44 + frame * 2, sample, Endian.little);
  }
  return wave;
}
