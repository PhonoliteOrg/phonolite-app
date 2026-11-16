import 'dart:async';

import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/settings/app_settings_controllers.dart';
import 'package:phonolite_app/pages/home/home_page.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/navigation/desktop_playback_shortcuts.dart';
import 'package:phonolite_app/ui/settings_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_viewport.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

/// The application's widget composition around controllers it borrows.
/// [PhonoliteApp] owns the controllers and their resources; feature tests pump
/// this same shell with substitutes.
class PhonoliteAppShell extends StatelessWidget {
  final AppController controller;

  /// Device-preference controllers; defaults to the process-wide ones.
  final AppSettingsControllers? settings;

  const PhonoliteAppShell({super.key, required this.controller, this.settings});

  void _togglePlayback() => unawaited(controller.pause(controller.playbackState.isPlaying));

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: controller,
      child: SettingsScope(
        settings: settings ?? AppSettingsControllers.shared,
        child: MaterialApp(
          title: 'Phonolite',
          theme: ObsidianTheme.build(),
          themeAnimationStyle: AnimationStyle.noAnimation,
          builder: (context, child) => DesktopPlaybackShortcuts(
            onTogglePlayPause: _togglePlayback,
            child: TooltipVisibility(visible: false, child: ObsidianViewport(child: child ?? const SizedBox.shrink())),
          ),
          home: const HomePage(),
        ),
      ),
    );
  }
}
