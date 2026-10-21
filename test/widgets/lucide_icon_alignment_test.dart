import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';

void main() {
  testWidgets('every bundled Lucide glyph paints in the center of its icon', (
    tester,
  ) async {
    final loader = FontLoader(PhonoliteIcons.fontFamily)
      ..addFont(rootBundle.load('assets/icons/lucide/PhonoliteLucide.ttf'));
    await loader.load();
    final manifest =
        jsonDecode(
              await rootBundle.loadString('assets/icons/lucide/manifest.json'),
            )
            as Map<String, dynamic>;
    final icons = manifest['icons'] as Map<String, dynamic>;

    const iconSize = 40.0;
    const pixelRatio = 4.0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: Wrap(
            children: [
              for (final entry in icons.entries)
                RepaintBoundary(
                  key: ValueKey(entry.key),
                  child: Icon(
                    IconData(
                      entry.value['codepoint'] as int,
                      fontFamily: PhonoliteIcons.fontFamily,
                    ),
                    size: iconSize,
                    color: const Color(0xFFFFFFFF),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    for (final name in icons.keys) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(ValueKey(name)),
      );
      final paintedBounds = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: pixelRatio);
        try {
          final pixels = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          var left = image.width;
          var right = -1;
          var top = image.height;
          var bottom = -1;
          for (var y = 0; y < image.height; y++) {
            for (var x = 0; x < image.width; x++) {
              if (pixels.getUint8((y * image.width + x) * 4 + 3) < 32) {
                continue;
              }
              if (x < left) left = x;
              if (x > right) right = x;
              if (y < top) top = y;
              if (y > bottom) bottom = y;
            }
          }
          expect(right, greaterThanOrEqualTo(left), reason: '$name is visible');
          return Rect.fromLTRB(
            left / pixelRatio,
            top / pixelRatio,
            (right + 1) / pixelRatio,
            (bottom + 1) / pixelRatio,
          );
        } finally {
          image.dispose();
        }
      });
      expect(
        paintedBounds!.center.dx,
        closeTo(iconSize / 2, 0.5),
        reason: '$name horizontal paint alignment',
      );
      expect(
        paintedBounds.center.dy,
        closeTo(iconSize / 2, 0.5),
        reason: '$name vertical paint alignment',
      );
    }
    expect(tester.takeException(), isNull);
  });
}
