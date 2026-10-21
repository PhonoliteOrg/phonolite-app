import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/controls/lucide_checkbox.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_list_row.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/responsive_breakpoints.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';
import 'package:phonolite_app/ui/shared/music/media_selection.dart';

/// Shared catalog row assembly. Album and artist rows supply their artwork.
class SelectableMediaRow extends StatelessWidget {
  final Widget artwork;
  final String title;
  final MediaSelection selection;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const SelectableMediaRow({
    super.key,
    required this.artwork,
    required this.title,
    required this.selection,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final compact = isCompactListWidth(context);

    return ObsidianListRow(
      title: title,
      subtitle: subtitle?.isNotEmpty == true ? subtitle : null,
      onTap: selection.tapAction(onTap),
      onLongPress: selection.longPressAction(onLongPress),
      isActive: selection.active,
      opacity: selection.opacity,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selection.selectionMode) ...[
            LucideCheckbox(
              value: selection.selected,
              onChanged: selection.canSelect && selection.onSelectionToggle != null
                  ? (_) => selection.onSelectionToggle!()
                  : null,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: const BorderSide(color: ObsidianPalette.border),
              activeColor: ObsidianPalette.gold,
            ),
            SizedBox(width: compact ? 8 : 10),
          ],
          artwork,
        ],
      ),
      trailingGap: compact ? 8 : 12,
      trailing: selection.isDeleting
          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
          : trailing ??
                (selection.selectionMode
                    ? null
                    : Icon(PhonoliteIcons.chevronRight, size: compact ? 22 : 24, color: Colors.white38)),
    );
  }
}
