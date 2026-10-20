import 'package:flutter/material.dart';

import '../modals/obsidian_modal_scope.dart';
import '../ui/obsidian_theme.dart';
import '../ui/button_haptics.dart';

class ObsidianToggleOption extends StatelessWidget {
  const ObsidianToggleOption({
    super.key,
    required this.label,
    required this.isActive,
    this.icon,
    this.onPressed,
  });

  final String label;
  final bool isActive;
  final Widget? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final touchLayout = ObsidianModalScope.usesTouchTargets(context);
    final style = ButtonStyle(
      minimumSize: touchLayout
          ? const WidgetStatePropertyAll(Size(88, 52))
          : null,
      visualDensity: touchLayout ? VisualDensity.standard : null,
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return ObsidianPalette.textMuted.withValues(alpha: 0.6);
        }
        final highlighted =
            isActive ||
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused) ||
            states.contains(WidgetState.pressed);
        return highlighted ? ObsidianPalette.gold : ObsidianPalette.textMuted;
      }),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      iconSize: const WidgetStatePropertyAll(18),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      textStyle: WidgetStatePropertyAll(
        Theme.of(context).textTheme.titleSmall?.copyWith(
          fontSize: touchLayout ? 16 : null,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    final labelWidget = Text(label.toUpperCase());
    return MergeSemantics(
      child: Semantics(
        selected: isActive,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isActive ? ObsidianPalette.gold : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: icon == null
              ? TextButton(
                  onPressed: withButtonHaptic(onPressed),
                  style: style,
                  child: labelWidget,
                )
              : TextButton.icon(
                  onPressed: withButtonHaptic(onPressed),
                  style: style,
                  icon: icon!,
                  label: labelWidget,
                ),
        ),
      ),
    );
  }
}
