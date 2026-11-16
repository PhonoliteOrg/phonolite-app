import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/data/models/downloads/download_quality.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_switch.dart';

import 'app_driver.dart';

/// Settings page steps. Rows are found by their visible title; switches by
/// the label they announce to assistive technology.
extension SettingsSteps on AppDriver {
  Finder _switch(String title) =>
      find.byWidgetPredicate((widget) => widget is ObsidianSwitch && widget.semanticLabel == title, description: title);

  bool switchValue(String title) => tester.widget<ObsidianSwitch>(_switch(title)).value;

  Future<void> openSettings() => openTab('Settings');

  /// Opens a settings row that leads to another page or dialog.
  Future<void> openSettingsRow(String title) => activate(find.text(title));

  Future<void> toggleSetting(String title) => activate(_switch(title));

  /// This run's saved default for future downloads.
  DownloadQuality get downloadQuality => settings.download.settings.quality;

  /// Opens Download quality and waits for the saved choice to load.
  Future<void> openDownloadQuality() async {
    await openSettingsRow('Download quality');
    await waitUntil(() => settings.download.ready, description: 'download settings to load');
    await settle();
  }

  /// Chooses a quality and waits until the choice has been written.
  Future<void> chooseDownloadQuality(DownloadQuality quality) async {
    await choose(quality.label);
    await waitUntil(() => !settings.download.saving, description: 'download quality to save');
    await settle();
  }

  Future<void> requestFullReset() => activate(labelled('Full reset'));
}
