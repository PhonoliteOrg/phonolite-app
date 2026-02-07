import 'package:flutter/material.dart';

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
      icon: isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      isActive: isLiked,
      onPressed: onPressed,
      size: size,
    );
  }
}
