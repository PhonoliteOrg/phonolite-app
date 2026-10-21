import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/interaction/button_haptics.dart';
import 'package:phonolite_app/ui/shared/design_system/surfaces/glass_panel.dart';
import 'package:phonolite_app/ui/shared/design_system/surfaces/obsidian_shapes.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/color_opacity.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

enum ObsidianButtonStyle { glass, subtle }

class ObsidianIconButton extends StatelessWidget {
  final IconData? icon;
  final Widget? iconWidget;
  final VoidCallback? onPressed;
  final bool isActive;
  final double size;
  final double cut;
  final ObsidianButtonStyle style;

  const ObsidianIconButton({
    super.key,
    this.icon,
    this.iconWidget,
    this.isActive = false,
    this.size = 46,
    this.cut = 12,
    this.style = ObsidianButtonStyle.glass,
    this.onPressed,
  }) : assert((icon == null) != (iconWidget == null));

  Widget _buildInk(Color color) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: withButtonHaptic(onPressed),
        child: Center(
          child: iconWidget != null
              ? IconTheme.merge(
                  data: IconThemeData(color: color, size: 20),
                  child: iconWidget!,
                )
              : Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final Color color;

    if (!enabled) {
      color = ObsidianPalette.textMuted.withByteOpacity(0.4);
    } else {
      color = isActive ? ObsidianPalette.gold : ObsidianPalette.textMuted;
    }

    final gradient = isActive && enabled && style == ObsidianButtonStyle.glass
        ? LinearGradient(
            colors: [ObsidianPalette.gold.withByteOpacity(0.2), ObsidianPalette.gold.withByteOpacity(0.05)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : null;

    final panel = style == ObsidianButtonStyle.glass
        ? GlassPanel(
            cut: cut,
            padding: EdgeInsets.zero,
            gradient: gradient,
            shadowColor: enabled ? Colors.black.withByteOpacity(0.4) : Colors.black.withByteOpacity(0.2),
            child: _buildInk(color),
          )
        : ClipPath(
            clipper: CyberClipper(cut: cut),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withByteOpacity(0.03),
                border: Border.all(
                  color: enabled
                      ? ObsidianPalette.border.withByteOpacity(0.6)
                      : ObsidianPalette.border.withByteOpacity(0.25),
                ),
              ),
              child: _buildInk(color),
            ),
          );

    return SizedBox(width: size, height: size, child: panel);
  }
}
