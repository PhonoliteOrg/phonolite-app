import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

class EmptyPlaylistText extends StatelessWidget {
  const EmptyPlaylistText({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(
        'No tracks yet.',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: ObsidianPalette.textMuted, letterSpacing: 0.6),
      ),
    );
  }
}
