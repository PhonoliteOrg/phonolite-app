import 'package:flutter/material.dart';

import '../entities/app_log.dart';
import '../widgets/layouts/app_scope.dart';
import '../widgets/ui/obsidian_theme.dart';
import '../widgets/ui/obsidian_widgets.dart';
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
            GlassPanel(
              cut: 18,
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.cloud_rounded),
                title: const Text('Server'),
                subtitle: Text(serverLabel),
              ),
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
            GlassPanel(
              cut: 18,
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.receipt_long_rounded),
                    title: const Text('Logs'),
                    subtitle: Text(logLabel),
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
                  ListTile(
                    leading: Icon(
                      Icons.logout_rounded,
                      color: theme.colorScheme.error,
                    ),
                    title: Text(
                      'Log out',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    subtitle: const Text('Disconnect from this server'),
                    onTap: () async {
                      await controller.logout();
                    },
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
