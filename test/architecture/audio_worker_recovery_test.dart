import 'dart:async';
import 'dart:isolate';
import 'dart:ui' show RootIsolateToken;

import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/infrastructure/audio/engine/audio_engine.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';

import '../support/streaming_test_helpers.dart' show waitUntil;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('worker startup is explicit and initialization is idempotent', () async {
    final factory = _Workers();
    final engine = AudioEngine(workerSpawner: factory.spawn);

    expect(factory.attempts, 0);

    final first = engine.initialize();
    final second = engine.initialize();

    expect(identical(first, second), isTrue);
    await first;
    expect(factory.attempts, 1);

    factory.acknowledgeStops();
    await engine.dispose();
    factory.close();
  });

  test('shutdown waits for output release and worker retirement without listening statistics', () async {
    final factory = _Workers();
    final engine = AudioEngine(workerSpawner: factory.spawn);
    addTearDown(() async {
      factory.acknowledgeStops();
      await engine.dispose();
      factory.close();
    });

    await _play(engine, 'closing');
    await waitUntil(() => factory.latest.commands.any((command) => command['cmd'] == 'play'));
    final worker = factory.latest;
    worker.acknowledgeShutdown = false;
    var closed = false;
    final closing = engine.dispose().then((_) => closed = true);

    await waitUntil(() => worker.commands.any((command) => command['cmd'] == 'stop'));
    final stop = worker.commands.lastWhere((command) => command['cmd'] == 'stop');

    expect(closed, isFalse);
    expect(worker.killed, isFalse);
    worker.emit({'type': 'listening_flushed', 'flush_request_id': stop['flush_request_id']});

    await waitUntil(() => worker.commands.any((command) => command['cmd'] == 'dispose'));
    expect(closed, isFalse);
    expect(worker.killed, isFalse);
    worker.emit({'type': 'disposed'});

    await closing.timeout(const Duration(seconds: 1));
    expect(closed, isTrue);
    expect(worker.killed, isTrue);
  });

  test('source rejection cancels pending seek and clears on a new play', () async {
    final factory = _Workers();
    late AudioEngine engine;
    final rejectedStates = <bool>[];
    engine = AudioEngine(workerSpawner: factory.spawn, onState: (_, __) => rejectedStates.add(engine.sourceRejected));
    addTearDown(() async {
      factory.acknowledgeStops();
      await engine.dispose();
      factory.close();
    });
    await _play(engine, 'rejected');
    await waitUntil(() => factory.latest.commands.any((c) => c['cmd'] == 'play'));
    final worker = factory.latest;
    final oldId = worker.commands.lastWhere((c) => c['cmd'] == 'play')['playback_id'];
    final seek = engine.seekTo(const Duration(seconds: 10));
    await waitUntil(() => worker.commands.any((c) => c['cmd'] == 'seek'));
    worker.emit({'type': 'state', 'playback_id': oldId, 'active': false, 'paused': false, 'source_rejected': true});
    expect(await seek.timeout(const Duration(seconds: 1)), isFalse);
    expect(engine.sourceRejected, isTrue);
    expect(engine.hasActivePlayer, isFalse);
    expect(rejectedStates.last, isTrue);
    await _play(engine, 'valid');
    expect(engine.sourceRejected, isFalse);
    worker.emit({'type': 'state', 'playback_id': oldId, 'active': false, 'paused': false, 'source_rejected': true});
    await Future<void>.delayed(Duration.zero);
    expect(engine.sourceRejected, isFalse);
  });

  test('next play replaces an exited worker and restores current settings', () async {
    final factory = _Workers();
    final engine = AudioEngine(workerSpawner: factory.spawn);
    addTearDown(() async {
      factory.acknowledgeStops();
      await engine.dispose();
      factory.close();
    });
    engine.setVolume(0.35);
    engine.setOutputDevice(7);
    await _play(engine, 'first');
    await waitUntil(() => factory.latest.commands.any((item) => item['cmd'] == 'play'));
    final original = factory.latest;
    final seek = engine.seekTo(const Duration(seconds: 10));
    original.exit();
    expect(await seek.timeout(const Duration(seconds: 1)), isFalse);
    expect(engine.hasActivePlayer, isFalse);

    engine.setVolume(0.6);
    engine.setOutputDevice(9);
    await engine.stop();
    expect(factory.attempts, 1);
    await _play(engine, 'second', paused: true);
    await waitUntil(() => factory.latest.commands.any((item) => item['cmd'] == 'play'));
    final replacement = factory.latest;
    expect(factory.attempts, 2);
    expect(original.killed, isTrue);
    expect(replacement.killed, isFalse);
    expect(engine.hasActivePlayer, isTrue);
    expect(engine.isPaused, isTrue);
    final playIndex = replacement.commands.indexWhere((item) => item['cmd'] == 'play');
    expect(
      replacement.commands.take(playIndex),
      containsAll([
        {'cmd': 'volume', 'value': 0.6},
        {'cmd': 'device', 'device_id': 9},
      ]),
    );
    expect(replacement.commands[playIndex]['track_id'], 'second');
    expect(replacement.commands[playIndex]['initial_paused'], isTrue);
  });

  test('output reset retires an unresponsive isolate and paused playback replaces it', () async {
    final workers = <_MemoryIsolateWorker>[];
    final messages = <String>[];
    final engine = AudioEngine(
      workerSpawner: (port, _) async {
        final worker = await _MemoryIsolateWorker.spawn(port, acknowledgeStops: workers.isNotEmpty);
        workers.add(worker);
        return worker;
      },
      onMessage: messages.add,
    );
    addTearDown(() async {
      await engine.dispose();
      for (final worker in workers) {
        worker.kill();
      }
    });

    await _play(engine, 'orphaned-output');
    await waitUntil(() => workers.isNotEmpty && workers.first.commands.any((command) => command['cmd'] == 'play'));
    final original = workers.single;
    var resetFinished = false;
    final elapsed = Stopwatch()..start();
    final resetting = engine.resetOutput().then((_) => resetFinished = true);

    await waitUntil(() => original.commands.any((command) => command['cmd'] == 'stop'));
    expect(resetFinished, isFalse);
    expect(original.killed, isFalse);
    await resetting.timeout(const Duration(seconds: 3));
    expect(elapsed.elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 1900)));
    expect(original.killed, isTrue);
    await original.exited.timeout(const Duration(seconds: 1));
    expect(engine.hasActivePlayer, isFalse);
    expect(messages.any((message) => message.contains('forced worker retirement')), isTrue);

    await _play(engine, 'replacement', paused: true);
    await waitUntil(() => workers.length == 2 && workers.last.commands.any((command) => command['cmd'] == 'play'));
    final replacement = workers.last;
    expect(replacement.killed, isFalse);
    expect(replacement.commands.singleWhere((command) => command['cmd'] == 'play')['initial_paused'], isTrue);

    original.messages.send({'type': 'state', 'active': false, 'paused': false, 'source_rejected': true});
    original.messages.send({'type': 'complete'});
    original.messages.send(null);
    replacement.messages.send({'type': 'message', 'text': 'replacement still alive'});
    await waitUntil(() => messages.contains('replacement still alive'));
    expect(engine.hasActivePlayer, isTrue);
    expect(engine.isPaused, isTrue);
    expect(engine.sourceRejected, isFalse);
    expect(replacement.killed, isFalse);
  });

  test('output reset requires a fresh release after a weaker stop times out', () async {
    final workers = <_MemoryIsolateWorker>[];
    final engine = AudioEngine(
      workerSpawner: (port, _) async {
        final worker = await _MemoryIsolateWorker.spawn(port, acknowledgeStops: workers.isNotEmpty);
        workers.add(worker);
        return worker;
      },
    )..configureListening({'session_id': 'orphaned-output'});
    addTearDown(() async {
      await engine.dispose();
      for (final worker in workers) {
        worker.kill();
      }
    });

    await _play(engine, 'orphaned-output');
    await waitUntil(() => workers.isNotEmpty && workers.first.commands.any((command) => command['cmd'] == 'play'));
    final original = workers.single;
    final stopping = engine.stop();

    await waitUntil(() => original.commands.any((command) => command['cmd'] == 'stop'));
    var resetFinished = false;
    final resetting = engine.resetOutput().then((_) => resetFinished = true);

    await stopping.timeout(const Duration(seconds: 3));
    await waitUntil(() => original.commands.where((command) => command['cmd'] == 'stop').length == 2);
    expect(resetFinished, isFalse);
    expect(original.killed, isFalse);

    final stops = original.commands.where((command) => command['cmd'] == 'stop').toList();
    expect(stops.last['flush_request_id'], greaterThan(stops.first['flush_request_id'] as int));
    await resetting.timeout(const Duration(seconds: 3));
    expect(original.killed, isTrue);
    await original.exited.timeout(const Duration(seconds: 1));

    await _play(engine, 'replacement', paused: true);
    await waitUntil(() => workers.length == 2 && workers.last.commands.any((command) => command['cmd'] == 'play'));
    expect(engine.hasActivePlayer, isTrue);
    expect(engine.isPaused, isTrue);
    expect(workers.last.killed, isFalse);
  });

  test('failed startup is retried only by a new remote or local play', () async {
    final factory = _Workers()..failNext = true;
    final states = <(bool, bool)>[];
    final engine = AudioEngine(workerSpawner: factory.spawn, onState: (active, paused) => states.add((active, paused)));
    addTearDown(() async {
      factory.acknowledgeStops();
      await engine.dispose();
      factory.close();
    });
    await _play(engine, 'first');
    await waitUntil(() => states.contains((false, false)));
    engine.setVolume(0.2);
    engine.setOutputDevice(3);
    engine.pause();
    await engine.stop();
    expect(factory.attempts, 1);

    await engine.playLocalFile(track: _track('downloaded'), filePath: 'unused.fake', initialPaused: true);
    await waitUntil(() => factory.latest.commands.any((item) => item['cmd'] == 'play_local'));
    expect(factory.attempts, 2);
    expect(engine.hasActivePlayer, isTrue);
    expect(engine.isPaused, isTrue);
    expect(factory.latest.commands.firstWhere((item) => item['cmd'] == 'play_local')['track_id'], 'downloaded');
  });

  test('late old spawn and messages cannot retire the replacement worker', () async {
    final initialResult = Completer<AudioWorkerHandle>();
    final factory = _Workers()..firstResult = initialResult;
    final engine = AudioEngine(workerSpawner: factory.spawn);
    addTearDown(() async {
      if (!initialResult.isCompleted) {
        initialResult.complete(factory.workers.first);
      }
      factory.acknowledgeStops();
      await engine.dispose();
      factory.close();
    });
    await _play(engine, 'retired');
    final original = factory.latest;
    original.crash();
    await waitUntil(() => !engine.hasActivePlayer);
    await _play(engine, 'current');
    await waitUntil(() => factory.latest.commands.any((item) => item['cmd'] == 'play'));
    final replacement = factory.latest;
    original.ready();
    original.emit({'type': 'state', 'active': false, 'paused': false});
    original.exit();
    initialResult.complete(original);
    await waitUntil(() => original.killed);
    engine.pause();
    await waitUntil(() => replacement.commands.any((item) => item['cmd'] == 'pause'));

    expect(engine.hasActivePlayer, isTrue);
    expect(replacement.killed, isFalse);
    expect(original.commands, isEmpty);
    expect(replacement.commands.where((item) => item['cmd'] == 'play').single['track_id'], 'current');
  });

  test('dispose releases pending startup and ignores a late worker handshake', () async {
    final initialResult = Completer<AudioWorkerHandle>();
    final factory = _Workers()..firstResult = initialResult;
    final engine = AudioEngine(workerSpawner: factory.spawn);
    addTearDown(() async {
      if (!initialResult.isCompleted) {
        initialResult.complete(factory.workers.first);
      }
      factory.acknowledgeStops();
      await engine.dispose();
      factory.close();
    });
    await _play(engine, 'cancelled');
    final original = factory.latest;
    final seek = engine.seekTo(const Duration(seconds: 10));
    await engine.dispose().timeout(const Duration(seconds: 1));
    expect(await seek.timeout(const Duration(seconds: 1)), isFalse);
    original.ready();
    initialResult.complete(original);
    await waitUntil(() => original.killed);
    await _play(engine, 'ignored');
    expect(original.commands, isEmpty);
    expect(factory.attempts, 1);
    expect(engine.hasActivePlayer, isFalse);
  });

  for (final acknowledge in [true, false]) {
    test('local deletion requires a stop acknowledgment without listening stats: $acknowledge', () async {
      final factory = _Workers();
      final engine = AudioEngine(workerSpawner: factory.spawn);
      addTearDown(() async {
        factory.acknowledgeStops();
        await engine.dispose();
        factory.close();
      });
      await engine.playLocalFile(track: _track('saved'), filePath: 'unused.fake');
      await waitUntil(() => factory.latest.commands.any((command) => command['cmd'] == 'play_local'));
      var finished = false;
      final stopping = engine.stop(waitForRelease: true).then((_) => finished = true);
      final failure = acknowledge ? null : expectLater(stopping, throwsA(isA<TimeoutException>()));
      await waitUntil(
        () => factory.latest.commands.any((command) => command['cmd'] == 'stop' && command['flush_request_id'] is int),
      );
      expect(finished, isFalse);
      if (acknowledge) {
        final request = factory.latest.commands.lastWhere(
          (command) => command['cmd'] == 'stop' && command['flush_request_id'] is int,
        );
        factory.latest.emit({'type': 'listening_flushed', 'flush_request_id': request['flush_request_id']});
        await stopping.timeout(const Duration(seconds: 1));
        expect(finished, isTrue);
      } else {
        await failure;
        expect(finished, isFalse);
      }
    });
  }

  test('stop waits for its own flush acknowledgment and final listening interval', () async {
    final factory = _Workers();
    final messages = <String>[];
    final segments = <Map<String, dynamic>>[];
    final engine = AudioEngine(workerSpawner: factory.spawn, onMessage: messages.add)
      ..onListeningSegment = segments.add
      ..configureListening({'session_id': 'listening-session'});
    addTearDown(() async {
      if (factory.workers.isNotEmpty) {
        final stops = factory.latest.commands.where((item) => item['cmd'] == 'stop');
        if (stops.isNotEmpty) {
          factory.latest.emit({'type': 'listening_flushed', 'flush_request_id': stops.last['flush_request_id']});
        }
      }
      engine.configureListening(null);
      factory.acknowledgeStops();
      await engine.dispose();
      factory.close();
    });
    await _play(engine, 'listening');
    await waitUntil(() => factory.latest.commands.any((item) => item['cmd'] == 'play'));
    final worker = factory.latest;

    final firstStop = engine.stop();
    await waitUntil(() => worker.commands.any((item) => item['cmd'] == 'stop'));
    final firstRequest = worker.commands.lastWhere((item) => item['cmd'] == 'stop')['flush_request_id'];
    expect(firstRequest, isA<int>());
    worker.emit({'type': 'listening_flushed', 'flush_request_id': firstRequest});
    await firstStop.timeout(const Duration(seconds: 1));

    var stopped = false;
    final secondStop = engine.stop().then((_) => stopped = true);
    await waitUntil(() => worker.commands.where((item) => item['cmd'] == 'stop').length == 2);
    final currentRequest = worker.commands.lastWhere((item) => item['cmd'] == 'stop')['flush_request_id'];
    expect(currentRequest, greaterThan(firstRequest as int));
    worker.emit({'type': 'listening_flushed'});
    worker.emit({'type': 'listening_flushed', 'flush_request_id': firstRequest});
    worker.emit({'type': 'message', 'text': 'stale acknowledgments processed'});
    await waitUntil(() => messages.contains('stale acknowledgments processed'));
    expect(stopped, isFalse);

    worker.emit({
      'type': 'listening_segment',
      'event': {'event_id': 'final-interval'},
    });
    worker.emit({'type': 'listening_flushed', 'flush_request_id': currentRequest});
    await secondStop.timeout(const Duration(seconds: 1));
    expect(stopped, isTrue);
    expect(segments.single['event_id'], 'final-interval');
  });

  test('concurrent stop and dispose share one flush and retain its final interval', () async {
    final factory = _Workers();
    final messages = <String>[];
    final segments = <Map<String, dynamic>>[];
    final engine = AudioEngine(workerSpawner: factory.spawn, onMessage: messages.add)
      ..onListeningSegment = segments.add
      ..configureListening({'session_id': 'shutdown-session'});
    addTearDown(() async {
      if (factory.workers.isNotEmpty) {
        final stops = factory.latest.commands.where((item) => item['cmd'] == 'stop');
        if (stops.isNotEmpty) {
          factory.latest.emit({'type': 'listening_flushed', 'flush_request_id': stops.last['flush_request_id']});
        }
      }
      engine.configureListening(null);
      factory.acknowledgeStops();
      await engine.dispose();
      factory.close();
    });
    await _play(engine, 'shutdown');
    await waitUntil(() => factory.latest.commands.any((item) => item['cmd'] == 'play'));
    final worker = factory.latest;
    var stopped = false;
    var disposed = false;
    final stopping = engine.stop().then((_) => stopped = true);
    final disposing = engine.dispose().then((_) => disposed = true);
    await waitUntil(() => worker.commands.any((item) => item['cmd'] == 'stop'));
    worker.emit({'type': 'message', 'text': 'shutdown pending'});
    await waitUntil(() => messages.contains('shutdown pending'));
    expect(worker.commands.where((item) => item['cmd'] == 'stop'), hasLength(1));
    expect(stopped, isFalse);
    expect(disposed, isFalse);
    expect(worker.killed, isFalse);

    final request = worker.commands.singleWhere((item) => item['cmd'] == 'stop')['flush_request_id'];
    expect(request, isA<int>());
    worker.emit({
      'type': 'listening_segment',
      'event': {'event_id': 'shutdown-tail'},
    });
    worker.emit({'type': 'listening_flushed', 'flush_request_id': request});
    await Future.wait([stopping, disposing]).timeout(const Duration(seconds: 1));
    expect(stopped, isTrue);
    expect(disposed, isTrue);
    expect(worker.killed, isTrue);
    expect(worker.commands.where((item) => item['cmd'] == 'stop'), hasLength(1));
    expect(segments.single['event_id'], 'shutdown-tail');
  });
}

