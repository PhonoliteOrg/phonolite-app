import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_list_row.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

/// A single choice in a [RadioGroup], using the shared responsive list frame.
class ObsidianRadioRow<T> extends StatelessWidget {
  final T value;
  final String title;
  final String? subtitle;
  final int? subtitleMaxLines;
  final bool selected;
  final bool enabled;
  final ValueChanged<T> onSelected;

  const ObsidianRadioRow({
    super.key,
    required this.value,
    required this.title,
    required this.selected,
    required this.onSelected,
    this.subtitle,
    this.subtitleMaxLines = 1,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: ObsidianListRow(
      title: title,
      subtitle: subtitle,
      subtitleMaxLines: subtitleMaxLines,
      isActive: selected,
      enabled: enabled,
      canRequestFocus: false,
      onTap: enabled ? () => onSelected(value) : null,
      leading: Radio<T>(
        value: value,
        enabled: enabled,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return ObsidianPalette.textMuted.withValues(alpha: 0.55);

          return states.contains(WidgetState.selected) ? ObsidianPalette.gold : ObsidianPalette.textMuted;
        }),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
  );
}
