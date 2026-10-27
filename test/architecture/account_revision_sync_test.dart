import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:phonolite_app/application/workflows/revision_snapshot_sync.dart';
import 'package:phonolite_app/data/models/auth/account_state.dart';
import 'package:phonolite_app/data/models/server/revision_event.dart';
import 'package:phonolite_app/data/models/server/server_capabilities.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';

void main() {
  test('vector changes merge independent clocks without treating old notifications as new snapshots', () async {
    final harness = _Harness();
    addTearDown(harness.close);
    harness.sync.start(baseUrl: 'https://test', token: 'alice');
    harness.send(RevisionEventKind.ready, _clock(10, 2, 1));
    await _settle();

    harness.state = _state(_clock(10, 3, 5));
    harness.send(RevisionEventKind.changed, _clock(9, 3, 1));
    harness.send(RevisionEventKind.changed, _clock(10, 2, 5));
    await _settle();
    await _settle(const Duration(milliseconds: 250));

    expect(harness.reads, 2);
    expect(harness.applied.last.revisions.collections, 10);
    expect(harness.applied.last.revisions.presets, 3);
    expect(harness.applied.last.revisions.statistics, 5);
    await harness.sync.stop();
  });

  test('account changes reconcile unchanged clocks while identical heartbeats remain idle', () async {
    final harness = _Harness();
    addTearDown(harness.close);
    harness.sync.start(baseUrl: 'https://test', token: 'alice');
    harness.send(RevisionEventKind.ready, harness.state.revisions);
    await _settle();
    harness.send(RevisionEventKind.revision, harness.state.revisions);
    await _settle(const Duration(milliseconds: 300));
    expect(harness.reads, 1);

    harness.state = _state(harness.state.revisions, username: 'Renamed');
    harness.send(RevisionEventKind.changed, harness.state.revisions);
    await _settle();
    await _settle(const Duration(milliseconds: 250));

    expect(harness.reads, 2);
    expect(harness.applied.last.username, 'Renamed');
    await harness.sync.stop();
  });

  test('a restored domain clock is accepted and failed application retries', () async {
    final harness = _Harness();
    addTearDown(harness.close);
    harness.sync.start(baseUrl: 'https://test', token: 'alice');
    harness.send(RevisionEventKind.ready, harness.state.revisions);
    await _settle();
    harness.state = _state(_clock(10, 0, 2));
    harness.failApply = true;
    harness.send(RevisionEventKind.revision, harness.state.revisions);
    await _settle();
    await _settle(const Duration(milliseconds: 250));
    expect(harness.sync.appliedRevision!.presets, 2);
    harness.failApply = false;
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(harness.sync.appliedRevision!.presets, 0);
    expect(harness.sync.appliedRevision!.statistics, 2);
    await harness.sync.stop();
  });

  test('account and remembered-track endpoint contracts preserve track-start identity', () async {
    Map<String, dynamic>? posted;
    final connection = ServerConnection(
      baseUrl: 'https://test',
      client: MockClient((request) async {
        switch (request.url.path) {
          case '/account/state':
            return http.Response(
              jsonEncode({
                'user_id': 'alice',
                'username': 'Alice',
                'role': 'user',
                'revisions': {'collections': 4, 'presets': 2, 'statistics': 9},
              }),
              200,
            );
          case '/account/last-track':
            if (request.method == 'POST') {
              posted = jsonDecode(request.body) as Map<String, dynamic>;
            }
            return http.Response(jsonEncode({'track_id': 'track/one', 'revision': 8}), 200);
          default:
            throw StateError('Unexpected endpoint ${request.url}');
        }
      }),
    )..setToken('alice');
    final account = await connection.fetchAccountState();
    expect(account.userId, 'alice');
    expect(account.revisions.statistics, 9);
    expect((await connection.fetchAccountLastTrack()).trackId, 'track/one');
    await connection.reportAccountTrackStart(
      trackId: 'track/one',
      sessionId: 'session',
      sequence: 3,
      requestId: 'request',
    );
    expect(posted, {'track_id': 'track/one', 'session_id': 'session', 'sequence': 3, 'request_id': 'request'});
  });

  test('new capabilities negotiate independently and event clocks reject malformed revisions', () {
    final old = ServerCapabilities.fromJson({});
    expect(old.accountEventsV2, isFalse);
    expect(old.shufflePresets, isFalse);
    expect(old.lastTrack, isFalse);
    expect(old.sessionManagement, isFalse);
    final current = ServerCapabilities.fromJson({
      'account_events_v2': '1',
      'shuffle_presets': '1',
      'last_track': '1',
      'session_management': '1',
      'catalogue_events': '1',
    });
    expect(current.accountEventsV2 && current.shufflePresets && current.lastTrack && current.sessionManagement, isTrue);
    expect(current.catalogueEvents, isTrue);
    expect(
      () => AccountState.eventFromJson({
        'kind': 'account_changed',
        'revisions': {'collections': 1, 'presets': -1, 'statistics': 1},
      }),
      throwsFormatException,
    );
  });
}

AccountRevisions _clock(int collections, int presets, int statistics) =>
    AccountRevisions(collections: collections, presets: presets, statistics: statistics);

AccountState _state(AccountRevisions revisions, {String username = 'Alice'}) =>
    AccountState(userId: 'alice', username: username, role: 'user', revisions: revisions);

class _Harness {
  final input = StreamController<RevisionEvent<AccountRevisions>>();
  final applied = <AccountState>[];
  AccountState state = _state(_clock(10, 2, 1));
  int reads = 0;
  bool failApply = false;
  late final sync = RevisionSnapshotSync<AccountState, AccountRevisions>(
    openStream: () => input.stream,
    fetchSnapshot: () async {
      reads++;
      return state;
    },
    applySnapshot: (snapshot) async {
      if (failApply) {
        throw StateError('Interrupted application');
      }
      applied.add(snapshot);
    },
    isSessionCurrent: (_, __) => true,
    onDiagnostic: (_) {},
    revisionOf: (snapshot) => snapshot.revisions,
    merge: (first, second) => first.merge(second),
    isAhead: (first, second) => first.isAheadOf(second),
    isRollback: (first, second) => first.isBehind(second),
    refreshUnchangedEvents: true,
    debounceDelay: const Duration(milliseconds: 2),
    retryDelay: const Duration(milliseconds: 40),
  );

  void send(RevisionEventKind kind, AccountRevisions revisions) =>
      input.add(RevisionEvent(kind: kind, revision: revisions));

  Future<void> close() async {
    await sync.stop();
    await input.close();
  }
}

Future<void> _settle([Duration delay = Duration.zero]) => Future<void>.delayed(const Duration(milliseconds: 15));
