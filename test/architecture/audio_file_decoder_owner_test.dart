import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_quic/phonolite_quic.dart';

import 'package:phonolite_app/data/models/audio/audio_file_format.dart';
import 'package:phonolite_app/infrastructure/audio/decoding/audio_file_decoder.dart';

void main() {
  final library = Platform.environment['PHONOLITE_QUIC_LIBRARY'];
  final enabled = library != null && File(library).existsSync();

  for (final scenario in [
    (duringOpen: false, silentExit: false),
    (duringOpen: true, silentExit: false),
    (duringOpen: true, silentExit: true),
  ]) {
    final duringOpen = scenario.duringOpen;
    test('parent cancellation interrupts a decoder blocked during ${duringOpen ? 'open' : 'read'}, '
        'silent exit=${scenario.silentExit}', () async {
      final activity = ReceivePort();
      final blocked = Completer<void>();
      final subscription = activity.listen((_) => blocked.complete());
      var ownerId = 0;
      final decoder = AudioFileDecoder.quic(
        host: 'unused.test',
        port: 4321,
        trackId: 'memory',
        token: 'unused',
        serverPin: 'unused',
        workerSpawner: (configuration, errors, exit) {
          ownerId = configuration['quic_owner_id'] as int;
          return Isolate.spawn(
            _memoryDecoder,
            {
              ...configuration,
              'activity': activity.sendPort,
              'block_open': duringOpen,
              'silent_exit': scenario.silentExit,
            },
            onError: errors,
            onExit: exit,
            errorsAreFatal: true,
          );
        },
      );
      addTearDown(() async {
        await decoder.close();
        await subscription.cancel();
        activity.close();
      });

      final initializing = decoder.initialize();
      late Future<void> failure;
      if (duringOpen) {
        failure = expectLater(initializing, throwsStateError);
      } else {
        await initializing;
        failure = expectLater(decoder.read32(4096), throwsStateError);
      }
      await blocked.future.timeout(const Duration(seconds: 2));
      final started = Stopwatch()..start();
      await decoder.close().timeout(const Duration(seconds: 1));
      await failure;
      expect(started.elapsed, lessThan(const Duration(seconds: 1)));
      expect(_ownerAlive()(ownerId), 0, reason: 'Closing also releases the registry entry.');
    }, skip: enabled ? false : 'Set PHONOLITE_QUIC_LIBRARY to the built native client DLL.');
  }

  test('a seek epoch interrupts a blocked read and accepts only the latest target', () async {
    final activity = ReceivePort();
    final blocked = Completer<void>();
    final subscription = activity.listen((_) => blocked.complete());
    final decoder = AudioFileDecoder.quic(
      host: 'unused.test',
      port: 4321,
      trackId: 'memory',
      token: 'unused',
      serverPin: 'unused',
      workerSpawner: (configuration, errors, exit) => Isolate.spawn(
        _memoryDecoder,
        {...configuration, 'activity': activity.sendPort},
        onError: errors,
        onExit: exit,
        errorsAreFatal: true,
      ),
    );
    addTearDown(() async {
      await decoder.close();
      await subscription.cancel();
      activity.close();
    });
    await decoder.initialize();
    final reading = expectLater(decoder.read32(4096), throwsStateError);
    await blocked.future.timeout(const Duration(seconds: 2));
    final started = Stopwatch()..start();
    final obsoleteSeek = expectLater(decoder.seek(const Duration(milliseconds: 50)), throwsStateError);
    decoder.interruptRead();
    final latestSeek = decoder.seek(const Duration(milliseconds: 200));
    await reading;
    await obsoleteSeek;
    expect(await latestSeek.timeout(const Duration(seconds: 1)), const Duration(milliseconds: 200));
    expect(started.elapsed, lessThan(const Duration(seconds: 1)));
  }, skip: enabled ? false : 'Set PHONOLITE_QUIC_LIBRARY to the built native client DLL.');
}

int Function(int) _ownerAlive() => ffi.DynamicLibrary.open(
  Platform.environment['PHONOLITE_QUIC_LIBRARY']!,
).lookupFunction<ffi.Int32 Function(ffi.Uint64), int Function(int)>('phonolite_quic_owner_alive');

/// A real isolate performing only synchronous memory/atomic checks, never audio
/// or network calls. It cannot process its queued close while this loop runs.
Future<void> _memoryDecoder(Map<String, dynamic> configuration) async {
  final reply = configuration['reply'] as SendPort;
  final activity = configuration['activity'] as SendPort;
  final owner = configuration['quic_owner_id'] as int;
  final ownerAlive = _ownerAlive();
  final commands = ReceivePort();
  reply.send({'type': 'commands', 'port': commands.sendPort});
  await for (final raw in commands) {
    if (raw == 'heartbeat') continue;
    if (raw == 'owner_exit') break;
    final command = raw as Map;
    final opening = command['command'] == 'open';
    final epoch = command['operation_epoch'] as int? ?? 0;
    if (!opening && command['command'] != 'close' && !QuicOwnerLease.beginOperation(owner, epoch)) {
      reply.send({'id': command['id'], 'error': 'Superseded.'});
      continue;
    }
    if ((opening && configuration['block_open'] == true) || command['command'] == 'read') {
      activity.send('blocked');
      while (ownerAlive(owner) != 0 && QuicOwnerLease.beginOperation(owner, epoch)) {
        sleep(const Duration(milliseconds: 2));
      }
      if (configuration['silent_exit'] == true && ownerAlive(owner) == 0) break;
      reply.send({'id': command['id'], 'error': 'Owner cancelled.'});
      if (ownerAlive(owner) == 0) break;
      continue;
    }
    if (opening) {
      reply.send({
        'type': 'ready',
        'format': const AudioFileFormat(sampleRate: 48000, channels: 2, bitDepth: 16, duration: Duration(seconds: 1)),
      });
    } else if (command['command'] == 'seek') {
      reply.send({'id': command['id'], 'position_ms': command['position_ms']});
    } else if (command['command'] == 'close') {
      reply.send({'id': command['id']});
      break;
    }
  }
  commands.close();
}
