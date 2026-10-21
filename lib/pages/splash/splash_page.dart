import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/interaction/button_haptics.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';
import 'package:phonolite_app/ui/shell/base_page.dart';

class SplashPage extends BaseStatelessPage {
  final VoidCallback? onTryDifferentServer;
  final bool isResetting;
  final int timeoutSeconds;

  const SplashPage({super.key, this.isResetting = false, this.timeoutSeconds = 10, this.onTryDifferentServer});

  @override
  bool get usesScaffold => true;

  @override
  bool get usesSafeArea => true;

  @override
  Color? get pageBackgroundColor => Colors.transparent;

  @override
  Widget pageContent(BuildContext context, PageAssembler assemble) {
    final theme = Theme.of(context);

    return assemble(
      context,
      body: PageBody.box(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/images/phonolite-logo-nobackground.png', width: 220, fit: BoxFit.contain),
                const SizedBox(height: 18),
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(ObsidianPalette.gold),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Connecting to saved server...',
                  style: theme.textTheme.titleMedium?.copyWith(letterSpacing: 0.6),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'This attempt will stop after $timeoutSeconds seconds.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: ObsidianPalette.textMuted, height: 1.4),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: withButtonHaptic(isResetting ? null : onTryDifferentServer),
                  child: Text(isResetting ? 'Preparing login...' : 'Try a different server'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
