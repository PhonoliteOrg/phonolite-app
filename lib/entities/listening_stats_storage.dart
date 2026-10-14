import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:sqlite3/sqlite3.dart';
import 'package:crypto/crypto.dart';

part 'listening_stats_counters.dart';

/// Reports attribute a listen to one identified main artist, rather than every
/// contributor. Older snapshots may include composers and band members; use a
/// matching saved credit only to recover the main artist's individual name.
({String id, String name})? listeningPrimaryArtist(
  Map<String, dynamic> metadata,
) {
  final id = metadata['artist_id']?.toString().trim() ?? '';
  final name = metadata['artist_name']?.toString().trim() ?? '';
  final credits = metadata['artists'] as List? ?? const [];
  if (id.isNotEmpty) {
    for (final credit in credits) {
      final artist = credit as Map;
      if (artist['id']?.toString().trim() == id) {
        final individual = artist['name']?.toString().trim() ?? '';
        if (individual.isNotEmpty) return (id: id, name: individual);
      }
    }
    return (id: id, name: name.isEmpty ? id : name);
  }
  if (name.isNotEmpty) return (id: '', name: name);
  for (final credit in credits) {
    final artist = credit as Map;
    final creditId = artist['id']?.toString().trim() ?? '';
    final creditName = artist['name']?.toString().trim() ?? '';
    if (creditId.isNotEmpty || creditName.isNotEmpty) {
      return (id: creditId, name: creditName.isEmpty ? creditId : creditName);
    }
  }
  return null;
}

/// One serialized, long-lived SQLite worker. No database work runs on the
/// playback/UI isolate, and counter changes and their playback state commit
/// together. The worker only exists during the owning application's lifetime.
class ListeningStatsStorage {
  ReceivePort? _replies;
  Isolate? _worker;
  SendPort? _commands;
  final _pending = <int, Completer<dynamic>>{};
  int _nextId = 0;

  Future<Map<String, dynamic>> initialize(
    String path, {
    required String deviceId,
  }) async {
    final ready = Completer<Map<String, dynamic>>();
    _replies = ReceivePort();
    _replies!.listen((dynamic message) {
      final value = message as Map;
      if (value.containsKey('ready')) {
        _commands = value['ready'] as SendPort;
        ready.complete(Map<String, dynamic>.from(value['state'] as Map));
      } else if (value.containsKey('startup_error')) {
        ready.completeError(StateError(value['startup_error'] as String));
      } else {
        final completion = _pending.remove(value['id']);
        if (value.containsKey('error')) {
          completion?.completeError(StateError(value['error'] as String));
        } else {
          completion?.complete(value['result']);
        }
      }
    });
    try {
      _worker = await Isolate.spawn(_listeningWorker, {
        'path': path,
        'device_id': deviceId,
        'reply': _replies!.sendPort,
      });
      return await ready.future;
    } catch (_) {
      _replies?.close();
      _worker?.kill();
      rethrow;
    }
  }

  Future<dynamic> request(String command, Map<String, dynamic> arguments) {
    if (_commands == null) {
      return Future.error(StateError('Listening database is unavailable'));
    }
    final id = ++_nextId;
    final completion = Completer<dynamic>();
    _pending[id] = completion;
    _commands!.send({'id': id, 'command': command, 'arguments': arguments});
    return completion.future;
  }

  Future<void> close() async {
    if (_commands != null) {
      await request('close', const {});
      _commands = null;
    }
    _replies?.close();
    _worker?.kill();
    _worker = null;
  }
}

void _listeningWorker(Map<String, dynamic> configuration) {
  final reply = configuration['reply'] as SendPort;
  final commands = ReceivePort();
  _ListeningDatabase database;
  try {
    database = _ListeningDatabase(
      configuration['path'] as String,
      configuration['device_id'] as String,
    );
    reply.send({'ready': commands.sendPort, 'state': database.state('local')});
  } catch (error) {
    reply.send({'startup_error': error.toString()});
    commands.close();
    return;
  }
  commands.listen((dynamic message) {
    final request = message as Map;
    final command = request['command'] as String;
    try {
      final result = database.execute(
        command,
        Map<String, dynamic>.from(request['arguments'] as Map),
      );
      reply.send({'id': request['id'], 'result': result});
      if (command == 'close') commands.close();
    } catch (error) {
      reply.send({'id': request['id'], 'error': error.toString()});
    }
  });
}

