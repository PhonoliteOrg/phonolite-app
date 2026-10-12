import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/entities/listening_stats.dart';
import 'package:phonolite_app/entities/models.dart';
import 'package:sqlite3/sqlite3.dart';
import 'listening_counter_fixtures.dart';

ListeningEvent interval({
  String id = 'event-1',
  String session = 'session-1',
  String device = 'device-1',
  String track = 'track-1',
  String artist = 'artist-1',
  String artistName = 'The Artist',
  List<ListeningArtist> artists = const [],
  List<String> genres = const ['Rock'],
  int listened = 60000,
  int? start,
  int? end,
  int? sessionStart,
  int trackDuration = 180000,
}) {
  final started = start ?? DateTime.utc(2026, 10, 8).millisecondsSinceEpoch;
  return ListeningEvent(
    eventId: id,
    sessionId: session,
    deviceId: device,
    trackId: track,
    title: 'The Song',
    artistId: artist,
    artistName: artistName,
    artists: artists,
    albumId: 'album-1',
    albumTitle: 'The Album',
    genres: genres,
    trackDurationMs: trackDuration,
    sessionStartedAtMs: sessionStart ?? started,
    startedAtMs: started,
    endedAtMs: end ?? started + listened,
    listenedMs: listened,
  );
}

void main() {
  late Directory temporary;
  late String databasePath;
  final services = <ListeningStatsService>[];

  Future<ListeningStatsService> open({bool memory = false}) async {
    final service = ListeningStatsService(
      databasePath: databasePath,
      inMemory: memory,
      clock: () => DateTime.utc(2026, 10, 8),
    );
    services.add(service);
    await service.initialize();
    return service;
  }

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('phonolite_stats_test_');
    databasePath = '${temporary.path}/stats.sqlite';
  });
  tearDown(() async {
    for (final service in services) {
      await service.close();
    }
    services.clear();
    await temporary.delete(recursive: true);
  });

  test(
    'cold opt-out stays disabled during initialization and after reopen',
    () async {
      final service = ListeningStatsService(databasePath: databasePath);
      services.add(service);
      final observed = <bool>[];
      final subscription = service.changes.listen(
        (_) => observed.add(service.enabled),
      );
      final disabling = service.setEnabled(false);
      expect(service.enabled, isFalse);
      await service.initialize();
      expect(service.enabled, isFalse);
      await disabling;
      expect(service.enabled, isFalse);
      expect(observed, isNotEmpty);
      expect(observed, everyElement(isFalse));
      await subscription.cancel();
      await service.close();
      final reopened = await open();
      expect(reopened.enabled, isFalse);
    },
  );

  test(
    'rapid cold toggles preserve the latest enabled intent through initialization',
    () async {
      final previous = await open();
      await previous.setEnabled(false);
      await previous.close();
      final service = ListeningStatsService(databasePath: databasePath);
      services.add(service);
      final disabling = service.setEnabled(false);
      final enabling = service.setEnabled(true);
      expect(service.enabled, isTrue);
      await service.initialize();
      expect(service.enabled, isTrue);
      await Future.wait([disabling, enabling]);
      expect(service.enabled, isTrue);
      await service.close();
      final reopened = await open();
      expect(reopened.enabled, isTrue);
    },
  );

  testWidgets('cold history closes outside its widget creation clock', (
    tester,
  ) async {
    final service = ListeningStatsService(inMemory: true);
    services.add(service);
    await tester.runAsync(() => service.close());
    // A cold close must finish without pumping the suspended widget clock.
    await tester.runAsync(() => service.close());
  });

  test(
    'enabled default, history, and random device ID survive reopen',
    () async {
      final first = await open();
      expect(first.enabled, isTrue);
      expect(first.deviceId, matches(RegExp(r'^[0-9a-f]{32}$')));
      final device = first.deviceId;
      await first.recordSegment(interval());
      await first.close();
      final second = await open();
      expect(second.deviceId, device);
      expect((await second.stats()).totalMinutes, 1);
      expect((await second.stats()).topTracks.single.plays, 1);
    },
  );

  test('opt-out stops recording, cancels uploads, and persists', () async {
    final first = await open();
    await first.setAccount(serverId: 'server-a', userId: 'user-a');
    await first.recordSegment(interval());
    expect(first.pendingCount, 1);
    await first.setEnabled(false);
    await first.recordSegment(interval(id: 'excluded', session: 'excluded'));
    expect(first.pendingCount, 0);
    expect(await first.pendingEvents(), isEmpty);
    expect((await first.stats()).totalMinutes, 1);
    await first.close();

    final second = await open();
    expect(second.enabled, isFalse);
    await second.setAccount(serverId: 'server-a', userId: 'user-a');
    await second.setEnabled(true);
    expect(await second.pendingEvents(), isEmpty);
    await second.recordSegment(interval(id: 'new', session: 'new'));
    expect(second.pendingCount, 1);
    expect((await second.stats()).totalMinutes, 2);
  });

  test('server replay and duplicate retries count a segment once', () async {
    final service = await open(memory: true);
    await service.setAccount(serverId: 'server-a', userId: 'user-a');
    final event = interval();
    await service.recordSegment(event);
    await service.recordSegment(event);
    expect(service.pendingCount, 1);
    await confirmCounterBatch(service);
    expect(service.pendingCount, 0);
    expect(service.cursor, 0);
    expect((await service.stats()).totalMinutes, 1);
    expect((await service.stats()).topTracks.single.plays, 1);
    final otherDevice = interval(
      id: 'mobile-event',
      session: 'mobile-session',
      device: 'mobile',
    );
    await service.applyRemote([otherDevice], cursor: 2, historyGeneration: 1);
    expect((await service.stats()).totalMinutes, 2);
    expect((await service.stats()).topTracks.single.plays, 2);
    expect(await service.pendingEvents(), isEmpty);
  });

  test('remote events and replication cursor commit atomically', () async {
    final service = await open(memory: true);
    await service.setAccount(serverId: 'server-a', userId: 'user-a');
    await expectLater(
      service.applyRemote(
        [interval(), interval(listened: 120000)],
        cursor: 10,
        historyGeneration: 1,
      ),
      throwsStateError,
    );
    expect(service.cursor, 0);
    expect((await service.stats()).totalMinutes, 0);
    await service.applyRemote([interval()], cursor: 1, historyGeneration: 1);
    expect(service.cursor, 1);
    expect((await service.stats()).totalMinutes, 1);
  });

  test(
    'anonymous history needs explicit import and accounts stay separate',
    () async {
      final service = await open(memory: true);
      await service.recordSegment(interval());
      await service.setAccount(serverId: 'server-a', userId: 'user-a');
      expect(service.canImportLocalHistory, isTrue);
      expect((await service.stats()).totalMinutes, 0);
      expect(await service.pendingEvents(), isEmpty);
      await service.importLocalHistory();
      expect(service.canImportLocalHistory, isFalse);
      expect((await service.stats()).totalMinutes, 1);
      expect(service.pendingCount, 1);
      await service.setAccount(serverId: 'server-a', userId: 'user-b');
      expect((await service.stats()).totalMinutes, 0);
      expect(await service.pendingEvents(), isEmpty);
      await service.recordSegment(interval(id: 'other', session: 'other'));
      await service.setAccount(serverId: 'server-b', userId: 'user-a');
      expect((await service.stats()).totalMinutes, 0);
      await service.setAccount(serverId: 'server-a', userId: 'user-a');
      expect(service.pendingCount, 1);
      await service.setAccount();
      expect((await service.stats()).totalMinutes, 0);
    },
  );

  test(
    'duration splits at UTC year boundary and play belongs to session start',
    () async {
      final service = await open(memory: true);
      final start = DateTime.utc(2025, 12, 31, 23, 59).millisecondsSinceEpoch;
      await service.recordSegment(interval(start: start, listened: 120000));
      final previous = await service.stats(year: 2025, month: 12);
      final next = await service.stats(year: 2026, month: 1);
      expect(previous.totalMinutes, 1);
      expect(next.totalMinutes, 1);
      expect(previous.topTracks.single.plays, 1);
      expect(next.topTracks.single.plays, 0);
    },
  );

  test('short checkpoints qualify an unordered session only once', () async {
    final service = await open(memory: true);
    final start = DateTime.utc(2026, 10, 8).millisecondsSinceEpoch;
    await service.recordSegment(
      interval(
        id: 'second',
        start: start + 15000,
        sessionStart: start,
        listened: 15000,
      ),
    );
    expect((await service.stats()).topTracks.single.plays, 0);
    await service.recordSegment(
      interval(id: 'first', start: start, sessionStart: start, listened: 15000),
    );
    await service.recordSegment(
      interval(
        id: 'third',
        start: start + 30000,
        sessionStart: start,
        listened: 15000,
      ),
    );
    await service.recordSegment(
      interval(
        id: 'fourth',
        start: start + 45000,
        sessionStart: start,
        listened: 15000,
      ),
    );
    final stats = await service.stats();
    expect(stats.totalMinutes, 1);
    expect(stats.topTracks.single.plays, 1);
  });

  test('history reset retires offline queue and stale replication', () async {
    final service = await open(memory: true);
    await service.setAccount(serverId: 'server-a', userId: 'user-a');
    final scope = service.accountScope;
    await service.recordSegment(interval());
    await service.applyRemote([], cursor: 0, historyGeneration: 2);
    expect(service.historyGeneration, 2);
    expect(service.pendingCount, 0);
    expect((await service.stats()).totalMinutes, 0);
    await service.recordSegment(
      interval(id: 'late'),
      scope: scope,
      generation: 1,
    );
    await service.applyRemote([interval()], cursor: 10, historyGeneration: 1);
    expect(service.historyGeneration, 2);
    expect(service.cursor, 0);
    expect((await service.stats()).totalMinutes, 0);
    await service.recordSegment(interval(id: 'fresh', session: 'fresh'));
    expect((await service.stats()).totalMinutes, 1);
    expect(service.pendingCount, 1);
  });

  test(
    'device-only reset deletes local rows and preserves account history and consent',
    () async {
      final service = await open();
      await service.recordSegment(interval(id: 'local'));
      final localGeneration = service.historyGeneration;
      await service.setAccount(serverId: 'server-a', userId: 'user-a');
      await service.recordSegment(interval(id: 'account'));
      await service.setEnabled(false);
      await service.resetLocalHistory();
      expect(service.enabled, isFalse);
      expect(service.historyGeneration, 1);
      expect(service.canImportLocalHistory, isFalse);
      expect((await service.stats()).totalMinutes, 1);
      await service.setAccount();
      expect(service.historyGeneration, localGeneration + 1);
      expect((await service.stats()).totalListeningMs, 0);
      await service.setEnabled(true);
      await service.recordSegment(
        interval(id: 'late'),
        scope: 'local',
        generation: localGeneration,
      );
      expect((await service.stats()).totalListeningMs, 0);
      final db = sqlite3.open(databasePath);
      try {
        for (final table in [
          'stats_events',
          'stats_sessions',
          'stats_daily',
          'stats_genre_metadata',
        ]) {
          expect(
            db.select("SELECT * FROM $table WHERE scope='local'"),
            isEmpty,
          );
        }
      } finally {
        db.dispose();
      }
      await service.recordSegment(interval(id: 'fresh', session: 'fresh'));
      expect((await service.stats()).totalMinutes, 1);
      await service.close();
      final reopened = await open();
      expect(reopened.historyGeneration, localGeneration + 1);
      expect((await reopened.stats()).totalMinutes, 1);
    },
  );

  test(
    'account generation change deletes old rows but keeps local and other accounts',
    () async {
      final service = await open();
      await service.recordSegment(interval(id: 'local'));
      await service.setAccount(serverId: 'server-a', userId: 'user-b');
      await service.recordSegment(interval(id: 'other'));
      await service.setAccount(serverId: 'server-a', userId: 'user-a');
      final scope = service.accountScope;
      await service.recordSegment(interval(id: 'account'));
      await service.updateGenreMetadata({
        'track-1': ['Jazz'],
      });
      await service.setAccount(
        serverId: 'server-a',
        userId: 'user-a',
        historyGeneration: 2,
      );
      final db = sqlite3.open(databasePath);
      try {
        for (final table in [
          'stats_events',
          'stats_sessions',
          'stats_daily',
          'stats_genre_metadata',
        ]) {
          expect(
            db.select('SELECT * FROM $table WHERE scope=?', [scope]),
            isEmpty,
          );
        }
      } finally {
        db.dispose();
      }
      expect(service.pendingCount, 0);
      expect((await service.stats()).totalListeningMs, 0);
      await service.setAccount(serverId: 'server-a', userId: 'user-b');
      expect((await service.stats()).totalMinutes, 1);
      await service.setAccount();
      expect((await service.stats()).totalMinutes, 1);
    },
  );

  test(
    'failed persistence initialization fails closed and surfaces error',
    () async {
      final service = ListeningStatsService(databasePath: temporary.path);
      services.add(service);
      await expectLater(service.initialize(), throwsStateError);
      expect(service.enabled, isFalse);
      expect(service.storageError, isNotEmpty);
      await expectLater(service.setEnabled(true), throwsStateError);
      expect(service.enabled, isFalse);
      await service.close();
      await service.close();
    },
  );

  test('period totals include all tracks beyond the top ten', () async {
    final service = await open(memory: true);
    for (var index = 0; index < 12; index++) {
      await service.recordSegment(
        interval(
          id: 'event-$index',
          session: 'session-$index',
          track: 'track-$index',
          artist: 'artist-$index',
        ),
      );
    }
    final stats = await service.stats();
    expect(stats.topTracks, hasLength(10));
    expect(stats.topArtists, hasLength(5));
    expect(stats.totalMinutes, 12);
    expect(stats.totalListeningMs, 720000);
    expect(stats.totalPlays, 12);
    expect(stats.uniqueTracks, 12);
    expect(stats.uniqueArtists, 12);
  });

  test(
    'canceled upload stays local and does not return after reopen',
    () async {
      final first = await open();
      await first.setAccount(serverId: 'server-a', userId: 'user-a');
      await first.recordSegment(interval());
      await first.setEnabled(false);
      await first.setEnabled(true);
      expect(first.pendingCount, 0);
      expect((await first.stats()).totalMinutes, 1);
      await first.close();
      final second = await open();
      await second.setAccount(serverId: 'server-a', userId: 'user-a');
      expect(await second.pendingEvents(), isEmpty);
      expect((await second.stats()).totalMinutes, 1);
    },
  );

  test('setting the same account does not trigger repeated changes', () async {
    final service = await open(memory: true);
    await service.setAccount(serverId: 'server-a', userId: 'user-a');
    var notifications = 0;
    final subscription = service.changes.listen((_) => notifications++);
    await service.setAccount(serverId: 'server-a', userId: 'user-a');
    await Future<void>.delayed(Duration.zero);
    expect(notifications, 0);
    await subscription.cancel();
  });

  test(
    'genre repair candidates advance beyond unresolved pages by track key',
    () async {
      final service = await open();
      for (var index = 0; index < 55; index++) {
        final key = index.toString().padLeft(3, '0');
        await service.recordSegment(
          interval(
            id: 'event-$key',
            session: 'session-$key',
            track: 'track-$key',
          ),
        );
      }
      final first = await service.genreMetadataCandidateEvents();
      expect(first.length, 50);
      expect(first.first.trackId, 'track-000');
      expect(first.last.trackId, 'track-049');
      // No first-page metadata resolved: the next lookup still advances.
      final next = await service.genreMetadataCandidates(
        afterTrackId: first.last.trackId,
      );
      expect(next, [
        'track-050',
        'track-051',
        'track-052',
        'track-053',
        'track-054',
      ]);
      final nextEvents = await service.genreMetadataCandidateEvents(
        afterTrackId: first.last.trackId,
      );
      expect(nextEvents.map((event) => event.trackId), next);
      expect(
        await service.genreMetadataCandidates(afterTrackId: next.last),
        isEmpty,
      );
      await service.updateGenreMetadata({
        'track-000': ['Jazz'],
      });
      final wrapped = await service.genreMetadataCandidates();
      expect(wrapped.first, 'track-001');
      expect(wrapped.length, 50);
    },
  );

  for (final example in [
    (
      label: 'missing destination projection',
      destination: null,
      expected: 'Jazz',
    ),
    (
      label: 'existing destination projection',
      destination: <String>['Soul'],
      expected: 'Soul',
    ),
    (
      label: 'explicit unknown destination projection',
      destination: <String>[],
      expected: null,
    ),
  ]) {
    test('offline history import preserves ${example.label}', () async {
      final service = await open();
      final shared = interval(
        id: 'local-shared',
        session: 'local-shared-session',
        track: 'shared-song',
      );
      final additional = interval(
        id: 'local-new',
        session: 'local-new-session',
        track: 'new-song',
        listened: 30000,
      );
      await service.recordSegment(shared);
      await service.recordSegment(additional);
      await service.updateGenreMetadata({
        'shared-song': ['Jazz'],
        'new-song': ['Funk'],
        'never-listened': ['Ghost'],
      });
      await service.setAccount(
        serverId: 'server-a',
        userId: 'user-a',
        historyGeneration: 2,
      );
      final existing = interval(
        id: 'account-shared',
        session: 'account-shared-session',
        track: 'shared-song',
        listened: 45000,
      );
      await service.recordSegment(existing);
      if (example.destination != null) {
        await service.updateGenreMetadata({
          'shared-song': example.destination!,
        });
      }
      await service.importLocalHistory();
      final stats = await service.stats();
      expect(stats.totalListeningMs, 135000);
      expect(
        {for (final genre in stats.topGenres) genre.name: genre.listeningMs},
        {
          if (example.expected != null) example.expected!: 105000,
          'Funk': 30000,
        },
      );
      expect(
        stats.unclassifiedListeningMs,
        example.expected == null ? 105000 : 0,
      );
      expect(await service.genreMetadataCandidates(), isEmpty);
      expect(service.pendingCount, 2);
      expect(
        (await pendingCounterBatch(service))['contributions'],
        hasLength(2),
      );
      final scope = service.accountScope;
      await service.close();
      final reopened = await open();
      expect((await reopened.stats()).totalListeningMs, 0);
      await reopened.setAccount(serverId: 'server-a', userId: 'user-a');
      expect((await reopened.stats()).totalListeningMs, 135000);
      expect(await reopened.genreMetadataCandidates(), isEmpty);
      await reopened.close();
      final database = sqlite3.open(databasePath);
      try {
        final projections = database.select(
          'SELECT track_id FROM stats_genre_metadata WHERE scope=? AND generation=? ORDER BY track_id',
          [scope, 2],
        );
        expect(projections.map((row) => row['track_id']), [
          'new-song',
          'shared-song',
        ]);
        expect(
          database.select(
            "SELECT 1 FROM stats_genre_metadata WHERE scope='local'",
          ),
          isEmpty,
        );
      } finally {
        database.dispose();
      }
    });
  }

  test(
    'catalog genre repair persists scoped projections without altering pending snapshots',
    () async {
      final service = await open();
      final local = interval(track: 'jamiroquai-song', genres: ['Pop', 'Rock']);
      await service.recordSegment(local);
      await service.setAccount(serverId: 'server-a', userId: 'user-a');
      final pending = interval(
        id: 'pending-jamiroquai',
        session: 'account-jamiroquai',
        track: 'jamiroquai-song',
        genres: ['Pop', 'Rock'],
      );
      final unknown = interval(
        id: 'unknown-event',
        session: 'unknown-session',
        track: 'unknown-song',
        genres: ['Pop'],
        listened: 15000,
      );
      await service.recordSegment(pending);
      await service.recordSegment(unknown);
      expect(await service.genreMetadataCandidates(limit: 1), [
        'jamiroquai-song',
      ]);
      final candidate = (await service.genreMetadataCandidateEvents(
        limit: 1,
      )).single;
      expect(counterMetadata(candidate), counterMetadata(pending));
      expect(candidate.albumId, 'album-1');
      await service.updateGenreMetadata({
        'jamiroquai-song': ['acid jazz', 'Electronic', 'funk', 'FUNK'],
        'unknown-song': [],
      });
      final stats = await service.stats();
      expect(stats.totalListeningMs, 75000);
      expect(stats.otherGenreListeningMs, 0);
      expect(stats.unclassifiedListeningMs, 15000);
      expect(
        {for (final genre in stats.topGenres) genre.name: genre.listeningMs},
        {'Acid Jazz': 20000, 'Electronic': 20000, 'Funk': 20000},
      );
      expect(await service.genreMetadataCandidates(), isEmpty);
      expect(await service.genreMetadataCandidateEvents(), isEmpty);
      expect((await pendingCounterBatch(service))['metadata'], {
        counterHash(counterMetadata(pending)): counterMetadata(pending),
        counterHash(counterMetadata(unknown)): counterMetadata(unknown),
      });
      expect(service.pendingCount, 2);
      await confirmCounterBatch(service);
      expect((await service.stats()).totalListeningMs, 75000);
      final scope = service.accountScope;
      await service.close();
      final reopened = await open();
      // Catalog enrichment in the account must not reinterpret anonymous history.
      expect((await reopened.stats()).topGenres.map((genre) => genre.name), [
        'Pop',
        'Rock',
      ]);
      await reopened.setAccount(serverId: 'server-a', userId: 'user-a');
      expect(await reopened.genreMetadataCandidates(), isEmpty);
      expect((await reopened.stats()).topGenres.map((genre) => genre.name), [
        'Acid Jazz',
        'Electronic',
        'Funk',
      ]);
      var notifications = 0;
      final subscription = reopened.changes.listen((_) => notifications++);
      await reopened.updateGenreMetadata({
        'jamiroquai-song': [' FUNK ', 'acid jazz', 'electronic'],
      });
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 0);
      await subscription.cancel();
      await reopened.setAccount(serverId: 'server-b', userId: 'user-b');
      await reopened.updateGenreMetadata(
        {
          'jamiroquai-song': ['Wrong'],
        },
        scope: scope,
        generation: 1,
      );
      await reopened.setAccount(serverId: 'server-a', userId: 'user-a');
      expect((await reopened.stats()).topGenres.map((genre) => genre.name), [
        'Acid Jazz',
        'Electronic',
        'Funk',
      ]);
    },
  );

  test(
    'remote genre metadata commits with events and rolls back on conflicting replay',
    () async {
      final service = await open();
      await service.setAccount(serverId: 'server-a', userId: 'user-a');
      final event = interval(track: 'jamiroquai-song', genres: ['Pop', 'Rock']);
      await service.applyRemote(
        [event],
        cursor: 1,
        historyGeneration: 1,
        genreMetadata: {
          'jamiroquai-song': ['acid jazz', 'Electronic', 'funk'],
        },
      );
      expect(
        (await service.stats()).topGenres.map((genre) => genre.listeningMs),
        [20000, 20000, 20000],
      );
      expect(await service.genreMetadataCandidates(), isEmpty);
      await expectLater(
        service.applyRemote(
          [
            interval(
              track: 'jamiroquai-song',
              genres: ['Altered wire metadata'],
            ),
          ],
          cursor: 2,
          historyGeneration: 1,
          genreMetadata: {
            'jamiroquai-song': ['Wrong'],
          },
        ),
        throwsStateError,
      );
      expect(service.cursor, 1);
      expect((await service.stats()).topGenres.map((genre) => genre.name), [
        'Acid Jazz',
        'Electronic',
        'Funk',
      ]);
      await service.applyRemote([], cursor: 3, historyGeneration: 2);
      await service.recordSegment(
        interval(id: 'next', session: 'next-session', track: 'jamiroquai-song'),
      );
      expect(await service.genreMetadataCandidates(), ['jamiroquai-song']);
      await service.updateGenreMetadata({
        'jamiroquai-song': ['Wrong'],
      }, generation: 1);
      expect((await service.stats()).topGenres.single.name, 'Rock');
    },
  );

  test(
    'genre ranking accounts for genres below the top five and unknown time',
    () async {
      final service = await open();
      await service.recordSegment(
        interval(genres: ['A', 'B', 'C', 'D', 'E', 'F'], listened: 60001),
      );
      await service.recordSegment(
        interval(
          id: 'unknown',
          session: 'unknown-session',
          genres: [],
          listened: 14999,
        ),
      );
      final stats = await service.stats();
      expect(stats.topGenres.length, 5);
      expect(stats.otherGenreListeningMs, 10000);
      expect(stats.unclassifiedListeningMs, 14999);
      expect(
        stats.topGenres.fold<int>(
              0,
              (total, genre) => total + genre.listeningMs,
            ) +
            stats.otherGenreListeningMs +
            stats.unclassifiedListeningMs,
        stats.totalListeningMs,
      );
    },
  );

  test(
    'main artists exclude older saved composer and band member credits',
    () async {
      final service = await open();
      await service.setAccount(serverId: 'server-a', userId: 'user-a');
      final jamiroquai = interval(
        artist: 'jamiroquai',
        artistName: 'Jamiroquai, Jason Kay, Sola Akingbola',
        artists: const [
          ListeningArtist(id: 'jason-kay', name: 'Jason Kay'),
          ListeningArtist(id: 'jamiroquai', name: 'Jamiroquai'),
          ListeningArtist(id: 'sola-akingbola', name: 'Sola Akingbola'),
        ],
      );
      await service.recordSegment(jamiroquai);
      await service.recordSegment(
        interval(
          id: 'in-flames-event',
          session: 'in-flames-session',
          track: 'in-flames-song',
          artist: 'in-flames',
          artistName: 'In Flames',
          listened: 45000,
        ),
      );
      await service.recordSegment(
        interval(
          id: 'avenged-event',
          session: 'avenged-session',
          track: 'avenged-song',
          artist: 'avenged-sevenfold',
          artistName: 'Avenged Sevenfold',
          listened: 15000,
        ),
      );
      final stats = await service.stats();
      expect(stats.uniqueArtists, 3);
      expect(
        {
          for (final artist in stats.topArtists)
            artist.name: artist.listeningMs,
        },
        {'Jamiroquai': 60000, 'In Flames': 45000, 'Avenged Sevenfold': 15000},
      );
      expect(
        stats.topArtists.fold<int>(
          0,
          (total, artist) => total + artist.listeningMs,
        ),
        stats.totalListeningMs,
      );
      expect(
        ((await pendingCounterBatch(service))['metadata'] as Map)[counterHash(
          counterMetadata(jamiroquai),
        )],
        counterMetadata(jamiroquai),
      );
      await confirmCounterBatch(service);
      expect((await service.stats()).totalListeningMs, 120000);
      expect((await service.stats()).uniqueArtists, 3);
    },
  );

  test(
    'missing primary artist uses one deterministic saved fallback',
    () async {
      for (final example in [
        (
          id: '',
          name: 'Jamiroquai',
          expectedId: 'Jamiroquai',
          expectedName: 'Jamiroquai',
        ),
        (
          id: 'jamiroquai',
          name: '',
          expectedId: 'jamiroquai',
          expectedName: 'Jamiroquai',
        ),
        (id: '', name: '', expectedId: 'jason-kay', expectedName: 'Jason Kay'),
      ]) {
        final service = await open(memory: true);
        await service.recordSegment(
          interval(
            artist: example.id,
            artistName: example.name,
            artists: const [
              ListeningArtist(id: '', name: ''),
              ListeningArtist(id: 'jason-kay', name: 'Jason Kay'),
              ListeningArtist(id: 'jamiroquai', name: 'Jamiroquai'),
            ],
          ),
        );
        final stats = await service.stats();
        expect(stats.uniqueArtists, 1);
        expect(stats.topArtists.single.id, example.expectedId);
        expect(stats.topArtists.single.name, example.expectedName);
        expect(stats.topArtists.single.listeningMs, stats.totalListeningMs);
      }
      final unknown = await open(memory: true);
      await unknown.recordSegment(interval(artist: '', artistName: ''));
      expect((await unknown.stats()).uniqueArtists, 0);
      expect((await unknown.stats()).totalListeningMs, 60000);
    },
  );

  test(
    'artist-only migration rebuilds all scopes and generations without changing history or consent',
    () async {
      final service = await open();
      ListeningEvent credited(String id, {int listened = 60001}) => interval(
        id: id,
        session: '$id-session',
        artist: 'jamiroquai',
        artistName: 'Jamiroquai, Jason Kay',
        artists: const [
          ListeningArtist(id: 'jamiroquai', name: 'Jamiroquai'),
          ListeningArtist(id: 'jason-kay', name: 'Jason Kay'),
        ],
        listened: listened,
      );
      await service.recordSegment(credited('local'));
      await service.setAccount(serverId: 'server-a', userId: 'user-a');
      await service.applyRemote(
        [credited('retired')],
        cursor: 7,
        historyGeneration: 1,
      );
      await service.applyRemote(
        [credited('remote')],
        cursor: 9,
        historyGeneration: 2,
      );
      final pending = credited('pending', listened: 15000);
      await service.recordSegment(pending);
      await service.setAccount(serverId: 'server-b', userId: 'user-b');
      await service.applyRemote(
        [credited('other')],
        cursor: 4,
        historyGeneration: 1,
      );
      final device = service.deviceId;
      await service.close();

      String preserved(Database database) => jsonEncode({
        for (final table in [
          'stats_accounts',
          'stats_sessions',
          'stats_events',
        ])
          table: [
            for (final row in database.select(
              'SELECT * FROM $table ORDER BY rowid',
            ))
              {for (final column in row.keys) column: row[column]},
          ],
        'stats_meta': [
          for (final row in database.select(
            "SELECT * FROM stats_meta WHERE key<>'artist_summary_version' ORDER BY key",
          ))
            {for (final column in row.keys) column: row[column]},
        ],
      });
      var database = sqlite3.open(databasePath);
      late String before;
      try {
        // Older clients retained retired generations. Recreate that saved
        // state explicitly now that generation changes delete their rows.
        final scope = jsonEncode(['server-a', 'user-a']);
        database.execute(
          'INSERT INTO stats_sessions SELECT scope,1,id,metadata,listened_ms,qualified '
          'FROM stats_sessions WHERE scope=? AND generation=2',
          [scope],
        );
        database.execute(
          'INSERT INTO stats_events SELECT scope,1,event_id,session_id,started_at_ms,'
          'ended_at_ms,listened_ms,rule_version,end_reason,0,rejected '
          'FROM stats_events WHERE scope=? AND generation=2',
          [scope],
        );
        database.execute(
          'INSERT INTO stats_daily SELECT scope,1,day,kind,item_key,name,artist,listened_ms,plays '
          'FROM stats_daily WHERE scope=? AND generation=2',
          [scope],
        );
        database.execute(
          "DELETE FROM stats_meta WHERE key='artist_summary_version'",
        );
        // Model a saved opt-out preference independently of the history rows.
        database.execute("UPDATE stats_meta SET value='0' WHERE key='enabled'");
        database.execute(
          "INSERT INTO stats_daily(scope,generation,day,kind,item_key,name,artist,listened_ms,plays) "
          "SELECT scope,generation,day,kind,'jason-kay','Jason Kay',artist,listened_ms,plays "
          "FROM stats_daily WHERE kind='artist'",
        );
        before = preserved(database);
      } finally {
        database.dispose();
      }

      final migrated = await open();
      expect(migrated.enabled, isFalse);
      expect(migrated.deviceId, device);
      expect((await migrated.stats()).topArtists.single.name, 'Jamiroquai');
      await migrated.setAccount(serverId: 'server-a', userId: 'user-a');
      expect(migrated.historyGeneration, 2);
      expect(migrated.cursor, 9);
      expect(migrated.pendingCount, 1);
      final stats = await migrated.stats();
      expect(stats.topArtists.single.listeningMs, 75001);
      expect(stats.uniqueArtists, 1);
      expect(stats.totalListeningMs, 75001);
      await migrated.close();
      database = sqlite3.open(databasePath);
      late String rebuilt;
      try {
        expect(preserved(database), before);
        expect(
          database
              .select(
                "SELECT value FROM stats_meta WHERE key='artist_summary_version'",
              )
              .single['value'],
          '1',
        );
        final artistRows = database.select(
          "SELECT * FROM stats_daily WHERE kind='artist' ORDER BY scope,generation,day,item_key",
        );
        expect(artistRows.length, 3);
        expect(
          artistRows.map((row) => row['name']),
          everyElement('Jamiroquai'),
        );
        rebuilt = jsonEncode([
          for (final row in artistRows)
            {for (final column in row.keys) column: row[column]},
        ]);
      } finally {
        database.dispose();
      }
      final reopened = await open();
      await reopened.close();
      database = sqlite3.open(databasePath);
      try {
        expect(
          jsonEncode([
            for (final row in database.select(
              "SELECT * FROM stats_daily WHERE kind='artist' ORDER BY scope,generation,day,item_key",
            ))
              {for (final column in row.keys) column: row[column]},
          ]),
          rebuilt,
        );
        expect(preserved(database), before);
      } finally {
        database.dispose();
      }
    },
  );

  test(
    'genre summaries trim and deduplicate without changing wire snapshots',
    () async {
      final service = await open(memory: true);
      await service.setAccount(serverId: 'server-a', userId: 'user-a');
      final segment = interval(genres: [' Rock ', 'Rock', 'rock', '', '  ']);
      await service.recordSegment(segment);
      final stats = await service.stats();
      expect(stats.topGenres.single.name, 'Rock');
      expect(stats.topGenres.single.minutes, 1);
      expect(
        ((await pendingCounterBatch(service))['metadata'] as Map)
            .values
            .single['genres'],
        segment.genres,
      );
      await confirmCounterBatch(service);
      expect((await service.stats()).topGenres.single.minutes, 1);
    },
  );

  test(
    'multiple genre tags share finite time across normalization, replay and reopen',
    () async {
      final service = await open();
      await service.setAccount(serverId: 'server-a', userId: 'user-a');
      final segment = interval(
        genres: [
          ' Rock ',
          'Acid   Jazz',
          'rock',
          '\tacid jazz\n',
          '\u0085ACID\u2003JAZZ\u00A0',
          '',
        ],
        listened: 60001,
      );
      await service.recordSegment(segment);
      await service.recordSegment(segment);
      expect(
        ((await pendingCounterBatch(service))['metadata'] as Map)
            .values
            .single['genres'],
        segment.genres,
      );
      await confirmCounterBatch(service);
      await service.close();

      final reopened = await open();
      await reopened.setAccount(serverId: 'server-a', userId: 'user-a');
      final stats = await reopened.stats();
      expect(stats.totalListeningMs, 60001);
      expect(stats.totalPlays, 1);
      expect(
        {for (final genre in stats.topGenres) genre.name: genre.listeningMs},
        {'Acid Jazz': 30001, 'Rock': 30000},
      );
      expect(
        stats.topGenres.fold<int>(
          0,
          (total, genre) => total + genre.listeningMs,
        ),
        stats.totalListeningMs,
      );
      expect(reopened.cursor, 0);
      expect(reopened.pendingCount, 0);
    },
  );

  test(
    'genre rounding conserves odd milliseconds across UTC day boundaries',
    () async {
      final service = await open();
      final start = DateTime.utc(
        2026,
        10,
        7,
        23,
        59,
        59,
        999,
      ).millisecondsSinceEpoch;
      await service.recordSegment(
        interval(
          genres: ['Rock', 'Jazz', 'Ambient'],
          listened: 5,
          start: start,
        ),
      );
      final stats = await service.stats(month: 10);
      expect(stats.totalListeningMs, 5);
      expect(
        {for (final genre in stats.topGenres) genre.name: genre.listeningMs},
        {'Ambient': 2, 'Jazz': 2, 'Rock': 1},
      );
      await service.close();
      final database = sqlite3.open(databasePath);
      try {
        final days = database.select(
          "SELECT day,item_key,listened_ms FROM stats_daily WHERE kind='genre' ORDER BY day,item_key",
        );
        final period = DateTime.utc(2026, 10).millisecondsSinceEpoch;
        expect(
          [
            for (final row in days)
              [row['day'], row['item_key'], row['listened_ms']],
          ],
          [
            [period, 'Ambient', 2],
            [period, 'Jazz', 2],
            [period, 'Rock', 1],
          ],
        );
      } finally {
        database.dispose();
      }
    },
  );

  test(
    'genre rounding matches monthly and annual UTC year boundaries',
    () async {
      final service = await open(memory: true);
      final start = DateTime.utc(
        2025,
        12,
        31,
        23,
        59,
        59,
        999,
      ).millisecondsSinceEpoch;
      await service.recordSegment(
        interval(
          genres: ['Rock', 'Jazz', 'Ambient'],
          listened: 5,
          start: start,
        ),
      );
      final previous = await service.stats(year: 2025, month: 12);
      final next = await service.stats(year: 2026, month: 1);
      expect(previous.totalListeningMs, 1);
      expect(next.totalListeningMs, 4);
      expect(
        {for (final genre in previous.topGenres) genre.name: genre.listeningMs},
        {'Ambient': 1},
      );
      expect(
        {for (final genre in next.topGenres) genre.name: genre.listeningMs},
        {'Jazz': 2, 'Ambient': 1, 'Rock': 1},
      );
      final previousYear = await service.stats(year: 2025);
      final nextYear = await service.stats(year: 2026);
      expect(previousYear.topGenres.single.listeningMs, 1);
      expect(
        {for (final genre in nextYear.topGenres) genre.name: genre.listeningMs},
        {'Jazz': 2, 'Ambient': 1, 'Rock': 1},
      );
    },
  );

  test(
    'missing genre tags leave time unclassified without inventing labels',
    () async {
      final service = await open(memory: true);
      await service.recordSegment(interval(genres: ['', ' \t ']));
      final stats = await service.stats();
      expect(stats.totalListeningMs, 60000);
      expect(stats.topGenres, isEmpty);
    },
  );

  test(
    'genre-only migration corrects saved totals and preserves history, cursors and consent',
    () async {
      final service = await open();
      final local = interval(genres: [' Pop ', 'Rock', 'pop'], listened: 60001);
      await service.recordSegment(local);
      await service.setAccount(serverId: 'server-a', userId: 'user-a');
      final remote = interval(
        id: 'remote-event',
        session: 'remote-session',
        genres: ['Jazz', '  Acid   Jazz '],
        listened: 45001,
      );
      await service.applyRemote([remote], cursor: 7, historyGeneration: 1);
      final pending = interval(
        id: 'pending-event',
        session: 'pending-session',
        genres: [],
      );
      await service.recordSegment(pending);
      final device = service.deviceId;
      await service.close();

      String preserved(Database database) => jsonEncode({
        for (final table in [
          'stats_accounts',
          'stats_sessions',
          'stats_events',
        ])
          table: [
            for (final row in database.select(
              'SELECT * FROM $table ORDER BY rowid',
            ))
              {for (final column in row.keys) column: row[column]},
          ],
        'stats_meta': [
          for (final row in database.select(
            "SELECT * FROM stats_meta WHERE key<>'genre_summary_version' ORDER BY key",
          ))
            {for (final column in row.keys) column: row[column]},
        ],
      });
      var database = sqlite3.open(databasePath);
      late String before;
      try {
        // Recreate the former full-duration credit per genre, with no upgrade marker.
        database.execute(
          "DELETE FROM stats_meta WHERE key='genre_summary_version'",
        );
        database.execute(
          "UPDATE stats_daily SET listened_ms=CASE WHEN scope='local' THEN 60001 ELSE 45001 END WHERE kind='genre'",
        );
        before = preserved(database);
      } finally {
        database.dispose();
      }

      final migrated = await open();
      expect(migrated.enabled, isTrue);
      expect(migrated.deviceId, device);
      final localStats = await migrated.stats();
      expect(localStats.totalListeningMs, 60001);
      expect(
        {
          for (final genre in localStats.topGenres)
            genre.name: genre.listeningMs,
        },
        {'Pop': 30001, 'Rock': 30000},
      );
      await migrated.setAccount(serverId: 'server-a', userId: 'user-a');
      expect(migrated.cursor, 7);
      expect(migrated.pendingCount, 1);
      expect(
        ((await pendingCounterBatch(migrated))['metadata'] as Map)
            .values
            .single,
        counterMetadata(pending),
      );
      final accountStats = await migrated.stats();
      expect(accountStats.totalListeningMs, 105001);
      expect(accountStats.totalPlays, 2);
      expect(
        {
          for (final genre in accountStats.topGenres)
            genre.name: genre.listeningMs,
        },
        {'Acid Jazz': 22501, 'Jazz': 22500},
      );
      await migrated.close();
      database = sqlite3.open(databasePath);
      try {
        expect(preserved(database), before);
        expect(
          database
              .select(
                "SELECT value FROM stats_meta WHERE key='genre_summary_version'",
              )
              .single['value'],
          '2',
        );
      } finally {
        database.dispose();
      }
      final reopened = await open();
      await reopened.setAccount(serverId: 'server-a', userId: 'user-a');
      expect(
        (await reopened.stats()).topGenres.map((genre) => genre.listeningMs),
        [22501, 22500],
      );
      expect(reopened.cursor, 7);
      expect(reopened.pendingCount, 1);
    },
  );

  test(
    'genre durations retain short listens after replay and reopen',
    () async {
      final service = await open();
      await service.setAccount(serverId: 'server-a', userId: 'user-a');
      final ambient = interval(
        id: 'ambient-event',
        session: 'ambient-session',
        track: 'ambient-track',
        genres: ['Ambient'],
        listened: 15000,
      );
      final jazz = interval(
        id: 'jazz-event',
        session: 'jazz-session',
        track: 'jazz-track',
        genres: ['Jazz'],
        listened: 45000,
      );
      await service.recordSegment(ambient);
      await service.recordSegment(jazz);
      await confirmCounterBatch(service);
      await service.close();

      final reopened = await open();
      await reopened.setAccount(serverId: 'server-a', userId: 'user-a');
      final stats = await reopened.stats();
      expect(stats.totalListeningMs, 60000);
      expect(stats.topGenres.map((genre) => genre.name), ['Jazz', 'Ambient']);
      expect(stats.topGenres.map((genre) => genre.minutes), [0, 0]);
      expect(stats.topGenres.map((genre) => genre.listeningMs), [45000, 15000]);
    },
  );

  test('older genre responses fall back to their whole-minute duration', () {
    final genre = StatsItem.fromJson({
      'id': 'Rock',
      'name': 'Rock',
      'minutes': 2,
    });
    expect(genre.listeningMs, 120000);
    final shortListen = StatsItem.fromJson({
      'id': 'Jazz',
      'name': 'Jazz',
      'minutes': 0,
      'listening_ms': 12500,
    });
    expect(shortListen.listeningMs, 12500);
  });

  test(
    'repeated acknowledgments cannot reduce the pending counter twice',
    () async {
      final service = await open(memory: true);
      await service.setAccount(serverId: 'server-a', userId: 'user-a');
      await service.recordSegment(interval());
      await service.recordSegment(
        interval(id: 'event-2', session: 'session-2'),
      );
      await service.acknowledge(['event-1', 'event-1', 'unknown']);
      expect(service.pendingCount, 1);
      await confirmCounterBatch(service);
      await service.acknowledge(['event-2', 'event-2']);
      expect(service.pendingCount, 0);
      expect((await service.stats()).totalMinutes, 2);
    },
  );

  test(
    'queued account switch cannot claim an import requested for another account',
    () async {
      final service = await open(memory: true);
      await service.recordSegment(interval());
      await service.setAccount(serverId: 'server-a', userId: 'user-a');
      final changingAccount = service.setAccount(
        serverId: 'server-a',
        userId: 'user-b',
      );
      final importing = service.importLocalHistory();
      await Future.wait([changingAccount, importing]);
      expect((await service.stats()).totalMinutes, 0);
      expect(service.pendingCount, 0);
      expect(service.canImportLocalHistory, isTrue);
      await service.setAccount();
      expect((await service.stats()).totalMinutes, 1);
    },
  );

  test(
    'queued history reset cancels an import requested for the old generation',
    () async {
      final service = await open(memory: true);
      await service.recordSegment(interval());
      await service.setAccount(serverId: 'server-a', userId: 'user-a');
      final resetting = service.setAccount(
        serverId: 'server-a',
        userId: 'user-a',
        historyGeneration: 2,
      );
      final importing = service.importLocalHistory();
      await Future.wait([resetting, importing]);
      expect(service.historyGeneration, 2);
      expect((await service.stats()).totalMinutes, 0);
      expect(service.pendingCount, 0);
      expect(service.canImportLocalHistory, isTrue);
      await service.importLocalHistory();
      expect((await service.stats()).totalMinutes, 1);
      expect(service.pendingCount, 1);
    },
  );
}
