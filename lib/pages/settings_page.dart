import 'package:flutter/material.dart';

import '../entities/app_log.dart';
import '../entities/custom_shuffle_settings.dart';
import '../widgets/layouts/app_scope.dart';
import '../widgets/ui/obsidian_theme.dart';
import '../widgets/ui/hover_row.dart';
import '../widgets/ui/obsidian_widgets.dart';
import 'custom_shuffle_settings_page.dart';
import 'logs_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return StreamBuilder<List<LogEntry>>(
      stream: controller.messageStream,
      initialData: controller.messages,
      builder: (context, snapshot) {
        final messages = snapshot.data ?? [];
        final theme = Theme.of(context);
        final serverLabel = controller.authState.baseUrl.trim().isEmpty
            ? 'Not connected'
            : controller.authState.baseUrl;
        final logLabel =
            messages.isEmpty ? 'No events yet' : '${messages.length} log entries';
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const ObsidianSectionHeader(
              title: 'Settings',
              subtitle: 'Preferences, diagnostics, and session controls',
            ),
            const SizedBox(height: 20),
            Text(
              'Session',
              style: theme.textTheme.titleSmall?.copyWith(
                color: ObsidianPalette.textMuted,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 12),
            _SettingsRow(
              context,
              leading: const Icon(Icons.cloud_rounded),
              title: 'Server',
              subtitle: serverLabel,
            ),
            const SizedBox(height: 20),
            Text(
              'Playback',
              style: theme.textTheme.titleSmall?.copyWith(
                color: ObsidianPalette.textMuted,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 12),
            StreamBuilder<CustomShuffleSettings>(
              stream: controller.customShuffleSettingsStream,
              initialData: controller.customShuffleSettings,
              builder: (context, snapshot) {
                final settings = snapshot.data ?? controller.customShuffleSettings;
                final artistCount = settings.artistIds.length;
                final genreCount = settings.genres.length;
                final summary = 'Artists: $artistCount, Genres: $genreCount';
                return _SettingsRow(
                  context,
                  leading: const Icon(Icons.shuffle_rounded),
                  title: 'Custom Shuffle',
                  subtitle: summary,
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const CustomShuffleSettingsPage(),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            Text(
              'Actions',
              style: theme.textTheme.titleSmall?.copyWith(
                color: ObsidianPalette.textMuted,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 12),
            Column(
              children: [
                _SettingsRow(
                  context,
                  leading: const Icon(Icons.receipt_long_rounded),
                  title: 'Logs',
                  subtitle: logLabel,
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const LogsPage(),
                    ),
                  ),
                ),
                Divider(
                  height: 1,
                  color: ObsidianPalette.border.withOpacity(0.6),
                ),
                _SettingsRow(
                  context,
                  leading: Icon(
                    Icons.logout_rounded,
                    color: theme.colorScheme.error,
                  ),
                  title: 'Log out',
                  subtitle: 'Disconnect from this server',
                  titleColor: theme.colorScheme.error,
                  onTap: () async {
                    await controller.logout();
                  },
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _SettingsRow(
    BuildContext context, {
    required Widget leading,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    Color? titleColor,
  }) {
    final showHover = onTap != null;
    return ObsidianHoverRow(
      onTap: onTap,
      enabled: showHover,
      borderColor: showHover ? ObsidianPalette.gold : Colors.transparent,
      hoverGradient: showHover
          ? null
          : const LinearGradient(colors: [Colors.transparent, Colors.transparent]),
      hoverColor: showHover ? null : Colors.transparent,
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Center(child: leading),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        letterSpacing: 0.6,
                        color: titleColor,
                      ),
                ),
                if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: ObsidianPalette.textMuted,
                        ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing,
          ],
        ],
      ),
    );
  }
}