class _ListeningDatabase {
  _ListeningDatabase(String path, String deviceId) : db = sqlite3.open(path) {
    try {
      db.execute('PRAGMA journal_mode = WAL');
      db.execute('PRAGMA synchronous = FULL');
      db.execute('PRAGMA busy_timeout = 5000');
      db.execute('''
        CREATE TABLE IF NOT EXISTS stats_meta (
          key TEXT PRIMARY KEY, value TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS stats_accounts (
          scope TEXT PRIMARY KEY, generation INTEGER NOT NULL DEFAULT 1,
          cursor INTEGER NOT NULL DEFAULT 0, synced_at INTEGER,
          pending_count INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS stats_sessions (
          scope TEXT NOT NULL, generation INTEGER NOT NULL, id TEXT NOT NULL,
          metadata TEXT NOT NULL, listened_ms INTEGER NOT NULL DEFAULT 0,
          qualified INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY(scope, generation, id)
        );
        CREATE TABLE IF NOT EXISTS stats_events (
          scope TEXT NOT NULL, generation INTEGER NOT NULL, event_id TEXT NOT NULL,
          session_id TEXT NOT NULL, started_at_ms INTEGER NOT NULL,
          ended_at_ms INTEGER NOT NULL, listened_ms INTEGER NOT NULL,
          rule_version INTEGER NOT NULL, end_reason TEXT,
          pending INTEGER NOT NULL DEFAULT 0,
          rejected INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY(scope, generation, event_id)
        );
        CREATE INDEX IF NOT EXISTS stats_pending
          ON stats_events(scope, generation, pending, started_at_ms);
        CREATE TABLE IF NOT EXISTS stats_daily (
          scope TEXT NOT NULL, generation INTEGER NOT NULL, day INTEGER NOT NULL,
          kind TEXT NOT NULL, item_key TEXT NOT NULL, name TEXT NOT NULL,
          artist TEXT NOT NULL, listened_ms INTEGER NOT NULL DEFAULT 0,
          plays INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY(scope, generation, day, kind, item_key)
        );
        CREATE TABLE IF NOT EXISTS stats_genre_metadata (
          scope TEXT NOT NULL, generation INTEGER NOT NULL,
          track_id TEXT NOT NULL, genres TEXT NOT NULL,
          PRIMARY KEY(scope, generation, track_id)
        );
        CREATE INDEX IF NOT EXISTS stats_session_track
          ON stats_sessions(scope, generation, json_extract(metadata,'\$.track_id'));
      ''');
      final accountColumns = db.select('PRAGMA table_info(stats_accounts)');
      if (!accountColumns.any((column) => column['name'] == 'pending_count')) {
        db.execute(
          'ALTER TABLE stats_accounts ADD COLUMN pending_count INTEGER NOT NULL DEFAULT 0',
        );
        db.execute(
          'UPDATE stats_accounts SET pending_count=(SELECT COUNT(*) FROM stats_events e '
          'WHERE e.scope=stats_accounts.scope AND e.generation=stats_accounts.generation AND e.pending=1)',
        );
      }
      final eventColumns = db.select('PRAGMA table_info(stats_events)');
      if (!eventColumns.any((column) => column['name'] == 'rejected')) {
        db.execute(
          'ALTER TABLE stats_events ADD COLUMN rejected INTEGER NOT NULL DEFAULT 0',
        );
      }
      db.execute('INSERT OR IGNORE INTO stats_meta(key,value) VALUES (?,?)', [
        'enabled',
        '1',
      ]);
      db.execute('INSERT OR IGNORE INTO stats_meta(key,value) VALUES (?,?)', [
        'device_id',
        deviceId,
      ]);
      _ensureAccount('local');
      _migrateDurationSummaries(
        'genre',
        'genre_summary_version',
        _genreSummaryVersion,
      );
      _migrateDurationSummaries(
        'artist',
        'artist_summary_version',
        _artistSummaryVersion,
      );
      _initializeCounters();
    } catch (_) {
      db.dispose();
      rethrow;
    }
  }