Future<void> _play(AudioEngine engine, String id, {bool paused = false}) => engine.playTrack(
  track: _track(id),
  connection: ServerConnection(baseUrl: 'http://unused.test'),
  settings: const StreamSettings(mode: 'fixed', quality: 'high'),
  initialPaused: paused,
);

Track _track(String id) =>
    Track(id: id, title: id, artist: 'Artist', album: 'Album', durationMs: 60000, liked: false, inPlaylists: false);

class _Workers {
  int attempts = 0;
  bool failNext = false;
  Completer<AudioWorkerHandle>? firstResult;
  final workers = <_Worker>[];
  _Worker get latest => workers.last;

  Future<AudioWorkerHandle> spawn(SendPort messages, RootIsolateToken? token) async {
    attempts++;
    if (failNext) {
      failNext = false;
      throw StateError('Injected worker startup failure');
    }
    final worker = _Worker(messages);
    workers.add(worker);
    if (attempts == 1 && firstResult != null) return firstResult!.future;
    worker.ready();
    return worker;
  }

  void acknowledgeStops() {
    for (final worker in workers) {
      worker.acknowledgeStops = true;
    }
  }

  void close() {
    for (final worker in workers) {
      worker.kill();
    }
  }
}

class _Worker implements AudioWorkerHandle {
  _Worker(this.messages) {
    commandsPort.listen((item) {
      final command = Map<String, dynamic>.from(item as Map);
      commands.add(command);
      if (acknowledgeShutdown && command['cmd'] == 'dispose') {
        emit({'type': 'disposed'});
      } else if (acknowledgeStops && command['cmd'] == 'stop') {
        emit({'type': 'listening_flushed', 'flush_request_id': command['flush_request_id']});
      }
    });
  }
  final SendPort messages;
  final commandsPort = ReceivePort();
  final commands = <Map<String, dynamic>>[];
  bool killed = false;
  bool acknowledgeStops = false;
  bool acknowledgeShutdown = true;
  void ready() => messages.send(commandsPort.sendPort);
  void crash() => messages.send(['Injected worker failure', 'stack']);
  void exit() => messages.send(null);
  void emit(Map<String, dynamic> message) => messages.send(message);

