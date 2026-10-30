import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

class EmptyStateText extends StatelessWidget {
  final String title;
  final String? message;
  final EdgeInsetsGeometry padding;

  const EmptyStateText({
    super.key,
    required this.title,
    this.message,
    this.padding = const EdgeInsets.symmetric(vertical: 24),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(color: ObsidianPalette.textMuted, letterSpacing: 0.6),
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                style: theme.textTheme.bodyMedium?.copyWith(color: ObsidianPalette.textMuted),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
