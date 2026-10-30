import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/ui/features/settings/widgets/settings_toggle.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/svg_asset_icon.dart';
import 'package:phonolite_app/ui/structures/sections/base_section.dart';

class PlaybackSettingsSection extends BaseSection {
  final AppController controller;

  const PlaybackSettingsSection({super.key, required this.controller});

  @override
  String get sectionTitle => 'Playback';

  @override
  List<Widget> sectionContent(BuildContext context) => [
    StreamBuilder<bool>(
      stream: controller.gaplessResamplingStream,
      initialData: controller.gaplessResampling,
      builder: (context, snapshot) {
        final enabled = snapshot.data ?? controller.gaplessResampling;
        return SettingsToggle(
          icon: const SvgAssetIcon(assetName: 'assets/icons/lucide/audio-lines.svg'),
          title: 'Seamless mixed-format playback',
          subtitle: enabled
              ? 'Keep one output format between tracks. Different sample rates are converted for a seamless transition.'
              : 'Preserve each track’s native format. Switching sample rates may briefly interrupt playback.',
          value: enabled,
          settingKey: 'gapless-resampling',
          onChanged: controller.setGaplessResampling,
        );
      },
    ),
  ];
}