  @override
  void kill() {
    killed = true;
    commandsPort.close();
  }
}

/// Exercises actual isolate retirement without opening an audio device.
class _MemoryIsolateWorker implements AudioWorkerHandle {
  final Isolate isolate;
  final ReceivePort observations;
  final SendPort messages;
  final List<Map<String, dynamic>> commands;
  final Future<void> exited;
  bool killed = false;

  _MemoryIsolateWorker(this.isolate, this.observations, this.messages, this.commands, this.exited);

  static Future<_MemoryIsolateWorker> spawn(SendPort messages, {required bool acknowledgeStops}) async {
    final observations = ReceivePort();
    final exits = ReceivePort();
    final exited = Completer<void>();
    final commands = <Map<String, dynamic>>[];

    observations.listen((command) => commands.add(Map<String, dynamic>.from(command as Map)));
    exits.listen((_) {
      exited.complete();
      exits.close();
    });

    final isolate = await Isolate.spawn(_memoryWorkerMain, (
      messages,
      observations.sendPort,
      acknowledgeStops,
    ), onExit: exits.sendPort);

    return _MemoryIsolateWorker(isolate, observations, messages, commands, exited.future);
  }

  @override
  void kill() {
    killed = true;
    isolate.kill(priority: Isolate.immediate);
    observations.close();
  }
}

void _memoryWorkerMain((SendPort, SendPort, bool) initialization) async {
  final (messages, observations, acknowledgeStops) = initialization;
  final commands = ReceivePort();

  messages.send(commands.sendPort);

  await for (final item in commands) {
    final command = item as Map;

    observations.send(command);

    if (acknowledgeStops && command['cmd'] == 'stop') {
      messages.send({'type': 'listening_flushed', 'flush_request_id': command['flush_request_id']});
    } else if (command['cmd'] == 'dispose') {
      messages.send({'type': 'disposed'});
      commands.close();
    }
  }
}
