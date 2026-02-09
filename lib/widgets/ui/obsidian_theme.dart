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
  static TextStyle? _scaleTextStyle(TextStyle? style, double scale) {
    if (style == null || scale == 1.0) {
      return style;
    }
    final fontSize = style.fontSize;
    if (fontSize == null) {
      return style;
    }
    return style.copyWith(
      fontSize: fontSize * scale,
      letterSpacing: style.letterSpacing == null
          ? null
          : style.letterSpacing! * scale,
      wordSpacing:
          style.wordSpacing == null ? null : style.wordSpacing! * scale,
    );
  }

  static TextTheme _scaleTextTheme(TextTheme theme, double scale) {
    if (scale == 1.0) {
      return theme;
    }
    return theme.copyWith(
      displayLarge: _scaleTextStyle(theme.displayLarge, scale),
      displayMedium: _scaleTextStyle(theme.displayMedium, scale),
      displaySmall: _scaleTextStyle(theme.displaySmall, scale),
      headlineLarge: _scaleTextStyle(theme.headlineLarge, scale),
      headlineMedium: _scaleTextStyle(theme.headlineMedium, scale),
      headlineSmall: _scaleTextStyle(theme.headlineSmall, scale),
      titleLarge: _scaleTextStyle(theme.titleLarge, scale),
      titleMedium: _scaleTextStyle(theme.titleMedium, scale),
      titleSmall: _scaleTextStyle(theme.titleSmall, scale),
      bodyLarge: _scaleTextStyle(theme.bodyLarge, scale),
      bodyMedium: _scaleTextStyle(theme.bodyMedium, scale),
      bodySmall: _scaleTextStyle(theme.bodySmall, scale),
      labelLarge: _scaleTextStyle(theme.labelLarge, scale),
      labelMedium: _scaleTextStyle(theme.labelMedium, scale),
      labelSmall: _scaleTextStyle(theme.labelSmall, scale),
    );
  }

  static ThemeData build({double scale = 1.0}) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
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
    final scaledBody = _scaleTextTheme(body, scale);
    final scaledDisplay = _scaleTextTheme(display, scale);

    const noOverlay = WidgetStatePropertyAll<Color>(Colors.transparent);

    return base.copyWith(
      textTheme: scaledBody.copyWith(
        displayLarge: scaledDisplay.displayLarge,
        displayMedium: scaledDisplay.displayMedium,
        displaySmall: scaledDisplay.displaySmall,
        headlineLarge: scaledDisplay.headlineLarge,
        headlineMedium: scaledDisplay.headlineMedium,
        headlineSmall: scaledDisplay.headlineSmall,
        titleLarge: scaledDisplay.titleLarge,
        titleMedium: scaledDisplay.titleMedium,
        titleSmall: scaledDisplay.titleSmall,
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
        titleTextStyle: scaledDisplay.titleLarge?.copyWith(
          color: ObsidianPalette.textPrimary,
          letterSpacing: 1.1,
        ),
        contentTextStyle:
            scaledBody.bodyMedium?.copyWith(color: ObsidianPalette.textPrimary),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: ObsidianPalette.textMuted,
        textColor: ObsidianPalette.textPrimary,
        titleTextStyle: scaledBody.titleMedium,
        subtitleTextStyle:
            scaledBody.bodySmall?.copyWith(color: ObsidianPalette.textMuted),
      ),
      iconTheme: const IconThemeData(color: ObsidianPalette.textMuted),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: ObsidianPalette.obsidianGlass,
        selectedColor: ObsidianPalette.goldSoft,
        labelStyle: scaledBody.labelLarge?.copyWith(
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
          scaledBody.labelSmall?.copyWith(letterSpacing: 1 * scale),
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
        labelStyle: scaledDisplay.labelLarge?.copyWith(letterSpacing: 1.1 * scale),
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
              padding:
                  EdgeInsets.symmetric(horizontal: 20 * scale, vertical: 14 * scale),
              textStyle:
                  scaledDisplay.labelLarge?.copyWith(letterSpacing: 1.1 * scale),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14 * scale),
              ),
            )
            .copyWith(overlayColor: noOverlay),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
              foregroundColor: ObsidianPalette.gold,
              textStyle:
                  scaledDisplay.labelLarge?.copyWith(letterSpacing: 1.1 * scale),
            )
            .copyWith(overlayColor: noOverlay),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: const ButtonStyle(overlayColor: noOverlay),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: const ButtonStyle(overlayColor: noOverlay),
      ),
      iconButtonTheme: const IconButtonThemeData(
        style: ButtonStyle(overlayColor: noOverlay),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        splashColor: Colors.transparent,
      ),
    );
  }
}
