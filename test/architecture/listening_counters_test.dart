import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:phonolite_app/data/models/listening_stats/listening_counters.dart';
import 'package:phonolite_app/data/models/listening_stats/listening_event.dart';
import 'package:phonolite_app/data/repositories/listening_stats_service.dart';

import 'listening_counter_fixtures.dart';
import 'listening_stats_test.dart' show interval;

void main() {
  late Directory directory;
  late String path;
  late ListeningStatsService history;
  Future<void> open() async {
    history = ListeningStatsService(databasePath: path, clock: () => DateTime.utc(2026, 10, 8));
    await history.initialize();
    await history.setAccount(serverId: 'server', userId: 'user');
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('phonolite_counters_');
    path = '${directory.path}/stats.sqlite';
    await open();
  });
  tearDown(() async {
    await history.close();
    await directory.delete(recursive: true);
  });

  Map<String, dynamic> page(Map<String, dynamic> batch, {int revision = 1, int? sequence}) {
    final first = (batch['contributions'] as List).first as Map;
    return {
      'year': first['year'],
      'month': first['month'],
      'history_generation': history.historyGeneration,
      'revision': revision,
      'checkpoint': {'last_sequence': sequence ?? batch['batch_sequence']},
      'contributions': batch['contributions'],
      'metadata': batch['metadata'],
      'genre_metadata': <String, dynamic>{},
      'next_key': '',
      'has_more': false,
    };
  }

  test('a thousand checkpoints retain one aggregate and bounded playback state', () async {
    final start = DateTime.utc(2026, 10, 8).millisecondsSinceEpoch;
    for (var i = 0; i < 1000; i++) {
      await history.recordSegment(
        interval(
          id: 'session:play:$i',
          session: 'session',
          start: start + i * 15000,
          sessionStart: start,
          listened: 15000,
        ),
      );
    }
    expect((await history.stats()).totalListeningMs, 15000000);
    expect((await history.stats()).totalPlays, 1);
    expect(history.pendingCount, 1);
    await history.close();
    final db = sqlite3.open(path);
    try {
      expect(db.select('SELECT COUNT(*) n FROM stats_events').single['n'], 0);
      expect(db.select('SELECT COUNT(*) n FROM stats_counter_rows').single['n'], 1);
      expect(db.select('SELECT COUNT(*) n FROM stats_counter_metadata').single['n'], 1);
      expect(db.select('SELECT COUNT(*) n FROM stats_counter_active').single['n'], 1);
    } finally {
      db.dispose();
    }
  });
  test('frozen batch survives reopen while new listening stays separate', () async {
    await history.recordSegment(interval());
    final frozen = await pendingCounterBatch(history);
    await history.recordSegment(interval(id: 'next', session: 'next'));
    await history.close();
    await open();
    expect(await pendingCounterBatch(history), frozen);
    await history.applyCounterCheckpoint(
      ListeningCounterCheckpoint.fromJson({'upgraded': true, 'last_sequence': 1}),
      collectionRevision: 0,
    );
    expect(history.pendingCount, 2);
    expect((await history.stats()).totalListeningMs, 120000);
    await history.applyCounterPage(ListeningCounterPage.fromJson(page(frozen)), after: '');
    expect(history.pendingCount, 1);
    expect((await history.stats()).totalListeningMs, 120000);
    final next = await history.prepareCounterBatch(collectionRevision: 0).then((batch) => batch?.toJson()) as Map;
    expect(next['batch_sequence'], 2);
    expect((next['contributions'] as List).single['listened_ms'], 60000);
  });
  test('snapshot pages stage atomically and restart after a revision conflict', () async {
    await history.recordSegment(interval());
    await history.recordSegment(interval(id: 'other', session: 'other', track: 'other'));
    final frozen = await pendingCounterBatch(history);
    final rows = frozen['contributions'] as List;
    final first = {
      ...page(frozen),
      'contributions': [rows.first],
      'has_more': true,
      'next_key': rows.first['metadata_id'],
    };
    await history.applyCounterPage(ListeningCounterPage.fromJson(first), after: '');
    expect(history.pendingCount, 2);
    expect((await history.stats()).totalListeningMs, 120000);
    await expectLater(
      history.applyCounterPage(
        ListeningCounterPage.fromJson({
          ...page(frozen, revision: 2),
          'contributions': [rows.last],
        }),
        after: first['next_key'],
      ),
      throwsStateError,
    );
    expect(history.pendingCount, 2);
    await history.applyCounterPage(ListeningCounterPage.fromJson({...first, 'revision': 2}), after: '');
    await history.applyCounterPage(
      ListeningCounterPage.fromJson({
        ...page(frozen, revision: 2),
        'contributions': [rows.last],
      }),
      after: first['next_key'],
    );
    expect(history.pendingCount, 0);
    expect((await history.stats()).totalListeningMs, 120000);
  });
  for (final accepted in [false, true]) {
    test('opt-out barrier resolves ${accepted ? 'accepted' : 'unaccepted'} outstanding batch', () async {
      await history.recordSegment(interval());
      final frozen = await pendingCounterBatch(history);
      await history.setEnabled(false);
      await history.setEnabled(true);
      await history.applyCounterCheckpoint(
        ListeningCounterCheckpoint.fromJson({'upgraded': true, 'last_sequence': accepted ? 1 : 0}),
        collectionRevision: 2,
      );
      if (accepted) {
        expect(history.pendingCount, 1);
        await history.applyCounterPage(ListeningCounterPage.fromJson(page(frozen)), after: '');
      }
      expect(history.pendingCount, 0);
      expect((await history.stats()).totalListeningMs, 60000);
      await history.recordSegment(interval(id: 'fresh', session: 'fresh'));
      final next = await history.prepareCounterBatch(collectionRevision: 2).then((batch) => batch?.toJson()) as Map;
      expect(next['batch_sequence'], accepted ? 2 : 1);
      expect((next['contributions'] as List).single['listened_ms'], 60000);
    });
  }
  test('v1 migration retains original pending IDs until handoff and compacts them', () async {
    final old = interval();
    await history.applyRemote([old], cursor: 1, historyGeneration: 1);
    final scope = history.accountScope;
    await history.close();
    final db = sqlite3.open(path);
    try {
      db.execute('UPDATE stats_events SET pending=1');
      db.execute('UPDATE stats_accounts SET pending_count=1 WHERE scope=?', [scope]);
      db.execute("DELETE FROM stats_meta WHERE key='counter_version'");
      for (final table in [
        'stats_counter_rows',
        'stats_counter_metadata',
        'stats_counter_devices',
        'stats_counter_months',
      ]) {
        db.execute('DELETE FROM $table');
      }
    } finally {
      db.dispose();
    }
    await open();
    expect((await history.pendingEvents()).single.toJson(), old.toJson());
    await history.recordSegment(interval(id: 'new', session: 'new'));
    expect((await history.stats()).totalListeningMs, 120000);
    await history.acknowledge([old.eventId]);
    await history.compactLegacyCounters();
    expect(await history.pendingEvents(), isEmpty);
    expect((await history.stats()).totalListeningMs, 120000);
    final batch = await pendingCounterBatch(history);
    expect((batch['contributions'] as List).single['listened_ms'], 60000);
    await history.close();
    final compacted = sqlite3.open(path);
    try {
      expect(compacted.select('SELECT COUNT(*) n FROM stats_events').single['n'], 0);
    } finally {
      compacted.dispose();
    }
  });
  test('genre projection rounds combined cache and pending monthly totals', () async {
    await history.recordSegment(interval(listened: 1));
    await confirmCounterBatch(history);
    await history.updateGenreMetadata({
      'track-1': ['Jazz', 'Metal'],
    });
    await history.recordSegment(interval(id: 'second', session: 'second', listened: 1));
    final before = await history.stats();
    expect({for (final genre in before.topGenres) genre.name: genre.listeningMs}, {'Jazz': 1, 'Metal': 1});
    final batch = await pendingCounterBatch(history);
    final row = Map<String, dynamic>.from((batch['contributions'] as List).single as Map);
    row['listened_ms'] = 2;
    row['genre_ms'] = {'Rock': 2};
    await history.applyCounterPage(
      ListeningCounterPage.fromJson({
        ...page(batch, revision: 2),
        'contributions': [row],
        'genre_metadata': {
          'track-1': ['Jazz', 'Metal'],
        },
      }),
      after: '',
    );
    final after = await history.stats();
    expect(after.totalListeningMs, before.totalListeningMs);
    expect({for (final genre in after.topGenres) genre.name: genre.listeningMs}, {'Jazz': 1, 'Metal': 1});
  });
  test('metadata IDs use canonical UTF-8 JSON shared with the server', () async {
    expect(
      counterHash({
        'track_id': 'track',
        'title': 'Song',
        'artist_id': 'artist',
        'artist_name': 'Artist',
        'album_id': 'album',
        'album_title': 'Album',
        'genres': ['Rock', 'Jazz'],
        'artists': [],
        'track_duration_ms': 180000,
      }),
      'e708f5b7c70a6ce7499354c4a0c9f7ad7357a58b16278e0cef3f6e86f40201da',
    );
    await history.recordSegment(interval(genres: ['Rock', 'Jazz']));
    final batch = await pendingCounterBatch(history);
    final metadata = batch['metadata'] as Map;
    expect(metadata.keys.single, counterHash(metadata.values.single));
    expect(utf8.encode(jsonEncode(batch)).length, lessThan(256 * 1024));
  });
  test('an oversized metadata snapshot remains local without blocking other tracks', () async {
    final credits = [for (var i = 0; i < 64; i++) ListeningArtist(id: 'artist-$i', name: 'x' * 4096)];
    await history.recordSegment(interval(artists: credits));
    await history.recordSegment(interval(id: 'other', session: 'other', track: 'other'));
    final batch = await pendingCounterBatch(history);
    expect(utf8.encode(jsonEncode(batch)).length, lessThanOrEqualTo(256 * 1024));
    expect((batch['metadata'] as Map).values.single['track_id'], 'other');
    await confirmCounterBatch(history);
    final next = await history.prepareCounterBatch(collectionRevision: 0).then((batch) => batch?.toJson());
    expect(next, isNull);
    expect(history.pendingCount, 0);
    expect((await history.stats()).totalListeningMs, 120000);
  });
}
