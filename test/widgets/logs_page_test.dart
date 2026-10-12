import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/entities/app_controller.dart';
import 'package:phonolite_app/entities/app_log.dart';
import 'package:phonolite_app/pages/logs_page.dart';
import 'package:phonolite_app/widgets/display/message_log.dart';
import 'package:phonolite_app/widgets/layouts/app_scope.dart';

import '../support/widget_test_helpers.dart';

class LogsController extends Fake implements AppController {
  final entries = <LogEntry>[];
  final updates = StreamController<List<LogEntry>>.broadcast();
  int clears = 0;

  @override
  List<LogEntry> get messages => List.unmodifiable(entries);

  @override
  Stream<List<LogEntry>> get messageStream => updates.stream;

  void add(String message, LogLevel level) {
    entries.add(LogEntry(message: message, level: level));
    updates.add(messages);
  }

  @override
  Future<void> clearMessages() async {
    clears++;
    entries.clear();
    updates.add(messages);
  }

  @override
  Future<void> close() => updates.close();
}

class CountingLogEntry extends LogEntry {
  CountingLogEntry(int index)
    : super(message: 'entry-$index', level: LogLevel.info);

  int formats = 0;

  @override
  String format() {
    formats++;
    return super.format();
  }
}

void main() {
  setUp(configureTestFonts);

  testWidgets(
    '3000 entries build lazily and Copy All includes offscreen history',
    (tester) async {
      final entries = List.generate(3000, CountingLogEntry.new);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(wrapInTestApp(MessageLog(messages: entries)));
      await tester.pumpAndSettle();
      expect(find.byType(SelectableText).evaluate().length, lessThan(50));
      expect(entries.first.formats, 0);
      expect(entries.last.formats, greaterThan(0));
      expect(entries.where((entry) => entry.formats > 0).length, lessThan(50));
      expect(tester.takeException(), isNull);

      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      scrollable.position.jumpTo(1500);
      await tester.pumpAndSettle();
      expect(find.byType(SelectableText).evaluate().length, lessThan(50));
      expect(entries.first.formats, 0);

      await tester.tap(find.text('Copy All'));
      await tester.pumpAndSettle();
      final copiedLines = copied!.split('\n');
      expect(copiedLines, hasLength(3000));
      expect(copiedLines.first, endsWith('entry-2999'));
      expect(copiedLines.last, endsWith('entry-0'));
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(MaterialBanner), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'categories filter live messages and Clear clears all on mobile',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = LogsController();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        final closing = controller.close();
        await tester.pump();
        await closing;
      });
      controller.add('info only', LogLevel.info);
      controller.add('warning only', LogLevel.warning);
      controller.add('error only', LogLevel.error);

      final logLines = find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText &&
            widget.data != null &&
            widget.data!.contains('only'),
      );
      await tester.pumpWidget(
        wrapInTestApp(
          AppScope(controller: controller, child: const LogsPage()),
        ),
      );
      expect(logLines, findsNWidgets(3));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(DropdownButton<LogCategory>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Issues').last);
      await tester.pumpAndSettle();
      expect(logLines, findsNWidgets(2));
      controller.add('new warning only', LogLevel.warning);
      await tester.pumpAndSettle();
      expect(find.text('issues.log • 3 entries'), findsOneWidget);
      expect(find.textContaining('new warning only'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byWidgetPredicate(
          (widget) =>
              widget is SelectableText &&
              widget.data?.endsWith('[WARN] warning only') == true,
        ),
        100,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(controller.clears, 1);
      expect(controller.entries, isEmpty);
      expect(logLines, findsNothing);
      expect(find.text('No events yet'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
