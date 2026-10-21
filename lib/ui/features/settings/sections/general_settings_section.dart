import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/data/models/auth/auth_state.dart';
import 'package:phonolite_app/ui/features/settings/widgets/server_connection_setting.dart';
import 'package:phonolite_app/ui/features/settings/widgets/settings_row.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/server_icon.dart';
import 'package:phonolite_app/ui/structures/sections/base_section.dart';

class GeneralSettingsSection extends BaseSection {
  final AppController controller;
  final AuthState authState;
  final VoidCallback onLogin;
  final VoidCallback onCustomShuffle;

  const GeneralSettingsSection({
    super.key,
    required this.controller,
    required this.authState,
    required this.onLogin,
    required this.onCustomShuffle,
  });

  @override
  String get sectionTitle => 'General';

  @override
  List<Widget> sectionContent(BuildContext context) => [
    buildSettingsRow(
      context,
      leading: const ServerIcon(),
      title: 'Server',
      subtitle: 'Your server provides access to your music library.',
      trailing: settingsServerActions(context, controller: controller, authState: authState, onLogin: onLogin),
    ),
    const SettingsDivider(),
    buildSettingsRow(
      context,
      leading: const Icon(PhonoliteIcons.shuffle),
      title: 'Custom Shuffle',
      subtitle: 'Custom shuffle plays music from your chosen artists and genres.',
      trailing: const Icon(PhonoliteIcons.chevronRight),
      onTap: onCustomShuffle,
    ),
  ];
}
