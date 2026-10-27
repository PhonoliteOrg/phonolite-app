import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/application/controllers/settings/desktop_settings_controller.dart';
import 'package:phonolite_app/data/models/preferences/desktop_settings.dart';
import 'package:phonolite_app/data/storage/preferences/desktop_settings_storage.dart';
import 'package:phonolite_app/infrastructure/platform/app/desktop_lifecycle_platform.dart';
import 'package:phonolite_app/ui/features/settings/sections/desktop_settings_section.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_switch.dart';

import '../support/widget_test_helpers.dart';

void main() {
  setUpAll(configureTestFonts);

  testWidgets('both desktop switches remain enabled while changes are saved', (tester) async {
    final storage = _DelayedStorage();
    final controller = DesktopSettingsController(storage: storage, platform: _Platform(), isSupported: () => true);
    await controller.initialize(beforeQuit: () async {});
    addTearDown(() async {
      storage.finishWrites();
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });
    await tester.pumpWidget(
      wrapInTestApp(
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) => DesktopSettingsSection(controller: controller),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final startup = find.byKey(const ValueKey('desktop-launch-at-startup'));
    final background = find.byKey(const ValueKey('desktop-run-in-background'));

    await tester.tap(startup);
    await tester.pumpAndSettle();

    expect(controller.saving, isTrue);
    expect(tester.widget<ObsidianSwitch>(startup).value, isFalse);
    expect(tester.widget<ObsidianSwitch>(background).value, isTrue);
    expect(tester.widget<ObsidianSwitch>(startup).onChanged, isNotNull);
    expect(tester.widget<ObsidianSwitch>(background).onChanged, isNotNull);

    await tester.tap(background);
    await tester.pumpAndSettle();
    await tester.tap(startup);
    await tester.pumpAndSettle();

    expect(tester.widget<ObsidianSwitch>(startup).value, isTrue);
    expect(tester.widget<ObsidianSwitch>(background).value, isFalse);
    expect(tester.widget<ObsidianSwitch>(startup).onChanged, isNotNull);
    expect(tester.widget<ObsidianSwitch>(background).onChanged, isNotNull);
    storage.finishWrites();
    await tester.pumpAndSettle();

    expect(storage.saved.toJson(), {'launchAtStartup': true, 'runInBackground': false});
    expect(controller.saving, isFalse);
    expect(tester.takeException(), isNull);
  });
}

class _DelayedStorage extends DesktopSettingsStorage {
  final Completer<void> _writes = Completer<void>();
  DesktopSettings saved = const DesktopSettings();

  void finishWrites() {
    if (!_writes.isCompleted) {
      _writes.complete();
    }
  }

  @override
  Future<DesktopSettings> read() async => saved;

  @override
  Future<void> write(DesktopSettings settings) async {
    await _writes.future;
    saved = settings;
  }
}

class _Platform implements DesktopLifecyclePlatform {
  @override
  Future<void> initialize({required Future<void> Function() onClose, required Future<void> Function() onQuit}) async {}

  @override
  Future<void> setLaunchAtStartup(bool enabled) async {}

  @override
  Future<void> setBackgroundEnabled(bool enabled) async {}

  @override
  Future<void> hide() async {}

  @override
  Future<void> show() async {}

  @override
  Future<void> quit() async {}

  @override
  Future<void> dispose() async {}
}
