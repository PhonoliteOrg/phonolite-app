import 'package:flutter/material.dart';

import '../ui/phonolite_icons.dart';
import '../ui/button_haptics.dart';

/// Keeps Material checkbox input, focus and accessibility while drawing Lucide.
class LucideCheckbox extends StatelessWidget {
  const LucideCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.visualDensity,
    this.materialTapTargetSize,
    this.activeColor,
    this.side,
    this.focusNode,
    this.autofocus = false,
  });

  final bool value;
  final ValueChanged<bool?>? onChanged;
  final VisualDensity? visualDensity;
  final MaterialTapTargetSize? materialTapTargetSize;
  final Color? activeColor;
  final BorderSide? side;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = onChanged == null
        ? theme.disabledColor
        : value
        ? activeColor ?? theme.colorScheme.primary
        : side?.color ?? theme.colorScheme.onSurfaceVariant;
    return Stack(
      alignment: Alignment.center,
      children: [
        Checkbox(
          value: value,
          onChanged: withSelectionHaptic(onChanged),
          visualDensity: visualDensity,
          materialTapTargetSize: materialTapTargetSize,
          focusNode: focusNode,
          autofocus: autofocus,
          fillColor: const WidgetStatePropertyAll(Colors.transparent),
          checkColor: Colors.transparent,
          side: WidgetStateBorderSide.resolveWith((_) => BorderSide.none),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused) ||
                states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.pressed)) {
              return color.withValues(alpha: 0.16);
            }
            return null;
          }),
        ),
        IgnorePointer(
          child: ExcludeSemantics(
            child: Icon(
              value ? PhonoliteIcons.squareCheck : PhonoliteIcons.square,
              size: 20,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
