import 'package:flutter/material.dart';

import '../ui/obsidian_theme.dart';
import '../ui/tech_button.dart';
import 'obsidian_modal_scope.dart';

class ModalActionButton extends StatelessWidget {
  const ModalActionButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.variant = TechButtonVariant.standard,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final TechButtonVariant variant;

  @override
  Widget build(BuildContext context) {
    final touchLayout = ObsidianModalScope.usesTouchTargets(context);
    final accent = variant == TechButtonVariant.danger
        ? Colors.redAccent
        : ObsidianPalette.gold;
    final textStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
      fontFamily: 'Rajdhani',
      fontSize: touchLayout ? 16 : null,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.1,
    );
    bool highlighted(Set<WidgetState> states) =>
        !states.contains(WidgetState.disabled) &&
        (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused) ||
            states.contains(WidgetState.pressed));

    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(
        Size(touchLayout ? 88 : 64, touchLayout ? 52 : 48),
      ),
      visualDensity: VisualDensity.standard,
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: touchLayout ? 16 : 10, vertical: 10),
      ),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return ObsidianPalette.textMuted.withValues(alpha: 0.6);
        }
        return highlighted(states) || variant == TechButtonVariant.danger
            ? accent
            : ObsidianPalette.textMuted;
      }),
      textStyle: WidgetStateProperty.resolveWith(
        (states) => textStyle?.copyWith(
          shadows: highlighted(states)
              ? [Shadow(color: accent.withValues(alpha: 0.7), blurRadius: 10)]
              : const [],
        ),
      ),
    );
    final iconData = icon;
    return iconData == null
        ? TextButton(
            onPressed: onPressed,
            style: style,
            child: Text(label.toUpperCase()),
          )
        : TextButton.icon(
            onPressed: onPressed,
            style: style,
            icon: Icon(iconData, size: touchLayout ? 20 : 16),
            label: Text(label.toUpperCase()),
          );
  }
}
