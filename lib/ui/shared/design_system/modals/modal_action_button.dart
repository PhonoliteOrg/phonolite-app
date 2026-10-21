import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/controls/tech_button.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/button_haptics.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

class ModalActionButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final TechButtonVariant variant;

  const ModalActionButton({
    super.key,
    required this.label,
    this.icon,
    this.variant = TechButtonVariant.standard,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final touchLayout = ObsidianModalScope.usesTouchTargets(context);
    final accent = variant == TechButtonVariant.danger ? Colors.redAccent : ObsidianPalette.gold;
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
      minimumSize: WidgetStatePropertyAll(Size(touchLayout ? 88 : 64, touchLayout ? 52 : 48)),
      visualDensity: VisualDensity.standard,
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: touchLayout ? 16 : 10, vertical: 10)),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return ObsidianPalette.textMuted.withValues(alpha: 0.6);
        }

        return highlighted(states) || variant == TechButtonVariant.danger ? accent : ObsidianPalette.textMuted;
      }),
      textStyle: WidgetStateProperty.resolveWith(
        (states) => textStyle?.copyWith(
          shadows: highlighted(states) ? [Shadow(color: accent.withValues(alpha: 0.7), blurRadius: 10)] : const [],
        ),
      ),
    );
    final iconData = icon;

    return iconData == null
        ? TextButton(onPressed: withButtonHaptic(onPressed), style: style, child: Text(label.toUpperCase()))
        : TextButton.icon(
            onPressed: withButtonHaptic(onPressed),
            style: style,
            icon: Icon(iconData, size: touchLayout ? 20 : 16),
            label: Text(label.toUpperCase()),
          );
  }
}
