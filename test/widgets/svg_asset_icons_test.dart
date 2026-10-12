import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/widgets/ui/edit_icon.dart';
import 'package:phonolite_app/widgets/ui/playlist_add_icon.dart';
import 'package:phonolite_app/widgets/ui/playlist_edit_icon.dart';
import 'package:phonolite_app/widgets/ui/playlist_icon.dart';
import 'package:phonolite_app/widgets/ui/reload_icon.dart';
import 'package:phonolite_app/widgets/ui/server_icon.dart';
import 'package:phonolite_app/widgets/ui/stats_icon.dart';

void main() {
  const icons = {
    'playlist': PlaylistIcon(),
    'playlist add': PlaylistAddIcon(),
    'playlist edit': PlaylistEditIcon(),
    'stats': StatsIcon(),
    'stats device reset': StatsIcon.deviceReset(),
    'stats account reset': StatsIcon.accountReset(),
    'server': ServerIcon(),
    'reload': ReloadIcon(),
    'edit': EditIcon(),
  };

  for (final entry in icons.entries) {
    testWidgets('${entry.key} SVG loads and follows icon theme changes', (
      tester,
    ) async {
      const boundaryKey = ValueKey('icon');
      for (final theme in const [
        IconThemeData(size: 40, color: Color(0xFF3366CC), opacity: 0.5),
        IconThemeData(size: 24, color: Color(0xFFFF0000), opacity: 1),
      ]) {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: IconTheme(
                data: theme,
                child: RepaintBoundary(key: boundaryKey, child: entry.value),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final boundary = find.byKey(boundaryKey);
        expect(tester.getSize(boundary), Size.square(theme.size!));

        final pixels = await _capturePixels(tester, boundary);
        var brightest = 0;
        for (var offset = 0; offset < pixels.length; offset += 4) {
          if (pixels[offset + 3] > pixels[brightest + 3]) {
            brightest = offset;
          }
        }
        final color = theme.color!;
        expect(pixels[brightest], closeTo(color.r * 255, 2));
        expect(pixels[brightest + 1], closeTo(color.g * 255, 2));
        expect(pixels[brightest + 2], closeTo(color.b * 255, 2));
        expect(pixels[brightest + 3], closeTo(theme.opacity! * 255, 1));
      }
    });
  }

  testWidgets('SVG icon glow paints outside the icon without changing layout', (
    tester,
  ) async {
    const boundaryKey = ValueKey('glow');
    const iconKey = ValueKey('reload');
    for (final highlighted in [false, true]) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: IconTheme(
                  data: IconThemeData(
                    size: 24,
                    color: const Color(0xFFFF0000),
                    shadows: [
                      if (highlighted)
                        const Shadow(
                          color: Color(0xFF00FF00),
                          offset: Offset(16, 0),
                          blurRadius: 4,
                        ),
                    ],
                  ),
                  child: const ReloadIcon(key: iconKey),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byKey(iconKey)), const Size.square(24));
      final pixels = await _capturePixels(tester, find.byKey(boundaryKey));
      var glowOutsideIcon = false;
      for (var y = 0; y < 72; y++) {
        for (var x = 48; x < 72; x++) {
          final offset = (y * 72 + x) * 4;
          if (pixels[offset + 1] > 200 && pixels[offset + 3] > 5) {
            glowOutsideIcon = true;
          }
        }
      }
      expect(glowOutsideIcon, highlighted);
    }
  });

  testWidgets('Stats keeps its explicit size inside a larger icon theme', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: IconTheme(
            data: IconThemeData(size: 40),
            child: StatsIcon(size: 20),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(StatsIcon)), const Size.square(20));
    expect(tester.takeException(), isNull);
  });
}

Future<Uint8List> _capturePixels(WidgetTester tester, Finder finder) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(finder);
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      ))!;
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  }))!;
}
