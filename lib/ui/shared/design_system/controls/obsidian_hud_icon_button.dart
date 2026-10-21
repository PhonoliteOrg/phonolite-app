import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/interaction/pointer_interaction.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/color_opacity.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

class ObsidianHudIconButton extends StatelessWidget {
  final IconData? icon;
  final Widget? iconWidget;
  final bool isActive;
  final double size;
  final VoidCallback? onPressed;

  const ObsidianHudIconButton({
    super.key,
    this.icon,
    this.iconWidget,
    this.isActive = false,
    this.size = 26,
    this.onPressed,
  }) : assert((icon == null) != (iconWidget == null));

  @override
  Widget build(BuildContext context) {
    return _HoverHudIconButton(
      icon: icon,
      iconWidget: iconWidget,
      size: size,
      isActive: isActive,
      onPressed: onPressed,
    );
  }
}

class _HoverHudIconButton extends StatefulWidget {
  final IconData? icon;
  final Widget? iconWidget;
  final double size;
  final bool isActive;
  final VoidCallback? onPressed;

  const _HoverHudIconButton({
    required this.icon,
    required this.iconWidget,
    required this.size,
    required this.isActive,
    required this.onPressed,
  });

  @override
  State<_HoverHudIconButton> createState() => _HoverHudIconButtonState();
}

class _HoverHudIconButtonState extends State<_HoverHudIconButton> with PointerInteraction<_HoverHudIconButton> {
  static const Duration _transition = Duration(milliseconds: 200);

  @override
  bool get interactionEnabled => widget.onPressed != null;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final highlight = enabled && (widget.isActive || hovered || pressed);
    final double glowOpacity;

    if (!enabled) {
      glowOpacity = 0.0;
    } else if (hovered) {
      glowOpacity = 0.7;
    } else {
      glowOpacity = widget.isActive ? 0.35 : 0.0;
    }

    final idleColor = enabled ? ObsidianPalette.textMuted : ObsidianPalette.textMuted.withByteOpacity(0.6);

    return pointerRegion(
      onTap: widget.onPressed,
      behavior: HitTestBehavior.opaque,
      child: Container(
        constraints: ObsidianModalScope.usesTouchTargets(context)
            ? const BoxConstraints(minWidth: 48, minHeight: 48)
            : null,
        padding: const EdgeInsets.all(8),
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: glowOpacity),
          duration: _transition,
          curve: Curves.easeOut,
          builder: (context, animatedGlow, child) {
            return TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: highlight ? ObsidianPalette.gold : idleColor),
              duration: _transition,
              curve: Curves.easeOut,
              builder: (context, animatedColor, _) {
                final shadows = [
                  if (animatedGlow > 0)
                    Shadow(color: ObsidianPalette.gold.withByteOpacity(animatedGlow), blurRadius: 10),
                ];

                if (widget.iconWidget != null) {
                  // Keep SVG artwork at the icon size inside touch targets.
                  return Center(
                    widthFactor: 1,
                    heightFactor: 1,
                    child: IconTheme.merge(
                      data: IconThemeData(color: animatedColor, size: widget.size, shadows: shadows),
                      child: widget.iconWidget!,
                    ),
                  );
                }

                return Icon(widget.icon, color: animatedColor, size: widget.size, shadows: shadows);
              },
            );
          },
        ),
      ),
    );
  }
}
