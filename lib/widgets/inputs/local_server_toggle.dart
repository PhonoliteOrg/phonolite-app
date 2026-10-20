import 'package:flutter/material.dart';

import '../../entities/playback_state.dart';
import '../modals/obsidian_modal_scope.dart';
import '../ui/button_haptics.dart';
import '../ui/obsidian_theme.dart';
import '../ui/phonolite_icons.dart';
import '../ui/server_icon.dart';

class LocalServerToggle extends StatelessWidget {
  const LocalServerToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final ActionScope value;
  final ValueChanged<ActionScope> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      children: [
        _LocalServerOption(
          label: 'LOCAL',
          icon: const Icon(PhonoliteIcons.download),
          selected: value == ActionScope.local,
          onTap: () => onChanged(ActionScope.local),
        ),
        _LocalServerOption(
          label: 'SERVER',
          icon: const ServerIcon(),
          selected: value == ActionScope.server,
          onTap: () => onChanged(ActionScope.server),
        ),
      ],
    );
  }
}

class _LocalServerOption extends StatelessWidget {
  const _LocalServerOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Widget icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? ObsidianPalette.gold : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: TextButton.icon(
          onPressed: withButtonHaptic(onTap),
          style: ButtonStyle(
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              final highlighted =
                  selected ||
                  states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused) ||
                  states.contains(WidgetState.pressed);
              return highlighted
                  ? ObsidianPalette.gold
                  : ObsidianPalette.textMuted;
            }),
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            iconSize: const WidgetStatePropertyAll(18),
            minimumSize: ObsidianModalScope.usesTouchTargets(context)
                ? const WidgetStatePropertyAll(Size(112, 48))
                : null,
            visualDensity: VisualDensity.standard,
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            textStyle: WidgetStatePropertyAll(
              Theme.of(context).textTheme.titleSmall?.copyWith(
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          icon: icon,
          label: Text(label),
        ),
      ),
    );
  }
}
