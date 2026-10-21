import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/command_link_button.dart';

import '../../integration_test/support/ui_harness.dart';

void main() {
  testWidgets('scroll journey selects overflowing inner viewport', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: 400,
            child: SingleChildScrollView(
              child: SizedBox(
                height: 380,
                child: ListView.builder(
                  itemCount: 60,
                  itemExtent: 50,
                  itemBuilder: (_, i) => Text('Row $i'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await UiHarness(tester, _UnusedBinding()).scrollRoundTrip();
    expect(tester.takeException(), isNull);
  });
  testWidgets('waiting for a first finder tolerates a not-yet-built control', (
    tester,
  ) async {
    final visible = ValueNotifier(false);
    addTearDown(visible.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: visible,
          builder: (_, ready, __) => Text(ready ? 'ready' : 'pending'),
        ),
      ),
    );
    final timer = Timer(
      const Duration(milliseconds: 150),
      () => visible.value = true,
    );
    addTearDown(timer.cancel);
    await UiHarness(tester, _UnusedBinding()).waitFor(find.text('ready').first);
    expect(find.text('ready'), findsOneWidget);
  });
  testWidgets('waiting for a reused finder survives a replaced widget tree', (
    tester,
  ) async {
    const key = ValueKey('replaceable-control');
    final control = find.byKey(key);
    await tester.pumpWidget(const MaterialApp(home: Text('old', key: key)));
    // Keep the finder's lazy result, just as a previous tap can do.
    expect(control.evaluate().isNotEmpty, isTrue);
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: Text('new', key: key)),
      ),
    );
    await UiHarness(tester, _UnusedBinding()).waitFor(control);
    expect(tester.widget<Text>(control).data, 'new');
  });

  testWidgets('back commands remain findable when their text is uppercased', (
    tester,
  ) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommandLinkButton(
            label: 'Back to settings',
            onTap: () => taps++,
          ),
        ),
      ),
    );
    expect(find.text('BACK TO SETTINGS'), findsOneWidget);
    final control = commandControl('Back to settings');
    expect(control.hitTestable(), findsOneWidget);
    await tester.tap(control);
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('hidden tooltip labels still locate their visible controls', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: TooltipVisibility(
          visible: false,
          child: Center(
            child: Tooltip(
              message: 'Download Manager',
              child: TextButton(
                onPressed: () => taps++,
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    final control = tooltipControl('Download Manager');
    expect(control.hitTestable(), findsOneWidget);
    await tester.tap(control);
    await tester.pump();
    expect(taps, 1);
  });
}

class _UnusedBinding extends Fake
    implements IntegrationTestWidgetsFlutterBinding {}
