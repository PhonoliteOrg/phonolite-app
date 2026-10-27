import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/application/collections/account_collection_sync.dart';
import 'package:phonolite_app/data/models/collections/account_collection_event.dart';
import 'package:phonolite_app/data/models/collections/account_collection_snapshot.dart';
import 'package:phonolite_app/data/models/server/server_errors.dart';

void main() {
  _syncTest('waits for subscription ready and reconciles duplicate or reversed notifications once', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.start();
    harness.input.add(_changed(4));
    await tester.pump(const Duration(seconds: 1));
    expect(harness.reads, 0);

    harness.revision = 4;
    harness.input.add(_ready(4));
    await tester.pump();
    expect(harness.applied, [4]);

    harness.revision = 8;
    harness.input.add(_changed(8));
    harness.input.add(_changed(7));
    harness.input.add(_changed(8));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(harness.applied, [4, 8]);
    expect(harness.reads, 2);
    await harness.sync.stop();
  });

  _syncTest('an event during snapshot fetch causes a second consistent reconciliation', (tester) async {
    final pending = Completer<AccountCollectionSnapshot>();
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.fetch = () => pending.future;
    harness.start();
    harness.input.add(_ready(1));
    await tester.pump();
    expect(harness.reads, 1);

    harness.input.add(_changed(2));
    await tester.pump(const Duration(milliseconds: 250));
    expect(harness.reads, 1);
    harness.fetch = null;
    harness.revision = 2;
    pending.complete(_snapshot(1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(harness.applied, [1, 2]);
    await harness.sync.stop();
  });

  _syncTest('failed fetches and failed application retain dirty state and retry', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.fetch = () => Future.error(StateError('offline'));
    harness.start();
    harness.input.add(_ready(3));
    await tester.pump();
    expect(harness.sync.appliedRevision, isNull);
    expect(harness.reads, 1);

    harness.fetch = null;
    harness.revision = 3;
    harness.failApply = true;
    await tester.pump(const Duration(seconds: 2));
    await _waitUntil(() => harness.diagnostics.length >= 2);
    expect(harness.sync.appliedRevision, isNull);
    expect(harness.reads, 2);

    harness.failApply = false;
    await tester.pump(const Duration(seconds: 2));
    expect(harness.sync.appliedRevision, 3);
    expect(harness.applied, [3]);
    expect(harness.diagnostics, hasLength(2));
    await harness.sync.stop();
  });

  _syncTest('every reconnect snapshots even when restored server revision is lower', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.revision = 15;
    harness.start();
    harness.start();
    harness.input.add(_ready(15));
    await tester.pump();
    expect(harness.applied, [15]);
    expect(harness.inputs, hasLength(1));

    await harness.input.close();
    await tester.pump(const Duration(seconds: 1));
    expect(harness.inputs, hasLength(2));
    harness.revision = 2;
    harness.input.add(_ready(2));
    await tester.pump();
    expect(harness.applied, [15, 2]);
    expect(harness.sync.appliedRevision, 2);
    await harness.sync.stop();
  });

  _syncTest('authoritative revision checks repair silent misses and database resets', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.revision = 4;
    harness.start();
    harness.input.add(_ready(4));
    await tester.pump();

    harness.revision = 5;
    harness.input.add(_revision(5));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    harness.revision = 1;
    harness.input.add(_revision(1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(harness.applied, [4, 5, 1]);
    await harness.sync.stop();
  });

  _syncTest('account switch rejects an old fetch and serializes the new account refresh', (tester) async {
    final pending = Completer<AccountCollectionSnapshot>();
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.fetch = () => pending.future;
    harness.start();
    harness.input.add(_ready(8));
    await tester.pump();

    harness.token = 'other-account';
    harness.fetch = null;
    harness.revision = 1;
    harness.start();
    harness.input.add(_ready(1));
    await tester.pump();
    pending.complete(_snapshot(8));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(harness.applied, [1]);
    expect(harness.sync.appliedRevision, 1);
    await harness.sync.stop();
  });

  _syncTest('refresh on foreground return fetches even without a newer event', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.start();
    harness.input.add(_ready(0));
    await tester.pump();
    harness.revision = 1;

    harness.sync.refresh();
    await tester.pump();
    expect(harness.applied, [0, 1]);
    await harness.sync.stop();
  });

  _syncTest('idle stream watchdog reconnects and stop retires every timer', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.start();
    harness.input.add(_ready(0));
    await tester.pump();
    await tester.pump(const Duration(seconds: 45));
    await tester.pump(const Duration(seconds: 1));
    expect(harness.inputs, hasLength(2));

    await harness.sync.stop();
    await tester.pump(const Duration(minutes: 2));
    expect(harness.inputs, hasLength(2));
    expect(harness.inputs.every((input) => !input.hasListener), isTrue);
  });

  _syncTest('authorization and unsupported errors stop instead of reconnect loops', (tester) async {
    for (final status in [401, 403, 404, 405]) {
      final harness = _Harness();
      addTearDown(harness.dispose);
      harness.start();
      harness.input.addError(ApiException(status, 'unavailable'));
      await tester.pump();
      await tester.pump(const Duration(minutes: 1));
      expect(harness.inputs, hasLength(1));
      expect(harness.unauthorized, status == 401 || status == 403 ? 1 : 0);
      expect(harness.unsupported, status == 404 || status == 405 ? 1 : 0);
    }
  });

  _syncTest('stop waits for stream release while discarding late snapshot results', (tester) async {
    final cancellation = Completer<void>();
    final pending = Completer<AccountCollectionSnapshot>();
    final harness = _Harness(onCancel: () => cancellation.future);
    addTearDown(harness.dispose);
    harness.fetch = () => pending.future;
    harness.start();
    harness.input.add(_ready(1));
    await tester.pump();
    var stopped = false;

    final stopping = harness.sync.stop();
    unawaited(stopping.then((_) => stopped = true));
    pending.complete(_snapshot(1));
    await tester.pump();
    expect(stopped, isFalse);
    expect(harness.applied, isEmpty);
    cancellation.complete();
    await tester.pump();
    await stopping;
    expect(stopped, isTrue);
  });

  _syncTest('a deleted playlist during snapshot application retries without disabling sync', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.applyError = ApiException(404, 'playlist deleted');
    harness.start();
    harness.input.add(_ready(0));
    await tester.pump();
    expect(harness.unsupported, 0);
    expect(harness.sync.appliedRevision, isNull);

    harness.applyError = null;
    harness.revision = 1;
    await tester.pump(const Duration(seconds: 2));
    expect(harness.applied, [1]);
    expect(harness.unsupported, 0);
    await harness.sync.stop();
  });

  _syncTest('an unsupported snapshot endpoint disables sync without retrying', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.fetch = () => Future.error(ApiException(404, 'snapshot unavailable'));
    harness.start();
    harness.input.add(_ready(0));
    await tester.pump();
    await tester.pump(const Duration(minutes: 1));
    expect(harness.unsupported, 1);
    expect(harness.reads, 1);
    expect(harness.inputs, hasLength(1));
  });
}

