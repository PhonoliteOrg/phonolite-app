import 'dart:async';
import 'dart:isolate';
import 'dart:ui' show RootIsolateToken;

import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/entities/audio_engine.dart';
import 'package:phonolite_app/entities/models.dart';
import 'package:phonolite_app/entities/server_connection.dart';

import '../support/streaming_test_helpers.dart' show waitUntil;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'source rejection cancels pending seek and clears on a new play',
    () async {
      final factory = _Workers();
      late AudioEngine engine;
      final rejectedStates = <bool>[];
      engine = AudioEngine(
        workerSpawner: factory.spawn,
        onState: (_, __) => rejectedStates.add(engine.sourceRejected),
      );
      addTearDown(() async {
        await engine.dispose();
        factory.close();
      });
      await _play(engine, 'rejected');
      await waitUntil(
        () => factory.latest.commands.any((c) => c['cmd'] == 'play'),
      );
      final worker = factory.latest;
      final oldId = worker.commands.lastWhere(
        (c) => c['cmd'] == 'play',
      )['playback_id'];
      final seek = engine.seekTo(const Duration(seconds: 10));
      await waitUntil(() => worker.commands.any((c) => c['cmd'] == 'seek'));
      worker.emit({
        'type': 'state',
        'playback_id': oldId,
        'active': false,
        'paused': false,
        'source_rejected': true,
      });
      expect(await seek.timeout(const Duration(seconds: 1)), isFalse);
      expect(engine.sourceRejected, isTrue);
      expect(engine.hasActivePlayer, isFalse);
      expect(rejectedStates.last, isTrue);
      await _play(engine, 'valid');
      expect(engine.sourceRejected, isFalse);
      worker.emit({
        'type': 'state',
        'playback_id': oldId,
        'active': false,
        'paused': false,
        'source_rejected': true,
      });
      await Future<void>.delayed(Duration.zero);
      expect(engine.sourceRejected, isFalse);
    },
  );

  test(
    'next play replaces an exited worker and restores current settings',
    () async {
      final factory = _Workers();
      final engine = AudioEngine(workerSpawner: factory.spawn);
      addTearDown(() async {
        await engine.dispose();
        factory.close();
      });
      engine.setVolume(0.35);
      engine.setOutputDevice(7);
      await _play(engine, 'first');
      await waitUntil(
        () => factory.latest.commands.any((item) => item['cmd'] == 'play'),
      );
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
      await waitUntil(
        () => factory.latest.commands.any((item) => item['cmd'] == 'play'),
      );
      final replacement = factory.latest;
      expect(factory.attempts, 2);
      expect(original.killed, isTrue);
      expect(replacement.killed, isFalse);
      expect(engine.hasActivePlayer, isTrue);
      expect(engine.isPaused, isTrue);
      final playIndex = replacement.commands.indexWhere(
        (item) => item['cmd'] == 'play',
      );
      expect(
        replacement.commands.take(playIndex),
        containsAll([
          {'cmd': 'volume', 'value': 0.6},
          {'cmd': 'device', 'device_id': 9},
        ]),
      );
      expect(replacement.commands[playIndex]['track_id'], 'second');
      expect(replacement.commands[playIndex]['initial_paused'], isTrue);
    },
  );

  test(
    'failed startup is retried only by a new remote or local play',
    () async {
      final factory = _Workers()..failNext = true;
      final states = <(bool, bool)>[];
      final engine = AudioEngine(
        workerSpawner: factory.spawn,
        onState: (active, paused) => states.add((active, paused)),
      );
      addTearDown(() async {
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

      await engine.playLocalFile(
        track: _track('downloaded'),
        filePath: 'unused.fake',
        initialPaused: true,
      );
      await waitUntil(
        () =>
            factory.latest.commands.any((item) => item['cmd'] == 'play_local'),
      );
      expect(factory.attempts, 2);
      expect(engine.hasActivePlayer, isTrue);
      expect(engine.isPaused, isTrue);
      expect(
        factory.latest.commands.firstWhere(
          (item) => item['cmd'] == 'play_local',
        )['track_id'],
        'downloaded',
      );
    },
  );

  test(
    'late old spawn and messages cannot retire the replacement worker',
    () async {
      final initialResult = Completer<AudioWorkerHandle>();
      final factory = _Workers()..firstResult = initialResult;
      final engine = AudioEngine(workerSpawner: factory.spawn);
      addTearDown(() async {
        if (!initialResult.isCompleted) {
          initialResult.complete(factory.workers.first);
        }
        await engine.dispose();
        factory.close();
      });
      await _play(engine, 'retired');
      final original = factory.latest;
      original.crash();
      await waitUntil(() => !engine.hasActivePlayer);
      await _play(engine, 'current');
      await waitUntil(
        () => factory.latest.commands.any((item) => item['cmd'] == 'play'),
      );
      final replacement = factory.latest;
      original.ready();
      original.emit({'type': 'state', 'active': false, 'paused': false});
      original.exit();
      initialResult.complete(original);
      await waitUntil(() => original.killed);
      engine.pause();
      await waitUntil(
        () => replacement.commands.any((item) => item['cmd'] == 'pause'),
      );

      expect(engine.hasActivePlayer, isTrue);
      expect(replacement.killed, isFalse);
      expect(original.commands, isEmpty);
      expect(
        replacement.commands
            .where((item) => item['cmd'] == 'play')
            .single['track_id'],
        'current',
      );
    },
  );

  test(
    'dispose releases pending startup and ignores a late worker handshake',
    () async {
      final initialResult = Completer<AudioWorkerHandle>();
      final factory = _Workers()..firstResult = initialResult;
      final engine = AudioEngine(workerSpawner: factory.spawn);
      addTearDown(() async {
        if (!initialResult.isCompleted) {
          initialResult.complete(factory.workers.first);
        }
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
    },
  );

  for (final acknowledge in [true, false]) {
    test(
      'local deletion requires a stop acknowledgment without listening stats: $acknowledge',
      () async {
        final factory = _Workers();
        final engine = AudioEngine(workerSpawner: factory.spawn);
        addTearDown(() async {
          await engine.dispose();
          factory.close();
        });
        await engine.playLocalFile(
          track: _track('saved'),
          filePath: 'unused.fake',
        );
        await waitUntil(
          () => factory.latest.commands.any(
            (command) => command['cmd'] == 'play_local',
          ),
        );
        var finished = false;
        final stopping = engine
            .stop(waitForRelease: true)
            .then((_) => finished = true);
        final failure = acknowledge
            ? null
            : expectLater(stopping, throwsA(isA<TimeoutException>()));
        await waitUntil(
          () => factory.latest.commands.any(
            (command) =>
                command['cmd'] == 'stop' && command['flush_request_id'] is int,
          ),
        );
        expect(finished, isFalse);
        if (acknowledge) {
          final request = factory.latest.commands.lastWhere(
            (command) =>
                command['cmd'] == 'stop' && command['flush_request_id'] is int,
          );
          factory.latest.emit({
            'type': 'listening_flushed',
            'flush_request_id': request['flush_request_id'],
          });
          await stopping.timeout(const Duration(seconds: 1));
          expect(finished, isTrue);
        } else {
          await failure;
          expect(finished, isFalse);
        }
      },
    );
  }

  test(
    'stop waits for its own flush acknowledgment and final listening interval',
    () async {
      final factory = _Workers();
      final messages = <String>[];
      final segments = <Map<String, dynamic>>[];
      final engine =
          AudioEngine(workerSpawner: factory.spawn, onMessage: messages.add)
            ..onListeningSegment = segments.add
            ..configureListening({'session_id': 'listening-session'});
      addTearDown(() async {
        if (factory.workers.isNotEmpty) {
          final stops = factory.latest.commands.where(
            (item) => item['cmd'] == 'stop',
          );
          if (stops.isNotEmpty) {
            factory.latest.emit({
              'type': 'listening_flushed',
              'flush_request_id': stops.last['flush_request_id'],
            });
          }
        }
        engine.configureListening(null);
        await engine.dispose();
        factory.close();
      });
      await _play(engine, 'listening');
      await waitUntil(
        () => factory.latest.commands.any((item) => item['cmd'] == 'play'),
      );
      final worker = factory.latest;

      final firstStop = engine.stop();
      await waitUntil(
        () => worker.commands.any((item) => item['cmd'] == 'stop'),
      );
      final firstRequest = worker.commands.lastWhere(
        (item) => item['cmd'] == 'stop',
      )['flush_request_id'];
      expect(firstRequest, isA<int>());
      worker.emit({
        'type': 'listening_flushed',
        'flush_request_id': firstRequest,
      });
      await firstStop.timeout(const Duration(seconds: 1));

      var stopped = false;
      final secondStop = engine.stop().then((_) => stopped = true);
      await waitUntil(
        () =>
            worker.commands.where((item) => item['cmd'] == 'stop').length == 2,
      );
      final currentRequest = worker.commands.lastWhere(
        (item) => item['cmd'] == 'stop',
      )['flush_request_id'];
      expect(currentRequest, greaterThan(firstRequest as int));
      worker.emit({'type': 'listening_flushed'});
      worker.emit({
        'type': 'listening_flushed',
        'flush_request_id': firstRequest,
      });
      worker.emit({
        'type': 'message',
        'text': 'stale acknowledgments processed',
      });
      await waitUntil(
        () => messages.contains('stale acknowledgments processed'),
      );
      expect(stopped, isFalse);

      worker.emit({
        'type': 'listening_segment',
        'event': {'event_id': 'final-interval'},
      });
      worker.emit({
        'type': 'listening_flushed',
        'flush_request_id': currentRequest,
      });
      await secondStop.timeout(const Duration(seconds: 1));
      expect(stopped, isTrue);
      expect(segments.single['event_id'], 'final-interval');
    },
  );

  test(
    'concurrent stop and dispose share one flush and retain its final interval',
    () async {
      final factory = _Workers();
      final messages = <String>[];
      final segments = <Map<String, dynamic>>[];
      final engine =
          AudioEngine(workerSpawner: factory.spawn, onMessage: messages.add)
            ..onListeningSegment = segments.add
            ..configureListening({'session_id': 'shutdown-session'});
      addTearDown(() async {
        if (factory.workers.isNotEmpty) {
          final stops = factory.latest.commands.where(
            (item) => item['cmd'] == 'stop',
          );
          if (stops.isNotEmpty) {
            factory.latest.emit({
              'type': 'listening_flushed',
              'flush_request_id': stops.last['flush_request_id'],
            });
          }
        }
        engine.configureListening(null);
        await engine.dispose();
        factory.close();
      });
      await _play(engine, 'shutdown');
      await waitUntil(
        () => factory.latest.commands.any((item) => item['cmd'] == 'play'),
      );
      final worker = factory.latest;
      var stopped = false;
      var disposed = false;
      final stopping = engine.stop().then((_) => stopped = true);
      final disposing = engine.dispose().then((_) => disposed = true);
      await waitUntil(
        () => worker.commands.any((item) => item['cmd'] == 'stop'),
      );
      worker.emit({'type': 'message', 'text': 'shutdown pending'});
      await waitUntil(() => messages.contains('shutdown pending'));
      expect(
        worker.commands.where((item) => item['cmd'] == 'stop'),
        hasLength(1),
      );
      expect(stopped, isFalse);
      expect(disposed, isFalse);
      expect(worker.killed, isFalse);

      final request = worker.commands.singleWhere(
        (item) => item['cmd'] == 'stop',
      )['flush_request_id'];
      expect(request, isA<int>());
      worker.emit({
        'type': 'listening_segment',
        'event': {'event_id': 'shutdown-tail'},
      });
      worker.emit({'type': 'listening_flushed', 'flush_request_id': request});
      await Future.wait([
        stopping,
        disposing,
      ]).timeout(const Duration(seconds: 1));
      expect(stopped, isTrue);
      expect(disposed, isTrue);
      expect(worker.killed, isTrue);
      expect(
        worker.commands.where((item) => item['cmd'] == 'stop'),
        hasLength(1),
      );
      expect(segments.single['event_id'], 'shutdown-tail');
    },
  );
}

Future<void> _play(AudioEngine engine, String id, {bool paused = false}) =>
    engine.playTrack(
      track: _track(id),
      connection: ServerConnection(baseUrl: 'http://unused.test'),
      settings: const StreamSettings(mode: 'fixed', quality: 'high'),
      initialPaused: paused,
    );

Track _track(String id) => Track(
  id: id,
  title: id,
  artist: 'Artist',
  album: 'Album',
  durationMs: 60000,
  liked: false,
  inPlaylists: false,
);

class _Workers {
  int attempts = 0;
  bool failNext = false;
  Completer<AudioWorkerHandle>? firstResult;
  final workers = <_Worker>[];
  _Worker get latest => workers.last;

  Future<AudioWorkerHandle> spawn(
    SendPort messages,
    RootIsolateToken? token,
  ) async {
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

  void close() {
    for (final worker in workers) {
      worker.kill();
    }
  }
}

class _Worker implements AudioWorkerHandle {
  _Worker(this.messages) {
    commandsPort.listen((item) {
      commands.add(Map<String, dynamic>.from(item as Map));
    });
  }
  final SendPort messages;
  final commandsPort = ReceivePort();
  final commands = <Map<String, dynamic>>[];
  bool killed = false;
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
