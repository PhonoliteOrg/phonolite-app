import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

void configureTestFonts() {
  GoogleFonts.config.allowRuntimeFetching = false;
}

Widget wrapInTestApp(Widget child) {
  return MaterialApp(
    theme: ObsidianTheme.build(),
    home: Scaffold(body: child),
  );
}