  final Database db;
  final _writes = <String, PreparedStatement>{};

  static const _genreSummaryVersion = '2';
  static const _artistSummaryVersion = '1';
  // Unicode White_Space matches the server's split_whitespace exactly.
  static final _genreWhitespace = RegExp(
    r'[\u0009-\u000D\u0020\u0085\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000]+',
  );

  // This changes only derived summaries. Wire snapshots remain immutable so
  // queued uploads, duplicate detection, and cross-device replay stay valid.
  void _migrateDurationSummaries(String kind, String marker, String target) {
    final version = db.select('SELECT value FROM stats_meta WHERE key=?', [
      marker,
    ]);
    if (version.isNotEmpty && version.single['value'] == target) {
      return;
    }
    _transaction(() {
      _rebuildDurationSummaries(kind);
      db.execute(
        'INSERT INTO stats_meta(key,value) VALUES (?,?) '
        'ON CONFLICT(key) DO UPDATE SET value=excluded.value',
        [marker, target],
      );
    });
  }

  void _rebuildDurationSummaries(
    String kind, {
    String? scope,
    int? generation,
  }) {
    final filter = scope == null ? '' : ' AND scope=? AND generation=?';
    final parameters = scope == null
        ? <Object?>[]
        : <Object?>[scope, generation];
    db.execute('DELETE FROM stats_daily WHERE kind=?$filter', [
      kind,
      ...parameters,
    ]);
    var afterRow = 0;
    while (true) {
      // Bound memory during migration and catalog enrichment for large histories.
      final rows = db.select(
        'SELECT e.rowid AS migration_rowid,e.scope,e.generation,'
        'e.started_at_ms,e.ended_at_ms,e.listened_ms,s.metadata '
        'FROM stats_events e JOIN stats_sessions s '
        'ON s.scope=e.scope AND s.generation=e.generation AND s.id=e.session_id '
        'WHERE e.rowid>?${scope == null ? '' : ' AND e.scope=? AND e.generation=?'} '
        'ORDER BY e.rowid LIMIT 512',
        [afterRow, ...parameters],
      );
      if (rows.isEmpty) break;
      final snapshots = <String, Map<String, dynamic>>{};
      for (final row in rows) {
        final encoded = row['metadata'] as String;
        final metadata = snapshots.putIfAbsent(
          encoded,
          () => Map<String, dynamic>.from(jsonDecode(encoded) as Map),
        );
        _duration(
          row['scope'] as String,
          row['generation'] as int,
          metadata,
          row['started_at_ms'] as int,
          row['ended_at_ms'] as int,
          row['listened_ms'] as int,
          genresOnly: kind == 'genre',
          artistsOnly: kind == 'artist',
        );
      }
      afterRow = rows.last['migration_rowid'] as int;
    }
  }

  bool _applyGenreMetadata(String scope, int generation, Map genres) {
    var changed = false;
    for (final entry in genres.entries) {
      final trackId = entry.key.toString().trim();
      if (trackId.isEmpty || entry.value is! List) continue;
      final encoded = jsonEncode(_genres({'genres': entry.value}));
      final previous = db.select(
        'SELECT genres FROM stats_genre_metadata WHERE scope=? AND generation=? AND track_id=?',
        [scope, generation, trackId],
      );
      if (previous.isNotEmpty && previous.single['genres'] == encoded) continue;
      _write(
        'INSERT INTO stats_genre_metadata(scope,generation,track_id,genres) VALUES (?,?,?,?) '
        'ON CONFLICT(scope,generation,track_id) DO UPDATE SET genres=excluded.genres',
        [scope, generation, trackId, encoded],
      );
      changed = true;
    }
    if (changed) {
      _rebuildDurationSummaries('genre', scope: scope, generation: generation);
    }
    return changed;
  }

