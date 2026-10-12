import 'package:flutter/material.dart';

import 'phonolite_icons.dart';
import 'package:google_fonts/google_fonts.dart';

import 'obsidian_theme.dart';
import 'obsidian_widgets.dart';
import 'tech_button.dart';
import '../modals/obsidian_modal_scope.dart';

class ObsidianMenuAction {
  const ObsidianMenuAction({
    required this.label,
    this.icon,
    this.iconWidget,
    required this.onTap,
    this.variant = TechButtonVariant.standard,
  }) : assert((icon == null) != (iconWidget == null));

  final String label;
  final IconData? icon;
  final Widget? iconWidget;
  final VoidCallback? onTap;
  final TechButtonVariant variant;
}

class ObsidianOverflowActionButton extends StatelessWidget {
  const ObsidianOverflowActionButton({
    super.key,
    required this.actions,
    required this.tooltip,
    this.icon = PhonoliteIcons.ellipsisVertical,
    this.size = 22,
  });

  final List<ObsidianMenuAction> actions;
  final String tooltip;
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final compact = ObsidianModalScope.isCompact(context);
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
            _menuItem(index: entry.$1, action: entry.$2, compact: compact),
        ],
        icon: Icon(icon, color: ObsidianPalette.textMuted, size: size),
      ),
    );
  }

  PopupMenuItem<int> _menuItem({
    required int index,
    required ObsidianMenuAction action,
    required bool compact,
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
      height: compact ? 56 : 40,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (action.iconWidget != null)
            IconTheme.merge(
              data: IconThemeData(size: compact ? 22 : 18, color: color),
              child: action.iconWidget!,
            )
          else
            Icon(action.icon, size: compact ? 22 : 18, color: color),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              action.label,
              style: GoogleFonts.rajdhani(
                fontSize: compact ? 16 : 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
