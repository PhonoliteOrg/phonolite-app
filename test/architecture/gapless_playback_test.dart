import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/data/models/audio/audio_file_format.dart';
import 'package:phonolite_app/data/models/audio/audio_source_rejected.dart';
import 'package:phonolite_app/infrastructure/audio/decoding/audio_file_decoder.dart';
import 'package:phonolite_app/infrastructure/audio/engine/audio_engine.dart';

import '../support/streaming_test_helpers.dart';

/// All audio, clocks and decoders are memory objects. These checks exercise the
/// production worker without launching a device, isolate, socket or server.
void main() {
  test('a seek joining a tail cancellation still releases the submitted head', () async {
    final closingC = Completer<void>();
    final a = _Decoder(List.generate(4800, (i) => i));
    final b = _Decoder(List.generate(4800, (i) => -i));
    final c = _Decoder(List.generate(4800, (i) => -i - 4800), closeGate: closingC);
    final fixture = _Fixture({
      'a': [a],
      'b': [b],
      'c': [c],
    });
    addTearDown(() async {
      if (!closingC.isCompleted) closingC.complete();
      await fixture.harness.close();
    });
    await fixture.harness.playOriginal('a');
    await fixture.harness.prepareOriginal('b', 67);
    await fixture.harness.prepareOriginal('c', 68, afterPreparationId: 67);
    await _wait(() => fixture.outputs.isNotEmpty && fixture.output.submitted.length > a.samples.length);
    final cancelling = fixture.harness.cancel(preparationId: 68);
    await _wait(() => c.closeRequested);
    final seeking = fixture.harness.seek(const Duration(milliseconds: 50));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(a.seeks, isEmpty);
    closingC.complete();
    await Future.wait([cancelling, seeking]);
    await _wait(() => a.seeks.isNotEmpty);
    expect(b.closed, isTrue);
    expect(c.closed, isTrue);
    expect(a.seeks, [const Duration(milliseconds: 50)]);
    await fixture.driveUntil(() => _events(fixture.harness, 'complete').isNotEmpty);
    expect(fixture.output.rendered, orderedEquals(a.samples.skip(2400)));
  });

  test('a generic seek waits for an already releasing targeted head cancellation', () async {
    final closingB = Completer<void>();
    final a = _Decoder(List.generate(4800, (i) => i));
    final b = _Decoder(List.generate(4800, (i) => -i), closeGate: closingB);
    final fixture = _Fixture({
      'a': [a],
      'b': [b],
    });
    addTearDown(() async {
      if (!closingB.isCompleted) closingB.complete();
      await fixture.harness.close();
    });
    await fixture.harness.playOriginal('a');
    await fixture.harness.prepareOriginal('b', 65);
    await _wait(() => fixture.outputs.isNotEmpty && fixture.output.submitted.length > a.samples.length);
    final cancelling = fixture.harness.cancel(preparationId: 65);
    await _wait(() => b.closeRequested);
    final seeking = fixture.harness.seek(const Duration(milliseconds: 50));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(a.seeks, isEmpty);
    closingB.complete();
    await Future.wait([cancelling, seeking]);
    await _wait(() => a.seeks.isNotEmpty);
    expect(a.seeks, [const Duration(milliseconds: 50)]);
    await fixture.driveUntil(() => _events(fixture.harness, 'complete').isNotEmpty);
    expect(fixture.output.rendered, orderedEquals(a.samples.skip(2400)));
  });

  test('resume during a pending pause cannot pause the prepared successor later', () async {
    final a = _Decoder(List.generate(48000, (i) => i));
    final b = _Decoder(List.generate(48000, (i) => i + 48000));
    final fixture = _Fixture({
      'a': [a],
      'b': [b],
    });
    final collection = Completer<void>();
    addTearDown(() async {
      if (!collection.isCompleted) collection.complete();
      await fixture.harness.close();
    });
    await fixture.harness.playOriginal('a');
    await fixture.harness.prepareOriginal('b', 66);
    await _wait(() => fixture.outputs.isNotEmpty && fixture.output.submitted.isNotEmpty && b.reads > 0);
    fixture.output.collectGate = collection;
    final pausing = fixture.harness.pause();
    await Future<void>.delayed(Duration.zero);
    fixture.harness.resume();
    fixture.output.collectGate = null;
    collection.complete();
    await pausing;
    expect(_events(fixture.harness, 'state').last['paused'], isFalse);
    await fixture.driveUntil(() => _events(fixture.harness, 'complete').isNotEmpty);
    expect(fixture.output.rendered, orderedEquals([...a.samples, ...b.samples]));
    expect(_events(fixture.harness, 'gapless_transition'), hasLength(1));
  });

  test('an interrupted old file read yields to the latest seek instead of failing playback', () async {
    final pendingRead = Completer<Int32List>();
    final a = _Decoder(List.generate(48000, (i) => i));
    a.onRead = (_) => pendingRead.future;
    a.onInterrupt = () {
      if (!pendingRead.isCompleted) {
        a.onRead = null;
        pendingRead.completeError(StateError('read superseded'));
      }
    };
    final fixture = _Fixture({
      'a': [a],
    });
    addTearDown(fixture.harness.close);
    await fixture.harness.playOriginal('a');
    await _wait(() => a.reads > 0);
    await fixture.harness.seek(const Duration(milliseconds: 250));
    await _wait(() => a.seeks.isNotEmpty);
    await fixture.driveUntil(() => _events(fixture.harness, 'complete').isNotEmpty);
    expect(a.seeks, [const Duration(milliseconds: 250)]);
    expect(fixture.output.rendered, orderedEquals(a.samples.skip(12000)));
    expect(_events(fixture.harness, 'state').where((event) => event['active'] == false), isEmpty);
  });

  test('a superseded file seek cannot stop the newer seek', () async {
    final firstSeek = Completer<Duration>();
    final a = _Decoder(List.generate(48000, (i) => i));
    a.onSeek = (_) => firstSeek.future;
    a.onInterrupt = () {
      if (a.seeks.isNotEmpty && !firstSeek.isCompleted) {
        a.onSeek = null;
        firstSeek.completeError(StateError('seek superseded'));
      }
    };
    final fixture = _Fixture({
      'a': [a],
    });
    addTearDown(fixture.harness.close);
    await fixture.harness.playOriginal('a');
    await _wait(() => a.reads > 0);
    await fixture.harness.seek(const Duration(milliseconds: 250));
    await _wait(() => a.seeks.isNotEmpty);
    await fixture.harness.seek(const Duration(milliseconds: 500));
    await _wait(() => a.seeks.length == 2);
    await fixture.driveUntil(() => _events(fixture.harness, 'complete').isNotEmpty);
    expect(a.seeks, [const Duration(milliseconds: 250), const Duration(milliseconds: 500)]);
    expect(fixture.output.rendered, orderedEquals(a.samples.skip(24000)));
    expect(_events(fixture.harness, 'state').where((event) => event['active'] == false), isEmpty);
  });

  for (final quality in ['high', 'medium', 'low']) {
    test('$quality seek cancellation cannot affect a replacement Original track', () async {
      final a = _ClosingQuic();
      final b = _ClosingQuic();
      for (final transport in [a, b]) {
        transport.onRequest = (start, seekId) =>
            transport.deliverRange(startMs: start, endMs: 100, durationMs: 100, seekId: seekId, endOfTrack: true);
      }
      final transports = ListQueue.of([a, b]);
      final replacement = _Decoder(List.generate(48000, (i) => i + 100));
      final outputs = <_Output>[];
      final harness = GaplessPlaybackHarness(
        transportFactory: (_) => transports.removeFirst(),
        decoderFactory: MemoryOpusDecoder.new,
        fileDecoderFactory: (_, __, ___) => replacement,
        outputFactory: (_, __, ___, ____, _____) {
          final output = _Output();
          outputs.add(output);
          return output;
        },
      );
      addTearDown(harness.close);
      await harness.playOpus('track', quality: quality);
      await harness.prepareOpus('track', 63, quality: quality);
      await _wait(() => outputs.isNotEmpty && outputs.first.submitted.length > 9600);
      Future<void>? nextPlay;
      b.onClose = () => nextPlay = harness.playOriginal('replacement');
      await harness.seek(const Duration(milliseconds: 50));
      await nextPlay;
      await _wait(() => replacement.reads > 0);
      expect(replacement.seeks, isEmpty);
      expect(_events(harness, 'seek_failed').single['playback_id'], 1);
      expect(_events(harness, 'complete'), isEmpty);
    });
  }

  test('a cached Opus seek with submitted successor suspends the old stream once', () async {
    final a = MemoryQuic();
    final b = MemoryQuic();
    for (final transport in [a, b]) {
      transport.onRequest = (start, seekId) =>
          transport.deliverRange(startMs: start, endMs: 100, durationMs: 100, seekId: seekId, endOfTrack: true);
    }
    final transports = ListQueue.of([a, b]);
    final output = _Output();
    final harness = GaplessPlaybackHarness(
      transportFactory: (_) => transports.removeFirst(),
      decoderFactory: MemoryOpusDecoder.new,
      outputFactory: (_, __, ___, ____, _____) => output,
    );
    addTearDown(harness.close);
    await harness.playOpus('track');
    await harness.prepareOpus('track', 64);
    await _wait(() => output.submitted.length > 9600);
    await harness.seek(const Duration(milliseconds: 50));
    await _wait(() => _events(harness, 'seek_ready').isNotEmpty);
    expect(a.suspensions, 1);
    expect(a.requestedPositions, [0]);
    expect(b.closed, isTrue);
    await _wait(() => _events(harness, 'complete').isNotEmpty, tick: () => output.advance(100000));
  });

  test('a seek waiting on successor release cannot seek a replacement track', () async {
    final opening = Completer<void>();
    final closingB = Completer<void>();
    final a = _Decoder(List.generate(4800, (i) => i), opening: opening.future);
    final b = _Decoder(List.generate(4800, (i) => -i), closeGate: closingB);
    final c = _Decoder(List.generate(48000, (i) => i + 42));
    final fixture = _Fixture({
      'a': [a],
      'b': [b],
      'c': [c],
    });
    addTearDown(() async {
      if (!closingB.isCompleted) closingB.complete();
      await fixture.harness.close();
    });
    await fixture.harness.playOriginal('a');
    await fixture.harness.prepareOriginal('b', 61);
    opening.complete();
    await _wait(() => fixture.outputs.isNotEmpty && fixture.output.submitted.length > a.samples.length);
    final oldSeek = fixture.harness.seek(const Duration(milliseconds: 50));
    await _wait(() => b.closeRequested);
    final newPlay = fixture.harness.playOriginal('c');
    await Future<void>.delayed(Duration.zero);
    closingB.complete();
    await Future.wait([oldSeek, newPlay]);
    await _wait(() => c.reads > 0);
    expect(c.seeks, isEmpty);
    expect(_events(fixture.harness, 'seek_failed').single['playback_id'], 1);
    expect(_events(fixture.harness, 'complete'), isEmpty);
  });

  for (final cancellationAlreadyStarted in [false, true]) {
    test('a handoff seek replaces the cancellation rewind, pending=$cancellationAlreadyStarted', () async {
      final opening = Completer<void>();
      final a = _Decoder(List.generate(4800, (i) => i), opening: opening.future);
      final b = _Decoder(List.generate(4800, (i) => -i));
      final fixture = _Fixture({
        'a': [a],
        'b': [b],
      });
      addTearDown(fixture.harness.close);
      await fixture.harness.playOriginal('a');
      await fixture.harness.prepareOriginal('b', 62);
      opening.complete();
      await _wait(() => fixture.outputs.isNotEmpty && fixture.output.submitted.length > a.samples.length);
      final cancelling = cancellationAlreadyStarted ? fixture.harness.cancel(preparationId: 62) : null;
      await fixture.harness.seek(const Duration(milliseconds: 50));
      await cancelling;
      await _wait(() => a.seeks.isNotEmpty);
      expect(a.seeks, [const Duration(milliseconds: 50)]);
      await fixture.driveUntil(() => _events(fixture.harness, 'complete').isNotEmpty);
      expect(fixture.output.rendered, orderedEquals(a.samples.skip(2400)));
      expect(_events(fixture.harness, 'gapless_transition'), isEmpty);
    });
  }

  test('Original output stalls retire playback instead of waiting indefinitely', () async {
    final a = _Decoder(List.generate(48000 * 12, (i) => i % 1000));
    final fixture = _Fixture({
      'a': [a],
    }, outputProgressTimeout: const Duration(milliseconds: 100));
    addTearDown(fixture.harness.close);
    await fixture.harness.playOriginal('a');
    await _wait(() => fixture.outputs.isNotEmpty && fixture.output.submitted.isNotEmpty);
    await _wait(() => _events(fixture.harness, 'state').any((event) => event['active'] == false));
    expect(fixture.output.disposed, isTrue);
    expect(a.closed, isTrue);
    expect(_events(fixture.harness, 'complete'), isEmpty);
    expect(_events(fixture.harness, 'message').any((event) => '${event['text']}'.contains('output')), isTrue);
  });

  test('a user pause suspends the output deadline and resumes exact PCM', () async {
    final a = _Decoder(List.generate(48000, (i) => i % 1000));
    final fixture = _Fixture({
      'a': [a],
    }, outputProgressTimeout: const Duration(milliseconds: 100));
    addTearDown(fixture.harness.close);
    await fixture.harness.playOriginal('a');
    await _wait(() => fixture.outputs.isNotEmpty && fixture.output.submitted.isNotEmpty);
    await fixture.harness.pause();
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(fixture.output.disposed, isFalse);
    expect(_events(fixture.harness, 'state').where((event) => event['active'] == false), isEmpty);
    fixture.harness.resume();
    await fixture.driveUntil(() => _events(fixture.harness, 'complete').isNotEmpty);
    expect(fixture.output.rendered, orderedEquals(a.samples));
  });

  test('a silent Opus successor releases the completed Original predecessor', () async {
    final opening = Completer<void>();
    final a = _Decoder([1, 2, 3], opening: opening.future);
    final transport = MemoryQuic();
    final output = _Output();
    final harness = GaplessPlaybackHarness(
      fileDecoderFactory: (_, __, ___) => a,
      outputFactory: (_, __, ___, ____, _____) => output,
      transportFactory: (_) => transport,
      decoderFactory: MemoryOpusDecoder.new,
      transportProgressTimeout: const Duration(milliseconds: 100),
    );
    addTearDown(harness.close);
    await harness.playOriginal('a');
    await harness.prepareOpus('track', 41);
    opening.complete();
    await _wait(() => _events(harness, 'complete').isNotEmpty, tick: () => output.advance(100));
    expect(_events(harness, 'gapless_preparation_failed').single['preparation_id'], 41);
    expect(_events(harness, 'gapless_transition'), isEmpty);
    expect(output.rendered, [1, 2, 3]);
    expect(transport.closed, isTrue);
  });

  test('Original joins sub-millisecond tails with one output and exact samples', () async {
    final opening = Completer<void>();
    final a = _Decoder(List.generate(137, (i) => i * 17 - 800), rate: 192000, opening: opening.future);
    final b = _Decoder(List.generate(196, (i) => i * 31 + 701), rate: 192000);
    final fixture = _Fixture({
      'a': [a],
      'b': [b],
    });
    addTearDown(fixture.harness.close);

    await fixture.harness.playOriginal('a');
    await fixture.harness.prepareOriginal('b', 1);
    await _wait(() => b.reads > 0);
    expect(fixture.outputs, isEmpty, reason: 'Preparing B must not acquire a device.');
    expect(_events(fixture.harness, 'gapless_transition'), isEmpty);
    opening.complete();

    await fixture.driveUntil(() => _events(fixture.harness, 'complete').isNotEmpty);
    expect(fixture.outputs, hasLength(1));
    expect(fixture.output.rendered, orderedEquals([...a.samples, ...b.samples]));
    expect(fixture.output.flushes, 0);
    expect(_events(fixture.harness, 'gapless_transition').single['preparation_id'], 1);
    expect(_events(fixture.harness, 'complete'), hasLength(1));
    expect(a.closed, isTrue);
    expect(b.closed, isTrue);
    await fixture.harness.close();
    expect(fixture.output.disposed, isTrue);
  });

  test('repeated IDs and short tracks receive distinct audible transitions', () async {
    final opening = Completer<void>();
    final a = _Decoder([11, 12, 13, 14, 15, 16, 17], opening: opening.future);
    final b = _Decoder([21, 22, 23, 24, 25, 26, 27, 28, 29, 30]);
    final c = _Decoder([31, 32, 33, 34, 35]);
    final fixture = _Fixture({
      'same': [a, b, c],
    });
    addTearDown(fixture.harness.close);
    await fixture.harness.playOriginal('same');
    await fixture.harness.prepareOriginal('same', 101);
    await _wait(() => b.reads > 0);
    opening.complete();
    await _wait(
      () => fixture.outputs.isNotEmpty && fixture.output.submitted.length >= a.samples.length + b.samples.length,
    );

    // The second occurrence has been submitted but must not be current yet.
    expect(_events(fixture.harness, 'gapless_transition'), isEmpty);
    fixture.output.advance(a.samples.length + 1);
    await _wait(() => _events(fixture.harness, 'gapless_transition').length == 1);
    fixture.harness.acknowledge(101);
    await fixture.harness.prepareOriginal('same', 102);
    await fixture.driveUntil(() => _events(fixture.harness, 'complete').isNotEmpty);

    expect(fixture.output.rendered, orderedEquals([...a.samples, ...b.samples, ...c.samples]));
    expect(_events(fixture.harness, 'gapless_transition').map((event) => event['preparation_id']), [101, 102]);
    expect(fixture.outputs, hasLength(1));
    expect(fixture.output.flushes, 0);
  });

  test('two prepared successors cross both markers in one renderer batch', () async {
    final opening = Completer<void>();
    final a = _Decoder(List.generate(137, (i) => i + 1), opening: opening.future);
    final b = _Decoder(List.generate(193, (i) => i + 1001));
    final c = _Decoder(List.generate(257, (i) => i + 2001));
    final fixture = _Fixture({
      'a': [a],
      'b': [b],
      'c': [c],
    });
    addTearDown(fixture.harness.close);
    await fixture.harness.playOriginal('a');
    await fixture.harness.prepareOriginal('b', 21);
    await fixture.harness.prepareOriginal('c', 22, afterPreparationId: 21);
    await _wait(() => b.reads > 0 && c.reads > 0);
    opening.complete();
    await _wait(() => fixture.outputs.isNotEmpty && fixture.output.submitted.length == 587);
    expect(_events(fixture.harness, 'gapless_transition'), isEmpty);
    fixture.output.advance(587);
    await _wait(() => _events(fixture.harness, 'complete').isNotEmpty);
    expect(fixture.output.rendered, orderedEquals([...a.samples, ...b.samples, ...c.samples]));
    expect(_events(fixture.harness, 'gapless_transition').map((event) => event['preparation_id']), [21, 22]);
    expect(_events(fixture.harness, 'complete'), hasLength(1));
    expect(fixture.outputs, hasLength(1));
    expect(fixture.output.flushes, 0);
  });

  test('cancelling the head preparation cascades to its prepared successor', () async {
    final opening = Completer<void>();
    final a = _Decoder([1, 2, 3], opening: opening.future);
    final b = _Decoder([4, 5, 6]);
    final c = _Decoder([7, 8, 9]);
    final fixture = _Fixture({
      'a': [a],
      'b': [b],
      'c': [c],
    });
    addTearDown(fixture.harness.close);
    await fixture.harness.playOriginal('a');
    await fixture.harness.prepareOriginal('b', 23);
    await fixture.harness.prepareOriginal('c', 24, afterPreparationId: 23);
    await _wait(() => b.reads > 0 && c.reads > 0);
    await fixture.harness.cancel(preparationId: 23);
    expect(b.closed, isTrue);
    expect(c.closed, isTrue);
    opening.complete();
    await fixture.driveUntil(() => _events(fixture.harness, 'complete').isNotEmpty);
    expect(fixture.output.rendered, orderedEquals(a.samples));
    expect(_events(fixture.harness, 'gapless_transition'), isEmpty);
  });

  test('cancelling a submitted head retracts both successors and rebuilds A once', () async {
    final opening = Completer<void>();
    final a = _Decoder([1, 2, 3], opening: opening.future);
    final b = _Decoder([4, 5, 6]);
    final c = _Decoder([7, 8, 9]);
    final fixture = _Fixture({
      'a': [a],
      'b': [b],
      'c': [c],
    });
    addTearDown(fixture.harness.close);
    await fixture.harness.playOriginal('a');
    await fixture.harness.prepareOriginal('b', 29);
    await fixture.harness.prepareOriginal('c', 30, afterPreparationId: 29);
    await _wait(() => b.reads > 0 && c.reads > 0);
    opening.complete();
    await _wait(() => fixture.outputs.isNotEmpty && fixture.output.submitted.length == 9);
    await fixture.harness.cancel(preparationId: 29);
    await fixture.driveUntil(() => _events(fixture.harness, 'complete').isNotEmpty);
    expect(fixture.output.rendered, orderedEquals(a.samples));
    expect(b.closed, isTrue);
    expect(c.closed, isTrue);
    expect(_events(fixture.harness, 'gapless_transition'), isEmpty);
    expect(_events(fixture.harness, 'complete'), hasLength(1));
  });

  test('a failed tail preparation cannot cancel the healthy prepared head', () async {
    final opening = Completer<void>();
    final a = _Decoder([1, 2, 3], opening: opening.future);
    final b = _Decoder([4, 5, 6]);
    final broken = _Decoder([], failure: StateError('tail failed'));
    final fixture = _Fixture({
      'a': [a],
      'b': [b],
      'broken': [broken],
    });
    addTearDown(fixture.harness.close);
    await fixture.harness.playOriginal('a');
    await fixture.harness.prepareOriginal('b', 25);
    await fixture.harness.prepareOriginal('broken', 26, afterPreparationId: 25);
    await _wait(() => _events(fixture.harness, 'gapless_preparation_failed').isNotEmpty);
    expect(_events(fixture.harness, 'gapless_preparation_failed').single['preparation_id'], 26);
    expect(b.closed, isFalse);
    opening.complete();
    await fixture.driveUntil(() => _events(fixture.harness, 'complete').isNotEmpty);
    expect(fixture.output.rendered, orderedEquals([...a.samples, ...b.samples]));
    expect(_events(fixture.harness, 'gapless_transition').single['preparation_id'], 25);
    expect(_events(fixture.harness, 'complete'), hasLength(1));
  });

  test('stale head handoff retracts descendants whose markers already crossed', () async {
    final opening = Completer<void>();
    final a = _Decoder([1, 2, 3], opening: opening.future);
    final b = _Decoder([4, 5, 6]);
    final c = _Decoder([7, 8, 9]);
    final fixture = _Fixture({
      'a': [a],
      'b': [b],
      'c': [c],
    });
    addTearDown(fixture.harness.close);
    await fixture.harness.playOriginal('a');
    await fixture.harness.prepareOriginal('b', 27);
    await fixture.harness.prepareOriginal('c', 28, afterPreparationId: 27);
    await _wait(() => b.reads > 0 && c.reads > 0);
    opening.complete();
    await _wait(() => fixture.outputs.isNotEmpty && fixture.output.submitted.length == 9);
    fixture.output.advance(7);
    await _wait(() => _events(fixture.harness, 'gapless_transition').length == 2);
    await fixture.harness.cancel(preparationId: 27);
    fixture.output.advance(100);
    expect(fixture.output.rendered, [1, 2, 3, 4, 5, 6, 7]);
    expect(b.closed, isTrue);
    expect(c.closed, isTrue);
    expect(_events(fixture.harness, 'complete'), hasLength(1));
  });

  test('failed preparation leaves the current track intact', () async {
    final opening = Completer<void>();
    final a = _Decoder(List.generate(5013, (i) => i - 2000), opening: opening.future);
    final broken = _Decoder([], failure: StateError('source failed'));
    final fixture = _Fixture({
      'a': [a],
      'broken': [broken],
    });
    addTearDown(fixture.harness.close);
    await fixture.harness.playOriginal('a');
    await fixture.harness.prepareOriginal('broken', 3);
    await _wait(() => _events(fixture.harness, 'gapless_preparation_failed').isNotEmpty);
    expect(a.closed, isFalse);
    expect(_events(fixture.harness, 'gapless_transition'), isEmpty);
    opening.complete();
    await fixture.driveUntil(() => _events(fixture.harness, 'complete').isNotEmpty);
    expect(fixture.output.rendered, orderedEquals(a.samples));
    expect(fixture.output.flushes, 0);
    expect(_events(fixture.harness, 'state').where((event) => event['active'] == false), isEmpty);
  });

  test('cancelling a prepared source closes it without rendering its samples', () async {
    final opening = Completer<void>();
    final a = _Decoder(List.generate(2401, (i) => i + 1), opening: opening.future);
    final b = _Decoder(List.filled(2400, -999));
    final fixture = _Fixture({
      'a': [a],
      'b': [b],
    });
    addTearDown(fixture.harness.close);
    await fixture.harness.playOriginal('a');
    await fixture.harness.prepareOriginal('b', 4);
    await _wait(() => b.reads > 0);
    await fixture.harness.cancel(preparationId: 4);
    expect(b.closed, isTrue);
    opening.complete();
    await fixture.driveUntil(() => _events(fixture.harness, 'complete').isNotEmpty);
    expect(fixture.output.rendered, orderedEquals(a.samples));
    expect(_events(fixture.harness, 'gapless_transition'), isEmpty);
    expect(fixture.output.flushes, 0);
  });

  test('obsolete cancellation cannot remove a replacement preparation', () async {
    final opening = Completer<void>();
    final a = _Decoder([1, 2, 3], opening: opening.future);
    final b = _Decoder([4, 5, 6]);
    final c = _Decoder([7, 8, 9]);
    final fixture = _Fixture({
      'a': [a],
      'b': [b],
      'c': [c],
    });
    addTearDown(fixture.harness.close);
    await fixture.harness.playOriginal('a');
    await fixture.harness.prepareOriginal('b', 5);
    await _wait(() => b.reads > 0);
    await fixture.harness.prepareOriginal('c', 6);
    await _wait(() => c.reads > 0);
    await fixture.harness.cancel(preparationId: 5);
    opening.complete();
    await fixture.driveUntil(() => _events(fixture.harness, 'complete').isNotEmpty);
    expect(fixture.output.rendered, orderedEquals([...a.samples, ...c.samples]));
    expect(_events(fixture.harness, 'gapless_transition').single['preparation_id'], 6);
  });

  test('a cancelled decoder finishing initialization cannot revive stale preparation', () async {
    final openingA = Completer<void>();
    final openingB = Completer<void>();
    final a = _Decoder([1, 2, 3], opening: openingA.future);
    final b = _Decoder([-1, -2, -3], opening: openingB.future);
    final c = _Decoder([7, 8, 9]);
    final fixture = _Fixture({
      'a': [a],
      'b': [b],
      'c': [c],
    });
    addTearDown(fixture.harness.close);
    await fixture.harness.playOriginal('a');
    await fixture.harness.prepareOriginal('b', 19);
    await fixture.harness.cancel(preparationId: 19);
    expect(b.closed, isTrue);
    await fixture.harness.prepareOriginal('c', 20);
    openingB.complete();
    await _wait(() => c.reads > 0);
    openingA.complete();
    await fixture.driveUntil(() => _events(fixture.harness, 'complete').isNotEmpty);
    expect(b.reads, 0);
    expect(fixture.output.rendered, orderedEquals([...a.samples, ...c.samples]));
    expect(_events(fixture.harness, 'gapless_transition').single['preparation_id'], 20);
  });

  test('pause preserves prepared audio and prevents an audible handoff', () async {
    final a = _Decoder(List.generate(8000, (i) => i + 1));
    final b = _Decoder(List.filled(1801, -7));
    final fixture = _Fixture({
      'a': [a],
      'b': [b],
    });
    addTearDown(fixture.harness.close);
    await fixture.harness.playOriginal('a', initialPaused: true);
    await fixture.harness.prepareOriginal('b', 7);
    await _wait(() => a.reads > 0 && b.reads > 0 && fixture.outputs.isNotEmpty);
    fixture.output.advance(100000);
    expect(fixture.output.rendered, isEmpty);
    expect(_events(fixture.harness, 'gapless_transition'), isEmpty);
    fixture.harness.resume();
    await fixture.driveUntil(() => _events(fixture.harness, 'complete').isNotEmpty);
    expect(fixture.output.rendered, orderedEquals([...a.samples, ...b.samples]));
    expect(fixture.output.flushes, 0);
  });

  test('empty prepared source terminates without an infinite drain or phantom transition', () async {
    final opening = Completer<void>();
    final a = _Decoder([3, 4, 5], opening: opening.future);
    final empty = _Decoder([]);
    final fixture = _Fixture({
      'a': [a],
      'empty': [empty],
    });
    addTearDown(fixture.harness.close);
    await fixture.harness.playOriginal('a');
    await fixture.harness.prepareOriginal('empty', 8);
    await _wait(() => empty.reads > 0);
    opening.complete();
    await fixture.driveUntil(() => _events(fixture.harness, 'complete').isNotEmpty);
    expect(fixture.output.rendered, orderedEquals(a.samples));
    expect(_events(fixture.harness, 'gapless_transition'), isEmpty);
    expect(_events(fixture.harness, 'complete'), hasLength(1));
  });

  test('cancelling submitted successor audio rebuilds the unheard current tail', () async {
    final a = _Decoder(List.generate(4801, (i) => i + 1));
    final b = _Decoder(List.filled(4800, -1001));
    final fixture = _Fixture({
      'a': [a],
      'b': [b],
    });
    addTearDown(fixture.harness.close);
    await fixture.harness.playOriginal('a');
    await fixture.harness.prepareOriginal('b', 9);
    await _wait(() => fixture.outputs.isNotEmpty && fixture.output.submitted.length > a.samples.length);
    expect(fixture.output.rendered, isEmpty);
    await fixture.harness.cancel(preparationId: 9);
    await fixture.driveUntil(() => _events(fixture.harness, 'complete').isNotEmpty);
    expect(fixture.output.rendered, orderedEquals(a.samples));
    expect(fixture.output.flushes, greaterThanOrEqualTo(1));
    expect(_events(fixture.harness, 'gapless_transition'), isEmpty);
    expect(b.closed, isTrue);
  });

  test('cancellation arriving after audible handoff cannot cancel the current occurrence', () async {
    final opening = Completer<void>();
    final a = _Decoder([1, 2, 3], opening: opening.future);
    final b = _Decoder([4, 5, 6, 7, 8]);
    final fixture = _Fixture({
      'a': [a],
      'b': [b],
    });
    addTearDown(fixture.harness.close);
    await fixture.harness.playOriginal('a');
    await fixture.harness.prepareOriginal('b', 10);
    await _wait(() => b.reads > 0);
    opening.complete();
    await _wait(() => fixture.outputs.isNotEmpty && fixture.output.submitted.length == 8);
    fixture.output.advance(4);
    await _wait(() => _events(fixture.harness, 'gapless_transition').isNotEmpty);
    fixture.harness.acknowledge(10);
    await fixture.harness.cancel(preparationId: 10);
    await fixture.driveUntil(() => _events(fixture.harness, 'complete').isNotEmpty);
    expect(fixture.output.rendered, [1, 2, 3, 4, 5, 6, 7, 8]);
    expect(fixture.output.flushes, 0);
    expect(_events(fixture.harness, 'gapless_transition'), hasLength(1));
  });

  test('an unacknowledged handoff can be cancelled while its event is in flight', () async {
    final opening = Completer<void>();
    final a = _Decoder([1, 2, 3], opening: opening.future);
    final b = _Decoder([4, 5, 6, 7, 8]);
    final fixture = _Fixture({
      'a': [a],
      'b': [b],
    });
    addTearDown(fixture.harness.close);
    await fixture.harness.playOriginal('a');
    await fixture.harness.prepareOriginal('b', 16);
    await _wait(() => b.reads > 0);
    opening.complete();
    await _wait(() => fixture.outputs.isNotEmpty && fixture.output.submitted.length == 8);
    fixture.output.advance(4);
    await _wait(() => _events(fixture.harness, 'gapless_transition').isNotEmpty);
    await fixture.harness.cancel(preparationId: 16);
    fixture.output.advance(100);
    expect(fixture.output.rendered, [1, 2, 3, 4]);
    expect(
      _events(fixture.harness, 'complete'),
      hasLength(1),
      reason: 'Retracting an unacknowledged successor returns control to the predecessor queue.',
    );
    expect(b.closed, isTrue);
  });

  test('one renderer batch spanning two tracks splits listening attribution', () async {
    final opening = Completer<void>();
    final a = _Decoder(List.filled(2401, 1), opening: opening.future);
    final b = _Decoder(List.filled(2401, 2));
    final fixture = _Fixture({
      'a': [a],
      'b': [b],
    });
    addTearDown(fixture.harness.close);
    await fixture.harness.playOriginal('a', context: _context('a'));
    await fixture.harness.prepareOriginal('b', 11, context: _context('b'));
    await _wait(() => b.reads > 0);
    opening.complete();
    await _wait(() => fixture.outputs.isNotEmpty && fixture.output.submitted.length == 4802);
    expect(_events(fixture.harness, 'listening_segment'), isEmpty);
    // Exactly one native completion observation spans both occurrence markers.
    fixture.output.advance(4802);
    await fixture.driveUntil(() => _events(fixture.harness, 'complete').isNotEmpty);
    final segments = _events(fixture.harness, 'listening_segment').map((message) => message['event'] as Map).toList();
    expect(segments.map((event) => (event['track_id'], event['listened_ms'])), [('a', 50), ('b', 50)]);
    expect(segments.every((event) => event['end_reason'] == 'finished'), isTrue);
  });

  test('statistics opt-out invalidates a prepared listening context', () async {
    final opening = Completer<void>();
    final a = _Decoder(List.filled(2401, 1), opening: opening.future);
    final b = _Decoder(List.filled(2401, 2));
    final fixture = _Fixture({
      'a': [a],
      'b': [b],
    });
    addTearDown(fixture.harness.close);
    await fixture.harness.playOriginal('a', context: _context('a'));
    await fixture.harness.prepareOriginal('b', 12, context: _context('b'));
    await _wait(() => b.reads > 0);
    fixture.harness.configureListening(null);
    opening.complete();
    await fixture.driveUntil(() => _events(fixture.harness, 'complete').isNotEmpty);
    expect(_events(fixture.harness, 'listening_segment'), isEmpty);
    expect(_events(fixture.harness, 'gapless_transition'), hasLength(1));
  });

  test('native-rate format changes drain the previous format before reopening', () async {
    final opening = Completer<void>();
    final a = _Decoder(List.generate(137, (i) => i + 1), rate: 44100, opening: opening.future);
    final b = _Decoder(List.generate(193, (i) => -i - 1), rate: 96000);
    final fixture = _Fixture({
      'a': [a],
      'b': [b],
    });
    addTearDown(fixture.harness.close);
    await fixture.harness.playOriginal('a');
    await fixture.harness.prepareOriginal('b', 13);
    await _wait(() => b.reads > 0);
    opening.complete();
    await _wait(() => fixture.outputs.isNotEmpty && fixture.output.submitted.isNotEmpty);
    expect(fixture.outputs, hasLength(1));
    expect(fixture.output.disposed, isFalse);
    fixture.output.advance(137);
    await fixture.driveUntil(() => _events(fixture.harness, 'complete').isNotEmpty);
    expect(fixture.outputs, hasLength(2));
    expect(fixture.formats.map((format) => format.$1), [44100, 96000]);
    expect(fixture.outputs.first.disposed, isTrue);
    expect(fixture.outputs.expand((output) => output.rendered), orderedEquals([...a.samples, ...b.samples]));
    expect(fixture.outputs.every((output) => output.flushes == 0), isTrue);
  });

  test('seamless conversion retains one device across rates and channel layouts', () async {
    final opening = Completer<void>();
    final a = _Decoder(List.filled(137 * 2, 100000), rate: 44100, channels: 2, opening: opening.future);
    final b = _Decoder(List.filled(193, 200000), rate: 48000);
    final fixture = _Fixture({
      'a': [a],
      'b': [b],
    });
    addTearDown(fixture.harness.close);
    fixture.harness.setGaplessResampling(true);
    await fixture.harness.playOriginal('a');
    await fixture.harness.prepareOriginal('b', 17);
    await _wait(() => b.reads > 0);
    opening.complete();
    await fixture.driveUntil(() => _events(fixture.harness, 'complete').isNotEmpty);
    expect(fixture.outputs, hasLength(1));
    expect(fixture.formats.single, (44100, 2, -1, 32, 32));
    const bOutputFrames = (193 * 44100 + 48000 ~/ 2) ~/ 48000;
    expect(fixture.output.rendered, hasLength((137 + bOutputFrames) * 2));
    expect(fixture.output.rendered.take(274), orderedEquals(a.samples));
    expect(fixture.output.rendered.skip(274), everyElement(200000));
    expect(fixture.output.flushes, 0);
    expect(_events(fixture.harness, 'gapless_transition'), hasLength(1));
  });

  test('a successor rounded to zero device frames cannot hang or claim listening', () async {
    final opening = Completer<void>();
    final a = _Decoder(List.filled(137, 100000), rate: 44100, opening: opening.future);
    final tiny = _Decoder([200000], rate: 192000);
    final fixture = _Fixture({
      'a': [a],
      'tiny': [tiny],
    });
    addTearDown(fixture.harness.close);
    fixture.harness.setGaplessResampling(true);
    await fixture.harness.playOriginal('a');
    await fixture.harness.prepareOriginal('tiny', 18, context: _context('tiny'));
    await _wait(() => tiny.reads > 0);
    opening.complete();
    await fixture.driveUntil(() => _events(fixture.harness, 'complete').isNotEmpty);
    expect(fixture.output.rendered, orderedEquals(a.samples));
    expect(_events(fixture.harness, 'gapless_transition'), isEmpty);
    expect(_events(fixture.harness, 'listening_segment'), isEmpty);
    expect(_events(fixture.harness, 'complete'), hasLength(1));
  });

  test('seek while paused retires preparation and preserves pause intent', () async {
    final a = _Decoder(List.generate(8000, (i) => i + 1));
    final b = _Decoder(List.filled(1801, -9));
    final fixture = _Fixture({
      'a': [a],
      'b': [b],
    });
    addTearDown(fixture.harness.close);
    await fixture.harness.playOriginal('a', initialPaused: true);
    await fixture.harness.prepareOriginal('b', 14);
    await _wait(() => a.reads > 0 && b.reads > 0 && fixture.outputs.isNotEmpty);
    await fixture.harness.seek(const Duration(milliseconds: 10));
    await _wait(() => a.seeks.isNotEmpty && a.reads > 2);
    expect(b.closed, isTrue);
    expect(fixture.output.rendered, isEmpty);
    expect(fixture.output.paused, isTrue);
    fixture.harness.resume();
    await fixture.driveUntil(() => _events(fixture.harness, 'complete').isNotEmpty);
    expect(fixture.output.rendered, orderedEquals(a.samples.skip(480)));
    expect(_events(fixture.harness, 'gapless_transition'), isEmpty);
  });

  test('stop releases sources and pending native writes before returning', () async {
    final gate = Completer<void>();
    final a = _Decoder(List.filled(8000, 1));
    final b = _Decoder(List.filled(8000, 2));
    final fixture = _Fixture({
      'a': [a],
      'b': [b],
    }, writeGate: gate);
    await fixture.harness.playOriginal('a');
    await fixture.harness.prepareOriginal('b', 15);
    await _wait(() => fixture.outputs.isNotEmpty && fixture.output.writeAttempts > 0 && b.reads > 0);
    await fixture.harness.close().timeout(const Duration(seconds: 2));
    expect(a.closed, isTrue);
    expect(b.closed, isTrue);
    expect(fixture.output.disposed, isTrue);
    expect(fixture.output.rendered, isEmpty);
    expect(_events(fixture.harness, 'gapless_transition'), isEmpty);
    expect(_events(fixture.harness, 'complete'), isEmpty);
  });

  for (final withSuccessor in [false, true]) {
    test('stop credits the final unpolled renderer batch${withSuccessor ? ' across the next marker' : ''}', () async {
      final opening = Completer<void>();
      final a = _Decoder(List.filled(2401, 1), opening: opening.future);
      final b = _Decoder(List.filled(2401, 2));
      final fixture = _Fixture({
        'a': [a],
        'b': [b],
      });
      addTearDown(fixture.harness.close);
      await fixture.harness.playOriginal('a', context: _context('a'));
      if (withSuccessor) await fixture.harness.prepareOriginal('b', 31, context: _context('b'));
      if (withSuccessor) await _wait(() => b.reads > 0);
      opening.complete();
      final total = withSuccessor ? 4802 : 2401;
      await _wait(() => fixture.outputs.isNotEmpty && fixture.output.submitted.length == total);
      fixture.output.advance(total);
      // No event-loop yield between the hardware observation and stop. The
      // normal statistics/drain timers have not collected these samples yet.
      await fixture.harness.close();
      final segments = _events(fixture.harness, 'listening_segment').map((event) => event['event'] as Map).toList();
      expect(
        segments.map((event) => (event['track_id'], event['listened_ms'])),
        withSuccessor ? [('a', 50), ('b', 50)] : [('a', 50)],
      );
      expect(
        _events(fixture.harness, 'gapless_transition'),
        isEmpty,
        reason: 'Stopping can account for heard B without publishing a late now-playing handoff.',
      );
      expect(fixture.output.disposed, isTrue);
    });
  }

  test('statistics opt-out during replacement source release cannot revive old context', () async {
    final oldClosing = Completer<void>();
    final old = _Decoder(List.filled(8000, -1), closeGate: oldClosing);
    final fresh = _Decoder(List.filled(2401, 2));
    final fixture = _Fixture({
      'old': [old],
      'fresh': [fresh],
    });
    addTearDown(fixture.harness.close);
    addTearDown(() {
      if (!oldClosing.isCompleted) oldClosing.complete();
    });
    await fixture.harness.playOriginal('old', context: _context('old'));
    await _wait(() => fixture.outputs.isNotEmpty && fixture.output.submitted.isNotEmpty);
    final replacing = fixture.harness.playOriginal('fresh', context: _context('fresh'));
    await _wait(() => old.closeRequested);
    fixture.harness.configureListening(null);
    oldClosing.complete();
    await replacing;
    await fixture.driveUntil(() => _events(fixture.harness, 'complete').isNotEmpty);
    expect(fixture.output.rendered, orderedEquals(fresh.samples));
    expect(_events(fixture.harness, 'listening_segment'), isEmpty);
    expect(old.closed, isTrue);
  });

  for (final pauseDuringRelease in [false, true]) {
    test('latest ${pauseDuringRelease ? 'pause' : 'resume'} intent survives pending source release', () async {
      final closing = Completer<void>();
      final old = _Decoder(List.filled(8000, -1), closeGate: closing);
      final fresh = _Decoder(List.filled(2401, 2));
      final fixture = _Fixture({
        'old': [old],
        'fresh': [fresh],
      });
      addTearDown(fixture.harness.close);
      addTearDown(() {
        if (!closing.isCompleted) closing.complete();
      });
      await fixture.harness.playOriginal('old');
      await _wait(() => fixture.outputs.isNotEmpty && fixture.output.submitted.isNotEmpty);
      final replacement = fixture.harness.playOriginal('fresh', initialPaused: !pauseDuringRelease);
      await _wait(() => old.closeRequested);
      if (pauseDuringRelease) {
        await fixture.harness.pause();
      } else {
        fixture.harness.resume();
      }
      closing.complete();
      await replacement;
      await _wait(() => fresh.reads > 0 && fixture.outputs.length == 2);
      expect(fixture.output.paused, pauseDuringRelease);
      if (pauseDuringRelease) {
        fixture.output.advance(100000);
        expect(fixture.output.rendered, isEmpty);
        fixture.harness.resume();
      }
      await fixture.driveUntil(() => _events(fixture.harness, 'complete').isNotEmpty);
      expect(fixture.output.rendered, orderedEquals(fresh.samples));
    });
  }

  test('a cancelled pending native initialization cannot dispose the replacement output', () async {
    final opening = Completer<void>();
    final nativeOpening = Completer<void>();
    final a = _Decoder(List.generate(137, (i) => i + 1), rate: 44100, opening: opening.future);
    final b = _Decoder(List.filled(193, -1), rate: 96000);
    final c = _Decoder(List.generate(257, (i) => i + 2001), rate: 96000);
    final fixture = _Fixture(
      {
        'a': [a],
        'b': [b],
        'c': [c],
      },
      initializationGates: [null, nativeOpening],
    );
    addTearDown(fixture.harness.close);
    addTearDown(() {
      if (!nativeOpening.isCompleted) nativeOpening.complete();
    });
    await fixture.harness.playOriginal('a');
    await fixture.harness.prepareOriginal('b', 32);
    await _wait(() => b.reads > 0);
    opening.complete();
    await _wait(() => fixture.outputs.isNotEmpty && fixture.output.submitted.length == 137);
    fixture.output.advance(137);
    await _wait(() => fixture.outputs.length == 2 && fixture.outputs[1].initializeCalls > 0);
    final cancelling = fixture.harness.cancel(preparationId: 32);
    final replacing = fixture.harness.prepareOriginal('c', 33);
    await Future<void>.delayed(Duration.zero);
    expect(fixture.outputs, hasLength(2), reason: 'New configuration must wait for the pending native open.');
    nativeOpening.complete();
    await cancelling;
    await replacing;
    await fixture.driveUntil(() => _events(fixture.harness, 'complete').isNotEmpty);
    expect(fixture.outputs.length, greaterThanOrEqualTo(3));
    expect(fixture.outputs[1].disposed, isTrue);
    expect(fixture.outputs[1].submitted, isEmpty);
    expect(fixture.outputs.expand((output) => output.rendered), orderedEquals([...a.samples, ...c.samples]));
    expect(_events(fixture.harness, 'gapless_transition').single['preparation_id'], 33);
  });

  test('preparation accepted during prior source release belongs to the new play', () async {
    final oldClosing = Completer<void>();
    final newOpening = Completer<void>();
    final old = _Decoder(List.filled(8000, -1), closeGate: oldClosing);
    final fresh = _Decoder([1, 2, 3], opening: newOpening.future);
    final next = _Decoder([4, 5, 6]);
    final fixture = _Fixture({
      'old': [old],
      'fresh': [fresh],
      'next': [next],
    });
    addTearDown(fixture.harness.close);
    addTearDown(() {
      if (!oldClosing.isCompleted) oldClosing.complete();
      if (!newOpening.isCompleted) newOpening.complete();
    });
    await fixture.harness.playOriginal('old');
    await _wait(() => fixture.outputs.isNotEmpty && fixture.output.submitted.isNotEmpty);
    final replacing = fixture.harness.playOriginal('fresh');
    await _wait(() => old.closeRequested);
    final preparing = fixture.harness.prepareOriginal('next', 34);
    oldClosing.complete();
    await replacing;
    await preparing;
    await _wait(() => next.reads > 0);
    newOpening.complete();
    await fixture.driveUntil(() => _events(fixture.harness, 'complete').isNotEmpty);
    expect(fixture.outputs.expand((output) => output.rendered), [1, 2, 3, 4, 5, 6]);
    expect(_events(fixture.harness, 'gapless_transition').single['preparation_id'], 34);
    expect(old.closed, isTrue);
  });

  test('a current source failure retires healthy preparation before it can render', () async {
    final opening = Completer<void>();
    final broken = _Decoder([], opening: opening.future, failure: const AudioSourceRejected('source unavailable'));
    final b = _Decoder(List.filled(2401, 2));
    final fixture = _Fixture({
      'broken': [broken],
      'b': [b],
    });
    addTearDown(fixture.harness.close);
    await fixture.harness.playOriginal('broken');
    await fixture.harness.prepareOriginal('b', 35);
    await _wait(() => b.reads > 0);
    opening.complete();
    await _wait(() => _events(fixture.harness, 'state').any((event) => event['active'] == false));
    await _wait(() => b.closed);
    for (final output in fixture.outputs) {
      output.advance(100000);
    }
    expect(fixture.outputs.expand((output) => output.rendered), isEmpty);
    expect(_events(fixture.harness, 'gapless_transition'), isEmpty);
    expect(_events(fixture.harness, 'complete'), isEmpty);
  });

  test('an empty initial source stops without a phantom completed occurrence', () async {
    final empty = _Decoder([]);
    final fixture = _Fixture({
      'empty': [empty],
    });
    addTearDown(fixture.harness.close);
    await fixture.harness.playOriginal('empty', context: _context('empty'));
    await _wait(() => _events(fixture.harness, 'state').any((event) => event['source_rejected'] == true));
    expect(_events(fixture.harness, 'complete'), isEmpty);
    expect(_events(fixture.harness, 'gapless_transition'), isEmpty);
    expect(_events(fixture.harness, 'listening_segment'), isEmpty);
    expect(fixture.outputs.every((output) => output.disposed), isTrue);
    expect(empty.closed, isTrue);
  });
}

