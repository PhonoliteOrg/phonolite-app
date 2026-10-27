import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/application/controllers/settings/account_sessions_controller.dart';
import 'package:phonolite_app/data/models/server/server_errors.dart';

void main() {
  test('revocation ignores stale accounts and concurrent submissions', () async {
    final controller = AccountSessionsController();
    final response = Completer<int>();
    var current = true;
    var calls = 0;

    Future<int> revoke() {
      calls++;

      return response.future;
    }

    final operation = controller.signOutOtherDevices(revoke, sessionIsCurrent: () => current);
    expect(controller.busy, isTrue);

    await controller.signOutOtherDevices(revoke, sessionIsCurrent: () => current);
    expect(calls, 1);

    current = false;
    response.complete(4);
    await operation;
    expect(controller.message, isNull);
    expect(controller.busy, isFalse);

    await controller.signOutOtherDevices(revoke, sessionIsCurrent: () => current);
    expect(calls, 1);
    controller.dispose();
  });

  test('successful response reports acknowledged session count', () async {
    final controller = AccountSessionsController();

    await controller.signOutOtherDevices(() async => 1, sessionIsCurrent: () => true);
    expect(controller.message, 'Signed out 1 other app session. This device stays signed in.');
    expect(controller.failed, isFalse);

    await controller.signOutOtherDevices(() async => 0, sessionIsCurrent: () => true);
    expect(controller.message, 'No other app sessions were signed in.');
    controller.dispose();
  });

  test('unconfirmed mutations show safe feedback and permit retry', () async {
    final controller = AccountSessionsController();

    await controller.signOutOtherDevices(
      () async => throw ApiException(503, 'private server details'),
      sessionIsCurrent: () => true,
    );
    expect(controller.failed, isTrue);
    expect(controller.message, contains('Could not confirm'));
    expect(controller.message, isNot(contains('private')));
    expect(controller.busy, isFalse);

    await controller.signOutOtherDevices(() async => 2, sessionIsCurrent: () => true);
    expect(controller.failed, isFalse);
    expect(controller.message, contains('Signed out 2 other app sessions'));
    controller.dispose();
  });

  test('sign out all can invalidate its own session without reporting a stale result', () async {
    final controller = AccountSessionsController();
    var current = true;

    await controller.signOutAllDevices(() async => current = false, sessionIsCurrent: () => current);
    expect(controller.message, isNull);
    expect(controller.failed, isFalse);
    expect(controller.busy, isFalse);
    controller.dispose();
  });

  test('disposing ignores late failures without touching the old account guard', () async {
    final controller = AccountSessionsController();
    final response = Completer<int>();
    var guardCalls = 0;
    final operation = controller.signOutOtherDevices(
      () => response.future,
      sessionIsCurrent: () {
        guardCalls++;

        return true;
      },
    );

    controller.dispose();
    response.completeError(StateError('unconfirmed'));
    await operation;
    expect(guardCalls, 1);
  });
}
