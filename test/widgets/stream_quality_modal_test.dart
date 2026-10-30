import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/data/models/playback/playback_state.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_labels.dart';
import 'package:phonolite_app/ui/features/playback/widgets/modals/stream_quality_modal.dart';

import '../support/widget_test_helpers.dart';

void main() {
  setUpAll(configureTestFonts);

  testWidgets('chooser shows bitrate targets and selects Original with an OG badge', (tester) async {
    var current = StreamMode.high;
    var selections = 0;

    await tester.pumpWidget(
      wrapInTestApp(
        StatefulBuilder(
          builder: (context, setState) => TextButton(
            onPressed: () => playbackShowStreamModal(
              context,
              current: current,
              onSelected: (mode) => setState(() {
                current = mode;
                selections++;
              }),
            ),
            child: Text(playbackStreamLabel(current)),
          ),
        ),
      ),
    );

    await tester.tap(find.text('HQ'));
    await tester.pumpAndSettle();

    expect(find.text('Original (source-preserving · QUIC)'), findsOneWidget);
    expect(find.text('High quality (160 kbps)'), findsOneWidget);
    expect(find.text('Medium quality (96 kbps)'), findsOneWidget);
    expect(find.text('Low quality (48 kbps)'), findsOneWidget);

    await tester.tap(find.text('Original (source-preserving · QUIC)'));
    await tester.pumpAndSettle();

    expect(current, StreamMode.original);
    expect(find.text('OG'), findsOneWidget);
    expect(selections, 1);

    await tester.tap(find.text('OG'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Original (source-preserving · QUIC)'));
    await tester.pumpAndSettle();

    expect(selections, 1);
    expect(tester.takeException(), isNull);
  });
}
