import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/ui/features/playlists/widgets/playlist_editor_modal.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_text_field.dart';

import '../support/widget_test_helpers.dart';

void main() {
  setUp(configureTestFonts);

  testWidgets('playlist fields limit length by user-perceived characters', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      wrapInTestApp(
        PlaylistEditorModal(
          title: 'Edit playlist',
          initialValue: '  ${'n' * 35}  ',
          initialDescription: '  ${'d' * 505}  ',
          onSubmit: (_, _, _, _) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fields = tester.widgetList<ObsidianTextField>(find.byType(ObsidianTextField)).toList();
    final name = fields[0].controller;
    final description = fields[1].controller;
    expect(name.text, 'n' * 32);
    expect(description.text, 'd' * 500);
    expect(find.text('32/32'), findsOneWidget);
    expect(find.text('500/500'), findsOneWidget);

    for (final (controller, limit) in [(name, 32), (description, 500)]) {
      const shortEdit = TextEditingValue(
        text: 'Short edit',
        selection: TextSelection(baseOffset: 2, extentOffset: 5),
        composing: TextRange(start: 1, end: 6),
      );
      await tester.showKeyboard(
        find.byWidgetPredicate((widget) => widget is EditableText && widget.controller == controller),
      );
      tester.testTextInput.updateEditingValue(shortEdit);
      await tester.pump();
      expect(controller.value, shortEdit);

      // Input past the limit is cut to the limit.
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: 'x' * (limit + 5),
          selection: TextSelection.collapsed(offset: limit + 5),
        ),
      );
      await tester.pump();
      expect(controller.text, 'x' * limit);
      expect(find.text('$limit/$limit'), findsOneWidget);

      // Limits count user-perceived characters: an emoji is one character and is never split.
      // (A full field keeps its value against longer input, so start from empty.)
      tester.testTextInput.updateEditingValue(TextEditingValue.empty);
      await tester.pump();
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: '😀' * (limit + 1),
          selection: TextSelection.collapsed(offset: 2 * (limit + 1)),
        ),
      );
      await tester.pump();
      expect(controller.text, '😀' * limit);
      expect(find.text('$limit/$limit'), findsOneWidget);
    }

    expect(name.text, '😀' * 32);
    expect(description.text, '😀' * 500);
    expect(tester.takeException(), isNull);
  });

  testWidgets('composing input is truncated only after the composition ends', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      wrapInTestApp(PlaylistEditorModal(title: 'Edit playlist', initialValue: '', onSubmit: (_, _, _, _) {})),
    );
    await tester.pumpAndSettle();

    final name = tester.widgetList<ObsidianTextField>(find.byType(ObsidianTextField)).first.controller;

    await tester.showKeyboard(find.byWidgetPredicate((widget) => widget is EditableText && widget.controller == name));

    // An IME (for example CJK) may briefly exceed the limit while composing; it is not interrupted.
    final composing = TextEditingValue(
      text: '${'x' * 31}ab',
      selection: const TextSelection.collapsed(offset: 33),
      composing: const TextRange(start: 31, end: 33),
    );
    tester.testTextInput.updateEditingValue(composing);
    await tester.pump();
    expect(name.value, composing);

    tester.testTextInput.updateEditingValue(composing.copyWith(composing: TextRange.empty));
    await tester.pump();
    expect(name.text, '${'x' * 31}a');
    expect(tester.takeException(), isNull);
  }, variant: const TargetPlatformVariant(<TargetPlatform>{TargetPlatform.iOS, TargetPlatform.macOS}));
}
