import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/application/workflows/serial_action_queue.dart';

void main() {
  test('failed actions report their error without blocking later actions', () async {
    final queue = SerialActionQueue();
    final firstGate = Completer<void>();
    final events = <String>[];
    final first = queue.add(() async {
      events.add('first started');
      await firstGate.future;

      throw StateError('write failed');
    });
    final failure = expectLater(first, throwsStateError);
    final second = queue.add(() async => events.add('second completed'));
    await Future<void>.delayed(Duration.zero);

    expect(events, ['first started']);
    firstGate.complete();
    await Future.wait([failure, second, queue.drain()]);

    expect(events, ['first started', 'second completed']);
  });

  test('draining includes work accepted while an earlier action is pending', () async {
    final queue = SerialActionQueue();
    final firstGate = Completer<void>();
    final secondGate = Completer<void>();
    final first = queue.add(() => firstGate.future);
    var drained = false;
    final drain = queue.drain().then((_) => drained = true);
    await Future<void>.delayed(Duration.zero);
    final second = queue.add(() => secondGate.future);
    firstGate.complete();
    await first;
    await Future<void>.delayed(Duration.zero);

    expect(drained, isFalse);
    secondGate.complete();
    await Future.wait([second, drain]);

    expect(drained, isTrue);
  });
}
