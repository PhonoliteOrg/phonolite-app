import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/widgets/ui/marquee_text.dart';

void main() {
  testWidgets('unchanged parent rebuilds reuse text measurement', (
    tester,
  ) async {
    final scaler = _CountingTextScaler(1);
    Widget fixture() =>
        _fixture(text: 'Short title', width: 600, textScaler: scaler);
    await tester.pumpWidget(fixture());
    scaler.calls = 0;
    for (var n = 0; n < 5; n++) {
      await tester.pumpWidget(fixture());
    }
    final repeatedMeasurementCalls = scaler.calls;
    debugPrint(
      'Text scaling calls across five unchanged builds: $repeatedMeasurementCalls',
    );
    expect(find.text('Short title'), findsOneWidget);
    expect(find.byType(Scrollable), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(repeatedMeasurementCalls, 0);
  });

  testWidgets('measurement follows text, style, scaling, locale and fonts', (
    tester,
  ) async {
    final scaler = _CountingTextScaler(1);
    Future<void> pump({
      String text = 'Short',
      double spacing = 0,
      bool bold = false,
      TextDirection direction = TextDirection.ltr,
      Locale locale = const Locale('en'),
      TextScaler? textScaler,
    }) async {
      await tester.pumpWidget(
        Localizations(
          locale: locale,
          delegates: const [DefaultWidgetsLocalizations.delegate],
          child: _fixture(
            text: text,
            width: 600,
            spacing: spacing,
            bold: bold,
            direction: direction,
            textScaler: textScaler ?? scaler,
          ),
        ),
      );
    }

    await pump();
    for (final update in <Future<void> Function()>[
      () => pump(text: 'Different title'),
      () => pump(text: 'Different title', spacing: 2),
      () => pump(bold: true),
      () => pump(direction: TextDirection.rtl),
      () => pump(locale: const Locale('ar')),
    ]) {
      await pump();
      scaler.calls = 0;
      await update();
      expect(scaler.calls, greaterThan(0));
    }
    final enlarged = _CountingTextScaler(1.6);
    await pump(textScaler: enlarged);
    expect(enlarged.calls, greaterThan(0));
    enlarged.calls = 0;
    await pump(textScaler: enlarged);
    expect(enlarged.calls, 0);
    await _notifyFontsChanged(tester);
    await tester.pumpAndSettle();
    expect(enlarged.calls, greaterThan(0));
    await tester.pumpWidget(const SizedBox.shrink());
    await _notifyFontsChanged(tester);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('unchanged rebuilds preserve a running scroll', (tester) async {
    Widget fixture() =>
        _fixture(text: 'A long artist and album title', width: 100);
    await tester.pumpWidget(fixture());
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 500));
    final scroll = find.byType(Scrollable);
    final before = tester.state<ScrollableState>(scroll).position.pixels;
    expect(before, greaterThan(0));
    for (var n = 0; n < 5; n++) {
      await tester.pumpWidget(fixture());
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      tester.state<ScrollableState>(scroll).position.pixels,
      greaterThan(before),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

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
  TextScaler? textScaler,
  bool bold = false,
  TextDirection direction = TextDirection.ltr,
}) => Directionality(
  textDirection: direction,
  child: MediaQuery(
    data: MediaQueryData(
      textScaler: textScaler ?? TextScaler.linear(textScale),
      boldText: bold,
    ),
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

class _CountingTextScaler extends TextScaler {
  _CountingTextScaler(this.factor);

  final double factor;
  final List<int> _calls = [0];
  int get calls => _calls[0];
  set calls(int value) => _calls[0] = value;

  @override
  double scale(double fontSize) {
    calls++;
    return fontSize * factor;
  }

  @override
  double get textScaleFactor => factor;
}

Future<void> _notifyFontsChanged(WidgetTester tester) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/system',
    const JSONMessageCodec().encodeMessage({'type': 'fontsChange'}),
    null,
  );
}
