import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_list_row.dart';

class PlaybackPickerOption<T> extends StatelessWidget {
  final String title;
  final T value;
  final bool enabled;
  final bool isSelected;

  const PlaybackPickerOption({
    super.key,
    required this.title,
    required this.value,
    required this.isSelected,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) => ObsidianModalListRow(
    title: title,
    onTap: () => Navigator.of(context).pop<T>(value),
    enabled: enabled,
    isSelected: isSelected,
    touchTitleMaxLines: null,
  );
}
