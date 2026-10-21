import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/interaction/button_haptics.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

class ObsidianToggleOption extends StatelessWidget {
  final String label;
  final bool isActive;
  final Widget? icon;
  final VoidCallback? onPressed;
  final Size touchMinimumSize;
  final double? touchFontSize;
  final VisualDensity? visualDensity;

  const ObsidianToggleOption({
    super.key,
    required this.label,
    required this.isActive,
    this.icon,
    this.touchMinimumSize = const Size(88, 52),
    this.touchFontSize = 16,
    this.visualDensity,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final touchLayout = ObsidianModalScope.usesTouchTargets(context);
    final style = ButtonStyle(
      minimumSize: touchLayout ? WidgetStatePropertyAll(touchMinimumSize) : null,
      visualDensity: visualDensity ?? (touchLayout ? VisualDensity.standard : null),
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
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
      textStyle: WidgetStatePropertyAll(
        Theme.of(context).textTheme.titleSmall?.copyWith(
          fontSize: touchLayout ? touchFontSize : null,
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
            border: Border(bottom: BorderSide(color: isActive ? ObsidianPalette.gold : Colors.transparent, width: 2)),
          ),
          child: icon == null
              ? TextButton(onPressed: withButtonHaptic(onPressed), style: style, child: labelWidget)
              : TextButton.icon(onPressed: withButtonHaptic(onPressed), style: style, icon: icon!, label: labelWidget),
        ),
      ),
    );
  }
}
