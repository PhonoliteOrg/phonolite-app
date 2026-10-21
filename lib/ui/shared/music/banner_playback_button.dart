import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_hud_icon_button.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';

class BannerPlaybackButton extends StatelessWidget {
  final String message;
  final VoidCallback? onPressed;
  final bool visible;

  const BannerPlaybackButton({super.key, required this.message, this.visible = true, this.onPressed});

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
            child: ObsidianHudIconButton(icon: PhonoliteIcons.play, size: 28, onPressed: onPressed),
          ),
        ),
      ),
    );
  }
}
