import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/application/playback/playback_presence_reporter.dart';
import 'package:phonolite_app/data/models/server/server_errors.dart';

void main() {
  testWidgets('presence is idle until playback, heartbeats, and stops immediately on pause and close', (tester) async {
    final reports = <(String, int, bool)>[];
    final reporter = PlaybackPresenceReporter(
      clientId: 'device',
      send: (id, sequence, playing) async => reports.add((id, sequence, playing)),
    );
    await tester.pump(const Duration(seconds: 20));
    expect(reports, isEmpty);
    reporter.update(true);
    await tester.pump();
    expect(reports, [('device', 1, true)]);
    reporter.update(true);
    await tester.pump(const Duration(seconds: 5));
    expect(reports.last, ('device', 2, true));
    reporter.update(false);
    await tester.pump();
    expect(reports.last, ('device', 3, false));
    await tester.pump(const Duration(seconds: 20));
    expect(reports, hasLength(3));
    reporter.update(true);
    await tester.pump();
    await reporter.close();
    expect(reports.last, ('device', 5, false));
    reporter.update(true);
    await tester.pump(const Duration(seconds: 20));
    expect(reports, hasLength(5));
  });

  testWidgets('only one request runs and rapid state changes replace one queued report', (tester) async {
    final gate = Completer<void>();
    final reports = <(int, bool)>[];
    final reporter = PlaybackPresenceReporter(
      clientId: 'device',
      send: (id, sequence, playing) {
        reports.add((sequence, playing));
        return sequence == 1 ? gate.future : Future<void>.value();
      },
    );
    reporter.update(true);
    reporter.update(false);
    reporter.update(true);
    reporter.update(false);
    expect(reports, [(1, true)]);
    gate.complete();
    await tester.pump();
    expect(reports, [(1, true), (4, false)]);
    await reporter.close();
  });

  testWidgets('timeouts are bounded and do not block a queued stop or leak heartbeat timers', (tester) async {
    final reports = <(int, bool)>[];
    final reporter = PlaybackPresenceReporter(
      clientId: 'device',
      send: (id, sequence, playing) {
        reports.add((sequence, playing));
        return playing ? Completer<void>().future : Future<void>.value();
      },
    );
    reporter.update(true);
    reporter.update(false);
    await tester.pump(const Duration(seconds: 3));
    expect(reports, [(1, true), (2, false)]);
    await reporter.close();
    await tester.pump(const Duration(seconds: 20));
    expect(reports, hasLength(2));
  });

  testWidgets('temporary failures recover at heartbeat and old servers disable reporting', (tester) async {
    var calls = 0;
    final reporter = PlaybackPresenceReporter(
      clientId: 'device',
      send: (id, sequence, playing) async {
        calls++;
        if (calls == 1) throw StateError('offline');
        throw ApiException(404, 'older server');
      },
    );
    reporter.update(true);
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(calls, 2);
    reporter.update(false);
    reporter.update(true);
    await tester.pump(const Duration(seconds: 30));
    expect(calls, 2);
    await reporter.close();
  });

  testWidgets('replacement sessions retain device identity and sequence ordering across late stops', (tester) async {
    var sequence = 0;
    final gate = Completer<void>();
    final reports = <(int, bool)>[];
    final old = PlaybackPresenceReporter(
      clientId: 'device',
      nextSequence: () => ++sequence,
      send: (id, seq, playing) {
        reports.add((seq, playing));
        return seq == 1 ? gate.future : Future<void>.value();
      },
    );
    old.update(true);
    final closing = old.close();
    final current = PlaybackPresenceReporter(
      clientId: 'device',
      nextSequence: () => ++sequence,
      send: (id, seq, playing) async => reports.add((seq, playing)),
    );
    current.update(true);
    await tester.pump();
    gate.complete();
    await tester.pump();
    await closing;
    expect(reports, [(1, true), (3, true), (2, false)]);
    await current.close();
  });
}
