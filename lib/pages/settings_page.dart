import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../widgets/ui/phonolite_icons.dart';
import '../widgets/ui/edit_icon.dart';
import '../widgets/ui/reload_icon.dart';
import '../widgets/ui/server_icon.dart';
import '../widgets/ui/stats_icon.dart';

import '../entities/app_log.dart';
import '../entities/app_controller.dart';
import '../entities/auth_state.dart';
import '../entities/log_storage_settings.dart';
import '../entities/offline_storage_settings.dart';
import '../entities/server_connection.dart';
import '../platform/desktop_directory_service.dart';
import '../widgets/inputs/obsidian_text_field.dart';
import '../widgets/layout/library_header.dart';
import '../widgets/layouts/app_scope.dart';
import '../widgets/layouts/playback_content_inset.dart';
import '../widgets/modals/confirmation_modal.dart';
import '../widgets/modals/modal_action_button.dart';
import '../widgets/modals/obsidian_dialog.dart';
import '../widgets/modals/obsidian_modal_scope.dart';
import '../widgets/ui/obsidian_theme.dart';
import '../widgets/ui/hover_row.dart';
import '../widgets/ui/obsidian_overflow_action_button.dart';
import '../widgets/ui/obsidian_widgets.dart';
import '../widgets/ui/responsive_breakpoints.dart';
import '../widgets/ui/tech_button.dart';
import 'custom_shuffle_settings_page.dart';
import 'login_page.dart';
import 'logs_page.dart';
import 'reset_user_password_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return StreamBuilder<AuthState>(
      stream: controller.authStream,
      initialData: controller.authState,
      builder: (context, authSnapshot) {
        final authState = authSnapshot.data ?? controller.authState;
        final sessionRevision = controller.connection.sessionRevision;
        return StreamBuilder<List<LogEntry>>(
          stream: controller.messageStream,
          initialData: controller.messages,
          builder: (context, snapshot) {
            final messages = snapshot.data ?? [];
            final logLabel = messages.isEmpty
                ? 'No events yet'
                : '${messages.length} log entries';
            return CustomScrollView(
              slivers: [
                const SliverPadding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
                  sliver: SliverToBoxAdapter(
                    child: LibraryHeader(title: 'SETTINGS', moduleCount: 0),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const ObsidianSectionHeader(title: 'General'),
                        const SizedBox(height: 12),
                        _settingsRow(
                          context,
                          leading: const ServerIcon(),
                          title: 'Server',
                          subtitle:
                              'Your server provides access to your music library.',
                          trailing: _serverActions(
                            context,
                            controller: controller,
                            authState: authState,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _settingsRow(
                          context,
                          leading: const Icon(PhonoliteIcons.shuffle),
                          title: 'Custom Shuffle',
                          subtitle:
                              'Custom shuffle plays music from your chosen artists and genres.',
                          trailing: const Icon(PhonoliteIcons.chevronRight),
                          onTap: () => Navigator.of(
                            context,
                          ).push(CustomShuffleSettingsPage.route()),
                        ),
                        const SizedBox(height: 24),
                        const ObsidianSectionHeader(title: 'User'),
                        const SizedBox(height: 12),
                        StreamBuilder<bool>(
                          stream: controller.statsCollectionEnabledStream,
                          initialData: controller.statsCollectionEnabled,
                          builder: (context, snapshot) =>
                              ListeningStatisticsSetting(
                                enabled:
                                    snapshot.data ??
                                    controller.statsCollectionEnabled,
                                onChanged: controller.setStatsCollectionEnabled,
                                serverConnected: authState.isAuthorized,
                                onReset: () async {
                                  if (controller.authState.isAuthorized !=
                                          authState.isAuthorized ||
                                      controller.connection.sessionRevision !=
                                          sessionRevision) {
                                    throw StateError(
                                      'The connection or signed-in account changed.',
                                    );
                                  }
                                  await controller.resetListeningStatistics();
                                },
                              ),
                        ),
                        if (authState.isAuthorized) ...[
                          const SizedBox(height: 12),
                          KeyedSubtree(
                            key: const ValueKey('reset-user-password'),
                            child: _settingsRow(
                              context,
                              leading: const Icon(PhonoliteIcons.lockKeyhole),
                              title: 'Reset user password',
                              subtitle:
                                  'Change the password for your signed-in account.',
                              trailing: const Icon(PhonoliteIcons.chevronRight),
                              onTap: () => Navigator.of(
                                context,
                              ).push(ResetUserPasswordPage.route(controller)),
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        const ObsidianSectionHeader(title: 'Local Storage'),
                        const SizedBox(height: 12),
                        StreamBuilder<OfflineStorageLocations>(
                          stream: controller.offlineStorageLocationsStream,
                          initialData: controller.offlineStorageLocations,
                          builder: (context, snapshot) {
                            final locations =
                                snapshot.data ??
                                controller.offlineStorageLocations;
                            final logger = AppLogger.instance;
                            return StreamBuilder<LogStorageLocation>(
                              stream: logger.storageLocationStream,
                              initialData: logger.storageLocation,
                              builder: (context, logSnapshot) {
                                final logsLocation =
                                    logSnapshot.data ?? logger.storageLocation;
                                return OfflineStorageSection(
                                  locations: locations,
                                  logsLocation: logsLocation,
                                  onChangeMetadata: locations == null
                                      ? null
                                      : () => _openStoragePathDialog(
                                          context,
                                          title: 'Metadata database folder',
                                          initialPath:
                                              locations.metadataDirectory,
                                          isDefault: locations
                                              .metadataDirectoryIsDefault,
                                          onSave: controller
                                              .updateOfflineMetadataDirectory,
                                        ),
                                  onResetMetadata: locations == null
                                      ? null
                                      : () => controller
                                            .resetOfflineMetadataDirectory(),
                                  onOpenMetadata: locations == null
                                      ? null
                                      : () => _openStorageDirectory(
                                          context,
                                          locations.metadataDirectory,
                                        ),
                                  onChangeDownloads: locations == null
                                      ? null
                                      : () => _openStoragePathDialog(
                                          context,
                                          title: 'Downloaded audio folder',
                                          initialPath:
                                              locations.downloadsDirectory,
                                          isDefault: locations
                                              .downloadsDirectoryIsDefault,
                                          onSave: controller
                                              .updateOfflineDownloadsDirectory,
                                        ),
                                  onResetDownloads: locations == null
                                      ? null
                                      : () => controller
                                            .resetOfflineDownloadsDirectory(),
                                  onOpenDownloads: locations == null
                                      ? null
                                      : () => _openStorageDirectory(
                                          context,
                                          locations.downloadsDirectory,
                                        ),
                                  onChangeLogs: logsLocation == null
                                      ? null
                                      : () => _openStoragePathDialog(
                                          context,
                                          title: 'Logs storage folder',
                                          initialPath: logsLocation.directory,
                                          isDefault: logsLocation.isDefault,
                                          onSave: logger.updateStorageDirectory,
                                        ),
                                  onResetLogs: logsLocation == null
                                      ? null
                                      : () => _resetLogsStorage(context),
                                  onOpenLogs: logsLocation == null
                                      ? null
                                      : () => _openStorageDirectory(
                                          context,
                                          logsLocation.directory,
                                        ),
                                  onResetOfflineData: locations == null
                                      ? null
                                      : () => _confirmResetOfflineData(
                                          context,
                                          controller,
                                        ),
                                );
                              },
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                        const ObsidianSectionHeader(title: 'Miscellaneous'),
                        const SizedBox(height: 12),
                        Column(
                          children: [
                            _settingsRow(
                              context,
                              leading: const Icon(PhonoliteIcons.receiptText),
                              title: 'Logs',
                              subtitle: logLabel,
                              trailing: const Icon(PhonoliteIcons.chevronRight),
                              onTap: () =>
                                  Navigator.of(context).push(LogsPage.route()),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SliverPlaybackInset(),
              ],
            );
          },
        );
      },
    );
  }

  String _loginActionLabel(SessionStatus status) {
    return switch (status) {
      SessionStatus.authenticated => 'Change server',
      SessionStatus.serverUnavailable => 'Change server',
      SessionStatus.serverReachable => 'Log in',
      SessionStatus.checking => 'Checking',
      SessionStatus.offline => 'Connect / Log in',
    };
  }

  void _openLogin(BuildContext context, AppController controller) {
    Navigator.of(context).push(LoginPage.route(controller));
  }

  bool _usesManagedOfflineStoragePaths(BuildContext context) {
    return Theme.of(context).platform == TargetPlatform.iOS;
  }

  void _openStoragePathDialog(
    BuildContext context, {
    required String title,
    required String initialPath,
    required bool isDefault,
    required Future<void> Function(String? path) onSave,
  }) {
    showDialog<void>(
      context: context,
      builder: (context) => _StoragePathDialog(
        title: title,
        initialPath: initialPath,
        isDefault: isDefault,
        onSave: onSave,
      ),
    );
  }

  Future<void> _openStorageDirectory(BuildContext context, String path) async {
    try {
      await const DesktopDirectoryService().openDirectory(path);
    } catch (error) {
      AppLogger.warning('Could not open storage folder: $error');
      if (!context.mounted) return;
      await _showStorageError(
        context,
        title: 'Could not open folder',
        message: 'Could not open this folder in your file manager:\n$path',
      );
    }
  }

  Future<void> _resetLogsStorage(BuildContext context) async {
    try {
      await AppLogger.instance.updateStorageDirectory(null);
    } catch (error) {
      AppLogger.warning('Could not reset logs storage: $error');
      if (!context.mounted) return;
      await _showStorageError(
        context,
        title: 'Could not reset logs storage',
        message:
            'Could not restore the default log folder. Your current logs have been kept.',
      );
    }
  }

  Future<void> _showStorageError(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => ObsidianAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          ModalActionButton(
            label: 'Close',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmResetOfflineData(
    BuildContext context,
    AppController controller,
  ) async {
    final usesManagedPaths = _usesManagedOfflineStoragePaths(context);
    final confirmed = await ConfirmationModal.show(
      context,
      title: 'Reset local data',
      message: usesManagedPaths
          ? 'Delete downloaded tracks, artwork, local metadata, local database files, and logs from this device? Local storage will remain managed automatically on this device.'
          : 'Delete downloaded tracks, artwork, local metadata, local database files, and logs from this device? Storage folder choices will be kept.',
      confirmLabel: 'Reset',
      confirmVariant: TechButtonVariant.danger,
    );
    if (!confirmed) {
      return;
    }
    await controller.resetOfflineData();
  }

  Widget _serverActions(
    BuildContext context, {
    required AppController controller,
    required AuthState authState,
  }) {
    final enabled = authState.status != SessionStatus.checking;
    final loginAction = enabled ? () => _openLogin(context, controller) : null;
    final canRetry = authState.status == SessionStatus.serverUnavailable;
    final retryAction = canRetry && !authState.isReconnecting
        ? () async => controller.retryServerConnection()
        : null;
    final retryLabel = authState.isReconnecting ? 'Reconnecting...' : 'Retry';
    final loginIcon = authState.status == SessionStatus.checking
        ? PhonoliteIcons.hourglass
        : authState.hasSession
        ? PhonoliteIcons.arrowLeftRight
        : PhonoliteIcons.logIn;

    if (isCompactListWidth(context)) {
      if (authState.hasSession) {
        return ObsidianOverflowActionButton(
          tooltip: 'Server actions',
          actions: [
            if (canRetry)
              ObsidianMenuAction(
                label: retryLabel,
                iconWidget: const ReloadIcon(),
                onTap: retryAction,
              ),
            ObsidianMenuAction(
              label: 'Change server',
              icon: PhonoliteIcons.arrowLeftRight,
              onTap: loginAction,
            ),
            ObsidianMenuAction(
              label: 'Disconnect',
              icon: PhonoliteIcons.logOut,
              variant: TechButtonVariant.danger,
              onTap: () async => controller.logout(),
            ),
          ],
        );
      }

      return _SettingsIconAction(
        tooltip: _loginActionLabel(authState.status),
        icon: loginIcon,
        onPressed: loginAction,
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (canRetry)
          TechButton(
            label: retryLabel,
            iconWidget: const ReloadIcon(),
            density: TechButtonDensity.compact,
            chrome: TechButtonChrome.borderless,
            onTap: retryAction,
          ),
        TechButton(
          label: _loginActionLabel(authState.status),
          icon: loginIcon,
          density: TechButtonDensity.compact,
          chrome: TechButtonChrome.borderless,
          onTap: loginAction,
        ),
        if (authState.hasSession)
          TechButton(
            label: 'Disconnect',
            icon: PhonoliteIcons.logOut,
            variant: TechButtonVariant.danger,
            density: TechButtonDensity.compact,
            chrome: TechButtonChrome.borderless,
            onTap: () async => controller.logout(),
          ),
      ],
    );
  }

  Widget _settingsRow(
    BuildContext context, {
    required Widget leading,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    Color? titleColor,
  }) {
    final showHover = onTap != null;
    final isCompact = isCompactListWidth(context);
    final leadingWidth = isCompact ? 28.0 : 32.0;
    final contentGap = isCompact ? 8.0 : 12.0;
    final trailingGap = isCompact ? 6.0 : 8.0;
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
      fontSize: isCompact ? 14.5 : null,
      letterSpacing: isCompact ? 0.2 : 0.6,
      color: titleColor,
    );
    final subtitleStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontSize: isCompact ? 12 : null,
      letterSpacing: isCompact ? 0 : null,
      color: ObsidianPalette.textMuted,
    );

    return ObsidianHoverRow(
      onTap: onTap,
      enabled: showHover,
      padding: isCompact
          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      borderColor: showHover ? ObsidianPalette.gold : Colors.transparent,
      hoverGradient: showHover
          ? null
          : const LinearGradient(
              colors: [Colors.transparent, Colors.transparent],
            ),
      hoverColor: showHover ? null : Colors.transparent,
      child: Row(
        children: [
          SizedBox(
            width: leadingWidth,
            child: Center(
              child: IconTheme.merge(
                data: IconThemeData(size: isCompact ? 20 : 24),
                child: leading,
              ),
            ),
          ),
          SizedBox(width: contentGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
                if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: subtitleStyle,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            SizedBox(width: trailingGap),
            IconTheme.merge(
              data: IconThemeData(size: isCompact ? 22 : 24),
              child: trailing,
            ),
          ],
        ],
      ),
    );
  }
}

class ListeningStatisticsSetting extends StatefulWidget {
  const ListeningStatisticsSetting({
    super.key,
    required this.enabled,
    required this.onChanged,
    required this.serverConnected,
    this.onReset,
  });

  final bool enabled;
  final Future<void> Function(bool) onChanged;
  final bool serverConnected;
  final Future<void> Function()? onReset;

  @override
  State<ListeningStatisticsSetting> createState() =>
      _ListeningStatisticsSettingState();
}

class _ListeningStatisticsSettingState
    extends State<ListeningStatisticsSetting> {
  bool _saving = false;
  bool _resetting = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _collectionTile(context),
        if (widget.enabled && widget.onReset != null) ...[
          const SizedBox(height: 12),
          _resetTile(context),
        ],
      ],
    );
  }

  Widget _collectionTile(BuildContext context) {
    final compact = isCompactListWidth(context);
    final theme = Theme.of(context);
    return ObsidianHoverRow(
      enabled: false,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 8 : 10,
      ),
      borderColor: Colors.transparent,
      hoverColor: Colors.transparent,
      hoverGradient: const LinearGradient(
        colors: [Colors.transparent, Colors.transparent],
      ),
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
          Semantics(
            label: 'Collect listening statistics',
            child: Switch.adaptive(
              key: const ValueKey('listening-statistics-switch'),
              value: widget.enabled,
              activeThumbColor: ObsidianPalette.gold,
              activeTrackColor: ObsidianPalette.gold.withValues(alpha: 0.3),
              hoverColor: Colors.transparent,
              onChanged: _saving || _resetting ? null : _change,
            ),
          ),
        ],
      ),
    );
  }

  Widget _resetTile(BuildContext context) {
    final compact = isCompactListWidth(context);
    final theme = Theme.of(context);
    final enabled = !_saving && !_resetting;
    final color = enabled ? theme.colorScheme.error : ObsidianPalette.textMuted;
    return Semantics(
      button: true,
      enabled: enabled,
      child: ObsidianHoverRow(
        key: const ValueKey('reset-listening-statistics'),
        enabled: enabled,
        onTap: _resetHistory,
        borderColor: ObsidianPalette.gold,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: compact ? 8 : 10,
        ),
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
            Icon(PhonoliteIcons.trash2, size: compact ? 22 : 24, color: color),
          ],
        ),
      ),
    );
  }

  Future<void> _change(bool enabled) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.onChanged(enabled);
    } catch (error) {
      AppLogger.warning('Could not save the statistics setting: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resetHistory() async {
    if (!widget.enabled || _saving || _resetting) return;
    // Capture the action before confirmation so an account change cannot
    // substitute a different account's callback while the dialog is open.
    final reset = widget.onReset;
    final serverConnected = widget.serverConnected;
    if (reset == null) return;
    setState(() => _resetting = true);
    try {
      final confirmed = await ConfirmationModal.show(
        context,
        title: 'Reset listening statistics?',
        message: serverConnected
            ? 'Permanently delete all listening statistics saved on this device and for your connected server account? Statistics saved on other devices must be cleared on each device. This cannot be undone.'
            : 'Permanently delete all listening statistics saved on this device? Server statistics and statistics saved on other devices are kept. This cannot be undone.',
        confirmLabel: 'Reset statistics',
      );
      if (!confirmed || !mounted || !widget.enabled) return;
      await reset();
    } catch (error) {
      final message =
          serverConnected &&
              error is ApiException &&
              (error.statusCode == 404 || error.statusCode == 405)
          ? 'This server needs an update to reset listening statistics.'
          : 'Could not reset listening statistics. Check your connection and try again.';
      AppLogger.warning('$message $error');
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }
}

class OfflineStorageSection extends StatelessWidget {
  const OfflineStorageSection({
    super.key,
    required this.locations,
    required this.onChangeMetadata,
    required this.onResetMetadata,
    required this.onChangeDownloads,
    required this.onResetDownloads,
    required this.onResetOfflineData,
    this.onOpenMetadata,
    this.onOpenDownloads,
    this.logsLocation,
    this.onChangeLogs,
    this.onResetLogs,
    this.onOpenLogs,
  });

  final OfflineStorageLocations? locations;
  final VoidCallback? onChangeMetadata;
  final VoidCallback? onResetMetadata;
  final VoidCallback? onChangeDownloads;
  final VoidCallback? onResetDownloads;
  final VoidCallback? onResetOfflineData;
  final VoidCallback? onOpenMetadata;
  final VoidCallback? onOpenDownloads;
  final LogStorageLocation? logsLocation;
  final VoidCallback? onChangeLogs;
  final VoidCallback? onResetLogs;
  final VoidCallback? onOpenLogs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final usesManagedPaths = Theme.of(context).platform == TargetPlatform.iOS;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (usesManagedPaths) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Text(
              'Folder selection and custom paths are not supported on iPhone or iPad.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: ObsidianPalette.textMuted,
              ),
            ),
          ),
          const Divider(height: 1),
        ],
        _sectionRow(
          context,
          leading: const Icon(PhonoliteIcons.database),
          title: 'Metadata database',
          subtitle: _subtitle(
            locations,
            metadata: true,
            managed: usesManagedPaths,
          ),
          trailing: usesManagedPaths
              ? const Icon(PhonoliteIcons.lockKeyhole)
              : _StorageActions(
                  onChange: onChangeMetadata,
                  onReset: onResetMetadata,
                  onOpen: onOpenMetadata,
                ),
        ),
        const Divider(height: 1),
        _sectionRow(
          context,
          leading: const Icon(PhonoliteIcons.folder),
          title: 'Downloaded audio',
          subtitle: _subtitle(
            locations,
            metadata: false,
            managed: usesManagedPaths,
          ),
          trailing: usesManagedPaths
              ? const Icon(PhonoliteIcons.lockKeyhole)
              : _StorageActions(
                  onChange: onChangeDownloads,
                  onReset: onResetDownloads,
                  onOpen: onOpenDownloads,
                ),
        ),
        const Divider(height: 1),
        _sectionRow(
          context,
          leading: const Icon(PhonoliteIcons.receiptText),
          title: 'Logs storage',
          subtitle: _directorySubtitle(
            logsLocation?.directory,
            isDefault: logsLocation?.isDefault ?? true,
            managed: usesManagedPaths,
          ),
          trailing: usesManagedPaths
              ? const Icon(PhonoliteIcons.lockKeyhole)
              : _StorageActions(
                  onChange: onChangeLogs,
                  onReset: onResetLogs,
                  onOpen: onOpenLogs,
                ),
        ),
        const Divider(height: 1),
        _sectionRow(
          context,
          leading: Icon(PhonoliteIcons.trash, color: theme.colorScheme.error),
          title: 'Reset local data',
          subtitle:
              'Delete local tracks, artwork, metadata, local databases, and logs',
          titleColor: theme.colorScheme.error,
          trailing: _resetAction(context, onTap: onResetOfflineData),
        ),
      ],
    );
  }

  String _subtitle(
    OfflineStorageLocations? locations, {
    required bool metadata,
    required bool managed,
  }) {
    if (locations == null) {
      return 'Loading storage path';
    }
    final isDefault = metadata
        ? locations.metadataDirectoryIsDefault
        : locations.downloadsDirectoryIsDefault;
    final path = metadata
        ? locations.metadataDirectory
        : locations.downloadsDirectory;
    return _directorySubtitle(path, isDefault: isDefault, managed: managed);
  }

  String _directorySubtitle(
    String? path, {
    required bool isDefault,
    required bool managed,
  }) {
    if (path == null) return 'Loading storage path';
    if (managed) {
      return 'Managed automatically on this device - $path';
    }
    return isDefault ? 'Default - $path' : path;
  }

  Widget _resetAction(BuildContext context, {required VoidCallback? onTap}) {
    if (isCompactListWidth(context)) {
      return _SettingsIconAction(
        tooltip: 'Full reset',
        icon: PhonoliteIcons.trash,
        variant: TechButtonVariant.danger,
        onPressed: onTap,
      );
    }

    return TechButton(
      label: 'Full reset',
      icon: PhonoliteIcons.trash,
      variant: TechButtonVariant.danger,
      density: TechButtonDensity.compact,
      chrome: TechButtonChrome.borderless,
      onTap: onTap,
    );
  }

  Widget _sectionRow(
    BuildContext context, {
    required Widget leading,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    Color? titleColor,
  }) {
    final showHover = onTap != null;
    final isCompact = isCompactListWidth(context);
    final leadingWidth = isCompact ? 28.0 : 32.0;
    final contentGap = isCompact ? 8.0 : 12.0;
    final trailingGap = isCompact ? 6.0 : 8.0;
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
      fontSize: isCompact ? 14.5 : null,
      letterSpacing: isCompact ? 0.2 : 0.6,
      color: titleColor,
    );
    final subtitleStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontSize: isCompact ? 12 : null,
      letterSpacing: isCompact ? 0 : null,
      color: ObsidianPalette.textMuted,
    );

    return ObsidianHoverRow(
      onTap: onTap,
      enabled: showHover,
      padding: isCompact
          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      borderColor: showHover ? ObsidianPalette.gold : Colors.transparent,
      hoverGradient: showHover
          ? null
          : const LinearGradient(
              colors: [Colors.transparent, Colors.transparent],
            ),
      hoverColor: showHover ? null : Colors.transparent,
      child: Row(
        children: [
          SizedBox(
            width: leadingWidth,
            child: Center(
              child: IconTheme.merge(
                data: IconThemeData(size: isCompact ? 20 : 24),
                child: leading,
              ),
            ),
          ),
          SizedBox(width: contentGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
                if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: subtitleStyle,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            SizedBox(width: trailingGap),
            IconTheme.merge(
              data: IconThemeData(size: isCompact ? 22 : 24),
              child: trailing,
            ),
          ],
        ],
      ),
    );
  }
}

