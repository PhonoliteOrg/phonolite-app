import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/ui/shared/design_system/controls/command_link_button.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/lucide_checkbox.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_hover_card.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_overflow_action_button.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_toggle_option.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_widgets.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/tech_button.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/button_haptics.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/hover_row.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/modal_action_button.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_scope.dart';
import 'package:phonolite_app/ui/shared/music/like_icon_button.dart';

import '../support/widget_test_helpers.dart';

const _lightImpact = 'HapticFeedbackType.lightImpact';

void main() {
  setUpAll(configureTestFonts);

  testWidgets(
    'enabled button families give one iOS pulse; disabled ones stay silent',
    (tester) async {
      final pulses = _capture(tester);
      final cases =
          <({Widget Function(VoidCallback?) build, Finder Function() target})>[
            for (final chrome in TechButtonChrome.values)
              (
                build: (action) =>
                    TechButton(label: 'Action', onTap: action, chrome: chrome),
                target: () => find.byType(TechButton),
              ),
            (
              build: (action) => ObsidianHudIconButton(
                icon: PhonoliteIcons.download,
                onPressed: action,
              ),
              target: () => find.byType(ObsidianHudIconButton),
            ),
            (
              build: (action) => ObsidianIconButton(
                icon: PhonoliteIcons.download,
                onPressed: action,
              ),
              target: () => find.byType(ObsidianIconButton),
            ),
            (
              build: (action) =>
                  ObsidianPlayButton(icon: Icons.play_arrow, onPressed: action),
              target: () => find.byType(ObsidianPlayButton),
            ),
            (
              build: (action) =>
                  LikeIconButton(isLiked: false, onPressed: action),
              target: () => find.byType(LikeIconButton),
            ),
            (
              build: (action) => ObsidianNavIcon(
                icon: const Icon(PhonoliteIcons.disc3),
                isSelected: false,
                onTap: action,
              ),
              target: () => find.byType(ObsidianNavIcon),
            ),
            (
              build: (action) =>
                  ModalActionButton(label: 'Action', onPressed: action),
              target: () => find.text('ACTION'),
            ),
            (
              build: (action) => CommandLinkButton(
                label: 'Action',
                onTap: action ?? () {},
                enabled: action != null,
              ),
              target: () => find.text('ACTION'),
            ),
            (
              build: (action) => ObsidianToggleOption(
                label: 'Action',
                isActive: false,
                onPressed: action,
              ),
              target: () => find.text('ACTION'),
            ),
            (
              build: (action) =>
                  ObsidianHoverRow(onTap: action, child: const Text('Action')),
              target: () => find.byType(ObsidianHoverRow),
            ),
            (
              build: (action) => ObsidianHoverCard(
                onTap: action,
                childBuilder: (_, _) => const Text('Action'),
              ),
              target: () => find.byType(ObsidianHoverCard),
            ),
            (
              build: (action) => LucideCheckbox(
                value: false,
                onChanged: action == null ? null : (_) => action(),
              ),
              target: () => find.byType(LucideCheckbox),
            ),
          ];
      for (final entry in cases) {
        for (final enabled in [true, false]) {
          pulses.clear();
          var actions = 0;
          await _pump(tester, entry.build(enabled ? () => actions++ : null));
          await tester.tap(entry.target(), warnIfMissed: false);
          await tester.pump();
          expect(
            actions,
            enabled ? 1 : 0,
            reason: '${entry.build(null).runtimeType}, enabled: $enabled',
          );
          expect(
            pulses,
            enabled && defaultTargetPlatform == TargetPlatform.iOS
                ? [_lightImpact]
                : <String>[],
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '${entry.build(null).runtimeType}, enabled: $enabled',
          );
        }
      }
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
      TargetPlatform.windows,
    }),
  );

  testWidgets(
    'nested buttons pulse once and dragging a row does not pulse',
    (tester) async {
      final pulses = _capture(tester);
      var rowActions = 0;
      var likes = 0;
      await _pump(
        tester,
        ObsidianHoverRow(
          onTap: () => rowActions++,
          child: Row(
            children: [
              const Expanded(child: Text('Open item')),
              LikeIconButton(isLiked: false, onPressed: () => likes++),
            ],
          ),
        ),
      );
      await tester.tap(find.byType(LikeIconButton));
      await tester.pump();
      expect(likes, 1);
      expect(rowActions, 0);
      expect(pulses, [_lightImpact]);
      await tester.tap(find.text('Open item'));
      await tester.pump();
      expect(rowActions, 1);
      expect(pulses, [_lightImpact, _lightImpact]);
      await tester.drag(find.text('Open item'), const Offset(0, -80));
      await tester.pumpAndSettle();
      expect(rowActions, 1);
      expect(pulses, [_lightImpact, _lightImpact]);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  for (final useModal in [false, true]) {
    testWidgets(
      '${useModal ? 'modal' : 'menu'} opening and enabled item selection each pulse once',
      (tester) async {
        final pulses = _capture(tester);
        var actions = 0;
        await _pump(
          tester,
          ObsidianOverflowActionButton(
            tooltip: 'Actions',
            modalTitle: useModal ? 'Track title' : null,
            actions: [
              ObsidianMenuAction(
                label: 'Run action',
                icon: PhonoliteIcons.download,
                onTap: () => actions++,
              ),
              const ObsidianMenuAction(
                label: 'Unavailable',
                icon: PhonoliteIcons.trash2,
                onTap: null,
              ),
            ],
          ),
        );
        await tester.tap(find.byTooltip('Actions'));
        await tester.pumpAndSettle();
        expect(pulses, [_lightImpact]);
        await tester.tap(find.text('Unavailable'), warnIfMissed: false);
        await tester.pump();
        expect(actions, 0);
        expect(pulses, [_lightImpact]);
        await tester.tap(find.text('Run action'));
        await tester.pumpAndSettle();
        expect(actions, 1);
        expect(pulses, [_lightImpact, _lightImpact]);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  }

  testWidgets(
    'unavailable haptics never prevent an enabled action',
    (tester) async {
      _capture(tester, fail: true);
      var actions = 0;
      await _pump(tester, TechButton(label: 'Action', onTap: () => actions++));
      await tester.tap(find.byType(TechButton));
      await tester.pump();
      expect(actions, 1);
      expect(tester.takeException(), isNull);
      expect(withButtonHaptic(null), isNull);
      expect(withSelectionHaptic<bool>(null), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}

List<String> _capture(WidgetTester tester, {bool fail = false}) {
  final pulses = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        if (fail) throw PlatformException(code: 'unavailable');
        pulses.add(call.arguments as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return pulses;
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 700);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    wrapInTestApp(
      ObsidianModalScope(
        builder: (_) => Center(
          child: KeyedSubtree(key: UniqueKey(), child: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
