import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/widgets/display/now_playing_bar.dart';
import 'package:phonolite_app/widgets/ui/obsidian_widgets.dart';
import 'package:phonolite_app/widgets/ui/phonolite_icons.dart';

import '../../support/journey.dart';
import '../../support/ui_harness.dart';

Future<void> _open(UiHarness ui) async {
  final mini = find.byType(NowPlayingMiniBar);
  if (mini.evaluate().isEmpty) {
    throw const MissingPrerequisite(
      'Expanded player requires a compact/mobile layout',
    );
  }
  await ui.tap(find.descendant(of: mini, matching: find.byType(InkWell)).first);
  await ui.waitFor(find.byType(NowPlayingExpandedSheet));
}

Future<void> _dismiss(UiHarness ui) async {
  final sheet = find.byType(NowPlayingExpandedSheet);
  final rect = ui.tester.getRect(sheet);
  await ui.tester.flingFrom(
    Offset(rect.center.dx, rect.top + 18),
    Offset(0, rect.height * .8),
    1800,
  );
  await ui.animate(800);
  expect(sheet, findsNothing);
}

Finder _icon(IconData icon) =>
    find.byWidgetPredicate((w) => w is ObsidianHudIconButton && w.icon == icon);

final playerJourneys = [
  UiJourney(
    id: 'player.tray_transition',
    feature: 'player',
    description:
        'Repeated player expansion and swipe dismissal, including idle state',
    interactions: ['player.expand', 'player.swipe_close'],
    run: (ui) async {
      for (var n = 0; n < UiHarness.repeats; n++) {
        await _open(ui);
        await _dismiss(ui);
      }
    },
  ),
  UiJourney(
    id: 'player.shuffle_dialog',
    feature: 'player',
    description: 'Inspect shuffle choices and dismiss without selecting a mode',
    interactions: ['shuffle.open', 'shuffle.close'],
    run: (ui) async {
      await _open(ui);
      for (var n = 0; n < UiHarness.repeats; n++) {
        await ui.tap(_icon(PhonoliteIcons.shuffle));
        expect(find.text('Shuffle'), findsOneWidget);
        await ui.closeDialog();
        expect(find.text('Shuffle'), findsNothing);
      }
      await _dismiss(ui);
    },
  ),
  UiJourney(
    id: 'player.output_dialog',
    feature: 'player',
    description: 'Open output device picker and close without changing output',
    interactions: ['output.open', 'output.close'],
    run: (ui) async {
      await _open(ui);
      for (var n = 0; n < UiHarness.repeats; n++) {
        await ui.tap(_icon(PhonoliteIcons.speaker));
        expect(find.text('Select output device'), findsOneWidget);
        await ui.closeDialog();
      }
      await _dismiss(ui);
    },
  ),
];
