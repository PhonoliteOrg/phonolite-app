import 'package:flutter/material.dart';

import '../entities/app_log.dart';
import '../entities/app_controller.dart';
import '../entities/auth_state.dart';
import '../entities/custom_shuffle_settings.dart';
import '../entities/offline_storage_settings.dart';
import '../widgets/inputs/obsidian_text_field.dart';
import '../widgets/layout/library_header.dart';
import '../widgets/layouts/app_scope.dart';
import '../widgets/modals/confirmation_modal.dart';
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
                        const ObsidianSectionHeader(title: 'Session'),
                        const SizedBox(height: 12),
                        _settingsRow(
                          context,
                          leading: Icon(
                            authState.isAuthorized
                                ? Icons.cloud_done_rounded
                                : authState.hasSession
                                ? Icons.cloud_sync_rounded
                                : Icons.cloud_off_rounded,
                          ),
                          title: 'Server',
                          subtitle: serverLabel,
                          trailing: _serverActions(
                            context,
                            controller: controller,
                            authState: authState,
                          ),
                        ),
                        const SizedBox(height: 24),
                        const ObsidianSectionHeader(title: 'Playback'),
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
                            final summary = authState.isAuthorized
                                ? 'Artists: $artistCount, Genres: $genreCount'
                                : authState.hasSession
                                ? 'Server unavailable; reconnect to edit filters'
                                : 'Connect to edit server shuffle filters';
                            return _settingsRow(
                              context,
                              leading: const Icon(Icons.shuffle_rounded),
                              title: 'Custom Shuffle',
                              subtitle: summary,
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () => Navigator.of(
                                context,
                              ).push(CustomShuffleSettingsPage.route()),
                            );
                          },
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
                              leading: const Icon(Icons.receipt_long_rounded),
                              title: 'Logs',
                              subtitle: logLabel,
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () =>
                                  Navigator.of(context).push(LogsPage.route()),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
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
        ? Icons.hourglass_top_rounded
        : authState.hasSession
        ? Icons.swap_horiz_rounded
        : Icons.login_rounded;

    if (isCompactListWidth(context)) {
      if (authState.hasSession) {
        return ObsidianOverflowActionButton(
          tooltip: 'Server actions',
          actions: [
            if (canRetry)
              ObsidianMenuAction(
                label: retryLabel,
                icon: Icons.sync_rounded,
                onTap: retryAction,
              ),
            ObsidianMenuAction(
              label: 'Change server',
              icon: Icons.swap_horiz_rounded,
              onTap: loginAction,
            ),
            ObsidianMenuAction(
              label: 'Disconnect',
              icon: Icons.logout_rounded,
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
            icon: Icons.sync_rounded,
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
            icon: Icons.logout_rounded,
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
          leading: const Icon(Icons.storage_rounded),
          title: 'Metadata database',
          subtitle: _subtitle(
            locations,
            metadata: true,
            managed: usesManagedPaths,
          ),
          trailing: usesManagedPaths
              ? const Icon(Icons.lock_outline_rounded)
              : _StorageActions(
                  onChange: onChangeMetadata,
                  onReset: onResetMetadata,
                ),
        ),
        const Divider(height: 1),
        _sectionRow(
          context,
          leading: const Icon(Icons.folder_rounded),
          title: 'Downloaded audio',
          subtitle: _subtitle(
            locations,
            metadata: false,
            managed: usesManagedPaths,
          ),
          trailing: usesManagedPaths
              ? const Icon(Icons.lock_outline_rounded)
              : _StorageActions(
                  onChange: onChangeDownloads,
                  onReset: onResetDownloads,
                ),
        ),
        const Divider(height: 1),
        _sectionRow(
          context,
          leading: Icon(
            Icons.delete_forever_rounded,
            color: theme.colorScheme.error,
          ),
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
        icon: Icons.delete_forever_rounded,
        variant: TechButtonVariant.danger,
        onPressed: onTap,
      );
    }

    return TechButton(
      label: 'Full reset',
      icon: Icons.delete_forever_rounded,
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
            icon: Icons.edit_rounded,
            onTap: onChange,
          ),
          ObsidianMenuAction(
            label: 'Reset',
            icon: Icons.restore_rounded,
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
          icon: Icons.edit_rounded,
          density: TechButtonDensity.compact,
          chrome: TechButtonChrome.borderless,
          onTap: onChange,
        ),
        TechButton(
          label: 'Reset',
          icon: Icons.restore_rounded,
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
  Widget build(BuildContext context) {
    return AlertDialog(
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
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving' : 'Save'),
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
