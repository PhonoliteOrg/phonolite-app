import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_hud_icon_button.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/modal_action_button.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_dialog.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';
import 'package:phonolite_app/ui/shell/toolbars/page_toolbar_actions.dart';

class StatsHistoryStatus extends StatelessWidget {
  final bool collectionEnabled;
  final bool hasAccount;
  final bool connected;
  final bool serverEnabled;
  final bool syncing;
  final DateTime? lastSyncedAt;
  final String? message;
  final VoidCallback? onImport;

  const StatsHistoryStatus({
    super.key,
    required this.collectionEnabled,
    required this.hasAccount,
    required this.connected,
    required this.serverEnabled,
    this.syncing = false,
    this.lastSyncedAt,
    this.message,
    this.onImport,
  });

  IconData get _statusIcon {
    if (!collectionEnabled) {
      return PhonoliteIcons.circlePause;
    }

    if (!hasAccount) {
      return PhonoliteIcons.database;
    }

    if (!connected || !serverEnabled) {
      return PhonoliteIcons.cloudOff;
    }

    return syncing ? PhonoliteIcons.cloudSync : PhonoliteIcons.cloudCheck;
  }

  Future<void> _showStatus(BuildContext context) async {
    final importRequested = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ObsidianAlertDialog(
        title: const Text('Listening history'),
        scrollable: true,
        content: DefaultTextStyle.merge(
          style: const TextStyle(color: ObsidianPalette.textMuted, height: 1.4),
          child: SizedBox(
            width: 360,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_statusText()),
                if (hasAccount && lastSyncedAt != null) ...[
                  const SizedBox(height: 8),
                  Text(_lastSyncText(dialogContext)),
                ],
                if (onImport != null) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Listening recorded before signing in stays on this device until you add it to your account.',
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          ModalActionButton(label: 'Close', onPressed: () => Navigator.of(dialogContext).pop(false)),
          if (onImport != null)
            ModalActionButton(
              label: 'Add local history',
              icon: PhonoliteIcons.cloud,
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
        ],
      ),
    );

    if (importRequested == true && context.mounted) {
      onImport?.call();
    }
  }

  String _statusText() {
    if (!collectionEnabled) {
      return 'Collection is off on this device. New listening and uploads are stopped; existing history is kept.';
    }

    final providedMessage = message?.trim();

    if (providedMessage != null && providedMessage.isNotEmpty) {
      return providedMessage;
    }

    if (!hasAccount) {
      return 'Listening is saved on this device, even offline.';
    }

    if (!serverEnabled) {
      return 'Server sync is disabled. Listening is saved on this device.';
    }

    if (!connected) {
      return 'Offline. Listening is saved on this device and will sync when connected.';
    }

    if (syncing) {
      return 'Syncing listening history across your apps…';
    }

    return 'Listening is saved on this device and synced across your apps.';
  }

  String _lastSyncText(BuildContext context) {
    final local = lastSyncedAt!.toLocal();
    final labels = MaterialLocalizations.of(context);
    final date = labels.formatShortDate(local);
    final time = labels.formatTimeOfDay(
      TimeOfDay.fromDateTime(local),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );

    return 'Last synced $date at $time.';
  }

  @override
  Widget build(BuildContext context) {
    final iconSize = PageToolbarActionLayout.of(context).iconSize;
    final statusIcon = _statusIcon;

    return Tooltip(
      message: 'Listening history status',
      child: ObsidianHudIconButton(icon: statusIcon, size: iconSize, onPressed: () => _showStatus(context)),
    );
  }
}
