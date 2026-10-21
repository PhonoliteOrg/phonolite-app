import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_hud_icon_button.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_list_row.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/tech_button.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/button_haptics.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/responsive_breakpoints.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

class SettingsTrailing extends StatelessWidget {
  final Widget child;

  const SettingsTrailing({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!isCompactListWidth(context)) {
      return child;
    }

    return SizedBox(width: 60, child: Center(heightFactor: 1, child: child));
  }
}

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
        child: Semantics(
          button: true,
          enabled: onPressed != null,
          label: tooltip,
          child: ObsidianHudIconButton(icon: icon, size: 22, onPressed: onPressed),
        ),
      );
    }

    final enabled = onPressed != null;
    final color = enabled ? Theme.of(context).colorScheme.error : ObsidianPalette.textMuted.withValues(alpha: 0.55);

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        child: GestureDetector(
          onTap: withButtonHaptic(onPressed),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 22, color: color),
          ),
        ),
      ),
    );
  }
}

Widget buildSettingsRow(
  BuildContext context, {
  required Widget leading,
  required String title,
  String? subtitle,
  Widget? trailing,
  VoidCallback? onTap,
  Color? titleColor,
}) {
  final isCompact = isCompactListWidth(context);
  final double trailingGap;

  if (trailing == null) {
    trailingGap = 0;
  } else {
    trailingGap = isCompact ? 6 : 8;
  }

  return ObsidianListRow(
    title: title,
    subtitle: subtitle?.trim().isNotEmpty == true ? subtitle : null,
    titleColor: titleColor,
    onTap: onTap,
    enabled: onTap != null,
    showHover: onTap != null,
    leadingGap: isCompact ? 8 : 12,
    trailingGap: trailingGap,
    leading: SizedBox(
      width: isCompact ? 28 : 32,
      child: Center(
        child: IconTheme.merge(
          data: IconThemeData(size: isCompact ? 20 : 24),
          child: leading,
        ),
      ),
    ),
    trailing: trailing == null
        ? null
        : IconTheme.merge(
            data: IconThemeData(size: isCompact ? 22 : 24),
            child: SettingsTrailing(child: trailing),
          ),
  );
}
