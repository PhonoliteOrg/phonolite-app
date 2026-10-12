import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/entities/metadata_event_listener.dart';
import 'package:phonolite_app/entities/models.dart';

MetadataUpdateEvent event(String id, int revision, {String kind = 'album'}) =>
    MetadataUpdateEvent(revision: revision, kind: kind, id: id, updatedAt: 0);

void main() {
  testWidgets('coalesces identities and applies updates in revision order', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.start();
    harness.input.add(event('a', 1));
    harness.input.add(event('b', 2));
    harness.input.add(event('a', 4));
    harness.input.add(event('a', 3, kind: 'artist'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 249));
    expect(harness.applied, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(harness.applied.map((e) => e.revision), [2, 3, 4]);
  });

  testWidgets(
    'keeps one subscription and reconnects only for the active session',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      harness.start();
      harness.start();
      expect(harness.streams, hasLength(1));
      await harness.input.close();
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(harness.streams, hasLength(2));
      harness.input.addError(StateError('disconnected'));
      await tester.pump();
      harness.authorized = false;
      await tester.pump(const Duration(seconds: 3));
      expect(harness.streams, hasLength(2));
      expect(harness.diagnostics.single, contains('disconnected'));
    },
  );

  testWidgets('stop cancels pending updates and reconnects', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.start();
    harness.input.add(event('a', 1));
    await tester.pump();
    await harness.input.close();
    await tester.pump();
    harness.listener.stop();
    await tester.pump(const Duration(seconds: 4));
    expect(harness.applied, isEmpty);
    expect(harness.streams, hasLength(1));
  });

  testWidgets(
    'a new session discards the old batch without overlapping application',
    (tester) async {
      final blocked = Completer<void>();
      final started = <String>[];
      final harness = _Harness(
        apply: (event) async {
          started.add(event.id);
          if (event.id == 'old-first') await blocked.future;
        },
      );
      addTearDown(harness.dispose);
      harness.start();
      harness.input.add(event('old-first', 1));
      harness.input.add(event('old-second', 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      harness.token = 'new-token';
      harness.start();
      harness.input.add(event('new', 3));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(started, ['old-first']);
      blocked.complete();
      await tester.pump();
      expect(started, ['old-first', 'new']);
    },
  );

  testWidgets('a failed refresh does not prevent later updates', (
    tester,
  ) async {
    final seen = <String>[];
    final harness = _Harness(
      apply: (event) async {
        seen.add(event.id);
        if (event.id == 'bad') throw StateError('refresh failure');
      },
    );
    addTearDown(harness.dispose);
    harness.start();
    harness.input.add(event('bad', 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    harness.input.add(event('good', 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(seen, ['bad', 'good']);
    expect(harness.diagnostics.single, contains('refresh failure'));
  });
}

class _Harness {
  _Harness({Future<void> Function(MetadataUpdateEvent)? apply}) {
    listener = MetadataEventListener(
      openStream: () {
        final controller = StreamController<MetadataUpdateEvent>();
        streams.add(controller);
        return controller.stream;
      },
      isSessionCurrent: (url, credential) =>
          authorized && url == 'server' && credential == token,
      applyEvent:
          apply ??
          (event) async {
            applied.add(event);
          },
      onDiagnostic: diagnostics.add,
    );
  }
  final streams = <StreamController<MetadataUpdateEvent>>[];
  final applied = <MetadataUpdateEvent>[];
  final diagnostics = <String>[];
  late final MetadataEventListener listener;
  String token = 'token';
  bool authorized = true;
  StreamController<MetadataUpdateEvent> get input => streams.last;
  void start() => listener.start(baseUrl: 'server', token: token);
  Future<void> dispose() async {
    listener.stop();
    for (final stream in streams) {
      if (!stream.isClosed) await stream.close();
    }
  }
}