  List<String> _genres(Map<String, dynamic> metadata) {
    final keys =
        (metadata['genres'] as List? ?? const [])
            .cast<String>()
            .map(
              (genre) => genre
                  .split(_genreWhitespace)
                  .where((word) => word.isNotEmpty)
                  .join(' ')
                  .toLowerCase(),
            )
            .where((genre) => genre.isNotEmpty)
            .toSet()
            .toList()
          ..sort(_compareGenreKeys);
    return [
      for (final key in keys)
        key
            .split(' ')
            .map((word) {
              final first = String.fromCharCode(word.runes.first);
              return first.toUpperCase() + word.substring(first.length);
            })
            .join(' '),
    ];
  }

  int _compareGenreKeys(String left, String right) {
    // Dart's UTF-16 ordering differs from Rust for supplementary letters.
    final leftRunes = left.runes.iterator;
    final rightRunes = right.runes.iterator;
    while (leftRunes.moveNext()) {
      if (!rightRunes.moveNext()) return 1;
      final order = leftRunes.current.compareTo(rightRunes.current);
      if (order != 0) return order;
    }
    return rightRunes.moveNext() ? -1 : 0;
  }

  int _genreShare(int milliseconds, int count, int index) =>
      milliseconds ~/ count + (index < milliseconds % count ? 1 : 0);

  void _write(String sql, List<Object?> parameters) {
    _writes.putIfAbsent(sql, () => db.prepare(sql)).execute(parameters);
  }

  bool get enabled => _meta('enabled') == '1';
  String _meta(String key) =>
      db.select('SELECT value FROM stats_meta WHERE key = ?', [
            key,
          ]).single['value']
          as String;

  void _ensureAccount(String scope) => db.execute(
    'INSERT OR IGNORE INTO stats_accounts(scope) VALUES (?)',
    [scope],
  );

  Row _account(String scope) {
    _ensureAccount(scope);
    return db.select('SELECT * FROM stats_accounts WHERE scope = ?', [
      scope,
    ]).single;
  }

  Map<String, dynamic> state(String scope) {
    final account = _account(scope);
    return {
      'enabled': enabled,
      'device_id': _meta('device_id'),
      'consent_epoch': int.parse(_meta('consent_epoch')),
      'generation': account['generation'],
      'cursor': account['cursor'],
      'synced_at': account['synced_at'],
      'pending_count':
          (account['pending_count'] as int) + _counterPendingCount(scope),
      'has_local_history': db
          .select(
            "SELECT 1 FROM stats_counter_rows WHERE scope = 'local' LIMIT 1",
          )
          .isNotEmpty,
    };
  }