class _StorageActions extends StatelessWidget {
  const _StorageActions({
    required this.onChange,
    required this.onReset,
    required this.onOpen,
  });

  final VoidCallback? onChange;
  final VoidCallback? onReset;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final showOpen =
        !kIsWeb &&
        switch (Theme.of(context).platform) {
          TargetPlatform.windows ||
          TargetPlatform.macOS ||
          TargetPlatform.linux => true,
          _ => false,
        };
    if (isCompactListWidth(context)) {
      return ObsidianOverflowActionButton(
        tooltip: 'Storage actions',
        actions: [
          ObsidianMenuAction(
            label: 'Change',
            iconWidget: const EditIcon(),
            onTap: onChange,
          ),
          ObsidianMenuAction(
            label: 'Reset path',
            icon: PhonoliteIcons.rotateCcw,
            onTap: onReset,
          ),
          if (showOpen)
            ObsidianMenuAction(
              label: 'Open folder',
              icon: PhonoliteIcons.folder,
              onTap: onOpen,
            ),
        ],
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        TechButton(
          label: 'Change',
          iconWidget: const EditIcon(),
          density: TechButtonDensity.compact,
          chrome: TechButtonChrome.borderless,
          onTap: onChange,
        ),
        TechButton(
          label: 'Reset path',
          icon: PhonoliteIcons.rotateCcw,
          density: TechButtonDensity.compact,
          chrome: TechButtonChrome.borderless,
          onTap: onReset,
        ),
        if (showOpen)
          TechButton(
            label: 'Open folder',
            icon: PhonoliteIcons.folder,
            density: TechButtonDensity.compact,
            chrome: TechButtonChrome.borderless,
            onTap: onOpen,
          ),
      ],
    );
  }
}

