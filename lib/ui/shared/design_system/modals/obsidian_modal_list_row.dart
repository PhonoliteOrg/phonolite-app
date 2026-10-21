import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/hover_row.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

/// A modal choice shares its selected/disabled presentation and touch layout.
class ObsidianModalListRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;
  final bool isSelected;
  final int? touchTitleMaxLines;

  const ObsidianModalListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.enabled = true,
    this.isSelected = false,
    this.touchTitleMaxLines = 2,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final touch = ObsidianModalScope.usesTouchTargets(context);

    return ObsidianHoverRow(
      onTap: enabled ? onTap : null,
      enabled: enabled,
      isActive: isSelected,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: touch ? touchTitleMaxLines : 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: enabled ? ObsidianPalette.textPrimary : ObsidianPalette.textMuted,
                    letterSpacing: 0.4,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: touch ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: ObsidianPalette.textMuted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing ??
              (isSelected ? const Icon(PhonoliteIcons.check, color: ObsidianPalette.gold) : const SizedBox.shrink()),
        ],
      ),
    );
  }
}
