import 'package:flutter/material.dart';

import 'package:phonolite_app/application/controllers/settings/app_updates_controller.dart';
import 'package:phonolite_app/ui/features/settings/widgets/settings_row.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

class AppUpdateTile extends StatelessWidget {
  final AppUpdatesController controller;

  const AppUpdateTile({super.key, required this.controller});

  String get _subtitle {
    if (controller.disabledReason case final reason?) {
      return reason;
    }
    if (controller.busy) {
      return 'Checking for updates…';
    }
    if (controller.error != null) {
      return controller.latestRelease != null
          ? 'Could not open the updater. Select to try again.'
          : 'Could not check for updates. Checks run on startup and every 2 hours.';
    }
    if (controller.latestRelease case final release?) {
      return 'Version ${release.displayVersion} is available. Download and install.';
    }
    return controller.ready ? 'You’re up to date.' : 'Updates are checked on startup and every 2 hours.';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final enabled = controller.canInstall;
      final color = enabled ? ObsidianPalette.gold : ObsidianPalette.textMuted;

      return Semantics(
        button: true,
        enabled: enabled,
        child: IconTheme.merge(
          data: IconThemeData(color: color),
          child: buildSettingsRow(
            context,
            leading: const Icon(PhonoliteIcons.refreshCw),
            title: 'App updates',
            subtitle: _subtitle,
            titleColor: enabled ? null : color,
            trailing: const Icon(PhonoliteIcons.chevronRight),
            onTap: enabled ? controller.installLatestUpdate : null,
          ),
        ),
      );
    },
  );
}