class _SettingsIconAction extends StatelessWidget {
  const _SettingsIconAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.variant = TechButtonVariant.standard,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final TechButtonVariant variant;

  @override
  Widget build(BuildContext context) {
    if (variant != TechButtonVariant.danger) {
      return Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          enabled: onPressed != null,
          label: tooltip,
          child: ObsidianHudIconButton(
            icon: icon,
            size: 22,
            onPressed: onPressed,
          ),
        ),
      );
    }

    final enabled = onPressed != null;
    final color = enabled
        ? Theme.of(context).colorScheme.error
        : ObsidianPalette.textMuted.withValues(alpha: 0.55);

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        child: GestureDetector(
          onTap: onPressed,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 22, color: color),
          ),
        ),
      ),
    );
  }
}

class _StoragePathDialog extends StatefulWidget {
  const _StoragePathDialog({
    required this.title,
    required this.initialPath,
    required this.isDefault,
    required this.onSave,
  });

  final String title;
  final String initialPath;
  final bool isDefault;
  final Future<void> Function(String? path) onSave;

  @override
  State<_StoragePathDialog> createState() => _StoragePathDialogState();
}

class _StoragePathDialogState extends State<_StoragePathDialog> {
  late final TextEditingController _controller;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.isDefault ? '' : widget.initialPath,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ObsidianModalScope(builder: _buildDialog);

  Widget _buildDialog(BuildContext context) {
    return ObsidianAlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ObsidianTextField(
              controller: _controller,
              label: 'Folder path',
              hintText: widget.initialPath,
              height: ObsidianModalScope.usesTouchTargets(context) ? 56 : 48,
              startPadding: 24,
              cut: 0,
              isDense: true,
              enabled: !_saving,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        ModalActionButton(
          label: 'Close',
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
        ModalActionButton(
          label: _saving ? 'Saving' : 'Save',
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final path = _controller.text.trim();
      await widget.onSave(path.isEmpty ? null : path);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (err) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = err.toString();
      });
    }
  }
}
