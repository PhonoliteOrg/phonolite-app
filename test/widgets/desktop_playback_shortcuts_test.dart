import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/widgets/navigation/desktop_playback_shortcuts.dart';

void main() {
  const desktops = TargetPlatformVariant({
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.linux,
  });

  testWidgets('Space toggles once per press, including when held', (
    tester,
  ) async {
    var toggles = 0;
    await tester.pumpWidget(_app(onToggle: () => toggles++));
    await tester.pumpAndSettle();
    expect(await tester.sendKeyDownEvent(LogicalKeyboardKey.space), isTrue);
    expect(toggles, 1);
    for (var i = 0; i < 3; i++) {
      expect(await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space), isTrue);
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    expect(toggles, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(toggles, 2);
  }, variant: desktops);

  testWidgets('modified Space and other keys do not toggle playback', (
    tester,
  ) async {
    var toggles = 0;
    await tester.pumpWidget(_app(onToggle: () => toggles++));
    await tester.pumpAndSettle();
    for (final modifier in [
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.altLeft,
      LogicalKeyboardKey.metaLeft,
    ]) {
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyUpEvent(modifier);
      expect(toggles, 0);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    expect(toggles, 0);
  }, variant: desktops);

  testWidgets('focused text inputs keep Space for typing', (tester) async {
    var toggles = 0;
    await tester.pumpWidget(
      _app(onToggle: () => toggles++, child: const TextField()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(await tester.sendKeyEvent(LogicalKeyboardKey.space), isFalse);
    await tester.enterText(find.byType(TextField), 'Artist name');
    expect(find.text('Artist name'), findsOneWidget);
    expect(toggles, 0);
  }, variant: desktops);

  testWidgets('focused buttons and checkboxes retain Space activation', (
    tester,
  ) async {
    var toggles = 0;
    var activations = 0;
    var checks = 0;
    final buttonFocus = FocusNode();
    final checkboxFocus = FocusNode();
    addTearDown(buttonFocus.dispose);
    addTearDown(checkboxFocus.dispose);
    await tester.pumpWidget(
      _app(
        onToggle: () => toggles++,
        child: Column(
          children: [
            TextButton(
              focusNode: buttonFocus,
              onPressed: () => activations++,
              child: const Text('Action'),
            ),
            Checkbox(
              focusNode: checkboxFocus,
              value: false,
              onChanged: (_) => checks++,
            ),
          ],
        ),
      ),
    );
    buttonFocus.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    expect(activations, 1);
    expect(toggles, 0);
    checkboxFocus.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(checks, 1);
    expect(toggles, 0);
  }, variant: desktops);

  testWidgets('modal dialogs do not toggle playback behind them', (
    tester,
  ) async {
    var toggles = 0;
    await tester.pumpWidget(_app(onToggle: () => toggles++));
    await tester.pumpAndSettle();
    showDialog<void>(
      context: tester.element(find.text('Content')),
      builder: (_) => const AlertDialog(content: Text('Dialog')),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(toggles, 0);
    Navigator.of(tester.element(find.text('Dialog'))).pop();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(toggles, 1);
  }, variant: desktops);

  testWidgets(
    'mobile platforms do not get the playback shortcut',
    (tester) async {
      var toggles = 0;
      await tester.pumpWidget(
        _app(
          onToggle: () => toggles++,
          child: const Focus(autofocus: true, child: SizedBox.shrink()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(toggles, 0);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );
}

Widget _app({required VoidCallback onToggle, Widget? child}) => MaterialApp(
  builder: (_, navigator) =>
      DesktopPlaybackShortcuts(onTogglePlayPause: onToggle, child: navigator!),
  home: Scaffold(body: child ?? const Center(child: Text('Content'))),
);
