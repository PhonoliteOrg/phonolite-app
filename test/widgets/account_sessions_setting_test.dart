import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/ui/features/settings/widgets/account_sessions_setting.dart';

import '../support/widget_test_helpers.dart';

void main() {
  setUp(configureTestFonts);

  testWidgets('other-device confirmation preserves this device and admin console sessions', (tester) async {
    var requests = 0;

    await tester.pumpWidget(
      wrapInTestApp(
        AccountSessionsSetting(
          onSignOutOtherDevices: () async => ++requests,
          onSignOutAllDevices: () async {},
          sessionIsCurrent: () => true,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('sign-out-other-devices')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Streaming on those devices will stop'), findsOneWidget);
    expect(find.textContaining('every other app session'), findsOneWidget);
    expect(find.textContaining('This device and admin console sessions stay signed in.'), findsOneWidget);

    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
    expect(requests, 0);

    await tester.tap(find.byKey(const ValueKey('sign-out-other-devices')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SIGN OUT OTHER DEVICES'));
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(find.text('Signed out 1 other app session. This device stays signed in.'), findsOneWidget);
  });

  testWidgets('all-device confirmation includes this app and preserves admin console sessions', (tester) async {
    var requests = 0;

    await tester.pumpWidget(
      wrapInTestApp(
        AccountSessionsSetting(
          onSignOutOtherDevices: () async => 0,
          onSignOutAllDevices: () async => requests++,
          sessionIsCurrent: () => true,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('sign-out-all-devices')));
    await tester.pumpAndSettle();
    expect(find.textContaining('every app session for this account, including this device?'), findsOneWidget);
    expect(
      find.text(
        'Sign out every app session for this account, including this device? Streaming will stop and all apps will need to sign in again. Admin console sessions stay signed in.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('SIGN OUT ALL DEVICES'));
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(find.text('Signed out all app sessions. Admin console sessions stay signed in.'), findsOneWidget);
  });

  testWidgets('account change while confirming cannot revoke the replacement account', (tester) async {
    var requests = 0;
    var current = true;

    await tester.pumpWidget(
      wrapInTestApp(
        AccountSessionsSetting(
          onSignOutOtherDevices: () async => ++requests,
          onSignOutAllDevices: () async => requests++,
          sessionIsCurrent: () => current,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('sign-out-all-devices')));
    await tester.pumpAndSettle();
    expect(find.textContaining('including this device'), findsOneWidget);

    current = false;
    await tester.tap(find.text('SIGN OUT ALL DEVICES'));
    await tester.pumpAndSettle();
    expect(requests, 0);
  });

  testWidgets('pending revocation disables both actions and failure remains visible', (tester) async {
    final response = Completer<int>();
    var allRequests = 0;

    await tester.pumpWidget(
      wrapInTestApp(
        AccountSessionsSetting(
          onSignOutOtherDevices: () => response.future,
          onSignOutAllDevices: () async => allRequests++,
          sessionIsCurrent: () => true,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('sign-out-other-devices')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SIGN OUT OTHER DEVICES'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('account-session-progress')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sign-out-all-devices')));
    await tester.pump();
    expect(find.text('Sign out all devices?'), findsNothing);
    expect(allRequests, 0);

    response.completeError(StateError('lost acknowledgement'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not confirm the sign-out request.'), findsOneWidget);
    expect(find.byKey(const ValueKey('account-session-progress')), findsNothing);
  });
}
