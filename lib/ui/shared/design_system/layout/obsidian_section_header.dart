import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

class ObsidianSectionHeader extends StatelessWidget {
  static const double _compactWidth = 640;

  final String title;
  final String? subtitle;
  final Widget? trailing;

  const ObsidianSectionHeader({super.key, required this.title, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isCompact = MediaQuery.sizeOf(context).width < _compactWidth;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: textTheme.headlineLarge?.copyWith(
                  color: ObsidianPalette.textPrimary,
                  fontSize: isCompact ? 18 : null,
                  letterSpacing: isCompact ? 0.8 : 1.2,
                  height: 1.05,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle!,
                  style: textTheme.labelLarge?.copyWith(color: ObsidianPalette.textMuted, letterSpacing: 1.2),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}
