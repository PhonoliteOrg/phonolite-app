import 'package:flutter/material.dart';

import 'hoverable.dart';
import 'button_haptics.dart';

class ObsidianHoverCard extends StatelessWidget {
  const ObsidianHoverCard({
    super.key,
    required this.childBuilder,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.all(16),
    this.splashColor,
  });

  final Widget Function(BuildContext context, bool hovered) childBuilder;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsets padding;
  final Color? splashColor;

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
          child: Padding(
            padding: padding,
            child: childBuilder(context, hovered),
          ),
        );

        if (!actionable) {
          return card;
        }

        if (enableHover) {
          return GestureDetector(
            onTap: withButtonHaptic(onTap),
            onLongPress: onLongPress,
            behavior: HitTestBehavior.opaque,
            child: card,
          );
        }

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: withButtonHaptic(onTap),
            onLongPress: onLongPress,
            splashColor: splashColor,
            child: card,
          ),
        );
      },
    );
  }
}
