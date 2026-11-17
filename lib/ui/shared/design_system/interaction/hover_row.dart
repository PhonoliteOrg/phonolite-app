import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/interaction/button_haptics.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/focus_highlight.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/hoverable.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/color_opacity.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

/// A list row whose pointer hover and keyboard focus share one highlight: a leading accent border
/// and a soft gradient.
class ObsidianHoverRow extends StatefulWidget {
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
  State<ObsidianHoverRow> createState() => _ObsidianHoverRowState();
}

class _ObsidianHoverRowState extends State<ObsidianHoverRow> with InkFocusHighlight<ObsidianHoverRow> {
  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    final onTap = widget.onTap;
    final onLongPress = widget.onLongPress;
    final hoverGradient = widget.hoverGradient;
    final actionable = enabled && (onTap != null || onLongPress != null);
    final cursor = actionable ? SystemMouseCursors.click : SystemMouseCursors.basic;

    return ObsidianHoverBuilder(
      cursor: cursor,
      builder: (context, pointerHovered) {
        final hovered = pointerHovered || focusHighlighted;
        final highlight = widget.isActive || hovered;
        final activeBorder = highlight ? widget.borderColor : Colors.transparent;
        final resolvedGradient = hovered
            ? hoverGradient ??
                  LinearGradient(
                    colors: [Colors.white.withByteOpacity(0.06), Colors.transparent],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  )
            : null;
        final resolvedColor = hovered && hoverGradient == null ? widget.hoverColor : null;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            canRequestFocus: widget.canRequestFocus,
            onTap: withButtonHaptic(enabled ? onTap : null),
            onLongPress: enabled ? onLongPress : null,
            onFocusChange: handleInkFocusChange,
            child: AnimatedContainer(
              constraints: ObsidianModalScope.usesTouchTargets(context) ? const BoxConstraints(minHeight: 56) : null,
              duration: widget.duration,
              curve: widget.curve,
              padding: widget.padding,
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: activeBorder, width: widget.borderWidth),
                ),
                gradient: resolvedGradient,
                color: resolvedColor,
              ),
              child: widget.child,
            ),
          ),
        );
      },
    );
  }
}
