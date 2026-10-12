import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/entities/models.dart';
import 'package:phonolite_app/entities/playback_state.dart';
import 'package:phonolite_app/widgets/inputs/obsidian_text_field.dart';
import 'package:phonolite_app/widgets/layouts/obsidian_scale.dart';
import 'package:phonolite_app/widgets/modals/add_to_playlist_modal.dart';
import 'package:phonolite_app/widgets/modals/confirmation_modal.dart';
import 'package:phonolite_app/widgets/modals/device_picker_modal.dart';
import 'package:phonolite_app/widgets/modals/download_manager_panel.dart';
import 'package:phonolite_app/widgets/modals/modal_action_button.dart';
import 'package:phonolite_app/widgets/modals/obsidian_adaptive_modal.dart';
import 'package:phonolite_app/widgets/modals/obsidian_dialog.dart';
import 'package:phonolite_app/widgets/modals/playlist_editor_modal.dart';
import 'package:phonolite_app/widgets/ui/obsidian_theme.dart';
import 'package:phonolite_app/widgets/ui/obsidian_widgets.dart';
import 'package:phonolite_app/widgets/ui/obsidian_overflow_action_button.dart';

import '../support/widget_test_helpers.dart';

enum _Kind { create, edit, add, device, confirmation, downloads }

String _title(_Kind kind) => switch (kind) {
  _Kind.create => 'Create playlist',
  _Kind.edit => 'Edit playlist',
  _Kind.add => 'Add to local playlist',
  _Kind.device => 'Select output device',
  _Kind.confirmation => 'Confirm removal',
  _Kind.downloads => 'Download Manager',
};

Widget _dialog(_Kind kind, VoidCallback onAction) => switch (kind) {
  _Kind.create || _Kind.edit => PlaylistEditorModal(
    title: _title(kind),
    initialValue: 'Focus',
    showTargetSelector: kind == _Kind.create,
    onSubmit: (_, _, _, _) => onAction(),
  ),
  _Kind.add => AddToPlaylistModal(
    scope: ActionScope.local,
    playlists: [Playlist(id: 'focus', name: 'Focus', trackIds: [])],
    trackId: 'track',
    canUsePlaylists: true,
    onSelected: (_) => onAction(),
  ),
  _Kind.device => DevicePickerModal(
    fetchDevices: (_) async => [OutputDevice(id: 1, name: 'Speakers')],
    selectedId: 1,
    onSelected: (_) async => onAction(),
  ),
  _Kind.confirmation => ConfirmationModal(
    title: _title(kind),
    message: 'Remove this selection from the device?',
    confirmLabel: 'Remove',
  ),
  _Kind.downloads => const DownloadManagerPanel(downloadsOverride: []),
};

