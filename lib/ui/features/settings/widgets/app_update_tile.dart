import 'package:flutter/material.dart';

import 'package:phonolite_app/application/controllers/settings/app_updates_controller.dart';
import 'package:phonolite_app/data/models/updates/app_update_progress.dart';
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
    if (controller.progress case final progress?) {
      switch (progress.phase) {
        case AppUpdatePhase.downloading:
          final percent = ((progress.fraction ?? 0) * 100).round();
          return 'Downloading update… $percent%. Select to cancel.';
        case AppUpdatePhase.verifying:
          return 'Verifying the downloaded update… Select to cancel.';
        case AppUpdatePhase.authorizing:
          return 'Waiting for administrator authorization…';
        case AppUpdatePhase.preparing:
          return 'Saving application state before restart…';
        case AppUpdatePhase.installing:
          return 'Installing update. Follow progress in the updater window.';
        case AppUpdatePhase.recoveryRequired:
        case AppUpdatePhase.restartRequired:
          return progress.message ?? 'Check the updater window for recovery details.';
        case AppUpdatePhase.failed:
          return '${progress.message} Select to check again.';
        case AppUpdatePhase.idle:
          if (progress.message != null) return progress.message!;
      }
    }
    if (controller.openingUpdater) {
      return 'Opening updater…';
    }
    if (controller.busy) {
      return 'Checking for updates…';
    }
    if (controller.error != null) {
      return controller.latestRelease != null
          ? 'Could not open the updater. Select to try again.'
          : controller.canCheckForUpdates
          ? 'Could not check for updates. Select to try again.'
          : 'Update checks are unavailable in this build.';
    }
    if (controller.latestRelease case final release?) {
      return 'Version ${release.displayVersion} is available. Download and install.';
    }
    return controller.ready
        ? 'You’re up to date. Select to check again.'
        : 'Updates are checked on startup and every 2 hours.';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final enabled = controller.canCheckForUpdates || controller.canCancelDownload;
      final color = controller.latestRelease != null ? ObsidianPalette.gold : ObsidianPalette.textMuted;

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
            onTap: controller.canCancelDownload
                ? controller.cancelDownload
                : enabled
                ? controller.canInstall
                      ? controller.installLatestUpdate
                      : controller.checkForUpdates
                : null,
          ),
        ),
      );
    },
  );
}
