import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/data/models/auth/auth_state.dart';
import 'package:phonolite_app/pages/playback/custom_shuffle_settings_page.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/features/playback/widgets/shuffle_preset_editor_modal.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/modal_action_button.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

import '../support/shuffle_preset_test_helpers.dart';
import '../support/widget_test_helpers.dart';

Finder _nameField() =>
    find.byWidgetPredicate((widget) => widget is TextField && widget.decoration?.hintText == 'Custom shuffle name');

Finder _action(String label) =>
    find.byWidgetPredicate((widget) => widget is ModalActionButton && widget.label == label);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _mount(
  WidgetTester tester,
  PresetTestApp app, {
  Size size = const Size(1000, 900),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await app.close();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: ObsidianTheme.build(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: AppScope(controller: app, child: const CustomShuffleSettingsPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(configureTestFonts);

  testWidgets('preset list applies rules explicitly and imports only on request', (tester) async {
    final app = PresetTestApp();
    await _mount(tester, app);
    expect(find.text('Night music'), findsOneWidget);
    expect(app.applied, isEmpty);
    expect(app.imports, 0);

    await _tap(tester, find.text('Night music'));
    expect(app.applied.single.id, 'night');
    await _tap(tester, _action('Import existing filters'));
    expect(app.imports, 1);
  });

  testWidgets('create editor keeps draft isolated until Save and Cancel discards it', (tester) async {
    final app = PresetTestApp();
    await _mount(tester, app);
    await _tap(tester, find.byTooltip('Create custom shuffle'));
    await tester.enterText(_nameField(), 'Work music');
    await _tap(tester, find.text('Beta artist'));
    await _tap(tester, _action('Cancel'));

    expect(app.writes, isEmpty);
    expect(app.localSaves, 0);
    await _tap(tester, find.byTooltip('Create custom shuffle'));
    await tester.enterText(_nameField(), 'Work music');
    await _tap(tester, find.text('Beta artist'));
    await _tap(tester, _action('Save'));

    expect(find.byType(ShufflePresetEditorModal), findsNothing);
    expect(app.writes.single['artistIds'], ['beta']);
    expect(app.applied, isEmpty);
    expect(app.customShuffleSettings.artistIds, ['device-artist']);
    expect(find.text('Work music'), findsOneWidget);
  });

  testWidgets('open editor retains unsaved name and filters after remote update', (tester) async {
    final app = PresetTestApp();
    await _mount(tester, app);
    await _tap(tester, find.byTooltip('Edit custom shuffles'));
    await _tap(tester, find.byTooltip('Edit Night music'));
    await tester.enterText(_nameField(), 'My draft');
    await _tap(tester, find.text('Beta artist'));

    app.publish([testShufflePreset(name: 'Remote name', revision: 2)]);
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(_nameField()).controller!.text, 'My draft');
    expect(find.textContaining('Your draft is preserved'), findsOneWidget);
    expect(_action('Reload'), findsOneWidget);
    await _tap(tester, _action('Save copy'));
    expect(app.writes.single['id'], isNull);
    expect(app.writes.single['name'], 'My draft');
    expect(app.writes.single['artistIds'], ['alpha', 'beta']);
    expect(find.text('Remote name'), findsOneWidget);
    expect(find.text('My draft'), findsOneWidget);
  });

  testWidgets('modify selection deletes only after confirmation', (tester) async {
    final app = PresetTestApp();
    await _mount(tester, app);
    await _tap(tester, find.byTooltip('Edit custom shuffles'));
    await _tap(tester, find.text('Night music'));
    await _tap(tester, find.byTooltip('Remove selected'));
    expect(app.deleted, isEmpty);
    await _tap(tester, find.text('DELETE'));
    expect(app.deleted.single.id, 'night');
    expect(find.textContaining('No saved custom shuffles'), findsOneWidget);
  });

  testWidgets('local rules remain editable offline through the source selector', (tester) async {
    final app = PresetTestApp();
    app.authState = AuthState(baseUrl: '', isAuthorized: false);
    app.shufflePresetsAvailable = false;
    await _mount(tester, app);
    await _tap(tester, find.text('LOCAL'));
    await _tap(tester, find.text('Local custom shuffle'));
    expect(_nameField(), findsNothing);
    await _tap(tester, _action('Save'));
    expect(app.writes, isEmpty);
    expect(app.localSaves, 1);
    expect(app.customShuffleSettings.artistIds, ['device-artist']);
  });

  for (final size in [const Size(320, 600), const Size(1440, 900)]) {
    testWidgets('preset editor fits ${size.width.toInt()}px with larger text', (tester) async {
      final app = PresetTestApp();
      await _mount(tester, app, size: size, textScale: 1.4);
      await _tap(tester, find.byTooltip('Create custom shuffle'));
      expect(tester.takeException(), isNull);
      await tester.enterText(_nameField(), 'Draft');
      await _tap(tester, _action('Cancel'));
      expect(find.byType(ShufflePresetEditorModal), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
