import 'package:flutter/material.dart';

import 'phonolite_icons.dart';

import 'obsidian_widgets.dart';
import 'svg_asset_icon.dart';

class LikeIconButton extends StatelessWidget {
  const LikeIconButton({
    super.key,
    required this.isLiked,
    this.onPressed,
    this.size = 26,
  });

  final bool isLiked;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ObsidianHudIconButton(
      icon: isLiked ? null : PhonoliteIcons.heart,
      iconWidget: isLiked
          ? const SvgAssetIcon(
              assetName: 'assets/icons/lucide/heart-filled.svg',
            )
          : null,
      isActive: isLiked,
      onPressed: onPressed,
      size: size,
    );
  }
}