Map<String, dynamic> _context(String id) => {'session_id': 'session-$id', 'track_id': id, 'session_started_at_ms': 0};

List<Map<String, dynamic>> _events(GaplessPlaybackHarness harness, String type) =>
    harness.messages.where((event) => event['type'] == type).toList();

Future<void> _wait(bool Function() done, {void Function()? tick}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 4));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) throw StateError('Gapless condition timed out.');
    tick?.call();
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

class _Fixture {
  final Map<String, List<_Decoder>> decoders;
  final List<_Output> outputs = [];
  final List<(int, int, int, int, int)> formats = [];
  late final GaplessPlaybackHarness harness;
  _Fixture(
    this.decoders, {
    Completer<void>? writeGate,
    List<Completer<void>?> initializationGates = const [],
    Duration outputProgressTimeout = const Duration(seconds: 5),
  }) {
    harness = GaplessPlaybackHarness(
      outputProgressTimeout: outputProgressTimeout,
      fileDecoderFactory: (id, uri, offset) => decoders[id]!.removeAt(0),
      outputFactory: (rate, channels, device, bits, validBits) {
        formats.add((rate, channels, device, bits, validBits));
        final output = _Output(
          writeGate: writeGate,
          initializeGate: outputs.length < initializationGates.length ? initializationGates[outputs.length] : null,
        );
        outputs.add(output);
        return output;
      },
    );
  }
  _Output get output => outputs.last;
  Future<void> driveUntil(bool Function() done) => _wait(
    done,
    tick: () {
      if (outputs.isNotEmpty) output.advance(100000);
    },
  );
}

