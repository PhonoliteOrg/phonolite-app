import 'dart:ui' show ColorSpace;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/ui/shared/design_system/theme/color_opacity.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

void main() {
  test('byte opacity retains existing palette alpha rounding', () {
    const color = Color(0xFF123456);
    final cases = <double, int>{
      0: 0x00123456,
      0.01: 0x03123456,
      0.02: 0x05123456,
      0.06: 0x0F123456,
      0.1: 0x1A123456,
      0.3: 0x4D123456,
      0.5: 0x80123456,
      0.75: 0xBF123456,
      1: 0xFF123456,
    };

    for (final entry in cases.entries) {
      expect(color.withByteOpacity(entry.key).toARGB32(), entry.value);
    }

    expect(color.withByteOpacity(15.49 / 255).toARGB32(), 0x0F123456);
    expect(color.withByteOpacity(15.51 / 255).toARGB32(), 0x10123456);
  });

  test('byte opacity retains RGB quantization and sRGB reconstruction', () {
    const color = Color.from(alpha: 0.2, red: 0.12345, green: 0.5555, blue: 0.9999, colorSpace: ColorSpace.displayP3);
    final adjusted = color.withByteOpacity(0.5);

    expect(adjusted.toARGB32(), 0x801F8EFF);
    expect(adjusted.a, 128 / 255);
    expect(adjusted.r, 31 / 255);
    expect(adjusted.g, 142 / 255);
    expect(adjusted.b, 1);
    expect(adjusted.colorSpace, ColorSpace.sRGB);
  });

  test('byte opacity retains the opacity range contract', () {
    for (final opacity in [-0.01, 1.01, double.nan, double.infinity]) {
      expect(() => Colors.white.withByteOpacity(opacity), throwsAssertionError);
    }
  });

  test('Material 3 roles and explicit surface paints retain their existing colors', () {
    for (final scale in [0.8, 1.0, 1.2]) {
      final theme = ObsidianTheme.build(scale: scale);
      final colors = theme.colorScheme;

      expect(theme.useMaterial3, isTrue);
      expect(colors.surface, const Color(0xFF0A0A0D));
      expect(colors.onSurface, const Color(0xFFF2F2F2));
      expect(colors.primary, const Color(0xFFFFD700));
      expect(colors.secondary, const Color(0x4DFFD700));

      for (final surface in [
        colors.surfaceDim,
        colors.surfaceBright,
        colors.surfaceContainerLowest,
        colors.surfaceContainerLow,
        colors.surfaceContainer,
        colors.surfaceContainerHigh,
        colors.surfaceContainerHighest,
      ]) {
        expect(surface, const Color(0xFF0A0A0D));
      }

      expect(theme.canvasColor, const Color(0xFF050505));
      expect(theme.scaffoldBackgroundColor, Colors.transparent);
      expect(theme.cardColor, const Color(0xFF0A0A0D));
      expect(theme.chipTheme.backgroundColor, const Color(0x99121214));
      expect(theme.dialogTheme.backgroundColor, const Color(0xE60A0A0D));
      expect(theme.navigationRailTheme.backgroundColor, const Color(0x59050505));
      expect(theme.navigationBarTheme.backgroundColor, const Color(0xEB0A0A0D));
      expect(theme.sliderTheme.inactiveTrackColor, const Color(0x338A8A9A));
    }
  });

  testWidgets('Material 3 card and snackbar retain their painted surface defaults', (tester) async {
    const cardKey = ValueKey('contract-card');
    final messengerKey = GlobalKey<ScaffoldMessengerState>();

    await tester.pumpWidget(
      MaterialApp(
        theme: ObsidianTheme.build(),
        scaffoldMessengerKey: messengerKey,
        home: const Scaffold(
          body: Card(key: cardKey, child: Text('Surface')),
        ),
      ),
    );

    final cardMaterial = tester.widget<Material>(
      find.descendant(of: find.byKey(cardKey), matching: find.byType(Material)).first,
    );

    expect(cardMaterial.color, const Color(0xFF0A0A0D));

    messengerKey.currentState!.showSnackBar(const SnackBar(content: Text('Message')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final snackbarMaterial = tester.widget<Material>(
      find.descendant(of: find.byType(SnackBar), matching: find.byType(Material)).first,
    );

    expect(snackbarMaterial.color, const Color(0xFFF2F2F2));

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
