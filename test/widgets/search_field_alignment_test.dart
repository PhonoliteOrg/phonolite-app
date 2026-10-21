import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_text_field.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/search_hud.dart';

import '../support/widget_test_helpers.dart';

void main() {
  setUp(configureTestFonts);

  for (final height in [48.0, 54.0]) {
    for (final textScale in [1.0, 1.4]) {
      testWidgets(
        'search text stays centered at height $height, scale $textScale',
        (tester) async {
          final controller = TextEditingController();
          addTearDown(controller.dispose);
          await tester.pumpWidget(
            wrapInTestApp(
              MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
                child: Center(
                  child: SizedBox(
                    width: 360,
                    height: height,
                    child: SearchHud(
                      controller: controller,
                      height: height,
                      onSubmit: () {},
                      onClear: () {},
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          double fieldCenter() =>
              tester.getCenter(find.byType(ObsidianTextField)).dy;
          expect(
            tester.getCenter(find.text('Search library')).dy,
            closeTo(fieldCenter(), 1),
            reason:
                'The placeholder should sit in the middle of the search bar.',
          );

          final bar = tester.getRect(find.byType(ObsidianTextField));
          expect(
            bar.width,
            360,
            reason: 'The search field should fill the available width.',
          );
          await tester.tapAt(bar.topLeft + const Offset(1, 1));
          await tester.pump();
          expect(
            tester
                .widget<TextField>(find.byType(TextField))
                .focusNode!
                .hasFocus,
            isTrue,
            reason: 'The search bar corner should be square and tappable.',
          );
          await tester.tapAt(Offset(bar.center.dx, bar.top + 2));
          await tester.pump();
          expect(
            tester
                .widget<TextField>(find.byType(TextField))
                .focusNode!
                .hasFocus,
            isTrue,
            reason: 'The full search bar should remain tappable.',
          );

          controller.text = 'Boards';
          await tester.pump();
          final editable = tester.allRenderObjects
              .whereType<RenderEditable>()
              .single;
          final caret = editable.getLocalRectForCaret(
            const TextPosition(offset: 0),
          );
          expect(
            editable.localToGlobal(caret.center).dy,
            closeTo(fieldCenter(), 2),
            reason:
                'Entered text should stay centered when the clear icon appears.',
          );
          await tester.tap(find.byTooltip('Clear search'));
          await tester.pump();
          expect(controller.text, isEmpty);
          expect(
            tester.getCenter(find.text('Search library')).dy,
            closeTo(fieldCenter(), 1),
          );
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant({
          TargetPlatform.android,
          TargetPlatform.windows,
        }),
      );
    }
  }

  testWidgets('multiline fields keep their text at the top', (tester) async {
    final controller = TextEditingController(
      text: 'First\nSecond\nThird\nFourth',
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      wrapInTestApp(
        Center(
          child: SizedBox(
            width: 360,
            height: 132,
            child: ObsidianTextField(
              controller: controller,
              height: 132,
              minLines: 4,
              maxLines: 4,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final editable = tester.allRenderObjects.whereType<RenderEditable>().single;
    final firstLine = editable.getLocalRectForCaret(
      const TextPosition(offset: 0),
    );
    expect(
      editable.localToGlobal(firstLine.center).dy,
      lessThan(tester.getCenter(find.byType(ObsidianTextField)).dy - 20),
    );
    expect(tester.takeException(), isNull);
  });
}
