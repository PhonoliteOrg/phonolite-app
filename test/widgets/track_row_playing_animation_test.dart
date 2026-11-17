import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/ui/shared/music/tracks/track_row_tile.dart';

import '../support/widget_test_helpers.dart';

void main() {
  testWidgets(
    'idle row starts independent playing bars, then stops and resumes',
    (tester) async {
      await _pumpRow(tester, isPlaying: false);
      await tester.pumpAndSettle();
      expect(_barHeights(tester), isEmpty);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await _pumpRow(tester, isPlaying: true);
      final before = _barHeights(tester);
      expect(before, hasLength(3));

      await tester.pump(const Duration(milliseconds: 150));
      final after = _barHeights(tester);
      final changes = [for (var i = 0; i < 3; i++) after[i] - before[i]];
      // A scaled static icon cannot move some bars up while others move down.
      expect(changes.any((change) => change > 0), isTrue);
      expect(changes.any((change) => change < 0), isTrue);

      await _pumpRow(tester, isPlaying: false);
      await tester.pumpAndSettle();
      expect(_barHeights(tester), isEmpty);
      expect(find.text('01'), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isFalse);

      await _pumpRow(tester, isPlaying: true);
      final resumed = _barHeights(tester);
      expect(resumed, hasLength(3));
      await tester.pump(const Duration(milliseconds: 150));
      expect(_barHeights(tester), isNot(equals(resumed)));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Future<void> _pumpRow(WidgetTester tester, {required bool isPlaying}) async {
  await tester.pumpWidget(
    wrapInTestApp(
      TrackRowTile(
        track: Track(
          id: 'animation-track',
          title: 'Playing track',
          artist: 'Artist',
          album: 'Album',
          durationMs: 180000,
          liked: false,
          inPlaylists: false,
        ),
        index: 1,
        isPlaying: isPlaying,
      ),
    ),
  );
}

/// Heights of the now-playing bars as the row's painters currently draw them.
List<double> _barHeights(WidgetTester tester) {
  const barColor = Color(0xFFFFA33A);
  final heights = <double>[];
  final painters = find.descendant(of: find.byType(TrackRowTile), matching: find.byType(CustomPaint));

  for (final element in painters.evaluate()) {
    final renderObject = element.renderObject! as RenderCustomPaint;
    final painter = renderObject.painter;

    if (painter == null) {
      continue;
    }

    final canvas = TestRecordingCanvas();
    painter.paint(canvas, renderObject.size);

    for (final recorded in canvas.invocations) {
      final invocation = recorded.invocation;

      if (invocation.memberName == #drawRRect &&
          (invocation.positionalArguments[1] as Paint).color.toARGB32() == barColor.toARGB32()) {
        heights.add((invocation.positionalArguments[0] as RRect).height);
      }
    }
  }

  return heights;
}