class _ClosingQuic extends MemoryQuic {
  void Function()? onClose;

  @override
  void close() {
    if (closed) return;
    super.close();
    final callback = onClose;
    onClose = null;
    callback?.call();
  }
}

class _Decoder implements AudioFileDecoder {
  final List<int> samples;
  final Future<void>? opening;
  final Object? failure;
  final Completer<void>? closeGate;
  @override
  final AudioFileFormat format;
  int reads = 0, _cursor = 0;
  final List<Duration> seeks = [];
  bool closed = false, closeRequested = false;
  Future<void>? _closing;
  Future<Int32List> Function(int maxSamples)? onRead;
  Future<Duration> Function(Duration position)? onSeek;
  void Function()? onInterrupt;
  _Decoder(this.samples, {int rate = 48000, int channels = 1, this.opening, this.failure, this.closeGate})
    : format = AudioFileFormat(
        sampleRate: rate,
        channels: channels,
        bitDepth: 32,
        duration: Duration(microseconds: samples.length * 1000000 ~/ (rate * channels)),
        playableFrames: samples.length ~/ channels,
      );
  @override
  Future<void> initialize() async {
    await opening;
    if (failure != null) throw failure!;
  }

  @override
  Future<Int32List> read32(int maxSamples) async {
    if (closed) throw StateError('Decoder used after close.');
    reads++;
    final handler = onRead;
    if (handler != null) return handler(maxSamples);
    final end = math.min(samples.length, _cursor + maxSamples);
    final result = Int32List.fromList(samples.sublist(_cursor, end));
    _cursor = end;
    return result;
  }

