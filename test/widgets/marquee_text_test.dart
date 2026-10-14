import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/widgets/ui/marquee_text.dart';

void main() {
  const text = 'A reasonably long artist - Album';
  const style = TextStyle(fontSize: 12);
  final painter = TextPainter(
    text: const TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  final width = painter.width + 5;
  painter.dispose();

  for (final layout in [
    (spacing: 2.0, scale: 1.0),
    (spacing: 0.0, scale: 1.6),
  ]) {
    testWidgets(
      'overflow scrolls with spacing ${layout.spacing} and text scale ${layout.scale}',
      (tester) async {
        await tester.pumpWidget(
          _fixture(
            text: text,
            width: width,
            spacing: layout.spacing,
            textScale: layout.scale,
          ),
        );
        final scroll = find.byType(Scrollable);
        expect(scroll, findsOneWidget);
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 800));
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          tester.state<ScrollableState>(scroll).position.pixels,
          greaterThan(0),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('text that fits stays stationary', (tester) async {
    await tester.pumpWidget(_fixture(text: 'Artist - Album', width: 600));
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(Scrollable), findsNothing);
    expect(find.text('Artist - Album'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('marquee responds to resizing and stops when text fits', (
    tester,
  ) async {
    await tester.pumpWidget(_fixture(text: text, width: 100));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
      greaterThan(0),
    );

    await tester.pumpWidget(_fixture(text: text, width: 700));
    expect(find.byType(Scrollable), findsNothing);
    await tester.pumpWidget(_fixture(text: text, width: 100));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
      greaterThan(0),
    );
    await tester.pumpWidget(_fixture(text: 'Short', width: 100));
    expect(find.byType(Scrollable), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}

Widget _fixture({
  required String text,
  required double width,
  double spacing = 0,
  double textScale = 1,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: DefaultTextStyle(
      style: TextStyle(fontFamily: 'Ahem', letterSpacing: spacing),
      child: Center(
        child: SizedBox(
          width: width,
          child: MarqueeText(text: text, style: const TextStyle(fontSize: 12)),
        ),
      ),
    ),
  ),
);
