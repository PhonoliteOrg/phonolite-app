import 'package:flutter/material.dart';

import 'package:phonolite_app/application/controllers/settings/display_settings_controller.dart';
import 'package:phonolite_app/ui/features/settings/widgets/settings_row.dart';
import 'package:phonolite_app/ui/features/settings/widgets/settings_toggle.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/playlist_icon.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/svg_asset_icon.dart';
import 'package:phonolite_app/ui/structures/sections/base_section.dart';

class DisplaySettingsSection extends BaseSection {
  final DisplaySettingsController controller;

  const DisplaySettingsSection({super.key, required this.controller});

  @override
  String get sectionTitle => 'Display';

  SettingsToggle _sourceOrderToggle({
    required Widget icon,
    required String page,
    required bool localFirst,
    required String settingKey,
    required ValueChanged<bool> onChanged,
  }) => SettingsToggle(
    icon: icon,
    title: localFirst ? '$page: local first' : '$page: server first',
    subtitle: localFirst ? 'Local lists appear before server lists.' : 'Server lists appear before local lists.',
    value: localFirst,
    settingKey: settingKey,
    onChanged: controller.ready ? onChanged : null,
  );

  @override
  List<Widget> sectionContent(BuildContext context) => [
    _sourceOrderToggle(
      icon: const SvgAssetIcon(assetName: 'assets/icons/lucide/library-big.svg'),
      page: 'Library',
      localFirst: controller.settings.libraryLocalFirst,
      settingKey: 'display-library-local-first',
      onChanged: controller.setLibraryLocalFirst,
    ),
    const SettingsDivider(),
    _sourceOrderToggle(
      icon: const PlaylistIcon(),
      page: 'Playlists',
      localFirst: controller.settings.playlistsLocalFirst,
      settingKey: 'display-playlists-local-first',
      onChanged: controller.setPlaylistsLocalFirst,
    ),
    const SettingsDivider(),
    _sourceOrderToggle(
      icon: const Icon(PhonoliteIcons.heart),
      page: 'Likes',
      localFirst: controller.settings.likesLocalFirst,
      settingKey: 'display-likes-local-first',
      onChanged: controller.setLikesLocalFirst,
    ),
    if (controller.error case final error?)
      Padding(
        padding: const EdgeInsets.all(12),
        child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ),
  ];
}
