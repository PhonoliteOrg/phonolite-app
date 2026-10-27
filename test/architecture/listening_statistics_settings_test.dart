import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/application/controllers/settings/listening_statistics_controller.dart';

void main() {
  test('rapid consent changes reach the service immediately and track every pending save', () async {
    final controller = ListeningStatisticsController();
    addTearDown(controller.dispose);
    final calls = <bool>[];
    final pending = <Completer<void>>[];

    Future<void> save(bool enabled) {
      calls.add(enabled);
      final gate = Completer<void>();
      pending.add(gate);

      return gate.future;
    }

    final first = controller.change(false, save);
    final second = controller.change(true, save);

    expect(calls, [false, true]);
    expect(controller.saving, isTrue);
    controller.beginReset();
    expect(controller.resetting, isFalse);
    var resets = 0;
    await controller.reset(() async => resets++, serverConnected: false);
    expect(resets, 0);

    pending.last.complete();
    await second;
    expect(controller.saving, isTrue);
    pending.first.complete();
    await first;
    expect(controller.saving, isFalse);

    controller.beginReset();
    expect(controller.resetting, isTrue);
    await controller.change(false, save);
    expect(calls, [false, true]);
    controller.endReset();
  });

  test('a failed preference save does not block later consent changes', () async {
    final controller = ListeningStatisticsController();
    addTearDown(controller.dispose);
    await controller.change(false, (_) async => throw StateError('Save failed'));
    expect(controller.saving, isFalse);

    var saved = false;
    await controller.change(true, (enabled) async => saved = enabled);

    expect(saved, isTrue);
    expect(controller.saving, isFalse);
  });

  test('disposing during a save prevents late notifications and new commands', () async {
    final controller = ListeningStatisticsController();
    final gate = Completer<void>();
    var notifications = 0;
    var calls = 0;
    controller.addListener(() => notifications++);
    final change = controller.change(false, (_) => gate.future);
    controller.dispose();
    final beforeCompletion = notifications;
    gate.complete();
    await change;
    await controller.change(true, (_) async => calls++);

    expect(notifications, beforeCompletion);
    expect(calls, 0);
  });
}
