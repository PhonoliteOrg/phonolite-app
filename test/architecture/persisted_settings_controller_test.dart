import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/data/repositories/device_preference.dart';

void main() {
  test('changes before loading are ignored and loading runs once', () async {
    final controller = _CountController(stored: 4);
    addTearDown(controller.dispose);

    await controller.set(9);

    expect(controller.settings, 0);
    expect(controller.writes, isEmpty);

    await Future.wait([controller.initialize(), controller.initialize()]);

    expect(controller.reads, 1);
    expect(controller.ready, isTrue);
    expect(controller.settings, 4);
  });

  test('an accepted change applies immediately and an unchanged value is not saved', () async {
    final controller = _CountController(stored: 1);
    addTearDown(controller.dispose);
    await controller.initialize();
    final write = Completer<void>();
    controller.pendingWrite = write.future;

    final saving = controller.set(2);

    expect(controller.settings, 2);
    expect(controller.saving, isTrue);

    write.complete();
    await saving;
    await controller.set(2);

    expect(controller.saving, isFalse);
    expect(controller.writes, [2]);
  });

  test('a failed newest save restores the last saved value and reports it', () async {
    final controller = _CountController(stored: 1);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.set(2);
    controller.failingWrites.add(3);

    await controller.set(3);

    expect(controller.settings, 2);
    expect(controller.saving, isFalse);
    expect(controller.error, contains('Could not save counts'));
  });

  test('a superseded failed save keeps the newer choice and does not block later saves', () async {
    final controller = _CountController(stored: 1);
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.failingWrites.add(2);

    final failed = controller.set(2);
    final newer = controller.set(3);
    await Future.wait([failed, newer]);

    expect(controller.settings, 3);
    expect(controller.error, isNull);
    expect(controller.writes, [3]);
    expect(controller.previousValues, [1, 1]);
  });

  test('a load failure is reported, rethrown, and can be retried', () async {
    final controller = _CountController(stored: 5)..failRead = true;
    addTearDown(controller.dispose);

    await expectLater(controller.initialize(), throwsStateError);

    expect(controller.ready, isFalse);
    expect(controller.error, contains('Could not load counts'));

    controller.failRead = false;
    await controller.initialize();

    expect(controller.ready, isTrue);
    expect(controller.settings, 5);
    expect(controller.error, isNull);
  });

  test('flush waits for accepted saves', () async {
    final controller = _CountController(stored: 1);
    addTearDown(controller.dispose);
    await controller.initialize();
    final write = Completer<void>();
    controller.pendingWrite = write.future;
    unawaited(controller.set(2));
    var flushed = false;

    final flushing = controller.flush().then((_) => flushed = true);
    await Future<void>.delayed(Duration.zero);

    expect(flushed, isFalse);

    write.complete();
    await flushing;

    expect(controller.writes, [2]);
  });
}

class _CountController {
  final int stored;
  final writes = <int>[];
  final previousValues = <int>[];
  final failingWrites = <int>{};
  Future<void>? pendingWrite;
  bool failRead = false;
  int reads = 0;

  _CountController({required this.stored});

  late final preference = DevicePreference(0, label: 'counts', read: _read, write: _write);
  int get settings => preference.value;
  bool get ready => preference.ready;
  bool get saving => preference.saving;
  String? get error => preference.error;
  void dispose() => preference.dispose();
  Future<void> flush() => preference.flush();

  Future<void> initialize() => preference.load();

  Future<void> set(int value) => preference.change(
    value,
    apply: (next, previous) async {
      previousValues.add(previous);
      return null;
    },
  );

  Future<void> _write(int next) async {
    await pendingWrite;
    pendingWrite = null;

    if (failingWrites.remove(next)) {
      throw StateError('write failed');
    }

    writes.add(next);
  }

  Future<int> _read() async {
    reads++;

    if (failRead) {
      throw StateError('read failed');
    }

    return stored;
  }
}
