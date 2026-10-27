import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_hud_icon_button.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/svg_asset_icon.dart';

/// The shared mute control beside each playback volume slider.
class PlaybackVolumeButton extends StatelessWidget {
  final bool muted;
  final VoidCallback onPressed;
  final double size;

  const PlaybackVolumeButton({super.key, required this.muted, required this.onPressed, this.size = 26});

  @override
  Widget build(BuildContext context) {
    final label = muted ? 'Unmute' : 'Mute';

    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        label: label,
        button: true,
        toggled: muted,
        onTap: onPressed,
        excludeSemantics: true,
        child: ObsidianHudIconButton(
          icon: muted ? null : PhonoliteIcons.volume2,
          iconWidget: muted ? const SvgAssetIcon(assetName: 'assets/icons/lucide/volume-x.svg') : null,
          size: size,
          onPressed: onPressed,
        ),
      ),
    );
  }
}
