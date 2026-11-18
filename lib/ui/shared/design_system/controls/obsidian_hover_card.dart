import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/interaction/button_haptics.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/focus_highlight.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/obsidian_focus_ring.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/obsidian_tap_target.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/hoverable.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/obsidian_supports_hover.dart';

class ObsidianHoverCard extends StatelessWidget {
  final Widget Function(BuildContext context, bool hovered) childBuilder;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsets padding;
  final Color? splashColor;

  const ObsidianHoverCard({
    super.key,
    required this.childBuilder,
    this.padding = const EdgeInsets.all(16),
    this.splashColor,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final enableHover = obsidianSupportsHover();
    final actionable = onTap != null || onLongPress != null;

    return ObsidianHoverBuilder(
      cursor: actionable ? SystemMouseCursors.click : SystemMouseCursors.basic,
      enableHover: enableHover,
      builder: (context, hovered) {
        final card = SizedBox(
          width: double.infinity,
          child: Padding(padding: padding, child: childBuilder(context, hovered)),
        );

        if (!actionable) {
          return card;
        }

        if (enableHover) {
          // Desktop paints its own hover; the tap target still makes the card keyboard-reachable.
          return ObsidianTapTarget(onTap: onTap, onLongPress: onLongPress, child: card);
        }

        return _TouchHoverCard(onTap: onTap, onLongPress: onLongPress, splashColor: splashColor, child: card);
      },
    );
  }
}

/// The touch-platform card: ink feedback for touches, a focus ring for an attached keyboard.
class _TouchHoverCard extends StatefulWidget {
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? splashColor;
  final Widget child;

  const _TouchHoverCard({
    required this.onTap,
    required this.onLongPress,
    required this.splashColor,
    required this.child,
  });

  @override
  State<_TouchHoverCard> createState() => _TouchHoverCardState();
}

class _TouchHoverCardState extends State<_TouchHoverCard> with InkFocusHighlight<_TouchHoverCard> {
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        onTap: withButtonHaptic(widget.onTap),
        onLongPress: widget.onLongPress,
        onFocusChange: handleInkFocusChange,
        splashColor: widget.splashColor,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: focusHighlighted ? obsidianFocusRing() : const BoxDecoration(),
          child: widget.child,
        ),
      ),
    );
  }
}
