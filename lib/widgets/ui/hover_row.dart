import 'package:flutter/material.dart';

import 'hoverable.dart';
import 'obsidian_theme.dart';

class ObsidianHoverRow extends StatelessWidget {
  const ObsidianHoverRow({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    this.borderColor = ObsidianPalette.gold,
    this.isActive = false,
    this.enabled = true,
    this.borderWidth = 2,
    this.duration = const Duration(milliseconds: 180),
    this.curve = Curves.easeOut,
    this.hoverGradient,
    this.hoverColor,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsets padding;
  final Color borderColor;
  final bool isActive;
  final bool enabled;
  final double borderWidth;
  final Duration duration;
  final Curve curve;
  final Gradient? hoverGradient;
  final Color? hoverColor;

  @override
  Widget build(BuildContext context) {
    final actionable = enabled && onTap != null;
    final cursor =
        actionable ? SystemMouseCursors.click : SystemMouseCursors.basic;
    return ObsidianHoverBuilder(
      cursor: cursor,
      builder: (context, hovered) {
        final highlight = isActive || hovered;
        final activeBorder = highlight ? borderColor : Colors.transparent;
        final resolvedGradient = hovered
            ? hoverGradient ??
                LinearGradient(
                  colors: [
                    Colors.white.withOpacity(0.06),
                    Colors.transparent,
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
            : null;
        final resolvedColor =
            hovered && hoverGradient == null ? hoverColor : null;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            onLongPress: enabled ? onLongPress : null,
            child: AnimatedContainer(
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
