import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/data/models/downloads/download_quality.dart';
import 'package:phonolite_app/data/storage/preferences/settings_files.dart';
import 'package:phonolite_app/pages/logs/logs_page.dart';
import 'package:phonolite_app/pages/playback/custom_shuffle_settings_page.dart';
import 'package:phonolite_app/pages/settings/download_quality_page.dart';
import 'package:phonolite_app/pages/settings/settings_page.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_nav_icon.dart';

import '../support/feature_scenario.dart';
import '../support/feature_world.dart';
import '../support/platform_profile.dart';
import '../support/settings_steps.dart';

const _managedResetNote = 'Local storage will remain managed automatically on this device.';
const _folderResetNote = 'Storage folder choices will be kept.';

/// Settings behavior expected on every platform, including the sections that
/// exist only where a platform offers the underlying capability.
final settingsScenarios = [
  FeatureScenario(
    id: 'settings.desktop_section',
    description: 'Launch-at-startup and background settings appear on exactly the desktop platforms',
    covers: [],
    world: () => FeatureWorld.offlineLibrary,
    run: (app) async {
      await app.openSettings();
      app.expectShownExactlyWhen(Capability.desktopLifecycle, 'Launch at startup');
      app.expectShownExactlyWhen(Capability.desktopLifecycle, 'Run in background');
    },
  ),
  FeatureScenario(
    id: 'settings.app_updates',
    description: 'The App updates tile appears on exactly the platforms that update themselves',
    covers: [],
    world: () => FeatureWorld.offlineLibrary,
    run: (app) async {
      await app.openSettings();
      app.expectShownExactlyWhen(Capability.selfUpdate, 'App updates');
    },
  ),
  FeatureScenario(
    id: 'settings.reset_cancel',
    description: 'Full reset explains what is kept on this platform, and Cancel keeps local data',
    covers: ['settings.reset_open', 'settings.reset_cancel'],
    world: () => FeatureWorld.offlineLibrary,
    run: (app) async {
      await app.openSettings();
      await app.requestFullReset();

      final managed = app.profile.supports(Capability.managedStorage);
      expect(find.textContaining(managed ? _managedResetNote : _folderResetNote), findsOneWidget);
      expect(find.textContaining(managed ? _folderResetNote : _managedResetNote), findsNothing);

      await app.modalAction('Cancel');
      expect(app.controller.localDataResets, 0);
    },
  ),
  FeatureScenario(
    id: 'settings.reset_confirm',
    description: 'Confirming Full reset clears local data once',
    covers: ['settings.reset_open', 'settings.reset_confirm'],
    world: () => FeatureWorld.offlineLibrary,
    run: (app) async {
      await app.openSettings();
      await app.requestFullReset();
      await app.modalAction('Reset');

      expect(app.controller.localDataResets, 1);
    },
  ),
  FeatureScenario(
    id: 'settings.statistics_toggle',
    description: 'Listening statistics collection controls whether the Stats tab exists',
    covers: ['settings.statistics_toggle', 'navigation.stats'],
    world: () => FeatureWorld.offlineLibrary,
    run: (app) async {
      const toggle = 'Collect listening statistics';
      Finder statsTab() => find.byWidgetPredicate((widget) => widget is ObsidianNavIcon && widget.label == 'Stats');

      await app.openSettings();
      final enabled = app.switchValue(toggle);
      expect(statsTab(), enabled ? findsOneWidget : findsNothing);

      await app.toggleSetting(toggle);
      expect(app.switchValue(toggle), !enabled);
      expect(statsTab(), enabled ? findsNothing : findsOneWidget);

      await app.toggleSetting(toggle);
      expect(statsTab(), enabled ? findsOneWidget : findsNothing);
    },
  ),
  FeatureScenario(
    id: 'settings.gapless_toggle',
    description: 'Seamless mixed-format playback switches the output conversion preference',
    covers: ['settings.gapless_format_policy'],
    world: () => FeatureWorld.offlineLibrary,
    run: (app) async {
      const toggle = 'Seamless mixed-format playback';
      final initial = app.controller.gaplessResampling;

      await app.openSettings();
      await app.toggleSetting(toggle);
      expect(app.controller.gaplessResampling, !initial);
      expect(app.switchValue(toggle), !initial);
    },
  ),
  FeatureScenario(
    id: 'settings.download_quality',
    description: 'A fresh install recommends High; choosing another quality saves it and updates Settings',
    covers: ['settings.download_quality_open', 'settings.download_quality_select', 'settings.download_quality_back'],
    world: () => FeatureWorld.offlineLibrary,
    run: (app) async {
      await app.openSettings();
      await app.openDownloadQuality();
      app.expectPage<DownloadQualityPage>();
      expect(app.downloadQuality, DownloadQuality.high);

      await app.chooseDownloadQuality(DownloadQuality.spaceSaver);
      expect(app.downloadQuality, DownloadQuality.spaceSaver);
      // The production resolver knows each platform's settings layout.
      final saved = await app.tester.runAsync(() => const SettingsFiles().resolve('download_settings.json'));

      expect(saved!.readAsStringSync(), contains(DownloadQuality.spaceSaver.wireValue));

      await app.tapBackLink('Back to settings');
      app.expectPage<SettingsPage>();
      expect(find.textContaining('${DownloadQuality.spaceSaver.label} · '), findsOneWidget);
    },
  ),
  FeatureScenario(
    id: 'settings.custom_shuffle',
    description: 'Custom Shuffle opens its settings page and returns to Settings',
    covers: ['settings.custom_shuffle', 'custom_shuffle.back'],
    world: () => FeatureWorld.offlineLibrary,
    run: (app) async {
      await app.openSettings();
      await app.openSettingsRow('Custom Shuffle');
      app.expectPage<CustomShuffleSettingsPage>();

      await app.tapBackLink('Back to settings');
      app.expectPage<SettingsPage>();
    },
  ),
  FeatureScenario(
    id: 'settings.logs',
    description: 'Logs opens the log viewer and returns to Settings',
    covers: ['settings.logs', 'logs.back'],
    world: () => FeatureWorld.offlineLibrary,
    run: (app) async {
      await app.openSettings();
      await app.openSettingsRow('Logs');
      app.expectPage<LogsPage>();

      await app.tapBackLink('Back to settings');
      app.expectPage<SettingsPage>();
    },
  ),
];
