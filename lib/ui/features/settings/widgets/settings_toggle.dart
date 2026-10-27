import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/features/settings/widgets/settings_row.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_switch.dart';

/// A settings row with the shared switch appearance, semantics and haptics.
class SettingsToggle extends StatelessWidget {
  final Widget icon;
  final String title;
  final String subtitle;
  final bool value;
  final String settingKey;
  final ValueChanged<bool>? onChanged;

  const SettingsToggle({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.settingKey,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => buildSettingsRow(
    context,
    leading: icon,
    title: title,
    subtitle: subtitle,
    trailing: ObsidianSwitch(key: ValueKey(settingKey), value: value, semanticLabel: title, onChanged: onChanged),
  );
}
