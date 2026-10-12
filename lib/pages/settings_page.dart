import 'package:flutter/material.dart';

import '../widgets/ui/phonolite_icons.dart';
import '../widgets/ui/edit_icon.dart';
import '../widgets/ui/reload_icon.dart';
import '../widgets/ui/server_icon.dart';
import '../widgets/ui/stats_icon.dart';

import '../entities/app_log.dart';
import '../entities/app_controller.dart';
import '../entities/auth_state.dart';
import '../entities/custom_shuffle_settings.dart';
import '../entities/offline_storage_settings.dart';
import '../entities/server_connection.dart';
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
            final serverLabel = _serverLabel(authState);
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
                          subtitle: serverLabel,
                          trailing: _serverActions(
                            context,
                            controller: controller,
                            authState: authState,
                          ),
                        ),
                        const SizedBox(height: 12),
                        StreamBuilder<CustomShuffleSettings>(
                          stream: controller.customShuffleSettingsStream,
                          initialData: controller.customShuffleSettings,
                          builder: (context, snapshot) {
                            final settings =
                                snapshot.data ??
                                controller.customShuffleSettings;
                            final artistCount = settings.artistIds.length;
                            final genreCount = settings.genres.length;
                            final localArtistCount =
                                settings.localArtistIds.length;
                            final localGenreCount = settings.localGenres.length;
                            final serverSummary = authState.isAuthorized
                                ? '$artistCount artists, $genreCount genres'
                                : authState.hasSession
                                ? 'unavailable'
                                : 'not connected';
                            final summary =
                                'Server: $serverSummary - Local: $localArtistCount artists, $localGenreCount genres';
                            return _settingsRow(
                              context,
                              leading: const Icon(PhonoliteIcons.shuffle),
                              title: 'Custom Shuffle',
                              subtitle: summary,
                              trailing: const Icon(PhonoliteIcons.chevronRight),
                              onTap: () => Navigator.of(
                                context,
                              ).push(CustomShuffleSettingsPage.route()),
                            );
                          },
                        ),
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
                                onResetLocalHistory:
                                    controller.resetLocalListeningHistory,
                                onResetAccountHistory: authState.isAuthorized
                                    ? () async {
                                        if (!controller
                                                .authState
                                                .isAuthorized ||
                                            controller
                                                    .connection
                                                    .sessionRevision !=
                                                sessionRevision) {
                                          throw StateError(
                                            'The signed-in account changed.',
                                          );
                                        }
                                        await controller
                                            .resetAccountListeningHistory();
                                      }
                                    : null,
                              ),
                        ),
                        const SizedBox(height: 24),
                        const ObsidianSectionHeader(title: 'Offline Storage'),
                        const SizedBox(height: 12),
                        StreamBuilder<OfflineStorageLocations>(
                          stream: controller.offlineStorageLocationsStream,
                          initialData: controller.offlineStorageLocations,
                          builder: (context, snapshot) {
                            final locations =
                                snapshot.data ??
                                controller.offlineStorageLocations;
                            return OfflineStorageSection(
                              locations: locations,
                              onChangeMetadata: locations == null
                                  ? null
                                  : () => _openStoragePathDialog(
                                      context,
                                      title: 'Metadata database folder',
                                      initialPath: locations.metadataDirectory,
                                      isDefault:
                                          locations.metadataDirectoryIsDefault,
                                      onSave: controller
                                          .updateOfflineMetadataDirectory,
                                    ),
                              onResetMetadata: locations == null
                                  ? null
                                  : () => controller
                                        .resetOfflineMetadataDirectory(),
                              onChangeDownloads: locations == null
                                  ? null
                                  : () => _openStoragePathDialog(
                                      context,
                                      title: 'Downloaded audio folder',
                                      initialPath: locations.downloadsDirectory,
                                      isDefault:
                                          locations.downloadsDirectoryIsDefault,
                                      onSave: controller
                                          .updateOfflineDownloadsDirectory,
                                    ),
                              onResetDownloads: locations == null
                                  ? null
                                  : () => controller
                                        .resetOfflineDownloadsDirectory(),
                              onResetOfflineData: locations == null
                                  ? null
                                  : () => _confirmResetOfflineData(
                                      context,
                                      controller,
                                    ),
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

  String _serverLabel(AuthState state) {
    final baseUrl = state.baseUrl.trim().isEmpty
        ? 'No server set'
        : state.baseUrl;
    final prefix = switch (state.status) {
      SessionStatus.authenticated => 'Connected',
      SessionStatus.serverUnavailable =>
        state.isReconnecting ? 'Reconnecting...' : 'Server unavailable',
      SessionStatus.serverReachable => 'Server reachable',
      SessionStatus.checking => 'Checking saved server',
      SessionStatus.offline => 'Offline',
    };
    final error = state.error?.trim();
    if (error != null && error.isNotEmpty) {
      return '$prefix - $baseUrl - $error';
    }
    return '$prefix - $baseUrl';
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

  Future<void> _confirmResetOfflineData(
    BuildContext context,
    AppController controller,
  ) async {
    final usesManagedPaths = _usesManagedOfflineStoragePaths(context);
    final confirmed = await ConfirmationModal.show(
      context,
      title: 'Reset offline data',
      message: usesManagedPaths
          ? 'Delete all locally downloaded tracks, artwork, offline metadata, and offline database files from this device? Offline storage will remain managed automatically on this device.'
          : 'Delete all locally downloaded tracks, artwork, offline metadata, and offline database files from this device? Storage folder choices will be kept.',
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
    this.onResetLocalHistory,
    this.onResetAccountHistory,
  });

  final bool enabled;
  final Future<void> Function(bool) onChanged;
  final Future<void> Function()? onResetLocalHistory;
  final Future<void> Function()? onResetAccountHistory;

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
        if (widget.onResetLocalHistory != null) ...[
          const SizedBox(height: 12),
          _resetTile(context, account: false),
        ],
        if (widget.onResetAccountHistory != null) ...[
          const SizedBox(height: 12),
          _resetTile(context, account: true),
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
                      ? 'Save listening on this device and sync with your account when the server allows it.'
                      : 'New listening and uploads are stopped on this device. Existing history is kept.',
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

  Widget _resetTile(BuildContext context, {required bool account}) {
    final compact = isCompactListWidth(context);
    final theme = Theme.of(context);
    final enabled = !_saving && !_resetting;
    final color = enabled ? theme.colorScheme.error : ObsidianPalette.textMuted;
    return Semantics(
      button: true,
      enabled: enabled,
      child: ObsidianHoverRow(
        key: ValueKey(
          account ? 'reset-account-history' : 'reset-device-only-history',
        ),
        enabled: enabled,
        onTap: () => _resetHistory(account),
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
                child: account
                    ? StatsIcon.accountReset(size: compact ? 20 : 24)
                    : StatsIcon.deviceReset(size: compact ? 20 : 24),
              ),
            ),
            SizedBox(width: compact ? 8 : 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account
                        ? 'Reset account history'
                        : 'Reset device-only history',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: compact ? 14.5 : null,
                      letterSpacing: compact ? 0.2 : 0.6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    account
                        ? 'Delete this account\'s listening statistics from the server and this app. Device-only history is kept.'
                        : 'Delete listening statistics recorded while signed out on this device. Account history is kept.',
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

  Future<void> _resetHistory(bool account) async {
    if (_saving || _resetting) return;
    // Capture the action before confirmation so an account change cannot
    // substitute a different account's callback while the dialog is open.
    final reset = account
        ? widget.onResetAccountHistory
        : widget.onResetLocalHistory;
    if (reset == null) return;
    setState(() => _resetting = true);
    try {
      final confirmed = await ConfirmationModal.show(
        context,
        title: account
            ? 'Reset account listening history?'
            : 'Reset device-only listening history?',
        message: account
            ? 'Permanently delete all listening statistics for this account on the server and this app? Other devices will clear their copies and old pending uploads when they reconnect. Device-only history recorded while signed out is kept. This cannot be undone.'
            : 'Permanently delete listening history recorded while signed out on this device? Server account history and its synced copy are kept. This cannot be undone.',
        confirmLabel: 'Reset history',
      );
      if (!confirmed || !mounted) return;
      await reset();
    } catch (error) {
      final message =
          account &&
              error is ApiException &&
              (error.statusCode == 404 || error.statusCode == 405)
          ? 'This server needs an update to reset account history.'
          : account
          ? 'Could not confirm the account reset. Check your connection and statistics before trying again.'
          : 'Could not reset device-only history. Try again.';
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
  });

  final OfflineStorageLocations? locations;
  final VoidCallback? onChangeMetadata;
  final VoidCallback? onResetMetadata;
  final VoidCallback? onChangeDownloads;
  final VoidCallback? onResetDownloads;
  final VoidCallback? onResetOfflineData;

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
                ),
        ),
        const Divider(height: 1),
        _sectionRow(
          context,
          leading: Icon(PhonoliteIcons.trash, color: theme.colorScheme.error),
          title: 'Reset offline data',
          subtitle:
              'Delete local tracks, artwork, metadata, and offline databases',
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
  const _StorageActions({required this.onChange, required this.onReset});

  final VoidCallback? onChange;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
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
            label: 'Reset',
            icon: PhonoliteIcons.rotateCcw,
            onTap: onReset,
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
          label: 'Reset',
          icon: PhonoliteIcons.rotateCcw,
          density: TechButtonDensity.compact,
          chrome: TechButtonChrome.borderless,
          onTap: onReset,
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
