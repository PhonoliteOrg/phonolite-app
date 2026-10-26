import 'package:flutter/material.dart';

import 'package:phonolite_app/application/controllers/settings/app_updates_controller.dart';
import 'package:phonolite_app/ui/features/settings/widgets/app_update_tile.dart';
import 'package:phonolite_app/ui/features/settings/widgets/settings_row.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/structures/sections/base_section.dart';

class MiscSettingsSection extends BaseSection {
  final String logLabel;
  final String appVersion;
  final VoidCallback onOpenLogs;
  final AppUpdatesController? updates;

  const MiscSettingsSection({
    super.key,
    required this.logLabel,
    required this.appVersion,
    required this.onOpenLogs,
    this.updates,
  });

  @override
  String get sectionTitle => 'Miscellaneous';

  @override
  List<Widget> sectionContent(BuildContext context) => [
    Column(
      children: [
        buildSettingsRow(
          context,
          leading: const Icon(PhonoliteIcons.receiptText),
          title: 'Logs',
          subtitle: logLabel,
          trailing: const Icon(PhonoliteIcons.chevronRight),
          onTap: onOpenLogs,
        ),
        const SettingsDivider(),
        buildSettingsRow(context, leading: const Icon(PhonoliteIcons.tag), title: 'App version', subtitle: appVersion),
        if (updates case final controller? when controller.showInSettings) ...[
          const SettingsDivider(),
          AppUpdateTile(controller: controller),
        ],
      ],
    ),
  ];
}
