import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'obsidian_shapes.dart';
class ObsidianPalette {
  static const Color obsidian = Color(0xFF050505);
  static const Color obsidianElevated = Color(0xFF0A0A0D);
  static const Color obsidianGlass = Color(0x99121214);
  static const Color gold = Color(0xFFFFD700);
  static const Color goldSoft = Color(0x4DFFD700);
  static const Color border = Color(0x1FFFFFFF);
  static const Color textPrimary = Color(0xFFF2F2F2);
  static const Color textMuted = Color(0xFF8A8A9A);
}

class ObsidianTheme {
  static ThemeData build() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: ObsidianPalette.gold,
        onPrimary: Colors.black,
        secondary: ObsidianPalette.goldSoft,
        background: ObsidianPalette.obsidian,
        surface: ObsidianPalette.obsidianElevated,
        surfaceVariant: ObsidianPalette.obsidianGlass,
        onSurface: ObsidianPalette.textPrimary,
        onBackground: ObsidianPalette.textPrimary,
      ),
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: ObsidianPalette.obsidian,
    );

    final body = GoogleFonts.poppinsTextTheme(base.textTheme).apply(
      bodyColor: ObsidianPalette.textPrimary,
      displayColor: ObsidianPalette.textPrimary,
    );
    final display = GoogleFonts.rajdhaniTextTheme(body);

    return base.copyWith(
      textTheme: body.copyWith(
        displayLarge: display.displayLarge,
        displayMedium: display.displayMedium,
        displaySmall: display.displaySmall,
        headlineLarge: display.headlineLarge,
        headlineMedium: display.headlineMedium,
        headlineSmall: display.headlineSmall,
        titleLarge: display.titleLarge,
        titleMedium: display.titleMedium,
        titleSmall: display.titleSmall,
      ),
      dividerTheme: DividerThemeData(
        color: ObsidianPalette.border,
        thickness: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: ObsidianPalette.obsidianElevated.withOpacity(0.9),
        surfaceTintColor: Colors.transparent,
        shape: const CyberShapeBorder(
          cut: 18,
          side: BorderSide(color: ObsidianPalette.border),
        ),
        titleTextStyle: display.titleLarge?.copyWith(
          color: ObsidianPalette.textPrimary,
          letterSpacing: 1.1,
        ),
        contentTextStyle: body.bodyMedium?.copyWith(color: ObsidianPalette.textPrimary),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: ObsidianPalette.textMuted,
        textColor: ObsidianPalette.textPrimary,
        titleTextStyle: body.titleMedium,
        subtitleTextStyle: body.bodySmall?.copyWith(color: ObsidianPalette.textMuted),
      ),
      iconTheme: const IconThemeData(color: ObsidianPalette.textMuted),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: ObsidianPalette.obsidianGlass,
        selectedColor: ObsidianPalette.goldSoft,
        labelStyle: body.labelLarge?.copyWith(
          color: ObsidianPalette.textPrimary,
          letterSpacing: 1,
        ),
        side: const BorderSide(color: ObsidianPalette.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: ObsidianPalette.obsidian.withOpacity(0.35),
        labelType: NavigationRailLabelType.none,
        selectedIconTheme: const IconThemeData(color: ObsidianPalette.gold),
        unselectedIconTheme: const IconThemeData(color: ObsidianPalette.textMuted),
        indicatorColor: Colors.transparent,
        useIndicator: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: ObsidianPalette.obsidianElevated.withOpacity(0.92),
        indicatorColor: ObsidianPalette.goldSoft,
        labelTextStyle: WidgetStatePropertyAll(
          body.labelSmall?.copyWith(letterSpacing: 1),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? ObsidianPalette.gold
                : ObsidianPalette.textMuted,
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: ObsidianPalette.gold,
        unselectedLabelColor: ObsidianPalette.textMuted,
        indicatorColor: ObsidianPalette.gold,
        labelStyle: display.labelLarge?.copyWith(letterSpacing: 1.1),
      ),
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: ObsidianPalette.gold,
        inactiveTrackColor: ObsidianPalette.textMuted.withOpacity(0.2),
        secondaryActiveTrackColor: ObsidianPalette.goldSoft,
        thumbColor: ObsidianPalette.gold,
        overlayColor: ObsidianPalette.goldSoft,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: ObsidianPalette.gold,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: display.labelLarge?.copyWith(letterSpacing: 1.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ObsidianPalette.gold,
          textStyle: display.labelLarge?.copyWith(letterSpacing: 1.1),
        ),
      ),
    );
  }
}
