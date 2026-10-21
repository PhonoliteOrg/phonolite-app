import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_hud_icon_button.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/svg_asset_icon.dart';

class LikeIconButton extends StatelessWidget {
  final bool isLiked;
  final VoidCallback? onPressed;
  final double size;

  const LikeIconButton({super.key, required this.isLiked, this.size = 26, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ObsidianHudIconButton(
      icon: isLiked ? null : PhonoliteIcons.heart,
      iconWidget: isLiked ? const SvgAssetIcon(assetName: 'assets/icons/lucide/heart-filled.svg') : null,
      isActive: isLiked,
      onPressed: onPressed,
      size: size,
    );
  }
}
