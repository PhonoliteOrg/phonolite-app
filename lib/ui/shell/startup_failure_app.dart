import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/controls/tech_button.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_palette.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

/// Shown instead of the app when startup cannot complete, so a failure is visible and
/// recoverable rather than leaving an empty window.
class StartupFailureApp extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const StartupFailureApp({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Phonolite',
      theme: ObsidianTheme.build(),
      home: _StartupFailureView(message: message, onRetry: onRetry),
    );
  }
}

class _StartupFailureView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _StartupFailureView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ObsidianPalette.obsidian,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: ObsidianPalette.textPrimary),
                  ),
                  const SizedBox(height: 20),
                  TechButton(label: 'Try again', onTap: onRetry),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
