import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_fonts.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

/// Registers the app's bundled font families with the test engine.
///
/// The test engine does not load the app's font manifest, so without this the
/// display and body families measure with the test font instead of the shipped
/// glyphs. Layout tests that depend on real text widths call this in `setUpAll`.
Future<void> loadBundledFonts() async {
  final display = FontLoader(ObsidianFonts.display)
    ..addFont(rootBundle.load('assets/fonts/Rajdhani-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Rajdhani-SemiBold.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Rajdhani-Bold.ttf'));
  final body = FontLoader(ObsidianFonts.body)..addFont(rootBundle.load('assets/fonts/Poppins-Regular.ttf'));

  await Future.wait([display.load(), body.load()]);
}

Widget wrapInTestApp(Widget child) {
  return MaterialApp(
    theme: ObsidianTheme.build(),
    home: Scaffold(body: child),
  );
}
