import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/interaction/button_haptics.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/hoverable.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_scale.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/color_opacity.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

class ObsidianNavIcon extends StatelessWidget {
  final Widget icon;
  final bool isSelected;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final String? label;
  final bool? enableHover;

  const ObsidianNavIcon({
    super.key,
    required this.icon,
    required this.isSelected,
    this.size = 52,
    this.iconSize = 32,
    this.label,
    this.enableHover,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scale = ObsidianScale.of(context);

    double s(double value) => value * scale;

    final boxSize = s(size).clamp(48.0, double.infinity);
    final resolvedIconSize = s(iconSize);
    final cursor = onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click;

    return ObsidianHoverBuilder(
      cursor: cursor,
      enableHover: enableHover,
      builder: (context, hovered) {
        final Color iconColor;

        if (isSelected) {
          iconColor = ObsidianPalette.gold;
        } else {
          iconColor = hovered ? Colors.grey.shade300.withByteOpacity(0.9) : ObsidianPalette.textMuted;
        }

        return Semantics(
          selected: isSelected,
          child: TweenAnimationBuilder<Color?>(
            duration: const Duration(milliseconds: 200),
            tween: ColorTween(end: iconColor),
            curve: Curves.easeOut,
            builder: (context, color, child) => IconButton(
              onPressed: withButtonHaptic(onTap),
              tooltip: label,
              iconSize: resolvedIconSize,
              style: ButtonStyle(
                fixedSize: WidgetStatePropertyAll(Size.square(boxSize)),
                padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
                overlayColor: const WidgetStatePropertyAll(Colors.transparent),
                foregroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.focused) ? ObsidianPalette.gold : color,
                ),
              ),
              icon: child!,
            ),
            child: icon,
          ),
        );
      },
    );
  }
}
