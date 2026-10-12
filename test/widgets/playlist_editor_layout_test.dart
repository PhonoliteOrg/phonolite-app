import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/widgets/inputs/obsidian_text_field.dart';
import 'package:phonolite_app/widgets/modals/playlist_editor_modal.dart';

import '../support/widget_test_helpers.dart';

void main() {
  setUp(configureTestFonts);

  for (final width in [430.0, 700.0, 1280.0]) {
    for (final textScale in [1.0, 1.4]) {
      for (final creating in [true, false]) {
        testWidgets(
          '${creating ? 'create' : 'edit'} playlist form aligns at $width, scale $textScale',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = Size(width, 900);
            addTearDown(tester.view.resetDevicePixelRatio);
            addTearDown(tester.view.resetPhysicalSize);

            await tester.pumpWidget(
              wrapInTestApp(
                Builder(
                  builder: (context) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(textScale)),
                    child: PlaylistEditorModal(
                      title: creating ? 'Create playlist' : 'Edit playlist',
                      initialValue: 'Focus',
                      showTargetSelector: creating,
                      onSubmit: (_, _, _, _) {},
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();

            final photo = tester.getRect(find.byTooltip('Choose image'));
            final name = tester.getRect(find.byType(ObsidianTextField).first);
            final description = tester.getRect(
              find.byType(ObsidianTextField).last,
            );
            final heading = tester.getRect(find.text('Name'));
            final formTop = creating
                ? tester.getRect(find.byType(Wrap)).top
                : heading.top;

            expect(photo.width, closeTo(photo.height, 0.1));
            expect(name.left, closeTo(description.left, 0.1));
            expect(name.right, closeTo(description.right, 0.1));
            expect(heading.left, closeTo(name.left, 0.1));
            if (width == 1280) {
              expect(photo.right, lessThan(name.left));
            } else if (width == 430) {
              expect(photo.bottom, lessThan(formTop));
            }
            if (creating) {
              expect(
                tester.getRect(find.byType(Wrap)).left,
                closeTo(name.left, 0.1),
              );
              expect(formTop, lessThan(heading.top));
            }
            if (photo.right < name.left) {
              expect(photo.top, closeTo(formTop, 0.1));
              expect(photo.bottom, closeTo(description.bottom, 0.1));
            } else {
              expect(photo.bottom, lessThan(formTop));
            }
            expect(tester.takeException(), isNull);

            await tester.enterText(find.byType(TextField).first, 'Updated');
            await tester.pumpAndSettle();
            expect(
              tester.getRect(find.byTooltip('Choose image')),
              photo,
              reason: 'Editing the name should keep the form geometry stable.',
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