  dynamic execute(String command, Map<String, dynamic> args) {
    if (command.startsWith('counter_')) return _counterCommand(command, args);
    switch (command) {
      case 'state':
        return state(args['scope'] as String);
      case 'enabled':
        _transaction(() {
          db.execute(
            "UPDATE stats_meta SET value=CAST(CAST(value AS INTEGER)+1 AS TEXT) WHERE key='consent_epoch'",
          );
          db.execute('UPDATE stats_meta SET value = ? WHERE key = ?', [
            args['enabled'] == true ? '1' : '0',
            'enabled',
          ]);
          if (args['enabled'] != true) {
            _disableCounters();
            // Opting out also cancels unsent uploads from earlier listening.
            db.execute('UPDATE stats_events SET pending = 0 WHERE pending = 1');
            db.execute('UPDATE stats_accounts SET pending_count=0');
          }
        });
        return null;
      case 'account':
        final scope = args['scope'] as String;
        _transaction(() {
          _ensureAccount(scope);
          if (args['generation'] != null) {
            _setGeneration(
              scope,
              args['generation'] as int,
              preserveLocalStatistics:
                  args['preserve_local_statistics'] == true,
            );
          }
        });
        return state(scope);
      case 'reset_local':
        _transaction(() {
          final generation = _account('local')['generation'] as int;
          _setGeneration('local', generation + 1);
        });
        return null;
      case 'reset_device':
        _transaction(() {
          for (final account in db.select(
            'SELECT scope,generation FROM stats_accounts',
          )) {
            final scope = account['scope'] as String;
            final generation = account['generation'] as int;
            _clearStatistics(scope);
            db.execute(
              'UPDATE stats_accounts SET generation=?,cursor=0,synced_at=NULL,pending_count=0 WHERE scope=?',
              [scope == 'local' ? generation + 1 : generation, scope],
            );
          }
        });
        return null;
      case 'record':
        if (!enabled) return null;
        final scope = args['scope'] as String;
        final generation = args['generation'] as int;
        _transaction(() {
          // A delayed segment from a deleted generation must not return.
          if (_account(scope)['generation'] != generation) return;
          _recordCounter(
            scope,
            generation,
            Map<String, dynamic>.from(args['event'] as Map),
          );
        });
        return null;
      case 'pending':
        if (!enabled) return <Map<String, dynamic>>[];
        final scope = args['scope'] as String;
        final generation = _account(scope)['generation'] as int;
        return db
            .select(
              'SELECT e.*, s.metadata FROM stats_events e '
              'JOIN stats_sessions s ON s.scope=e.scope AND s.generation=e.generation '
              'AND s.id=e.session_id WHERE e.scope=? AND e.generation=? AND e.pending=1 '
              'ORDER BY e.started_at_ms, e.event_id LIMIT ?',
              [scope, generation, args['limit']],
            )
            .map(_payload)
            .toList();
      case 'acknowledge':
      case 'reject':
        final scope = args['scope'] as String;
        final generation = _account(scope)['generation'];
        _transaction(() {
          for (final id in args['ids'] as List) {
            _write(
              'UPDATE stats_events SET pending=0,rejected=? WHERE scope=? AND generation=? AND event_id=? AND pending=1',
              [command == 'reject' ? 1 : 0, scope, generation, id],
            );
            final settled = db.updatedRows;
            if (settled > 0) {
              _write(
                'UPDATE stats_accounts SET pending_count=pending_count-? WHERE scope=?',
                [settled, scope],
              );
            }
          }
          _rebuildLegacyCounters(scope);
        });
        return null;
      case 'remote':
        final scope = args['scope'] as String;
        if (scope == 'local') {
          throw StateError('Remote history needs an account');
        }
        final generation = args['generation'] as int;
        _transaction(() {
          _ensureAccount(scope);
          if (!_setGeneration(scope, generation)) return;
          _applyGenreMetadata(
            scope,
            generation,
            args['genre_metadata'] as Map? ?? const {},
          );
          for (final event in args['events'] as List) {
            _insert(
              scope,
              generation,
              Map<String, dynamic>.from(event as Map),
              pending: false,
            );
          }
          _rebuildLegacyCounters(scope);
          db.execute(
            'UPDATE stats_accounts SET cursor=MAX(cursor,?), synced_at=? WHERE scope=?',
            [args['cursor'], args['synced_at'], scope],
          );
        });
        return null;
      case 'genre_metadata_candidates':
      case 'genre_metadata_candidate_events':
        return _counterCandidates(command, args);
      case 'genre_metadata':
        final scope = args['scope'] as String;
        final generation = args['generation'] as int;
        if (_account(scope)['generation'] != generation) return false;
        var changed = false;
        _transaction(() {
          changed = _applyGenreMetadata(
            scope,
            generation,
            args['genres'] as Map,
          );
        });
        return changed;
      case 'import':
        _transaction(() => _importCounters(args['scope'] as String));
        return null;
      case 'stats':
        _projectCounters(args['scope'] as String);
        return _stats(args);
      case 'close':
        for (final statement in _writes.values) {
          statement.dispose();
        }
        _writes.clear();
        db.dispose();
        return null;
      default:
        throw ArgumentError('Unknown listening storage operation: $command');
    }
  }

  void _clearStatistics(String scope, {bool preserveLocalStatistics = false}) {
    if (preserveLocalStatistics) {
      // A reset on another device retires old uploads, but that device cannot
      // delete this device's local totals. Retain them without uploading them.
      for (final row in db.select(
        "SELECT DISTINCT bucket FROM stats_counter_rows WHERE scope=? AND bucket!='private'",
        [scope],
      )) {
        _moveBucket(scope, row['bucket'] as String, 'private');
      }
    }
    for (final table in [
      if (!preserveLocalStatistics) 'stats_counter_rows',
      if (!preserveLocalStatistics) 'stats_counter_metadata',
      'stats_counter_devices',
      'stats_counter_months',
      'stats_counter_active',
      'stats_counter_batch',
      'stats_counter_stage',
      'stats_events',
      'stats_sessions',
      'stats_daily',
      if (!preserveLocalStatistics) 'stats_genre_metadata',
    ]) {
      db.execute('DELETE FROM $table WHERE scope=?', [scope]);
    }
  }

