import 'package:flutter/material.dart';

import '../ui/obsidian_widgets.dart';
import '../ui/phonolite_icons.dart';

class BannerPlaybackButton extends StatelessWidget {
  const BannerPlaybackButton({
    super.key,
    required this.message,
    this.onPressed,
    this.visible = true,
  });

  final String message;
  final VoidCallback? onPressed;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    return Visibility(
      visible: visible,
      maintainState: true,
      maintainAnimation: true,
      maintainSize: true,
      child: Tooltip(
        message: message,
        child: SizedBox.square(
          dimension: 48,
          child: Semantics(
            button: true,
            enabled: onPressed != null,
            child: ObsidianHudIconButton(
              icon: PhonoliteIcons.play,
              size: 28,
              onPressed: onPressed,
            ),
          ),
        ),
      ),
    );
  }
}
