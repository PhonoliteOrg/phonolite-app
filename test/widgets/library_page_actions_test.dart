import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/data/models/diagnostics/log_entry.dart';
import 'package:phonolite_app/data/models/downloads/offline_deletion.dart';
import 'package:phonolite_app/data/storage/logs/app_log.dart';
import 'package:phonolite_app/pages/library/library_page.dart';
import 'package:phonolite_app/ui/app_scope.dart';

import '../support/page_test_controller.dart';
import '../support/widget_test_helpers.dart';

void main() {
  testWidgets('the Download Manager action opens the Download Manager panel', (tester) async {
    final app = PageTestController();
    await _pumpLibrary(tester, app);

    expect(find.text('Pause all'), findsNothing);
    await tester.tap(find.byTooltip('Download Manager'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.descendant(of: find.byType(Dialog), matching: find.text('Download Manager')), findsOneWidget);
    expect(find.byTooltip('Pause all'), findsOneWidget);

    await _dispose(tester, app);
  });

  for (final fails in [false, true]) {
    testWidgets(
      'offline edit mode removes the selected artist after confirmation${fails ? ' and logs a failure' : ''}',
      (tester) async {
        final app = PageTestController()
          ..downloadedTracks = [
            downloadedPageTrack('a1'),
            downloadedPageTrack('a2', album: 'Album 2'),
            downloadedPageTrack('b1', artist: 'Artist B', album: 'Album B'),
          ];
        if (fails) {
          app.removalError = StateError('disk busy');
        }
        final logged = <LogEntry>[];
        AppLogger.instance.attach(logged.add, includeHistory: false);
        addTearDown(() => AppLogger.instance.detach(logged.add));
        await _pumpLibrary(tester, app);

        await tester.tap(find.byTooltip('Edit'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Artist A'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Remove selected'));
        await tester.pumpAndSettle();

        expect(find.text('Remove download'), findsOneWidget);
        expect(find.textContaining('Remove 2 downloads for Artist A from this device?'), findsOneWidget);

        await tester.tap(find.text('CANCEL'));
        await tester.pumpAndSettle();
        expect(find.text('Remove download'), findsNothing);
        expect(app.removals, isEmpty);

        await tester.tap(find.byTooltip('Remove selected'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('REMOVE'));
        await tester.pumpAndSettle();

        final removal = app.removals.single;
        expect(removal.trackIds, unorderedEquals(['a1', 'a2']));
        expect(removal.label, 'Artist A');
        expect(removal.scope.kind, OfflineDeletionScopeKind.artist);
        expect(removal.scope.ids, ['artist-artist-a']);
        expect(find.byTooltip('Remove selected'), findsNothing, reason: 'The selection is cleared.');
        expect(find.byTooltip('Edit'), findsOneWidget);

        final warnings = logged.where((entry) => entry.level == LogLevel.warning).map((entry) => entry.message);
        expect(warnings, fails ? [contains('Failed to remove Artist A')] : isEmpty);

        await _dispose(tester, app);
      },
    );
  }
}

Future<void> _pumpLibrary(WidgetTester tester, PageTestController app) async {
  tester.view.physicalSize = const Size(1000, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final display = await memoryDisplaySettings();
  addTearDown(display.dispose);

  await tester.pumpWidget(
    AppScope(
      controller: app,
      child: wrapInTestApp(LibraryPage(displaySettings: display)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _dispose(WidgetTester tester, PageTestController app) async {
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox.shrink());
  await app.close();
}