void main() {
  setUp(configureTestFonts);

  for (final width in [320.0, 390.0, 700.0, 1280.0]) {
    for (final textScale in [1.0, 1.4]) {
      for (final kind in _Kind.values) {
        testWidgets('${kind.name} modal at $width, scale $textScale', (
          tester,
        ) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 844);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          var actionCalls = 0;
          var closed = false;
          Object? result;
          final scale = ObsidianScale.compute(width);
          final theme = ObsidianTheme.build(scale: scale);
          final modalTheme = width < 820 ? ObsidianTheme.build() : theme;

          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: ObsidianScale(scale: scale, child: child!),
              ),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () async {
                      result = kind == _Kind.downloads
                          ? await ObsidianAdaptiveModal.show<Object>(
                              context: context,
                              builder: (_, presentation) =>
                                  DownloadManagerPanel(
                                    downloadsOverride: const [],
                                    presentation: presentation,
                                  ),
                            )
                          : await showDialog<Object>(
                              context: context,
                              builder: (_) =>
                                  _dialog(kind, () => actionCalls++),
                            );
                      closed = true;
                    },
                    child: const Text('Open modal'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open modal'));
          await tester.pumpAndSettle();

          final title = find.text(_title(kind));
          final surface = tester.getRect(find.byType(ObsidianFrostedSurface));
          final titleRect = tester.getRect(title);
          final titleStyle = tester
              .renderObject<RenderParagraph>(title)
              .text
              .style!;
          expect(
            titleStyle.fontSize,
            modalTheme.dialogTheme.titleTextStyle!.fontSize,
          );
          expect(
            titleStyle.fontFamily,
            modalTheme.dialogTheme.titleTextStyle!.fontFamily,
          );
          if (textScale == 1) {
            expect(titleRect.left - surface.left, closeTo(24, 0.1));
          }

          final labels = tester
              .widgetList<ModalActionButton>(find.byType(ModalActionButton))
              .map((button) => button.label.toUpperCase())
              .toList();
          final expected = switch (kind) {
            _Kind.create || _Kind.edit => ['CLOSE', 'SAVE'],
            _Kind.device => ['CLOSE', 'REFRESH'],
            _Kind.confirmation => ['CANCEL', 'REMOVE'],
            _ => ['CLOSE'],
          };
          expect(labels, expected);
          final dismiss = find.widgetWithText(
            ModalActionButton,
            expected.first,
          );
          final primary = find.widgetWithText(ModalActionButton, expected.last);
          final dismissRect = tester.getRect(dismiss);
          final primaryRect = tester.getRect(primary);
          expect(surface.right - primaryRect.right, closeTo(24, 0.1));
          expect(surface.bottom - primaryRect.bottom, closeTo(16, 0.1));
          expect(titleRect.bottom, lessThan(dismissRect.top));
          expect(dismissRect.height, greaterThanOrEqualTo(48));
          if (width < 820 && kind != _Kind.downloads) {
            expect(surface.width, closeTo(width - 24, 0.1));
          }
          if (expected.length > 1) {
            expect(dismissRect.top, lessThanOrEqualTo(primaryRect.top));
            if (dismissRect.top == primaryRect.top) {
              expect(dismissRect.right, lessThan(primaryRect.left));
            }
          }
          expect(tester.takeException(), isNull);

          await tester.tap(dismiss);
          await tester.pumpAndSettle();
          expect(closed, isTrue);
          expect(actionCalls, 0);
          expect(result, kind == _Kind.confirmation ? isFalse : isNull);
          expect(title, findsNothing);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  for (final kind in [
    _Kind.create,
    _Kind.edit,
    _Kind.add,
    _Kind.device,
    _Kind.confirmation,
  ]) {
    testWidgets('${kind.name} stays usable above the mobile keyboard', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(wrapInTestApp(_dialog(kind, () {})));
      await tester.pumpAndSettle();
      final dismiss = find.byType(ModalActionButton).first;
      final rect = tester.getRect(dismiss);
      expect(rect.height, greaterThanOrEqualTo(48));
      expect(rect.bottom, lessThanOrEqualTo(360));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('playlist action and search clear accept taps at their edges', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    var added = 0;
    await tester.pumpWidget(wrapInTestApp(_dialog(_Kind.add, () => added++)));
    await tester.pumpAndSettle();
    final add = find.byType(ObsidianHudIconButton).last;
    final rect = tester.getRect(add);
    expect(rect.width, greaterThanOrEqualTo(48));
    expect(rect.height, greaterThanOrEqualTo(48));
    await tester.tapAt(rect.bottomRight - const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(added, 1);
    expect(
      tester.getSize(find.byType(ObsidianTextField)).height,
      greaterThanOrEqualTo(56),
    );
    await tester.enterText(find.byType(TextField), 'Focus');
    await tester.pumpAndSettle();
    final clear = find.descendant(
      of: find.byTooltip('Clear search'),
      matching: find.byType(ObsidianHudIconButton),
    );
    final clearRect = tester.getRect(clear);
    expect(clearRect.width, greaterThanOrEqualTo(48));
    expect(clearRect.height, greaterThanOrEqualTo(48));
    await tester.tapAt(clearRect.bottomRight - const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile popup actions wrap labels and accept edge taps', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    var selected = 0;
    await tester.pumpWidget(
      wrapInTestApp(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(1.4),
          ),
          child: ObsidianOverflowActionButton(
            tooltip: 'More actions',
            actions: [
              ObsidianMenuAction(
                label: 'Remove this downloaded selection',
                icon: Icons.delete,
                onTap: () => selected++,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byType(PopupMenuItem<int>));
    expect(rect.height, greaterThanOrEqualTo(48));
    await tester.tapAt(rect.bottomRight - const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(selected, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'modal footer wraps long actions and supports keyboard activation',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      var dismissed = false;
      await tester.pumpWidget(
        wrapInTestApp(
          ObsidianAlertDialog(
            title: const Text('Confirm changes'),
            content: const Text('Choose an action.'),
            actions: [
              ModalActionButton(
                label: 'Close without saving changes',
                onPressed: () => dismissed = true,
              ),
              ModalActionButton(
                label: 'Save all playlist changes',
                onPressed: () {},
              ),
            ],
          ),
        ),
      );
      final dismiss = find.byType(TextButton).first;
      final primary = find.byType(TextButton).last;
      expect(
        tester.getRect(dismiss).bottom,
        lessThan(tester.getRect(primary).top),
      );
      Focus.of(
        tester.element(find.text('CLOSE WITHOUT SAVING CHANGES')),
      ).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(dismissed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
