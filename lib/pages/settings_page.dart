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
import '../widgets/ui/obsidian_widgets.dart';
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
            final theme = Theme.of(context);
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
                                : Icons.cloud_off_rounded,
                          ),
                          title: 'Server',
                          subtitle: serverLabel,
                          trailing: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              TechButton(
                                label: _loginActionLabel(authState.status),
                                icon: authState.isAuthorized
                                    ? Icons.swap_horiz_rounded
                                    : Icons.login_rounded,
                                density: TechButtonDensity.compact,
                                chrome: TechButtonChrome.borderless,
                                onTap:
                                    authState.status == SessionStatus.checking
                                    ? null
                                    : () => _openLogin(context, controller),
                              ),
                              if (authState.isAuthorized)
                                TechButton(
                                  label: 'Disconnect',
                                  icon: Icons.logout_rounded,
                                  variant: TechButtonVariant.danger,
                                  density: TechButtonDensity.compact,
                                  chrome: TechButtonChrome.borderless,
                                  onTap: () async => controller.logout(),
                                ),
                            ],
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
                                : 'Connect to edit server shuffle filters';
                            return _settingsRow(
                              context,
                              leading: const Icon(Icons.shuffle_rounded),
                              title: 'Custom Shuffle',
                              subtitle: summary,
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const CustomShuffleSettingsPage(),
                                ),
                              ),
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
                            return Column(
                              children: [
                                _settingsRow(
                                  context,
                                  leading: const Icon(Icons.storage_rounded),
                                  title: 'Metadata database',
                                  subtitle: _storageSubtitle(
                                    locations,
                                    metadata: true,
                                  ),
                                  trailing: _StorageActions(
                                    onChange: locations == null
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
                                    onReset: locations == null
                                        ? null
                                        : () => controller
                                              .resetOfflineMetadataDirectory(),
                                  ),
                                ),
                                const Divider(height: 1),
                                _settingsRow(
                                  context,
                                  leading: const Icon(Icons.folder_rounded),
                                  title: 'Downloaded audio',
                                  subtitle: _storageSubtitle(
                                    locations,
                                    metadata: false,
                                  ),
                                  trailing: _StorageActions(
                                    onChange: locations == null
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
                                    onReset: locations == null
                                        ? null
                                        : () => controller
                                              .resetOfflineDownloadsDirectory(),
                                  ),
                                ),
                                const Divider(height: 1),
                                _settingsRow(
                                  context,
                                  leading: Icon(
                                    Icons.delete_forever_rounded,
                                    color: theme.colorScheme.error,
                                  ),
                                  title: 'Reset offline data',
                                  subtitle:
                                      'Delete local tracks, artwork, metadata, and offline databases',
                                  titleColor: theme.colorScheme.error,
                                  trailing: TechButton(
                                    label: 'Full reset',
                                    icon: Icons.delete_forever_rounded,
                                    variant: TechButtonVariant.danger,
                                    density: TechButtonDensity.compact,
                                    chrome: TechButtonChrome.borderless,
                                    onTap: locations == null
                                        ? null
                                        : () => _confirmResetOfflineData(
                                            context,
                                            controller,
                                          ),
                                  ),
                                ),
                              ],
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
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const LogsPage(),
                                ),
                              ),
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
      SessionStatus.serverReachable => 'Log in',
      SessionStatus.checking => 'Checking',
      SessionStatus.offline => 'Connect / Log in',
    };
  }

  void _openLogin(BuildContext context, AppController controller) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LoginPage(controller: controller)),
    );
  }

  String _storageSubtitle(
    OfflineStorageLocations? locations, {
    required bool metadata,
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
    return isDefault ? 'Default - $path' : path;
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
    final confirmed = await ConfirmationModal.show(
      context,
      title: 'Reset offline data',
      message:
          'Delete all locally downloaded tracks, artwork, offline metadata, and offline database files from this device? Storage folder choices will be kept.',
      confirmLabel: 'Reset',
      confirmVariant: TechButtonVariant.danger,
    );
    if (!confirmed) {
      return;
    }
    await controller.resetOfflineData();
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
    return ObsidianHoverRow(
      onTap: onTap,
      enabled: showHover,
      borderColor: showHover ? ObsidianPalette.gold : Colors.transparent,
      hoverGradient: showHover
          ? null
          : const LinearGradient(
              colors: [Colors.transparent, Colors.transparent],
            ),
      hoverColor: showHover ? null : Colors.transparent,
      child: Row(
        children: [
          SizedBox(width: 32, child: Center(child: leading)),
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
          if (trailing != null) ...[const SizedBox(width: 8), trailing],
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
