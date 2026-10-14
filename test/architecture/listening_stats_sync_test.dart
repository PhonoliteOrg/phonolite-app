import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:phonolite_app/entities/listening_stats.dart';
import 'package:phonolite_app/entities/listening_stats_sync.dart';
import 'package:phonolite_app/entities/server_connection.dart';
import 'listening_counter_fixtures.dart';

ListeningEvent event(int index, {String device = 'desktop'}) {
  final start =
      DateTime.utc(2026, 10, 8).millisecondsSinceEpoch + index * 60000;
  return ListeningEvent(
    eventId: '$device-event-$index',
    sessionId: '$device-session-$index',
    deviceId: device,
    trackId: 'track-1',
    title: 'The Song',
    artistName: 'Artist',
    albumTitle: 'Album',
    trackDurationMs: 180000,
    sessionStartedAtMs: start,
    startedAtMs: start,
    endedAtMs: start + 60000,
    listenedMs: 60000,
  );
}

/// A deterministic in-process protocol peer; no sockets or server are started.
class FakeListeningConnection extends ServerConnection {
  FakeListeningConnection()
    : super(
        baseUrl: 'https://unused.test',
        client: MockClient(
          (_) async => throw StateError('Unexpected HTTP request'),
        ),
      ) {
    setToken('user-a');
  }

  String user = 'user-a';
  bool collectionEnabled = true;
  int _generation = 1;
  int get generation => _generation;
  set generation(int value) {
    if (_generation != value) {
      counterRows.remove(user);
      records.remove(user);
    }
    _generation = value;
  }

  bool loseNextUploadReply = false;
  bool rejectNextCounterBatch = false;
  Completer<void>? uploadGate;
  Completer<void>? uploadStarted;
  Completer<void>? changesGate;
  Completer<void>? changesStarted;
  int uploads = 0;
  int resets = 0;
  Completer<void>? resetGate;
  Completer<void>? resetStarted;
  bool failReset = false;
  final records = <String, List<Map<String, dynamic>>>{};
  final preferences = <String, Map<String, dynamic>>{};
  final genreMetadata = <String, dynamic>{};
  final checkpoints = <String, Map<String, dynamic>>{};
  final counterRows = <String, Map<String, Map<String, dynamic>>>{};
  final metadata = <String, Map<String, dynamic>>{};
  final seenLegacy = <String>{};
  int counterRevision = 0;

  Map<String, dynamic> checkpoint(String device) => checkpoints.putIfAbsent(
    '$user:$generation:$device',
    () => {'last_sequence': 0, 'last_hash': '', 'upgraded': false},
  );
  void addContribution(String owner, Map<String, dynamic> row) {
    final key = '${row['year']}:${row['month']}:${row['metadata_id']}';
    final rows = counterRows.putIfAbsent(owner, () => {});
    final previous = rows[key];
    final genres = Map<String, dynamic>.from(
      previous?['genre_ms'] as Map? ?? {},
    );
    for (final entry in (row['genre_ms'] as Map).entries) {
      genres[entry.key as String] =
          (genres[entry.key] as int? ?? 0) + (entry.value as int);
    }
    rows[key] = {
      ...row,
      'listened_ms':
          (row['listened_ms'] as int) + (previous?['listened_ms'] as int? ?? 0),
      'plays': (row['plays'] as int) + (previous?['plays'] as int? ?? 0),
      'genre_ms': genres,
    };
  }

  void seedLegacy() {
    for (final record in records[user] ?? []) {
      if (record['counter'] == true ||
          !seenLegacy.add('$user:$generation:${record['event_id']}')) {
        continue;
      }
      final value = counterMetadata(ListeningEvent.fromJson(record));
      final id = counterHash(value);
      metadata[id] = value;
      final at = DateTime.fromMillisecondsSinceEpoch(
        record['started_at_ms'] as int,
        isUtc: true,
      );
      final ms = record['listened_ms'] as int;
      final genres =
          (record['genres'] as List)
              .cast<String>()
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      addContribution(user, {
        'year': at.year,
        'month': at.month,
        'metadata_id': id,
        'listened_ms': ms,
        'plays': ms >= 30000 ? 1 : 0,
        'genre_ms': {
          for (var i = 0; i < genres.length; i++)
            genres[i]: ms ~/ genres.length + (i < ms % genres.length ? 1 : 0),
        },
      });
      counterRevision++;
    }
  }

