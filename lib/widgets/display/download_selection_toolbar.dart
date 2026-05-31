import 'package:flutter/material.dart';

import '../ui/obsidian_theme.dart';
import '../ui/tech_button.dart';

class DownloadSelectionToolbar extends StatelessWidget {
  const DownloadSelectionToolbar({
    super.key,
    required this.selectedCount,
    required this.totalCount,
    required this.onCancel,
    required this.onSelectAll,
    required this.onRemove,
  });

  final int selectedCount;
  final int totalCount;
  final VoidCallback onCancel;
  final VoidCallback onSelectAll;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final label = selectedCount == 1 ? '1 selected' : '$selectedCount selected';
    final totalLabel = totalCount == 1
        ? '1 available'
        : '$totalCount available';
    final actions = <Widget>[
      TechButton(
        label: 'Cancel',
        icon: Icons.close_rounded,
        density: TechButtonDensity.compact,
        onTap: onCancel,
      ),
      TechButton(
        label: 'Select all',
        icon: Icons.select_all_rounded,
        density: TechButtonDensity.compact,
        onTap: onSelectAll,
      ),
      if (selectedCount > 0 && onRemove != null)
        TechButton(
          label: 'Remove',
          icon: Icons.delete_outline_rounded,
          density: TechButtonDensity.compact,
          variant: TechButtonVariant.danger,
          onTap: onRemove,
        ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        border: Border.all(color: ObsidianPalette.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final countLabel = Text(
            '$label / $totalLabel',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: ObsidianPalette.textMuted,
              letterSpacing: 1.0,
            ),
          );
          final actionWrap = Wrap(
            alignment: WrapAlignment.end,
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: actions,
          );

          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                countLabel,
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerRight, child: actionWrap),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: countLabel),
              const SizedBox(width: 12),
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: actionWrap,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
