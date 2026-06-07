import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'obsidian_theme.dart';
import 'obsidian_widgets.dart';
import 'tech_button.dart';

class ObsidianMenuAction {
  const ObsidianMenuAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.variant = TechButtonVariant.standard,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final TechButtonVariant variant;
}

class ObsidianOverflowActionButton extends StatelessWidget {
  const ObsidianOverflowActionButton({
    super.key,
    required this.actions,
    required this.tooltip,
    this.icon = Icons.more_vert_rounded,
    this.size = 22,
  });

  final List<ObsidianMenuAction> actions;
  final String tooltip;
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final enabled = actions.any((action) => action.onTap != null);
    if (!enabled) {
      return Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          enabled: false,
          label: tooltip,
          child: ObsidianHudIconButton(icon: icon, size: size),
        ),
      );
    }

    return Semantics(
      button: true,
      label: tooltip,
      child: PopupMenuButton<int>(
        tooltip: tooltip,
        color: ObsidianPalette.obsidianElevated,
        elevation: 8,
        popUpAnimationStyle: AnimationStyle.noAnimation,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: ObsidianPalette.border),
          borderRadius: BorderRadius.circular(4),
        ),
        position: PopupMenuPosition.under,
        onSelected: (index) => actions[index].onTap?.call(),
        itemBuilder: (context) => [
          for (final entry in actions.indexed)
            _menuItem(index: entry.$1, action: entry.$2),
        ],
        icon: Icon(icon, color: ObsidianPalette.textMuted, size: size),
      ),
    );
  }

  PopupMenuItem<int> _menuItem({
    required int index,
    required ObsidianMenuAction action,
  }) {
    final enabled = action.onTap != null;
    final danger = action.variant == TechButtonVariant.danger;
    final baseColor = danger ? Colors.redAccent : ObsidianPalette.textPrimary;
    final color = enabled
        ? baseColor
        : ObsidianPalette.textMuted.withValues(alpha: 0.55);

    return PopupMenuItem<int>(
      value: index,
      enabled: enabled,
      height: 40,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(action.icon, size: 18, color: color),
          const SizedBox(width: 10),
          Text(
            action.label,
            style: GoogleFonts.rajdhani(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
