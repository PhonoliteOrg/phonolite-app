import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_hud_icon_button.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/tech_button_variant.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/obsidian_tap_target.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_palette.dart';

class SettingsIconAction extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final TechButtonVariant variant;

  const SettingsIconAction({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.variant = TechButtonVariant.standard,
  });

  @override
  Widget build(BuildContext context) {
    if (variant != TechButtonVariant.danger) {
      return Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: ObsidianHudIconButton(semanticLabel: tooltip, icon: icon, size: 22, onPressed: onPressed),
      );
    }

    final enabled = onPressed != null;
    final color = enabled ? Theme.of(context).colorScheme.error : ObsidianPalette.textMuted.withValues(alpha: 0.55);

    return Tooltip(
      message: tooltip,
      child: ObsidianTapTarget(
        onTap: onPressed,
        semanticLabel: tooltip,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 22, color: color),
        ),
      ),
    );
  }
}
