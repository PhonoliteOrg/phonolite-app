import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/edit_icon.dart';
import 'package:phonolite_app/ui/shared/music/like_icon_button.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_widgets.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/playlist_add_icon.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/playlist_edit_icon.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/playlist_icon.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/reload_icon.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/server_icon.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/stats_icon.dart';

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

  testWidgets('liked hearts paint a filled interior', (tester) async {
    final loader = FontLoader(PhonoliteIcons.fontFamily)
      ..addFont(rootBundle.load('assets/icons/lucide/PhonoliteLucide.ttf'));
    await loader.load();
    const key = ValueKey('heart');
    for (final liked in [false, true]) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: key,
              child: LikeIconButton(isLiked: liked, size: 40),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final finder = find.byKey(key);
      final pixels = await _capturePixels(tester, finder);
      final dimension = tester.getSize(finder).width.toInt();
      final center = dimension ~/ 2;
      final centerAlpha = pixels[(center * dimension + center) * 4 + 3];
      expect(centerAlpha > 100, liked);
      expect(tester.takeException(), isNull);
    }
  });

  for (final width in [390.0, 1280.0]) {
    testWidgets('playlist control matches neighboring icons at width $width', (
      tester,
    ) async {
      final loader = FontLoader(PhonoliteIcons.fontFamily)
        ..addFont(rootBundle.load('assets/icons/lucide/PhonoliteLucide.ttf'));
      await loader.load();
      final size = width < 820 ? 22.0 : 26.0;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: MediaQueryData(size: Size(width, 800)),
            child: ObsidianModalScope(
              builder: (context) => Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RepaintBoundary(
                      key: const ValueKey('playlist'),
                      child: ObsidianHudIconButton(
                        iconWidget: const PlaylistAddIcon(),
                        size: size,
                      ),
                    ),
                    RepaintBoundary(
                      key: const ValueKey('heart'),
                      child: LikeIconButton(isLiked: false, size: size),
                    ),
                    RepaintBoundary(
                      key: const ValueKey('device'),
                      child: ObsidianHudIconButton(
                        icon: PhonoliteIcons.speaker,
                        size: size,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final painted = <String, Rect>{};
      final buttonSize = Size.square(width < 820 ? 48 : size + 16);
      for (final name in ['playlist', 'heart', 'device']) {
        final finder = find.byKey(ValueKey(name));
        expect(tester.getSize(finder), buttonSize);
        painted[name] = await _paintedBounds(tester, finder);
      }
      final playlist = painted['playlist']!;
      final playlistExtent = playlist.size.longestSide;
      for (final name in ['heart', 'device']) {
        expect(
          playlistExtent,
          closeTo(painted[name]!.size.longestSide, 1.25),
          reason: 'playlist artwork matches the visible $name size',
        );
      }
      expect(playlist.center.dx, closeTo(buttonSize.width / 2, 0.75));
      expect(playlist.center.dy, closeTo(buttonSize.height / 2, 0.75));
      expect(tester.takeException(), isNull);
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

Future<Rect> _paintedBounds(WidgetTester tester, Finder finder) async {
  final pixels = await _capturePixels(tester, finder);
  final size = tester.getSize(finder);
  var left = size.width.toInt();
  var top = size.height.toInt();
  var right = 0;
  var bottom = 0;
  for (var y = 0; y < size.height.toInt(); y++) {
    for (var x = 0; x < size.width.toInt(); x++) {
      if (pixels[(y * size.width.toInt() + x) * 4 + 3] < 32) continue;
      if (x < left) left = x;
      if (y < top) top = y;
      if (x > right) right = x;
      if (y > bottom) bottom = y;
    }
  }
  return Rect.fromLTRB(
    left.toDouble(),
    top.toDouble(),
    right + 1.0,
    bottom + 1.0,
  );
}
