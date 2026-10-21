import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/settings/listening_statistics_controller.dart';
import 'package:phonolite_app/data/models/auth/auth_state.dart';
import 'package:phonolite_app/ui/features/settings/widgets/listening_statistics_setting.dart';
import 'package:phonolite_app/ui/features/settings/widgets/settings_row.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/structures/sections/base_section.dart';

class UserSettingsSection extends BaseSection {
  final AppController controller;
  final AuthState authState;
  final int sessionRevision;
  final VoidCallback onResetPassword;

  const UserSettingsSection({
    super.key,
    required this.controller,
    required this.authState,
    required this.sessionRevision,
    required this.onResetPassword,
  });

  @override
  String get sectionTitle => 'User';

  Future<void> _resetListeningStatistics() => ListeningStatisticsController.resetForSession(
    controller,
    serverConnected: authState.isAuthorized,
    sessionRevision: sessionRevision,
  );

  @override
  List<Widget> sectionContent(BuildContext context) => [
    StreamBuilder<bool>(
      stream: controller.statsCollectionEnabledStream,
      initialData: controller.statsCollectionEnabled,
      builder: (context, snapshot) => ListeningStatisticsSetting(
        enabled: snapshot.data ?? controller.statsCollectionEnabled,
        onChanged: controller.setStatsCollectionEnabled,
        serverConnected: authState.isAuthorized,
        onReset: _resetListeningStatistics,
      ),
    ),
    if (authState.isAuthorized) ...[
      const SettingsDivider(),
      KeyedSubtree(
        key: const ValueKey('reset-user-password'),
        child: buildSettingsRow(
          context,
          leading: const Icon(PhonoliteIcons.lockKeyhole),
          title: 'Reset user password',
          subtitle: 'Change the password for your signed-in account.',
          trailing: const Icon(PhonoliteIcons.chevronRight),
          onTap: onResetPassword,
        ),
      ),
    ],
  ];
}
