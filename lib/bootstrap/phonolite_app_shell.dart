import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

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

  /// The app's own copy is English, so only English locales are offered: Material's built-in
  /// strings stay in the same language while dates and times follow the user's region.
  static const supportedLocales = <Locale>[
    Locale('en', 'US'),
    Locale('en', 'GB'),
    Locale('en', 'AU'),
    Locale('en', 'CA'),
    Locale('en', 'IE'),
    Locale('en', 'IN'),
    Locale('en', 'NZ'),
    Locale('en', 'SG'),
    Locale('en', 'ZA'),
    Locale('en'),
  ];

  void _togglePlayback() => unawaited(controller.pause(controller.playbackState.isPlaying));

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: controller,
      child: SettingsScope(
        settings: settings ?? AppSettingsControllers.shared,
        child: MaterialApp(
          title: 'Phonolite',
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: supportedLocales,
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
