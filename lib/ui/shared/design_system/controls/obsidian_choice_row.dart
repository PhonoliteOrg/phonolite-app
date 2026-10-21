import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/controls/lucide_checkbox.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_list_row.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

/// A checkbox choice composes the standard responsive row presentation.
class ObsidianChoiceRow extends StatelessWidget {
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const ObsidianChoiceRow({super.key, required this.title, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: ObsidianListRow(
      title: title,
      isActive: selected,
      onTap: onTap,
      leading: LucideCheckbox(
        value: selected,
        onChanged: (_) => onTap(),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: const BorderSide(color: ObsidianPalette.textMuted),
        activeColor: ObsidianPalette.gold,
      ),
    ),
  );
}
