import 'package:flutter/material.dart';

import 'package:phonolite_app/application/controllers/settings/settings_controller.dart';
import 'package:phonolite_app/ui/controller_binding.dart';
import 'package:phonolite_app/ui/features/settings/widgets/settings_row.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_switch.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/stats_icon.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/hover_row.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/responsive_breakpoints.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/confirmation_modal.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

class ListeningStatisticsSetting extends StatefulWidget {
  final bool enabled;
  final Future<void> Function(bool) onChanged;
  final bool serverConnected;
  final Future<void> Function()? onReset;

  const ListeningStatisticsSetting({
    super.key,
    required this.enabled,
    required this.onChanged,
    required this.serverConnected,
    this.onReset,
  });

  @override
  State<ListeningStatisticsSetting> createState() => SettingsListeningStatisticsSettingState();
}

class SettingsListeningStatisticsSettingState extends State<ListeningStatisticsSetting>
    with ControllerBinding<ListeningStatisticsSetting> {
  late final ListeningStatisticsController _feature = bindController(ListeningStatisticsController());

  Widget settingsCollectionTile(BuildContext context) {
    final compact = isCompactListWidth(context);
    final theme = Theme.of(context);

    return ObsidianHoverRow(
      enabled: false,
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12, vertical: compact ? 8 : 10),
      borderColor: Colors.transparent,
      hoverColor: Colors.transparent,
      hoverGradient: const LinearGradient(colors: [Colors.transparent, Colors.transparent]),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: compact ? 28 : 32,
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: StatsIcon(size: compact ? 20 : 24),
            ),
          ),
          SizedBox(width: compact ? 8 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Listening statistics',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: compact ? 14.5 : null,
                    letterSpacing: compact ? 0.2 : 0.6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.enabled
                      ? 'Save listening statistics on this device and sync with your account when the server allows it.'
                      : 'New listening statistics and uploads are stopped on this device. Existing statistics are kept.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: compact ? 12 : null,
                    color: ObsidianPalette.textMuted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'This setting applies only to this app on this device.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: compact ? 12 : null,
                    color: ObsidianPalette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          SettingsTrailing(
            child: ObsidianSwitch(
              key: const ValueKey('listening-statistics-switch'),
              value: widget.enabled,
              semanticLabel: 'Collect listening statistics',
              onChanged: _feature.resetting ? null : settingsChange,
            ),
          ),
        ],
      ),
    );
  }

  Widget settingsResetTile(BuildContext context) {
    final compact = isCompactListWidth(context);
    final theme = Theme.of(context);
    final enabled = !_feature.saving && !_feature.resetting;
    final color = enabled ? theme.colorScheme.error : ObsidianPalette.textMuted;

    return Semantics(
      button: true,
      enabled: enabled,
      child: ObsidianHoverRow(
        key: const ValueKey('reset-listening-statistics'),
        enabled: enabled,
        onTap: settingsResetHistory,
        borderColor: ObsidianPalette.gold,
        padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12, vertical: compact ? 8 : 10),
        child: Row(
          children: [
            SizedBox(
              width: compact ? 28 : 32,
              child: IconTheme.merge(
                data: const IconThemeData(color: ObsidianPalette.textMuted),
                child: StatsIcon.deviceReset(size: compact ? 20 : 24),
              ),
            ),
            SizedBox(width: compact ? 8 : 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reset listening statistics',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: compact ? 14.5 : null,
                      letterSpacing: compact ? 0.2 : 0.6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.serverConnected
                        ? 'Delete listening statistics from this device and your connected server account.'
                        : 'Delete listening statistics saved on this device.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: compact ? 12 : null,
                      color: ObsidianPalette.textMuted,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: compact ? 6 : 8),
            SettingsTrailing(
              child: Icon(PhonoliteIcons.trash2, size: compact ? 22 : 24, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> settingsChange(bool enabled) => _feature.change(enabled, widget.onChanged);

  Future<void> settingsResetHistory() async {
    if (!widget.enabled || _feature.saving || _feature.resetting) {
      return;
    }

    // Capture the action before confirmation so an account change cannot
    // substitute a different account's callback while the dialog is open.
    final reset = widget.onReset;
    final serverConnected = widget.serverConnected;

    if (reset == null) {
      return;
    }

    _feature.beginReset();

    try {
      final confirmed = await ConfirmationModal.show(
        context,
        title: 'Reset listening statistics?',
        message: serverConnected
            ? 'Permanently delete all listening statistics saved on this device and for your connected server account? Statistics saved on other devices must be cleared on each device. This cannot be undone.'
            : 'Permanently delete all listening statistics saved on this device? Server statistics and statistics saved on other devices are kept. This cannot be undone.',
        confirmLabel: 'Reset statistics',
      );

      if (!confirmed || !mounted || !widget.enabled) {
        return;
      }

      await _feature.reset(reset, serverConnected: serverConnected);
    } finally {
      _feature.endReset();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        settingsCollectionTile(context),
        if (widget.enabled && widget.onReset != null) ...[const SettingsDivider(), settingsResetTile(context)],
      ],
    );
  }
}
