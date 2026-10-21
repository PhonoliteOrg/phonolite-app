import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/ui/features/playlists/widgets/playlist_editor_modal.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_text_field.dart';

import '../support/widget_test_helpers.dart';

void main() {
  setUp(configureTestFonts);

  testWidgets('playlist fields retain their individual length and cursor rules', (tester) async {
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
      controller.value = shortEdit;
      await tester.pump();
      expect(controller.value, shortEdit);

      for (final cursor in [4, -1, limit + 2]) {
        controller.value = TextEditingValue(
          text: 'x' * (limit + 5),
          selection: TextSelection.collapsed(offset: cursor),
          composing: const TextRange(start: 1, end: 6),
        );
        await tester.pump();

        expect(controller.text, 'x' * limit);
        expect(controller.selection, TextSelection.collapsed(offset: cursor == 4 ? 4 : limit));
        expect(controller.value.composing, TextRange.empty);
      }
    }

    expect(name.text, 'x' * 32);
    expect(description.text, 'x' * 500);
    expect(tester.takeException(), isNull);
  });
}
