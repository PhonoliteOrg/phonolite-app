import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_list_row.dart';

class PlaybackHudModalListRow extends StatelessWidget {
  final String title;
  final Widget trailing;
  final VoidCallback? onTap;
  final bool enabled;
  final bool isSelected;

  const PlaybackHudModalListRow({
    super.key,
    required this.title,
    required this.trailing,
    required this.onTap,
    required this.enabled,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) => ObsidianModalListRow(
    title: title,
    trailing: trailing,
    onTap: onTap,
    enabled: enabled,
    isSelected: isSelected,
    touchTitleMaxLines: null,
  );
}
