import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/bootstrap/phonolite_app_shell.dart';
import 'package:phonolite_app/ui/navigation/retained_tab_view.dart';
import 'package:phonolite_app/ui/shell/navigation/app_side_navigation.dart';
import 'package:window_manager/window_manager.dart';

import '../features/support/feature_world.dart';

void main() {
  testWidgets('Windows caption clears the sidebar and stays usable over a dialog', (tester) async {
    const channel = MethodChannel('window_manager');
    final messenger = tester.binding.defaultBinaryMessenger;
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return call.method == 'isMaximized' ? false : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final controller = (await tester.runAsync(() async => WorldController(const FeatureWorld())))!;
    try {
      await tester.pumpWidget(PhonoliteAppShell(controller: controller, customWindowsCaption: true));
      await tester.pump();
      final rail = tester.getRect(find.byType(AppSideNavigation));
      final drag = tester.getRect(find.byType(DragToMoveArea));
      expect(rail.top, 0);
      expect(drag.topLeft, rail.topRight);
      expect(tester.getTopLeft(find.byType(RetainedTabView)), Offset(rail.right, drag.bottom));

      unawaited(
        showDialog<void>(
          context: tester.element(find.byType(RetainedTabView)),
          builder: (_) => const AlertDialog(content: Text('Dialog')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Minimize'));
      await tester.tap(find.bySemanticsLabel('Maximize'));
      final reply = await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(const MethodCall('onEvent', {'eventName': 'maximize'})),
        (_) {},
      );
      const StandardMethodCodec().decodeEnvelope(reply!);
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Restore'));
      await tester.tap(find.bySemanticsLabel('Close'));
      expect(calls, containsAllInOrder(['minimize', 'maximize', 'unmaximize', 'close']));
      expect(find.text('Dialog'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(controller.close);
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