AccountCollectionEvent _ready(int revision) =>
    AccountCollectionEvent(kind: AccountCollectionEventKind.ready, revision: revision);

AccountCollectionEvent _changed(int revision) =>
    AccountCollectionEvent(kind: AccountCollectionEventKind.collectionsChanged, revision: revision);

AccountCollectionEvent _revision(int revision) =>
    AccountCollectionEvent(kind: AccountCollectionEventKind.revision, revision: revision);

AccountCollectionSnapshot _snapshot(int revision) =>
    AccountCollectionSnapshot(userId: 'listener', revision: revision, likes: const [], playlists: const []);

class _Harness {
  final FutureOr<void> Function()? onCancel;
  final inputs = <StreamController<AccountCollectionEvent>>[];
  final applied = <int>[];
  final diagnostics = <String>[];
  late final AccountCollectionSync sync;
  Future<AccountCollectionSnapshot> Function()? fetch;
  String token = 'account';
  int revision = 0;
  int reads = 0;
  int unauthorized = 0;
  int unsupported = 0;
  bool failApply = false;
  Object? applyError;

  _Harness({this.onCancel}) {
    sync = AccountCollectionSync(
      openStream: _open,
      fetchSnapshot: _fetch,
      applySnapshot: _apply,
      isSessionCurrent: (_, expectedToken) => token == expectedToken,
      onDiagnostic: diagnostics.add,
      onUnauthorized: () => unauthorized++,
      onUnsupported: () => unsupported++,
      debounceDelay: const Duration(milliseconds: 2),
      retryDelay: const Duration(milliseconds: 20),
      reconnectDelay: const Duration(milliseconds: 10),
      idleTimeout: const Duration(milliseconds: 450),
      reconnectJitter: 0,
    );
  }

  StreamController<AccountCollectionEvent> get input => inputs.last;

  void start() => sync.start(baseUrl: 'https://music.test/api', token: token);

  Future<void> dispose() async {
    await sync.stop();

    for (final input in inputs) {
      await input.close();
    }
  }

  Stream<AccountCollectionEvent> _open() {
    final controller = StreamController<AccountCollectionEvent>(onCancel: onCancel);
    inputs.add(controller);

    return controller.stream;
  }

  Future<AccountCollectionSnapshot> _fetch() {
    reads++;

    return fetch?.call() ?? Future.value(_snapshot(revision));
  }

  Future<void> _apply(AccountCollectionSnapshot snapshot) async {
    final error = applyError;

    if (error != null) {
      throw error;
    }

    if (failApply) {
      throw StateError('reconciliation interrupted');
    }

    applied.add(snapshot.revision);
  }
}

void _syncTest(String description, Future<void> Function(_TestClock) body) =>
    test(description, () => body(_TestClock()));

class _TestClock {
  Future<void> pump([Duration duration = Duration.zero]) =>
      Future<void>.delayed(Duration(microseconds: duration.inMicroseconds ~/ 100 + 1000));
}

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));

  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('The expected reconciliation checkpoint was not reached');
    }

    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}
