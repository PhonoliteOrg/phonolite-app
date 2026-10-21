import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/settings/settings_controller.dart';
import 'package:phonolite_app/data/models/auth/auth_state.dart';
import 'package:phonolite_app/data/models/diagnostics/log_entry.dart';
import 'package:phonolite_app/pages/auth/login_page.dart';
import 'package:phonolite_app/pages/auth/reset_user_password_page.dart';
import 'package:phonolite_app/pages/logs/logs_page.dart';
import 'package:phonolite_app/pages/playback/custom_shuffle_settings_page.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/features/settings/sections/general_settings_section.dart';
import 'package:phonolite_app/ui/features/settings/sections/local_storage_settings_section.dart';
import 'package:phonolite_app/ui/features/settings/sections/misc_settings_section.dart';
import 'package:phonolite_app/ui/features/settings/sections/user_settings_section.dart';
import 'package:phonolite_app/ui/shell/base_page.dart';
import 'package:phonolite_app/ui/shell/page_scroll_view.dart';
import 'package:phonolite_app/ui/shell/toolbars/library_header.dart';

export 'package:phonolite_app/ui/features/settings/widgets/listening_statistics_setting.dart'
    show ListeningStatisticsSetting;
export 'package:phonolite_app/ui/features/settings/widgets/offline_storage_section.dart' show OfflineStorageSection;

class SettingsPage extends BaseStatelessPage {
  const SettingsPage({super.key});

  Widget _settingsContent(
    BuildContext context,
    PageAssembler assemble,
    AppController controller, {
    required AsyncSnapshot<List<LogEntry>> snapshot,
    required AuthState authState,
    required int sessionRevision,
  }) {
    final messages = snapshot.data ?? [];
    final logLabel = messages.isEmpty ? 'No events yet' : '${messages.length} log entries';

    return assemble(
      context,
      navbar: const LibraryHeader(title: 'SETTINGS'),
      body: PageBody.slivers(
        slivers: [
          PageSliverBox(
            top: 8,
            bottom: 32,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GeneralSettingsSection(
                  controller: controller,
                  authState: authState,
                  onLogin: () => Navigator.of(context).push(LoginPage.route(controller)),
                  onCustomShuffle: () => Navigator.of(context).push(CustomShuffleSettingsPage.route()),
                ),
                const SizedBox(height: 24),
                UserSettingsSection(
                  controller: controller,
                  authState: authState,
                  sessionRevision: sessionRevision,
                  onResetPassword: () => Navigator.of(context).push(ResetUserPasswordPage.route(controller)),
                ),
                const SizedBox(height: 24),
                LocalStorageSettingsSection(controller: controller),
                const SizedBox(height: 24),
                FutureBuilder<String>(
                  future: SettingsController.instance.loadAppVersion(),
                  builder: (context, versionSnapshot) => MiscSettingsSection(
                    logLabel: logLabel,
                    appVersion: versionSnapshot.data ?? (versionSnapshot.hasError ? 'Unavailable' : 'Loading…'),
                    onOpenLogs: () => Navigator.of(context).push(LogsPage.route()),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget pageContent(BuildContext context, PageAssembler assemble) {
    final controller = AppScope.of(context);

    return StreamBuilder<AuthState>(
      stream: controller.authStream,
      initialData: controller.authState,
      builder: (context, authSnapshot) {
        final authState = authSnapshot.data ?? controller.authState;
        final sessionRevision = controller.catalog.sessionRevision;

        return StreamBuilder<List<LogEntry>>(
          stream: controller.messageStream,
          initialData: controller.messages,
          builder: (context, snapshot) => _settingsContent(
            context,
            assemble,
            controller,
            snapshot: snapshot,
            authState: authState,
            sessionRevision: sessionRevision,
          ),
        );
      },
    );
  }
}
