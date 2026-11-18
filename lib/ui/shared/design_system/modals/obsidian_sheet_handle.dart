import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_scale.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/color_opacity.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_palette.dart';

class ObsidianSheetHandle extends StatelessWidget {
  final bool wide;

  const ObsidianSheetHandle({super.key, this.wide = false});

  @override
  Widget build(BuildContext context) {
    final scale = wide ? ObsidianScale.of(context) : 1.0;
    final height = wide ? 6 * scale : 4.0;
    return Padding(
      padding: wide ? EdgeInsets.symmetric(vertical: 12 * scale) : const EdgeInsets.only(top: 8, bottom: 6),
      child: Center(
        child: Container(
          width: wide ? 64 * scale : 42,
          height: height,
          decoration: BoxDecoration(
            color: wide ? Colors.white.withByteOpacity(0.35) : ObsidianPalette.textMuted.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(height / 2),
          ),
        ),
      ),
    );
  }
}
