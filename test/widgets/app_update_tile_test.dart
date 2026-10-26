import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/application/controllers/settings/app_updates_controller.dart';
import 'package:phonolite_app/data/models/updates/app_update_configuration.dart';
import 'package:phonolite_app/data/models/updates/app_update_release.dart';
import 'package:phonolite_app/infrastructure/platform/app/app_update_platform.dart';
import 'package:phonolite_app/infrastructure/updates/app_update_feed.dart';
import 'package:phonolite_app/ui/features/settings/sections/misc_settings_section.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_list_row.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

import '../support/widget_test_helpers.dart';

void main() {
  setUpAll(configureTestFonts);

  Future<void> pumpSettings(WidgetTester tester, AppUpdatesController controller) => tester.pumpWidget(
    MaterialApp(
      theme: ObsidianTheme.build(),
      home: Scaffold(
        body: MiscSettingsSection(
          logLabel: 'No events yet',
          appVersion: '0.2.0',
          onOpenLogs: () {},
          updates: controller,
        ),
      ),
    ),
  );

  ObsidianListRow updateRow(WidgetTester tester) => tester.widget<ObsidianListRow>(
    find.ancestor(of: find.text('App updates'), matching: find.byType(ObsidianListRow)),
  );

  testWidgets('one greyed update tile lives under Miscellaneous when no update exists', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final platform = _Platform();
    final feed = _Feed()..result.complete(null);
    final controller = AppUpdatesController(platform: platform, feed: feed, isSupported: () => true);
    try {
      await controller.initialize(onInstall: () async {});
      await pumpSettings(tester, controller);
      expect(find.text('Miscellaneous'), findsOneWidget);
      expect(find.descendant(of: find.byType(MiscSettingsSection), matching: find.text('App updates')), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
      expect(find.text('You’re up to date.'), findsOneWidget);
      expect(updateRow(tester).onTap, isNull);
      expect(updateRow(tester).titleColor, ObsidianPalette.textMuted);
      expect(platform.opens, 0);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await controller.shutdown();
      controller.dispose();
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('the startup result enables the tile and clicking opens the newest updater', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final platform = _Platform();
    final feed = _Feed();
    final controller = AppUpdatesController(platform: platform, feed: feed, isSupported: () => true);
    try {
      final starting = controller.initialize(onInstall: () async {});
      await pumpSettings(tester, controller);
      expect(find.text('Checking for updates…'), findsOneWidget);
      expect(updateRow(tester).onTap, isNull);
      feed.result.complete(const AppUpdateRelease(version: '0.2.4.0'));
      await starting;
      await tester.pumpAndSettle();
      expect(find.text('Version 0.2.4 is available. Download and install.'), findsOneWidget);
      expect(updateRow(tester).onTap, isNotNull);
      expect(platform.opens, 0);
      await tester.tap(find.text('App updates'));
      await tester.pumpAndSettle();
      expect(platform.opens, 1);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await controller.shutdown();
      controller.dispose();
      debugDefaultTargetPlatformOverride = null;
    }
  });

  for (final target in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('Miscellaneous excludes the desktop update tile on $target', (tester) async {
      debugDefaultTargetPlatformOverride = target;
      final controller = AppUpdatesController(platform: _Platform(), feed: _Feed());
      try {
        await pumpSettings(tester, controller);
        expect(find.text('Miscellaneous'), findsOneWidget);
        expect(find.text('App version'), findsOneWidget);
        expect(find.text('App updates'), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await controller.shutdown();
        controller.dispose();
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}

class _Platform implements AppUpdatePlatform {
  int opens = 0;

  @override
  Future<AppUpdateConfiguration> initialize({required Future<void> Function() onInstall}) async =>
      const AppUpdateConfiguration(
        available: true,
        feedUrl: 'https://example.com/appcast.xml',
        currentVersion: '0.2.0.0',
      );

  @override
  Future<void> showUpdate() async => opens++;

  @override
  Future<void> dispose() async {}
}

class _Feed implements AppUpdateFeed {
  final result = Completer<AppUpdateRelease?>();

  @override
  Future<AppUpdateRelease?> latest(AppUpdateConfiguration configuration) => result.future;

  @override
  void close() {
    if (!result.isCompleted) {
      result.complete(null);
    }
  }
}
