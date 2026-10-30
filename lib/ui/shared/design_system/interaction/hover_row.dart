import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/interaction/button_haptics.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/hoverable.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/color_opacity.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

class ObsidianHoverRow extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsets padding;
  final Color borderColor;
  final bool isActive;
  final bool enabled;
  final bool canRequestFocus;
  final double borderWidth;
  final Duration duration;
  final Curve curve;
  final Gradient? hoverGradient;
  final Color? hoverColor;

  const ObsidianHoverRow({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    this.borderColor = ObsidianPalette.gold,
    this.isActive = false,
    this.enabled = true,
    this.canRequestFocus = true,
    this.borderWidth = 2,
    this.duration = const Duration(milliseconds: 180),
    this.curve = Curves.easeOut,
    this.hoverGradient,
    this.hoverColor,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final actionable = enabled && (onTap != null || onLongPress != null);
    final cursor = actionable ? SystemMouseCursors.click : SystemMouseCursors.basic;

    return ObsidianHoverBuilder(
      cursor: cursor,
      builder: (context, hovered) {
        final highlight = isActive || hovered;
        final activeBorder = highlight ? borderColor : Colors.transparent;
        final resolvedGradient = hovered
            ? hoverGradient ??
                  LinearGradient(
                    colors: [Colors.white.withByteOpacity(0.06), Colors.transparent],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  )
            : null;
        final resolvedColor = hovered && hoverGradient == null ? hoverColor : null;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            canRequestFocus: canRequestFocus,
            onTap: withButtonHaptic(enabled ? onTap : null),
            onLongPress: enabled ? onLongPress : null,
            child: AnimatedContainer(
              constraints: ObsidianModalScope.usesTouchTargets(context) ? const BoxConstraints(minHeight: 56) : null,
              duration: duration,
              curve: curve,
              padding: padding,
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: activeBorder, width: borderWidth),
                ),
                gradient: resolvedGradient,
                color: resolvedColor,
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
