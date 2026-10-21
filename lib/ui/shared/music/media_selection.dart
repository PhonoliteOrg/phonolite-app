import 'package:flutter/material.dart';

/// Presentation policy shared by every selectable catalog card and row.
/// Functional selection state continues to belong to the caller's controller.
class MediaSelection {
  final bool selectionMode;
  final bool selected;
  final bool selectable;
  final bool isDeleting;
  final VoidCallback? onSelectionToggle;

  const MediaSelection({
    this.selectionMode = false,
    this.selected = false,
    this.selectable = true,
    this.isDeleting = false,
    this.onSelectionToggle,
  });

  bool get canSelect => selectable && !isDeleting;

  bool get active => selectionMode && selected;

  double get opacity => isDeleting ? 0.45 : 1;

  VoidCallback? tapAction(VoidCallback? onTap) {
    if (selectionMode) {
      return canSelect ? onSelectionToggle : null;
    }

    return isDeleting ? null : onTap;
  }

  VoidCallback? longPressAction(VoidCallback? onLongPress) => selectionMode || isDeleting ? null : onLongPress;
}
