import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/widgets/layouts/obsidian_viewport.dart';
import 'package:phonolite_app/widgets/ui/obsidian_theme.dart';

import '../support/widget_test_helpers.dart';

void main() {
  setUp(configureTestFonts);

  testWidgets(
    'outgoing page clears and incoming content updates during transition',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 400);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final navigator = GlobalKey<NavigatorState>();
      final boundary = GlobalKey();
      final incomingColor = ValueNotifier<Color>(const Color(0xFF00FF00));
      addTearDown(incomingColor.dispose);

      Widget page(Color color, Alignment alignment) => Scaffold(
        body: Align(
          alignment: alignment,
          child: ColoredBox(
            color: color,
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ObsidianTheme.build(),
          themeAnimationStyle: AnimationStyle.noAnimation,
          builder: (context, child) => RepaintBoundary(
            key: boundary,
            child: ObsidianViewport(child: child!),
          ),
          home: Navigator(
            key: navigator,
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) =>
                  page(const Color(0xFFFF0000), Alignment.centerLeft),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_countColor(await _capture(tester, boundary), 0), greaterThan(0));

      final route = MaterialPageRoute<void>(
        builder: (_) => ValueListenableBuilder<Color>(
          valueListenable: incomingColor,
          builder: (_, color, _) => page(color, Alignment.centerRight),
        ),
      );
      navigator.currentState!.push<void>(route);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(route.animation!.value, inExclusiveRange(0, 1));
      final duringPush = await _capture(tester, boundary);
      expect(
        _countColor(duringPush, 0),
        0,
        reason: 'Old page must fade out early',
      );
      expect(_countColor(duringPush, 1), greaterThan(0));

      incomingColor.value = const Color(0xFF0000FF);
      await tester.pump(const Duration(milliseconds: 16));
      expect(route.animation!.value, lessThan(1));
      final updated = await _capture(tester, boundary);
      expect(_countColor(updated, 1), 0);
      expect(_countColor(updated, 2), greaterThan(0));
      await tester.pumpAndSettle();

      navigator.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(route.animation!.value, inExclusiveRange(0, 1));
      final duringPop = await _capture(tester, boundary);
      expect(_countColor(duringPop, 2), 0);
      expect(_countColor(duringPop, 0), greaterThan(0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.fuchsia,
      TargetPlatform.linux,
      TargetPlatform.windows,
    }),
  );
}

Future<Uint8List> _capture(WidgetTester tester, GlobalKey key) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
    } finally {
      image.dispose();
    }
  }))!;
}

int _countColor(Uint8List pixels, int channel) {
  var count = 0;
  for (var offset = 0; offset < pixels.length; offset += 4) {
    if (pixels[offset + channel] > 40 &&
        pixels[offset + (channel + 1) % 3] < 16 &&
        pixels[offset + (channel + 2) % 3] < 16) {
      count++;
    }
  }
  return count;
}