  @override
  Future<Map<String, dynamic>> fetchListeningCounterState({
    required String deviceId,
  }) async {
    seedLegacy();
    final pref = preference(deviceId);
    return {
      'server_id': 'server-a',
      'user_id': user,
      'history_generation': generation,
      'collection_enabled': collectionEnabled,
      'device_enabled': pref['enabled'],
      'preference_revision': pref['revision'],
      'checkpoint': Map.of(checkpoint(deviceId)),
      'months': [
        for (final period
            in (counterRows[user]?.values ?? <Map<String, dynamic>>[])
                .map((r) => '${r['year']}:${r['month']}')
                .toSet())
          {
            'year': int.parse(period.split(':')[0]),
            'month': int.parse(period.split(':')[1]),
            'revision': counterRevision,
          },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> activateListeningCounters({
    required String deviceId,
    required int historyGeneration,
  }) async {
    checkpoint(deviceId)['upgraded'] = true;
    return Map.of(checkpoint(deviceId));
  }

  @override
  Future<Map<String, dynamic>> uploadListeningCounters(
    Map<String, dynamic> batch,
  ) async {
    uploads++;
    if (rejectNextCounterBatch) {
      rejectNextCounterBatch = false;
      throw ApiException(400, 'Invalid batch metadata');
    }
    final owner = user;
    final device = batch['device_id'] as String;
    final cp = checkpoint(device);
    if (batch['history_generation'] != generation) {
      throw ApiException(409, 'Generation changed');
    }
    if (preference(device)['enabled'] != true ||
        preference(device)['revision'] != batch['collection_revision']) {
      throw ApiException(409, 'Preference changed');
    }
    if ((batch['batch_sequence'] as int) > (cp['last_sequence'] as int)) {
      if (batch['batch_sequence'] != (cp['last_sequence'] as int) + 1) {
        throw ApiException(409, 'Sequence gap');
      }
      metadata.addAll(
        (batch['metadata'] as Map).map(
          (key, value) =>
              MapEntry(key as String, Map<String, dynamic>.from(value as Map)),
        ),
      );
      for (final row in batch['contributions'] as List) {
        addContribution(owner, Map<String, dynamic>.from(row as Map));
        records.putIfAbsent(owner, () => []).add({
          ...Map<String, dynamic>.from(metadata[row['metadata_id']] as Map),
          'counter': true,
          'event_id': batch['batch_sequence'],
          'listened_ms': row['listened_ms'],
        });
      }
      cp['last_sequence'] = batch['batch_sequence'];
      cp['last_hash'] = counterHash(batch);
      counterRevision++;
    } else if (batch['batch_sequence'] == cp['last_sequence'] &&
        counterHash(batch) != cp['last_hash']) {
      throw ApiException(409, 'Payload changed');
    }
    uploadStarted?.complete();
    uploadStarted = null;
    final gate = uploadGate;
    uploadGate = null;
    if (gate != null) await gate.future;
    if (loseNextUploadReply) {
      loseNextUploadReply = false;
      throw TimeoutException('Committed but acknowledgment lost');
    }
    return Map.of(cp);
  }

  @override
  Future<Map<String, dynamic>> fetchListeningCounterSnapshot({
    required String deviceId,
    required int year,
    required int month,
    int? revision,
    String after = '',
  }) async {
    seedLegacy();
    final rows = (counterRows[user]?.values ?? <Map<String, dynamic>>[])
        .where((r) => r['year'] == year && r['month'] == month)
        .toList();
    final response = <String, dynamic>{
      'history_generation': generation,
      'year': year,
      'month': month,
      'revision': counterRevision,
      'checkpoint': Map.of(checkpoint(deviceId)),
      'contributions': rows,
      'metadata': {
        for (final row in rows)
          row['metadata_id']: metadata[row['metadata_id']],
      },
      'genre_metadata': genreMetadata[user] ?? <String, dynamic>{},
      'has_more': false,
      'next_key': '',
    };
    changesStarted?.complete();
    changesStarted = null;
    final gate = changesGate;
    changesGate = null;
    if (gate != null) await gate.future;
    return response;
  }

  void switchUser(String value) {
    user = value;
    setToken(value);
  }

  Map<String, dynamic> preference(String device) => preferences.putIfAbsent(
    '$user:$device',
    () => {'enabled': true, 'revision': 0},
  );

  @override
  Future<Map<String, dynamic>> fetchListeningChanges({
    required String deviceId,
    int after = 0,
    int limit = 200,
  }) async {
    final data = records[user] ?? const [];
    final page = data.skip(after).take(limit).toList();
    final pref = preference(deviceId);
    final response = <String, dynamic>{
      'server_id': 'server-a',
      'user_id': user,
      'history_generation': generation,
      'collection_enabled': collectionEnabled,
      'device_enabled': pref['enabled'],
      'preference_revision': pref['revision'],
      'events': [
        for (var i = 0; i < page.length; i++)
          {'cursor': after + i + 1, 'event': page[i]},
      ],
      'next_cursor': after + page.length,
      'has_more': after + page.length < data.length,
      if (genreMetadata.containsKey(user))
        'genre_metadata': genreMetadata[user] is Map
            ? {
                for (final trackId
                    in page.map((event) => event['track_id']).toSet())
                  if ((genreMetadata[user] as Map).containsKey(trackId))
                    trackId: (genreMetadata[user] as Map)[trackId],
              }
            : genreMetadata[user],
    };
    if (limit != 1) {
      changesStarted?.complete();
      changesStarted = null;
      final gate = changesGate;
      changesGate = null;
      if (gate != null) await gate.future;
    }
    return response;
  }

  @override
  Future<Map<String, dynamic>> updateListeningPreference({
    required String deviceId,
    required bool enabled,
    required int revision,
  }) async {
    final pref = preference(deviceId);
    if (revision >= (pref['revision'] as int)) {
      pref['enabled'] = enabled;
      pref['revision'] = revision;
    }
    return Map.of(pref);
  }

  @override
  Future<Map<String, dynamic>> uploadListeningEvents({
    required String deviceId,
    required int historyGeneration,
    required List<Map<String, dynamic>> events,
  }) async {
    uploads++;
    if (historyGeneration != generation) {
      throw ApiException(409, 'History generation mismatch');
    }
    if (events.any((item) => item['device_id'] != deviceId)) {
      throw ApiException(400, 'Event device does not match the batch');
    }
    final owner = user;
    final data = records.putIfAbsent(owner, () => []);
    for (final item in events) {
      if (!data.any((old) => old['event_id'] == item['event_id'])) {
        data.add(item);
      }
    }
    uploadStarted?.complete();
    uploadStarted = null;
    final gate = uploadGate;
    uploadGate = null;
    if (gate != null) await gate.future;
    if (loseNextUploadReply) {
      loseNextUploadReply = false;
      throw TimeoutException('The server committed, but its reply was lost');
    }
    return {
      'accepted': events.map((item) => item['event_id']).toList(),
      'rejected': [],
    };
  }

  @override
  Future<Map<String, dynamic>> resetListeningHistory({
    required int historyGeneration,
  }) async {
    resets++;
    if (failReset) throw ApiException(503, 'Unavailable');
    final owner = user;
    if (historyGeneration == generation) {
      generation++;
      records.remove(owner);
    }
    final result = {
      'server_id': 'server-a',
      'user_id': owner,
      'history_generation': generation,
    };
    resetStarted?.complete();
    resetStarted = null;
    final gate = resetGate;
    resetGate = null;
    if (gate != null) await gate.future;
    return result;
  }
}

void main() {
  late ListeningStatsService history;
  late FakeListeningConnection connection;
  late ListeningStatsSync sync;
  var authorized = true;
  ListeningEvent localEvent(int index) =>
      event(index, device: history.deviceId);

  setUp(() async {
    authorized = true;
    history = ListeningStatsService(inMemory: true);
    await history.initialize();
    await history.setAccount(serverId: 'server-a', userId: 'user-a');
    connection = FakeListeningConnection();
    sync = ListeningStatsSync(
      history: history,
      connection: connection,
      isAuthorized: () => authorized,
      onChanged: () {},
      onIdentity: (_, __) async {},
    );
  });
  tearDown(() async {
    await sync.close();
    await history.close();
  });

  test(
    'account reset clears synced and pending history, retaining device-only history',
    () async {
      await history.setAccount();
      await history.recordSegment(localEvent(9));
      await history.setAccount(serverId: 'server-a', userId: 'user-a');
      await history.recordSegment(localEvent(0));
      await sync.sync(immediate: true);
      await history.recordSegment(localEvent(1));
      await sync.resetAccountHistory();
      expect(connection.resets, 1);
      expect(history.historyGeneration, 2);
      expect(history.pendingCount, 0);
      expect((await history.stats(year: 2026)).totalListeningMs, 0);
      expect(connection.records['user-a'], isNull);
      expect(history.canImportLocalHistory, isTrue);
      await history.recordSegment(localEvent(2));
      await sync.sync(immediate: true);
      expect(connection.records['user-a'], hasLength(1));
      expect((await history.stats(year: 2026)).totalMinutes, 1);
    },
  );

  test(
    'reset waits for in-flight upload and blocks new sync until it finishes',
    () async {
      await history.recordSegment(localEvent(0));
      final uploadGate = Completer<void>();
      final uploadStarted = Completer<void>();
      connection.uploadGate = uploadGate;
      connection.uploadStarted = uploadStarted;
      final uploading = sync.sync(immediate: true);
      await uploadStarted.future;
      final resetGate = Completer<void>();
      final resetStarted = Completer<void>();
      connection.resetGate = resetGate;
      connection.resetStarted = resetStarted;
      final resetting = sync.resetAccountHistory();
      expect(connection.resets, 0);
      uploadGate.complete();
      await uploading;
      await resetStarted.future;
      await sync.sync(immediate: true);
      expect(connection.resets, 1);
      expect(connection.uploads, 1);
      resetGate.complete();
      await resetting;
      expect((await history.stats(year: 2026)).totalListeningMs, 0);
    },
  );

  test(
    'connected reset clears the server and every copy on this device',
    () async {
      await history.setAccount();
      await history.recordSegment(localEvent(9));
      await history.setAccount(serverId: 'server-a', userId: 'user-a');
      await history.recordSegment(localEvent(0));
      await sync.sync(immediate: true);
      await history.recordSegment(localEvent(1));
      await sync.resetListeningStatistics(resetServer: true);
      expect(connection.resets, 1);
      expect(connection.records['user-a'], isNull);
      expect(history.historyGeneration, 2);
      expect(history.pendingCount, 0);
      expect(history.canImportLocalHistory, isFalse);
      expect((await history.stats(year: 2026)).totalListeningMs, 0);
      await history.setAccount();
      expect((await history.stats(year: 2026)).totalListeningMs, 0);
      await history.setAccount(serverId: 'server-a', userId: 'user-a');
      await history.recordSegment(localEvent(2));
      await sync.sync(immediate: true);
      expect((await history.stats(year: 2026)).totalListeningMs, 60000);
      expect(connection.records['user-a'], hasLength(1));
    },
  );

  test(
    'offline reset clears cached account totals and pending uploads without contacting the server',
    () async {
      await history.recordSegment(localEvent(0));
      await sync.sync(immediate: true);
      final generation = history.historyGeneration;
      authorized = false;
      await history.recordSegment(localEvent(1));
      final uploads = connection.uploads;
      await sync.resetListeningStatistics(resetServer: false);
      expect(connection.resets, 0);
      expect(connection.uploads, uploads);
      expect(history.historyGeneration, generation);
      expect(history.pendingCount, 0);
      expect((await history.stats(year: 2026)).totalListeningMs, 0);
      expect(
        connection.counterRows['user-a']!.values.single['listened_ms'],
        60000,
      );

      await history.recordSegment(localEvent(2));
      authorized = true;
      await sync.sync(immediate: true);
      expect(
        connection.counterRows['user-a']!.values.single['listened_ms'],
        120000,
      );
      expect(history.pendingCount, 0);
    },
  );

  test(
    'a server reset leaves another device statistics until that device is reset',
    () async {
      await history.recordSegment(localEvent(0));
      await sync.sync(immediate: true);
      final other = ListeningStatsService(
        inMemory: true,
        clock: () => DateTime.utc(2026, 10, 8),
      );
      await other.initialize();
      final otherSync = ListeningStatsSync(
        history: other,
        connection: connection,
        isAuthorized: () => true,
        onChanged: () {},
        onIdentity: (_, __) async {},
      );
      addTearDown(() async {
        await otherSync.close();
        await other.close();
      });
      await otherSync.sync(immediate: true);
      await other.recordSegment(event(1, device: other.deviceId));
      expect((await other.stats(year: 2026)).totalListeningMs, 120000);

      await sync.resetListeningStatistics(resetServer: true);
      await otherSync.sync(immediate: true);
      expect((await history.stats(year: 2026)).totalListeningMs, 0);
      expect((await other.stats(year: 2026)).totalListeningMs, 120000);
      expect(other.pendingCount, 0);
      expect(connection.counterRows['user-a'], isNull);
      await other.recordSegment(event(2, device: other.deviceId));
      await otherSync.sync(immediate: true);
      expect((await other.stats(year: 2026)).totalListeningMs, 180000);
      expect(
        connection.counterRows['user-a']!.values.single['listened_ms'],
        60000,
      );
      await otherSync.resetListeningStatistics(resetServer: false);
      expect((await other.stats(year: 2026)).totalListeningMs, 0);
      expect(
        connection.counterRows['user-a']!.values.single['listened_ms'],
        60000,
      );
    },
  );

  test('a failed connected reset keeps device statistics intact', () async {
    await history.recordSegment(localEvent(0));
    connection.failReset = true;
    await expectLater(
      sync.resetListeningStatistics(resetServer: true),
      throwsA(isA<ApiException>()),
    );
    expect((await history.stats(year: 2026)).totalListeningMs, 60000);
    expect(history.pendingCount, 1);
  });

  test(
    'other devices retain local totals and retire stale uploads after a server reset',
    () async {
      await history.recordSegment(localEvent(0));
      connection.generation = 2;
      await sync.sync(immediate: true);
      expect(connection.uploads, 0);
      expect(history.pendingCount, 0);
      expect(history.historyGeneration, 2);
      expect((await history.stats(year: 2026)).totalListeningMs, 60000);
      await history.recordSegment(localEvent(1));
      await history.setEnabled(false);
      connection.generation = 3;
      await sync.sync(immediate: true);
      expect(history.enabled, isFalse);
      expect(history.historyGeneration, 3);
      expect((await history.stats(year: 2026)).totalListeningMs, 120000);
      expect(connection.uploads, 0);
    },
  );

  test(
    'failed reset preserves history and a changed account ignores the reply',
    () async {
      await history.recordSegment(localEvent(0));
      connection.failReset = true;
      await expectLater(
        sync.resetAccountHistory(),
        throwsA(isA<ApiException>()),
      );
      expect(history.pendingCount, 1);
      expect((await history.stats(year: 2026)).totalMinutes, 1);
      connection.failReset = false;
      final gate = Completer<void>();
      final started = Completer<void>();
      connection.resetGate = gate;
      connection.resetStarted = started;
      final resetting = sync.resetAccountHistory();
      final failed = expectLater(resetting, throwsStateError);
      await started.future;
      connection.switchUser('user-b');
      await history.setAccount(serverId: 'server-a', userId: 'user-b');
      await history.recordSegment(localEvent(1));
      gate.complete();
      await failed;
      expect(history.accountScope, contains('user-b'));
      expect((await history.stats(year: 2026)).totalMinutes, 1);
    },
  );

  test(
    'lost upload acknowledgment retries IDs and never double counts',
    () async {
      await history.recordSegment(localEvent(0));
      connection.loseNextUploadReply = true;
      await sync.sync(immediate: true);
      expect(history.pendingCount, 1);
      expect(connection.records['user-a'], hasLength(1));
      await sync.sync(immediate: true);
      expect(history.pendingCount, 0);
      expect(connection.records['user-a'], hasLength(1));
      expect((await history.stats(year: 2026)).totalListeningMs, 60000);
      expect(history.cursor, 0);
      expect(history.lastSyncedAt, isNotNull);
    },
  );

  test(
    'server-disabled collection retains local queue and pulls account history',
    () async {
      await history.recordSegment(localEvent(0));
      connection.collectionEnabled = false;
      connection.records['user-a'] = [event(1, device: 'mobile').toJson()];
      await sync.sync(immediate: true);
      expect(connection.uploads, 0);
      expect(history.pendingCount, 1);
      expect((await history.stats(year: 2026)).totalMinutes, 2);
      expect(sync.serverCollectionEnabled, isFalse);
    },
  );

  test(
    'opt-out during upload cancels remaining batch and sends disabled preference',
    () async {
      for (var index = 0; index < 201; index++) {
        await history.recordSegment(
          ListeningEvent.fromJson({
            ...localEvent(index).toJson(),
            'track_id': 'track-$index',
          }),
        );
      }
      final started = connection.uploadStarted = Completer<void>();
      final gate = connection.uploadGate = Completer<void>();
      final running = sync.sync(immediate: true);
      await started.future;
      await history.setEnabled(false);
      final preferenceSync = sync.sync(immediate: true);
      gate.complete();
      await Future.wait([running, preferenceSync]);
      expect(connection.uploads, 1);
      expect(connection.records['user-a'], hasLength(200));
      expect(connection.preference(history.deviceId)['enabled'], isFalse);
      expect(history.pendingCount, 0);
      expect((await history.stats(year: 2026)).totalMinutes, 201);
    },
  );

  test(
    'late reply from old account cannot acknowledge current account queue',
    () async {
      await history.recordSegment(localEvent(0));
      final started = connection.uploadStarted = Completer<void>();
      final gate = connection.uploadGate = Completer<void>();
      final running = sync.sync(immediate: true);
      await started.future;
      connection.switchUser('user-b');
      await history.setAccount(serverId: 'server-a', userId: 'user-b');
      await history.recordSegment(localEvent(1));
      gate.complete();
      await running;
      expect(history.pendingCount, 1);
      await sync.sync(immediate: true);
      expect(
        connection.records['user-b']!.single['listened_ms'],
        localEvent(1).listenedMs,
      );
      expect((await history.stats(year: 2026)).totalMinutes, 1);
      await history.setAccount(serverId: 'server-a', userId: 'user-a');
      // The ignored old reply leaves a safe retry; the server deduplicates it.
      expect(history.pendingCount, 1);
      expect((await history.stats(year: 2026)).totalMinutes, 1);
    },
  );

  test(
    'server reset retains local statistics without uploading the old copies',
    () async {
      await history.recordSegment(localEvent(0));
      connection.generation = 2;
      await sync.sync(immediate: true);
      expect(history.historyGeneration, 2);
      expect(history.pendingCount, 0);
      expect(connection.uploads, 0);
      expect((await history.stats(year: 2026)).totalMinutes, 1);
    },
  );

  test(
    'permanent batch rejection preserves local totals and permits later listening',
    () async {
      await history.recordSegment(localEvent(0));
      connection.rejectNextCounterBatch = true;
      await sync.sync(immediate: true);
      expect(sync.message, contains('local history is retained'));
      await history.recordSegment(localEvent(1));
      await sync.sync(immediate: true);
      expect(history.pendingCount, 0);
      expect(
        connection.counterRows['user-a']!.values.single['listened_ms'],
        60000,
      );
      expect((await history.stats(year: 2026)).totalListeningMs, 120000);
      expect(connection.checkpoint(history.deviceId)['last_sequence'], 1);
    },
  );

  test('signed-out synchronization performs no transport work', () async {
    await history.recordSegment(localEvent(0));
    authorized = false;
    await sync.sync(immediate: true);
    expect(connection.records, isEmpty);
    expect(history.pendingCount, 1);
  });

  test(
    'offline off/on creates a consent fence even when the server revision is higher',
    () async {
      connection.preference(history.deviceId)['revision'] = 100;
      await history.recordSegment(localEvent(0));
      await history.counterOperation(
        'checkpoint',
        arguments: {
          'checkpoint': {'upgraded': true, 'last_sequence': 0},
          'collection_revision': 100,
        },
      );
      await history.counterOperation(
        'consent_ack',
        arguments: {'consent_epoch': history.collectionIntentRevision},
      );
      final old = Map<String, dynamic>.from(
        await history.counterOperation(
              'prepare',
              arguments: {'collection_revision': 100},
            )
            as Map,
      );
      await history.setEnabled(false);
      await history.setEnabled(true);
      await history.recordSegment(localEvent(1));
      await sync.sync(immediate: true);
      expect(connection.preference(history.deviceId)['revision'], 101);
      expect(history.pendingCount, 0);
      expect((await history.stats(year: 2026)).totalListeningMs, 120000);
      expect(
        connection.counterRows['user-a']!.values.single['listened_ms'],
        60000,
      );
      await expectLater(
        connection.uploadListeningCounters(old),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test(
    'catalog genre repairs reconcile uploaded and remote history without changing snapshots',
    () async {
      final local = ListeningEvent.fromJson({
        ...localEvent(0).toJson(),
        'genres': ['Rock', 'Pop'],
      });
      final remote = {
        ...event(1, device: 'mobile').toJson(),
        'genres': ['Rock', 'Pop'],
      };
      await history.recordSegment(local);
      connection.records['user-a'] = [remote];
      connection.genreMetadata['user-a'] = {
        'track-1': ['acid jazz', 'Electronic', 'funk'],
      };

      await sync.sync(immediate: true);
      final stats = await history.stats(year: 2026);
      expect(stats.totalListeningMs, 120000);
      expect(stats.totalPlays, 2);
      expect(stats.uniqueTracks, 1);
      expect(stats.topGenres.map((item) => item.name).toSet(), {
        'Acid Jazz',
        'Electronic',
        'Funk',
      });
      expect(
        stats.topGenres.map((item) => item.listeningMs),
        everyElement(40000),
      );
      expect(history.cursor, 0);
      expect(history.pendingCount, 0);
      expect(
        connection.records['user-a']!.map((item) => item['genres']),
        everyElement(['Rock', 'Pop']),
      );

      final replica = ListeningStatsService(inMemory: true);
      addTearDown(replica.close);
      await replica.initialize();
      final replicaSync = ListeningStatsSync(
        history: replica,
        connection: connection,
        isAuthorized: () => true,
        onChanged: () {},
        onIdentity: (_, __) async {},
      );
      addTearDown(replicaSync.close);
      await replicaSync.sync(immediate: true);
      final replicated = await replica.stats(year: 2026);
      expect(replicated.totalListeningMs, stats.totalListeningMs);
      expect(replicated.topGenres.map((item) => item.name).toSet(), {
        'Acid Jazz',
        'Electronic',
        'Funk',
      });
      expect(
        replicated.topGenres.map((item) => item.listeningMs),
        everyElement(40000),
      );
      expect(replica.cursor, 0);

      // Repeated synchronization must not duplicate either raw intervals or
      // derived duration changes, including after this client's cursor advances.
      await sync.sync(immediate: true);
      expect((await history.stats(year: 2026)).totalListeningMs, 120000);
      expect(
        (await history.stats(
          year: 2026,
        )).topGenres.map((item) => item.listeningMs),
        everyElement(40000),
      );
    },
  );

  test(
    'present empty genre projection classifies the time as unknown',
    () async {
      connection.records['user-a'] = [
        {
          ...event(0, device: 'mobile').toJson(),
          'genres': ['Rock', 'Pop'],
        },
      ];
      connection.genreMetadata['user-a'] = {'track-1': <String>[]};
      await sync.sync(immediate: true);
      final stats = await history.stats(year: 2026);
      expect(stats.totalListeningMs, 60000);
      expect(stats.topGenres, isEmpty);
      expect(history.cursor, 0);
    },
  );

  test(
    'malformed genre projection cannot commit its events or cursor',
    () async {
      connection.records['user-a'] = [event(0, device: 'mobile').toJson()];
      connection.genreMetadata['user-a'] = {
        'track-1': ['Funk', 7],
      };
      await sync.sync(immediate: true);
      expect((await history.stats(year: 2026)).totalListeningMs, 0);
      expect(history.cursor, 0);
      expect(sync.message, contains('Waiting to sync'));
    },
  );

  test('late repair page cannot update a newly selected account', () async {
    connection.records['user-a'] = [
      {
        ...event(0, device: 'mobile').toJson(),
        'genres': ['Rock', 'Pop'],
      },
    ];
    connection.genreMetadata['user-a'] = {
      'track-1': ['Funk'],
    };
    final started = connection.changesStarted = Completer<void>();
    final gate = connection.changesGate = Completer<void>();
    final running = sync.sync(immediate: true);
    await started.future;
    connection.switchUser('user-b');
    await history.setAccount(serverId: 'server-a', userId: 'user-b');
    await history.recordSegment(
      ListeningEvent.fromJson({
        ...localEvent(1).toJson(),
        'genres': ['Metal'],
      }),
    );
    gate.complete();
    await running;
    final stats = await history.stats(year: 2026);
    expect(stats.totalListeningMs, 60000);
    expect(stats.topGenres.single.name, 'Metal');
    expect(history.cursor, 0);
    expect(history.pendingCount, 1);
  });
}
