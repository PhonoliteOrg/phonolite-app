import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:phonolite_app/data/models/preferences/log_storage_location.dart';
import 'package:phonolite_app/data/models/preferences/offline_storage_locations.dart';
import 'package:phonolite_app/ui/features/settings/widgets/settings_row.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_overflow_action_button.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/tech_button.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/edit_icon.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/hover_row.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/responsive_breakpoints.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

class OfflineStorageSection extends StatelessWidget {
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

  const OfflineStorageSection({
    super.key,
    required this.locations,
    required this.onChangeMetadata,
    required this.onResetMetadata,
    required this.onChangeDownloads,
    required this.onResetDownloads,
    required this.onResetOfflineData,
    this.logsLocation,
    this.onOpenMetadata,
    this.onOpenDownloads,
    this.onChangeLogs,
    this.onResetLogs,
    this.onOpenLogs,
  });

  String settingsSubtitle(OfflineStorageLocations? locations, {required bool metadata}) {
    if (locations == null) {
      return 'Loading storage path';
    }

    final isDefault = metadata ? locations.metadataDirectoryIsDefault : locations.downloadsDirectoryIsDefault;
    final path = metadata ? locations.metadataDirectory : locations.downloadsDirectory;

    return settingsDirectorySubtitle(path, isDefault: isDefault);
  }

  String settingsDirectorySubtitle(String? path, {required bool isDefault}) {
    if (path == null) {
      return 'Loading storage path';
    }

    return isDefault ? 'Default - $path' : path;
  }

  Widget settingsResetAction(BuildContext context, {required VoidCallback? onTap}) {
    if (isCompactListWidth(context)) {
      return SettingsIconAction(
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

  Widget settingsSectionRow(
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
      hoverGradient: showHover ? null : const LinearGradient(colors: [Colors.transparent, Colors.transparent]),
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
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: titleStyle),
                if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: subtitleStyle),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            SizedBox(width: trailingGap),
            IconTheme.merge(
              data: IconThemeData(size: isCompact ? 22 : 24),
              child: SettingsTrailing(child: trailing),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hideStoragePaths = switch (theme.platform) {
      TargetPlatform.iOS || TargetPlatform.android => true,
      TargetPlatform.windows || TargetPlatform.macOS || TargetPlatform.linux || TargetPlatform.fuchsia => false,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!hideStoragePaths) ...[
          settingsSectionRow(
            context,
            leading: const Icon(PhonoliteIcons.database),
            title: 'Metadata database',
            subtitle: settingsSubtitle(locations, metadata: true),
            trailing: SettingsStorageActions(
              onChange: onChangeMetadata,
              onReset: onResetMetadata,
              onOpen: onOpenMetadata,
            ),
          ),
          const SettingsDivider(),
          settingsSectionRow(
            context,
            leading: const Icon(PhonoliteIcons.folder),
            title: 'Downloaded audio',
            subtitle: settingsSubtitle(locations, metadata: false),
            trailing: SettingsStorageActions(
              onChange: onChangeDownloads,
              onReset: onResetDownloads,
              onOpen: onOpenDownloads,
            ),
          ),
          const SettingsDivider(),
          settingsSectionRow(
            context,
            leading: const Icon(PhonoliteIcons.receiptText),
            title: 'Logs storage',
            subtitle: settingsDirectorySubtitle(logsLocation?.directory, isDefault: logsLocation?.isDefault ?? true),
            trailing: SettingsStorageActions(onChange: onChangeLogs, onReset: onResetLogs, onOpen: onOpenLogs),
          ),
          const SettingsDivider(),
        ],
        settingsSectionRow(
          context,
          leading: Icon(PhonoliteIcons.trash, color: theme.colorScheme.error),
          title: 'Reset local data',
          subtitle: 'Delete local tracks, artwork, metadata, local databases, and logs',
          titleColor: theme.colorScheme.error,
          trailing: settingsResetAction(context, onTap: onResetOfflineData),
        ),
      ],
    );
  }
}

class SettingsStorageActions extends StatelessWidget {
  final VoidCallback? onChange;
  final VoidCallback? onReset;
  final VoidCallback? onOpen;

  const SettingsStorageActions({super.key, required this.onChange, required this.onReset, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final showOpen =
        !kIsWeb &&
        switch (Theme.of(context).platform) {
          TargetPlatform.windows || TargetPlatform.macOS || TargetPlatform.linux => true,
          TargetPlatform.android || TargetPlatform.fuchsia || TargetPlatform.iOS => false,
        };

    if (isCompactListWidth(context)) {
      return ObsidianOverflowActionButton(
        tooltip: 'Storage actions',
        actions: [
          ObsidianMenuAction(label: 'Change', iconWidget: const EditIcon(), onTap: onChange),
          ObsidianMenuAction(label: 'Reset path', icon: PhonoliteIcons.rotateCcw, onTap: onReset),
          if (showOpen) ObsidianMenuAction(label: 'Open folder', icon: PhonoliteIcons.folder, onTap: onOpen),
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