  // Server generations only advance. A reset initiated on this device clears
  // its copies; learning about another device's reset preserves local totals.
  bool _setGeneration(
    String scope,
    int generation, {
    bool preserveLocalStatistics = false,
  }) {
    if (generation < 1) throw ArgumentError('Invalid history generation');
    final current = _account(scope)['generation'] as int;
    if (generation < current) return false;
    if (generation > current) {
      _clearStatistics(scope, preserveLocalStatistics: preserveLocalStatistics);
      if (preserveLocalStatistics) {
        db.execute(
          'UPDATE stats_genre_metadata SET generation=? WHERE scope=?',
          [generation, scope],
        );
      }
      db.execute(
        'UPDATE stats_accounts SET generation=?,cursor=0,synced_at=NULL,pending_count=0 WHERE scope=?',
        [generation, scope],
      );
    }
    return true;
  }

  void _transaction(void Function() body) {
    db.execute('BEGIN IMMEDIATE');
    try {
      body();
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  Map<String, dynamic> _snapshot(Map<String, dynamic> event) => {
    'session_id': event['session_id'],
    'device_id': event['device_id'],
    'track_id': event['track_id'],
    'title': event['title'] ?? '',
    'artist_id': event['artist_id'] ?? '',
    'artist_name': event['artist_name'] ?? '',
    'album_id': event['album_id'] ?? '',
    'album_title': event['album_title'] ?? '',
    'genres': event['genres'] ?? <String>[],
    'artists': event['artists'] ?? <Map<String, dynamic>>[],
    'track_duration_ms': event['track_duration_ms'] ?? 0,
    'session_started_at_ms': event['session_started_at_ms'],
  };

  Map<String, dynamic> _payload(Row row) => {
    'event_id': row['event_id'],
    ...Map<String, dynamic>.from(jsonDecode(row['metadata'] as String) as Map),
    'started_at_ms': row['started_at_ms'],
    'ended_at_ms': row['ended_at_ms'],
    'listened_ms': row['listened_ms'],
    'rule_version': row['rule_version'],
    if (row['end_reason'] != null) 'end_reason': row['end_reason'],
  };

  void _insert(
    String scope,
    int generation,
    Map<String, dynamic> event, {
    required bool pending,
  }) {
    final listened = (event['listened_ms'] as num).toInt();
    final start = (event['started_at_ms'] as num).toInt();
    final end = (event['ended_at_ms'] as num).toInt();
    final sessionStart = (event['session_started_at_ms'] as num).toInt();
    if (listened < 0 ||
        start < 0 ||
        end < start ||
        sessionStart < 0 ||
        (listened == 0 && event['end_reason'] == null) ||
        (event['rule_version'] as num? ?? 1) != 1 ||
        ['event_id', 'session_id', 'device_id', 'track_id'].any(
          (key) => event[key] is! String || (event[key] as String).isEmpty,
        )) {
      throw ArgumentError('Invalid listening interval');
    }
    final metadata = _snapshot(event);
    final encoded = jsonEncode(metadata);
    final existing = db.select(
      'SELECT e.*,s.metadata FROM stats_events e JOIN stats_sessions s '
      'ON s.scope=e.scope AND s.generation=e.generation AND s.id=e.session_id '
      'WHERE e.scope=? AND e.generation=? AND e.event_id=?',
      [scope, generation, event['event_id']],
    );
    if (existing.isNotEmpty) {
      final previous = _payload(existing.single);
      final normalized = {
        'event_id': event['event_id'],
        ...metadata,
        'started_at_ms': start,
        'ended_at_ms': end,
        'listened_ms': listened,
        'rule_version': event['rule_version'] ?? 1,
        if (event['end_reason'] != null) 'end_reason': event['end_reason'],
      };
      if (jsonEncode(previous) != jsonEncode(normalized)) {
        throw StateError('Listening event ID was reused with different data');
      }
      // A replay from the server confirms ingestion without queueing it again.
      if (!pending) {
        db.execute(
          'UPDATE stats_events SET pending=0,rejected=0 WHERE scope=? AND generation=? AND event_id=?',
          [scope, generation, event['event_id']],
        );
        if (existing.single['pending'] == 1) {
          _write(
            'UPDATE stats_accounts SET pending_count=pending_count-1 WHERE scope=?',
            [scope],
          );
        }
      }
      return;
    }
    _write(
      'INSERT OR IGNORE INTO stats_sessions(scope,generation,id,metadata) VALUES (?,?,?,?)',
      [scope, generation, event['session_id'], encoded],
    );
    final session = db.select(
      'SELECT * FROM stats_sessions WHERE scope=? AND generation=? AND id=?',
      [scope, generation, event['session_id']],
    ).single;
    if (session['metadata'] != encoded) {
      throw StateError('Listening session metadata changed');
    }
    _write(
      'INSERT INTO stats_events(scope,generation,event_id,session_id,started_at_ms,'
      'ended_at_ms,listened_ms,rule_version,end_reason,pending) VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        scope,
        generation,
        event['event_id'],
        event['session_id'],
        start,
        end,
        listened,
        event['rule_version'] ?? 1,
        event['end_reason'],
        pending ? 1 : 0,
      ],
    );
    if (pending) {
      _write(
        'UPDATE stats_accounts SET pending_count=pending_count+1 WHERE scope=?',
        [scope],
      );
    }
    _duration(scope, generation, metadata, start, end, listened);
    final total = (session['listened_ms'] as int) + listened;
    final trackDuration = (metadata['track_duration_ms'] as num).toInt();
    final threshold = trackDuration > 0
        ? min(30000, max(1, (trackDuration / 2).ceil()))
        : 30000;
    final qualified = session['qualified'] == 1 || total >= threshold;
    if (session['qualified'] == 0 && qualified) {
      _summary(
        scope,
        generation,
        _day(sessionStart),
        'track',
        metadata['track_id'] as String,
        metadata['title'] as String,
        metadata['artist_name'] as String,
        0,
        1,
      );
    }
    _write(
      'UPDATE stats_sessions SET listened_ms=?,qualified=? WHERE scope=? AND generation=? AND id=?',
      [total, qualified ? 1 : 0, scope, generation, event['session_id']],
    );
  }

  static const _dayMs = 86400000;
  int _day(int time) => time ~/ _dayMs * _dayMs;

  void _duration(
    String scope,
    int generation,
    Map<String, dynamic> metadata,
    int start,
    int end,
    int listened, {
    bool genresOnly = false,
    bool artistsOnly = false,
  }) {
    if (listened == 0) return;
    final projection = artistsOnly
        ? const <Row>[]
        : db.select(
            'SELECT genres FROM stats_genre_metadata WHERE scope=? AND generation=? AND track_id=?',
            [scope, generation, metadata['track_id']],
          );
    final genres = artistsOnly
        ? const <String>[]
        : _genres(
            projection.isEmpty
                ? metadata
                : {'genres': jsonDecode(projection.single['genres'] as String)},
          );
    final artist = genresOnly ? null : listeningPrimaryArtist(metadata);
    var position = start;
    var allocated = 0;
    do {
      final day = _day(position);
      final next = min(end, day + _dayMs);
      final cumulative = end == start
          ? listened
          : (listened * (next - start)) ~/ (end - start);
      final portion = cumulative - allocated;
      if (!genresOnly && !artistsOnly) {
        _summary(scope, generation, day, 'total', '', '', '', portion, 0);
        _summary(
          scope,
          generation,
          day,
          'track',
          metadata['track_id'] as String,
          metadata['title'] as String,
          metadata['artist_name'] as String,
          portion,
          0,
        );
      }
      if (artist != null) {
        _summary(
          scope,
          generation,
          day,
          'artist',
          artist.id.isEmpty ? artist.name : artist.id,
          artist.name,
          '',
          portion,
          0,
        );
      }
      for (var index = 0; index < genres.length; index++) {
        // Allocate the event's finite listening time once across its tags.
        // Cumulative shares keep rounding identical across daily/monthly cuts.
        final share =
            _genreShare(cumulative, genres.length, index) -
            _genreShare(allocated, genres.length, index);
        if (share > 0) {
          final genre = genres[index];
          _summary(scope, generation, day, 'genre', genre, genre, '', share, 0);
        }
      }
      allocated = cumulative;
      position = next;
    } while (position < end);
  }

  void _summary(
    String scope,
    int generation,
    int day,
    String kind,
    String key,
    String name,
    String artist,
    int listened,
    int plays,
  ) {
    _write(
      'INSERT INTO stats_daily(scope,generation,day,kind,item_key,name,artist,listened_ms,plays) '
      'VALUES (?,?,?,?,?,?,?,?,?) ON CONFLICT(scope,generation,day,kind,item_key) DO UPDATE SET '
      'listened_ms=listened_ms+excluded.listened_ms,plays=plays+excluded.plays,'
      'name=excluded.name,artist=excluded.artist',
      [scope, generation, day, kind, key, name, artist, listened, plays],
    );
  }

  Map<String, dynamic> _stats(Map<String, dynamic> args) {
    final scope = args['scope'] as String;
    final generation = _account(scope)['generation'];
    final year = args['year'] as int;
    final month = args['month'] as int?;
    if (year < 1970 ||
        year > 9998 ||
        (month != null && (month < 1 || month > 12))) {
      throw ArgumentError('Invalid statistics period');
    }
    final start = DateTime.utc(year, month ?? 1).millisecondsSinceEpoch;
    final end =
        (month == null ? DateTime.utc(year + 1) : DateTime.utc(year, month + 1))
            .millisecondsSinceEpoch;
    List<Map<String, dynamic>> ranking(String kind, {int limit = 5}) => db
        .select(
          'SELECT item_key,name,artist,SUM(listened_ms) AS duration,SUM(plays) AS plays '
          'FROM stats_daily WHERE scope=? AND generation=? AND day>=? AND day<? AND kind=? '
          'GROUP BY item_key ORDER BY duration DESC,plays DESC,item_key LIMIT ?',
          [scope, generation, start, end, kind, limit],
        )
        .map(
          (row) => {
            'id': row['item_key'],
            'name': row['name'],
            'title': row['name'],
            'artist': row['artist'],
            'minutes': (row['duration'] as int) ~/ 60000,
            'listening_ms': row['duration'],
            'plays': row['plays'],
          },
        )
        .toList();
    final total =
        db.select(
              "SELECT COALESCE(SUM(listened_ms),0) AS duration FROM stats_daily "
              "WHERE scope=? AND generation=? AND day>=? AND day<? AND kind='total'",
              [scope, generation, start, end],
            ).single['duration']
            as int;
    int unique(String kind) =>
        db.select(
              'SELECT COUNT(DISTINCT item_key) AS count FROM stats_daily '
              'WHERE scope=? AND generation=? AND day>=? AND day<? '
              'AND kind=? AND listened_ms>0',
              [scope, generation, start, end, kind],
            ).single['count']
            as int;
    final plays = db.select(
      'SELECT COALESCE(SUM(plays),0) AS count FROM stats_daily '
      "WHERE scope=? AND generation=? AND day>=? AND day<? AND kind='track'",
      [scope, generation, start, end],
    ).single['count'];
    final topGenres = ranking('genre');
    final classified =
        db.select(
              "SELECT COALESCE(SUM(listened_ms),0) AS duration FROM stats_daily "
              "WHERE scope=? AND generation=? AND day>=? AND day<? AND kind='genre'",
              [scope, generation, start, end],
            ).single['duration']
            as int;
    final rankedGenreTime = topGenres.fold<int>(
      0,
      (sum, genre) => sum + (genre['listening_ms'] as int),
    );
    return {
      'year': year,
      'month': month,
      'total_minutes': total ~/ 60000,
      'total_listening_ms': total,
      'total_plays': plays,
      'unique_tracks': unique('track'),
      'unique_artists': unique('artist'),
      'top_artists': ranking('artist'),
      'top_tracks': ranking('track', limit: 10),
      'top_genres': topGenres,
      'other_genre_listening_ms': max(0, classified - rankedGenreTime),
      'unclassified_listening_ms': max(0, total - classified),
    };
  }
}
