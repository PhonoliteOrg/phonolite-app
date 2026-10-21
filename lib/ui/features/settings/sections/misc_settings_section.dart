import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/features/settings/widgets/settings_row.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/structures/sections/base_section.dart';

class MiscSettingsSection extends BaseSection {
  final String logLabel;
  final VoidCallback onOpenLogs;

  const MiscSettingsSection({super.key, required this.logLabel, required this.onOpenLogs});

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
      ],
    ),
  ];
}