  @override
  Future<Duration> seek(Duration position) async {
    seeks.add(position);
    final handler = onSeek;
    if (handler != null) return handler(position);
    _cursor = math.min(samples.length, (position.inMicroseconds * format.sampleRate ~/ 1000000) * format.channels);
    return position;
  }

  @override
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    closeRequested = true;
    interruptRead();
    await closeGate?.future;
    closed = true;
  }

  @override
  void interruptRead() => onInterrupt?.call();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Output implements AudioPcmOutput, AudioPcm32Output {
  final List<int> submitted = [], rendered = [];
  final ListQueue<int> _pending = ListQueue();
  int _done = 0, flushes = 0;
  int writeAttempts = 0;
  final Completer<void>? writeGate;
  final Completer<void>? initializeGate;
  int initializeCalls = 0;
  Completer<void>? collectGate;
  bool paused = false, disposed = false;
  _Output({this.writeGate, this.initializeGate});
  @override
  Future<void> initialize() async {
    initializeCalls++;
    await initializeGate?.future;
    if (disposed) throw StateError('Cancelled native initialization completed after release.');
  }

  @override
  Future<void> write(Int16List samples) => _write(samples);
  @override
  Future<void> writePcm32(Int32List samples) => _write(samples);
  Future<void> _write(List<int> samples) async {
    writeAttempts++;
    await writeGate?.future;
    if (disposed) return;
    submitted.addAll(samples);
    _pending.addAll(samples);
  }

  void advance(int samples) {
    if (paused || disposed) return;
    final count = math.min(samples, _pending.length);
    for (var i = 0; i < count; i++) {
      rendered.add(_pending.removeFirst());
    }
    _done += count;
  }

  @override
  Future<int> collectDoneSamples() async {
    await collectGate?.future;
    final done = _done;
    _done = 0;
    return done;
  }

  @override
  Future<bool> isIdle() async => _pending.isEmpty;
  @override
  Future<void> flush() async {
    flushes++;
    _pending.clear();
    _done = 0;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    _pending.clear();
    final gate = writeGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  void pause() {
    paused = true;
  }

  @override
  void resume() {
    paused = false;
  }

  @override
  void setVolume(double value) {}
}
