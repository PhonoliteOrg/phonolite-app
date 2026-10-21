import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/infrastructure/audio/engine/audio_engine.dart';
import 'package:phonolite_app/infrastructure/platform/audio/android_channel_output.dart';

import '../support/streaming_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;

  AndroidChannelPlayer output() => AndroidChannelPlayer(sampleRate: 48000, channels: 2, deviceId: 7);

  void mockChannel(Future<Object?> Function(MethodCall) respond) {
    messenger.setMockMethodCallHandler(androidAudioOutputChannel, (call) {
      calls.add(call);

      return respond(call);
    });
  }

  setUp(() => calls = []);
  tearDown(() => messenger.setMockMethodCallHandler(androidAudioOutputChannel, null));

  test('construction and pending configuration perform no native I/O', () async {
    mockChannel((call) async => call.method == 'open' ? 42 : null);
    final player = output();

    player.setVolume(0.25);
    player.pause();
    expect(await player.isIdle(), isTrue);
    expect(await player.collectDoneSamples(), 0);
    expect(calls, isEmpty);

    await player.initialize();

    expect(calls.map((call) => call.method), ['open', 'setVolume', 'pause']);
    expect(calls.first.arguments, {'sampleRate': 48000, 'channels': 2, 'deviceId': 7});
    expect(calls[1].arguments, {'id': 42, 'value': 0.25});

    await player.dispose();
  });

  test('concurrent and repeated initialize share one native open', () async {
    final opening = Completer<Object?>();
    final opened = Completer<void>();
    mockChannel((call) async {
      if (call.method == 'open') {
        opened.complete();

        return opening.future;
      }

      return null;
    });
    final player = output();
    final first = player.initialize();
    final second = player.initialize();

    expect(identical(first, second), isTrue);
    await opened.future;
    expect(calls.where((call) => call.method == 'open'), hasLength(1));

    opening.complete(42);
    await Future.wait([first, second]);
    await player.initialize();

    expect(calls.where((call) => call.method == 'open'), hasLength(1));
    expect(calls.where((call) => call.method == 'setVolume'), hasLength(1));

    await player.dispose();
  });

  test('dispose completes only after native close and shares that completion', () async {
    final closing = Completer<Object?>();
    final closeStarted = Completer<void>();
    mockChannel((call) async {
      if (call.method == 'open') {
        return 42;
      }

      if (call.method == 'close') {
        closeStarted.complete();

        return closing.future;
      }

      return null;
    });
    final player = output();
    await player.initialize();
    var completed = false;

    final shutdown = player.dispose();
    unawaited(shutdown.then((_) => completed = true));
    await closeStarted.future;

    expect(completed, isFalse);
    expect(identical(shutdown, player.dispose()), isTrue);
    expect(calls.last.arguments, {'id': 42});

    closing.complete();
    await shutdown;

    expect(completed, isTrue);
    expect(calls.where((call) => call.method == 'close'), hasLength(1));
  });

  test('dispose during open waits for the late handle to close once', () async {
    final opening = Completer<Object?>();
    final closing = Completer<Object?>();
    final openStarted = Completer<void>();
    final closeStarted = Completer<void>();
    mockChannel((call) async {
      if (call.method == 'open') {
        openStarted.complete();

        return opening.future;
      }

      if (call.method == 'close') {
        closeStarted.complete();

        return closing.future;
      }

      return null;
    });
    final player = output();
    final startup = player.initialize();
    await openStarted.future;
    var completed = false;

    final shutdown = player.dispose();
    unawaited(shutdown.then((_) => completed = true));
    expect(completed, isFalse);

    opening.complete(42);
    await closeStarted.future;

    expect(completed, isFalse);
    expect(calls.map((call) => call.method), ['open', 'close']);
    expect(calls.last.arguments, {'id': 42});

    closing.complete();
    await Future.wait([startup, shutdown]);
    await player.dispose();

    expect(completed, isTrue);
    expect(calls.where((call) => call.method == 'close'), hasLength(1));
  });

  test('dispose before initialize makes no native calls and prevents startup', () async {
    mockChannel((call) async => throw StateError('Unexpected native call: ${call.method}'));
    final player = output();

    await player.dispose();
    await player.dispose();
    await expectLater(player.initialize(), throwsStateError);

    expect(calls, isEmpty);
  });

  test('session stop owns pending output startup and awaits its release', () async {
    final transport = MemoryQuic();
    final player = _OpeningOutput();

    transport.onRequest = (startMs, seekId) =>
        transport.deliverRange(startMs: startMs, endMs: startMs + 2000, seekId: seekId, complete: false);

    final session = AudioPlaybackHarness(
      transport: transport,
      decoderFactory: MemoryOpusDecoder.new,
      outputFactory: (_, __, ___) => player,
    );

    try {
      session.start();
      await player.openStarted.future.timeout(const Duration(seconds: 2));
      var stopped = false;

      final stopping = session.requestStop();
      unawaited(stopping.then((_) => stopped = true));
      await Future<void>.delayed(Duration.zero);

      expect(player.closeRequested.isCompleted, isTrue);
      expect(stopped, isFalse);

      player.openAllowed.complete();
      await Future<void>.delayed(Duration.zero);

      expect(stopped, isFalse);

      player.closeAllowed.complete();
      await stopping.timeout(const Duration(seconds: 2));

      expect(stopped, isTrue);
      expect(player.disposed, isTrue);
      expect(player.releases, 1);
    } finally {
      if (!player.openAllowed.isCompleted) {
        player.openAllowed.complete();
      }

      if (!player.closeAllowed.isCompleted) {
        player.closeAllowed.complete();
      }

      await session.close().timeout(const Duration(seconds: 2));
    }
  });

  test('session close releases its transport while propagating an output-close failure', () async {
    final transport = MemoryQuic();
    final player = _FailingCloseOutput();

    transport.onRequest = (startMs, seekId) =>
        transport.deliverRange(startMs: startMs, endMs: startMs + 2000, seekId: seekId, complete: false);

    final session = AudioPlaybackHarness(
      transport: transport,
      decoderFactory: MemoryOpusDecoder.new,
      outputFactory: (_, __, ___) => player,
    );

    try {
      session.start();
      await waitUntil(() => player.writes > 0);

      await expectLater(session.close(), throwsA(same(player.closeFailure)));

      expect(transport.closed, isTrue);
      expect(player.disposed, isTrue);
      expect(player.releases, 1);
    } finally {
      if (!player.disposed) {
        await expectLater(session.close(), throwsA(same(player.closeFailure)));
      }
    }
  });
}

class _FailingCloseOutput extends MemoryPcmOutput {
  final StateError closeFailure = StateError('Native output close failed.');
  Future<void>? _shutdown;
  int releases = 0;

  @override
  Future<void> dispose() => _shutdown ??= _close();

  Future<void> _close() async {
    await super.dispose();

    releases++;

    throw closeFailure;
  }
}

class _OpeningOutput extends MemoryPcmOutput {
  final Completer<void> openStarted = Completer<void>();
  final Completer<void> openAllowed = Completer<void>();
  final Completer<void> closeRequested = Completer<void>();
  final Completer<void> closeAllowed = Completer<void>();
  Future<void>? _shutdown;
  int releases = 0;

  @override
  Future<void> initialize() {
    openStarted.complete();

    return openAllowed.future;
  }

  @override
  Future<void> dispose() => _shutdown ??= _close();

  Future<void> _close() async {
    closeRequested.complete();

    await openAllowed.future;
    await closeAllowed.future;
    await super.dispose();

    releases++;
  }
}
