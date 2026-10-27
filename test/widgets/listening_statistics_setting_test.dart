import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/ui/features/settings/widgets/listening_statistics_setting.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_switch.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/hover_row.dart';

import '../support/widget_test_helpers.dart';

const _switchKey = ValueKey('listening-statistics-switch');
const _resetKey = ValueKey('reset-listening-statistics');

void main() {
  setUpAll(configureTestFonts);

  testWidgets('preference saves keep the switch enabled and reset waits for every save', (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.finishSaves);
    await tester.pumpWidget(wrapInTestApp(_Host(fixture: fixture)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(_switchKey));
    await tester.pumpAndSettle();

    expect(tester.widget<ObsidianSwitch>(find.byKey(_switchKey)).value, isFalse);
    expect(tester.widget<ObsidianSwitch>(find.byKey(_switchKey)).enabled, isTrue);

    await tester.tap(find.byKey(_switchKey));
    await tester.pumpAndSettle();

    expect(fixture.choices, [false, true]);
    expect(tester.widget<ObsidianSwitch>(find.byKey(_switchKey)).value, isTrue);
    expect(tester.widget<ObsidianSwitch>(find.byKey(_switchKey)).enabled, isTrue);
    expect(tester.widget<ObsidianHoverRow>(find.byKey(_resetKey)).enabled, isFalse);

    fixture.pending.last.complete();
    await tester.pumpAndSettle();

    expect(tester.widget<ObsidianHoverRow>(find.byKey(_resetKey)).enabled, isFalse);
    expect(tester.widget<ObsidianSwitch>(find.byKey(_switchKey)).enabled, isTrue);
    fixture.pending.first.complete();
    await tester.pumpAndSettle();

    expect(tester.widget<ObsidianHoverRow>(find.byKey(_resetKey)).enabled, isTrue);
    expect(tester.widget<ObsidianSwitch>(find.byKey(_switchKey)).enabled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reset confirmation disables the switch until the dialog closes', (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(wrapInTestApp(_Host(fixture: fixture)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_resetKey));
    await tester.pumpAndSettle();

    expect(find.text('Reset listening statistics?'), findsOneWidget);
    expect(tester.widget<ObsidianSwitch>(find.byKey(_switchKey)).enabled, isFalse);
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();

    expect(tester.widget<ObsidianSwitch>(find.byKey(_switchKey)).enabled, isTrue);
    expect(fixture.choices, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

class _Fixture {
  final choices = <bool>[];
  final pending = <Completer<void>>[];
  bool enabled = true;

  Future<void> save(bool value) {
    choices.add(value);
    final gate = Completer<void>();
    pending.add(gate);

    return gate.future;
  }

  void finishSaves() {
    for (final gate in pending) {
      if (!gate.isCompleted) {
        gate.complete();
      }
    }
  }
}

class _Host extends StatefulWidget {
  final _Fixture fixture;

  const _Host({required this.fixture});

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  Future<void> _change(bool value) {
    setState(() => widget.fixture.enabled = value);

    return widget.fixture.save(value);
  }

  @override
  Widget build(BuildContext context) => ListeningStatisticsSetting(
    enabled: widget.fixture.enabled,
    onChanged: _change,
    serverConnected: false,
    onReset: () async {},
  );
}
