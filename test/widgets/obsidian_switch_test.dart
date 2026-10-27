import 'dart:ui' show SemanticsAction, SemanticsActionEvent;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/ui/navigation/desktop_playback_shortcuts.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_switch.dart';

import '../support/widget_test_helpers.dart';

void main() {
  setUpAll(configureTestFonts);

  testWidgets('the complete touch target activates once and the parent owns the value', (tester) async {
    final changes = <bool>[];

    Future<void> pumpValue(bool value) =>
        tester.pumpWidget(_app(ObsidianSwitch(value: value, semanticLabel: 'Example setting', onChanged: changes.add)));

    await pumpValue(false);
    final target = find.byType(ObsidianSwitch);
    final bounds = tester.getRect(target);

    expect(bounds.width, greaterThanOrEqualTo(48));
    expect(bounds.height, greaterThanOrEqualTo(48));
    await tester.tapAt(bounds.topLeft + const Offset(2, 2));
    await tester.pumpAndSettle();

    expect(changes, [true]);
    expect(tester.widget<ObsidianSwitch>(target).value, isFalse);
    await pumpValue(true);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();

    expect(changes, [true, false]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('accessibility exposes a labeled toggle and only enabled activation', (tester) async {
    final semantics = tester.ensureSemantics();

    try {
      final changes = <bool>[];

      Future<void> pumpValue(bool value, {bool enabled = true}) => tester.pumpWidget(
        _app(ObsidianSwitch(value: value, semanticLabel: 'Example setting', onChanged: enabled ? changes.add : null)),
      );

      await pumpValue(false);
      var data = tester.getSemantics(find.byType(ObsidianSwitch)).getSemanticsData();

      expect(data.label, 'Example setting');
      expect(data.flagsCollection.hasToggledState, isTrue);
      expect(data.flagsCollection.isToggled, isFalse);
      expect(data.flagsCollection.hasEnabledState, isTrue);
      expect(data.flagsCollection.isEnabled, isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      tester.binding.performSemanticsAction(
        SemanticsActionEvent(
          type: SemanticsAction.tap,
          viewId: tester.view.viewId,
          nodeId: tester.getSemantics(find.byType(ObsidianSwitch)).id,
        ),
      );

      expect(changes, [true]);

      await pumpValue(true, enabled: false);
      await tester.pumpAndSettle();
      data = tester.getSemantics(find.byType(ObsidianSwitch)).getSemanticsData();

      expect(data.flagsCollection.isToggled, isTrue);
      expect(data.flagsCollection.isEnabled, isFalse);
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      await tester.tap(find.byType(ObsidianSwitch));
      await tester.pumpAndSettle();

      expect(changes, [true]);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'Space and Enter activate once without triggering playback shortcuts',
    (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final changes = <bool>[];
      var playbackToggles = 0;
      await tester.pumpWidget(
        _app(
          DesktopPlaybackShortcuts(
            onTogglePlayPause: () => playbackToggles++,
            child: ObsidianSwitch(
              value: false,
              semanticLabel: 'Example setting',
              focusNode: focus,
              onChanged: changes.add,
            ),
          ),
        ),
      );
      focus.requestFocus();
      await tester.pumpAndSettle();

      for (final key in [LogicalKeyboardKey.space, LogicalKeyboardKey.enter]) {
        await tester.sendKeyDownEvent(key);
        await tester.sendKeyRepeatEvent(key);
        await tester.sendKeyRepeatEvent(key);
        await tester.sendKeyUpEvent(key);
        await tester.pumpAndSettle();
      }

      expect(changes, [true, true]);
      expect(playbackToggles, 0);
      expect(focus.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets('disabling a focused toggle prevents pointer and keyboard changes', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final changes = <bool>[];

    Future<void> pumpEnabled(bool enabled) => tester.pumpWidget(
      _app(
        ObsidianSwitch(
          value: false,
          semanticLabel: 'Example setting',
          focusNode: focus,
          onChanged: enabled ? changes.add : null,
        ),
      ),
    );

    await pumpEnabled(true);
    focus.requestFocus();
    await tester.pumpAndSettle();
    await pumpEnabled(false);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ObsidianSwitch));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(changes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'clicking another switch moves subsequent keyboard activation to it',
    (tester) async {
      final firstFocus = FocusNode();
      final secondFocus = FocusNode();
      addTearDown(firstFocus.dispose);
      addTearDown(secondFocus.dispose);
      final firstChanges = <bool>[];
      final secondChanges = <bool>[];
      await tester.pumpWidget(
        _app(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ObsidianSwitch(
                key: const ValueKey('first-switch'),
                value: false,
                semanticLabel: 'First setting',
                focusNode: firstFocus,
                onChanged: firstChanges.add,
              ),
              ObsidianSwitch(
                key: const ValueKey('second-switch'),
                value: false,
                semanticLabel: 'Second setting',
                focusNode: secondFocus,
                onChanged: secondChanges.add,
              ),
            ],
          ),
        ),
      );
      firstFocus.requestFocus();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('second-switch')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();

      expect(firstChanges, isEmpty);
      expect(secondChanges, [true, true]);
      expect(secondFocus.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets('hover and a canceled pointer press do not change the value', (tester) async {
    final changes = <bool>[];
    await tester.pumpWidget(
      _app(ObsidianSwitch(value: false, semanticLabel: 'Example setting', onChanged: changes.add)),
    );
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(pointer.removePointer);
    await pointer.addPointer(location: Offset.zero);
    await pointer.moveTo(tester.getCenter(find.byType(ObsidianSwitch)));
    await tester.pumpAndSettle();
    await pointer.down(tester.getCenter(find.byType(ObsidianSwitch)));
    await tester.pump();
    await pointer.cancel();
    await tester.pumpAndSettle();

    expect(changes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the thumb follows the logical start and end in both writing directions', (tester) async {
    for (final direction in TextDirection.values) {
      for (final value in [false, true]) {
        await tester.pumpWidget(
          _app(
            ObsidianSwitch(value: value, semanticLabel: 'Example setting', onChanged: (_) {}),
            direction: direction,
          ),
        );
        await tester.pumpAndSettle();
        final thumb = tester.getCenter(find.byKey(const ValueKey('obsidian-switch-thumb')));
        final target = tester.getCenter(find.byType(ObsidianSwitch));
        final expectRight = direction == TextDirection.ltr ? value : !value;

        expect(thumb.dx, expectRight ? greaterThan(target.dx) : lessThan(target.dx));
      }
    }

    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion places the thumb at its new endpoint immediately', (tester) async {
    Future<void> pumpValue(bool value) => tester.pumpWidget(
      _app(ObsidianSwitch(value: value, semanticLabel: 'Example setting', onChanged: (_) {}), reduceMotion: true),
    );

    await pumpValue(false);
    await pumpValue(true);
    final thumb = tester.getCenter(find.byKey(const ValueKey('obsidian-switch-thumb')));
    final target = tester.getCenter(find.byType(ObsidianSwitch));

    expect(thumb.dx, greaterThan(target.dx));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'one activation emits one platform-appropriate haptic',
    (tester) async {
      final pulses = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          pulses.add(call.arguments as String);
        }

        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final changes = <bool>[];
      await tester.pumpWidget(
        _app(ObsidianSwitch(value: false, semanticLabel: 'Example setting', onChanged: changes.add)),
      );
      await tester.tap(find.byType(ObsidianSwitch));
      await tester.pumpAndSettle();

      expect(changes, [true]);
      expect(pulses, defaultTargetPlatform == TargetPlatform.iOS ? ['HapticFeedbackType.lightImpact'] : isEmpty);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.android, TargetPlatform.windows}),
  );
}

Widget _app(Widget child, {TextDirection direction = TextDirection.ltr, bool reduceMotion = false}) => wrapInTestApp(
  Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
      child: Directionality(
        textDirection: direction,
        child: Center(child: child),
      ),
    ),
  ),
);
