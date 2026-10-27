import 'package:flutter/material.dart';

import 'package:phonolite_app/application/controllers/settings/desktop_settings_controller.dart';
import 'package:phonolite_app/ui/features/settings/widgets/settings_row.dart';
import 'package:phonolite_app/ui/features/settings/widgets/settings_toggle.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/svg_asset_icon.dart';
import 'package:phonolite_app/ui/structures/sections/base_section.dart';

class DesktopSettingsSection extends BaseSection {
  final DesktopSettingsController controller;

  const DesktopSettingsSection({super.key, required this.controller});

  @override
  String get sectionTitle => 'Desktop';

  SettingsToggle _toggle({
    required String title,
    required String subtitle,
    required Widget icon,
    required bool value,
    required String settingKey,
    required ValueChanged<bool> onChanged,
  }) => SettingsToggle(
    icon: icon,
    title: title,
    subtitle: subtitle,
    value: value,
    settingKey: settingKey,
    onChanged: controller.ready ? onChanged : null,
  );

  @override
  List<Widget> sectionContent(BuildContext context) => [
    _toggle(
      title: 'Launch at startup',
      subtitle: 'Open Phonolite automatically when you sign in to your computer.',
      icon: const SvgAssetIcon(assetName: 'assets/icons/lucide/square-power.svg'),
      value: controller.settings.launchAtStartup,
      settingKey: 'desktop-launch-at-startup',
      onChanged: controller.setLaunchAtStartup,
    ),
    const SettingsDivider(),
    _toggle(
      title: 'Run in background',
      subtitle:
          'Keep playback and downloads running when you close the window. Use the tray or menu bar to show or quit Phonolite.',
      icon: const SvgAssetIcon(assetName: 'assets/icons/lucide/layers-arrow-down.svg'),
      value: controller.settings.runInBackground,
      settingKey: 'desktop-run-in-background',
      onChanged: controller.setRunInBackground,
    ),
    if (controller.error case final error?)
      Padding(
        padding: const EdgeInsets.all(12),
        child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ),
  ];
}
