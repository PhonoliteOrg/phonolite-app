import 'package:flutter/material.dart';

import 'phonolite_icons.dart';

import 'obsidian_widgets.dart';

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
      icon: PhonoliteIcons.heart,
      isActive: isLiked,
      onPressed: onPressed,
      size: size,
    );
  }
}
