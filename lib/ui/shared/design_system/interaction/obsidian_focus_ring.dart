import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_palette.dart';

/// The focus ring painted over custom controls while they are keyboard-focused.
BoxDecoration obsidianFocusRing({BorderRadius borderRadius = const BorderRadius.all(Radius.circular(4))}) {
  return BoxDecoration(
    borderRadius: borderRadius,
    border: Border.all(color: ObsidianPalette.gold, width: 1.5),
  );
}
