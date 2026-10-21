part of 'listening_stats_storage.dart';

/// Storage implementation for protocol v2. Interval messages are ephemeral;
/// the database retains aggregated deltas and at most one frozen upload.
class _ListeningCounterStore {
  final _ListeningDatabase _database;

  _ListeningCounterStore(this._database);

  void initialize() {
    _database.db.execute('''
      CREATE TABLE IF NOT EXISTS stats_counter_metadata (
        scope TEXT NOT NULL, id TEXT NOT NULL, payload TEXT NOT NULL,
        PRIMARY KEY(scope,id));
      CREATE TABLE IF NOT EXISTS stats_counter_rows (
        scope TEXT NOT NULL, bucket TEXT NOT NULL, year INTEGER NOT NULL,
        month INTEGER NOT NULL, metadata_id TEXT NOT NULL,
        listened_ms INTEGER NOT NULL, plays INTEGER NOT NULL, genre_ms TEXT NOT NULL,
        PRIMARY KEY(scope,bucket,year,month,metadata_id));
      CREATE TABLE IF NOT EXISTS stats_counter_devices (
        scope TEXT PRIMARY KEY, last_sequence INTEGER NOT NULL DEFAULT 0,
        upgraded INTEGER NOT NULL DEFAULT 0, consent_epoch INTEGER NOT NULL DEFAULT -1);
      CREATE TABLE IF NOT EXISTS stats_counter_months (
        scope TEXT NOT NULL, year INTEGER NOT NULL, month INTEGER NOT NULL,
        revision INTEGER NOT NULL, PRIMARY KEY(scope,year,month));
      CREATE TABLE IF NOT EXISTS stats_counter_active (
        scope TEXT NOT NULL, id TEXT NOT NULL, metadata TEXT NOT NULL,
        listened_ms INTEGER NOT NULL, qualified INTEGER NOT NULL,
        event_id TEXT NOT NULL, event_hash TEXT NOT NULL, sequence INTEGER,
        touched INTEGER NOT NULL, ended INTEGER NOT NULL,
        PRIMARY KEY(scope,id));
      CREATE TABLE IF NOT EXISTS stats_counter_batch (
        scope TEXT PRIMARY KEY, payload TEXT NOT NULL, canceled INTEGER NOT NULL DEFAULT 0);
      CREATE TABLE IF NOT EXISTS stats_counter_stage (
        scope TEXT NOT NULL, year INTEGER NOT NULL, month INTEGER NOT NULL,
        payload TEXT NOT NULL, PRIMARY KEY(scope,year,month));
    ''');

    if (!_database.db
        .select('PRAGMA table_info(stats_counter_devices)')
        .any((column) => column['name'] == 'consent_epoch')) {
      _database.db.execute('ALTER TABLE stats_counter_devices ADD COLUMN consent_epoch INTEGER NOT NULL DEFAULT -1');
    }

    _database.db.execute("INSERT OR IGNORE INTO stats_meta(key,value) VALUES ('consent_epoch','0')");

    if (_database.db.select("SELECT 1 FROM stats_meta WHERE key='counter_version'").isEmpty) {
      _database._transaction(() {
        for (final account in _database.db.select('SELECT scope FROM stats_accounts')) {
          rebuildLegacy(account['scope'] as String);
        }

        moveBucket('local', 'legacy_private', 'private');

        for (final table in ['stats_events', 'stats_sessions', 'stats_daily']) {
          _database.db.execute("DELETE FROM $table WHERE scope='local'");
        }

        _database.db.execute("INSERT INTO stats_meta(key,value) VALUES ('counter_version','3')");
      });
    }
  }

  int pendingCount(String scope) => scope == 'local'
      ? 0
      : _database.db.select(
              "SELECT COUNT(*) AS n FROM stats_counter_rows WHERE scope=? AND bucket IN ('pending','inflight')",
              [scope],
            ).single['n']
            as int;

  dynamic execute(String command, Map<String, dynamic> args) {
    final scope = args['scope'] as String;

    if (args['generation'] != null && args['generation'] != _database._account(scope)['generation']) {
      return null;
    }

    switch (command) {
      case 'counter_quarantine':
        _database._transaction(() {
          _database.db.execute('UPDATE stats_counter_batch SET canceled=1 WHERE scope=?', [scope]);
          // Fence every possible delayed copy before abandoning its sequence.
          _database.db.execute(
            "UPDATE stats_meta SET value=CAST(CAST(value AS INTEGER)+1 AS TEXT) WHERE key='consent_epoch'",
          );
        });

        return null;
      case 'counter_consent':
        final rows = _database.db.select('SELECT consent_epoch FROM stats_counter_devices WHERE scope=?', [scope]);

        return rows.isEmpty ? -1 : rows.single['consent_epoch'];
      case 'counter_consent_ack':
        _database.db.execute(
          'INSERT INTO stats_counter_devices(scope,consent_epoch) VALUES (?,?) '
          'ON CONFLICT(scope) DO UPDATE SET consent_epoch=excluded.consent_epoch',
          [scope, args['consent_epoch']],
        );

        return null;
      case 'counter_prepare':
        Map<String, dynamic>? batch;

        _database._transaction(() {
          batch = _prepareBatch(scope, args['collection_revision'] as int);
        });

        return batch;
      case 'counter_months':
        return [
          for (final row in _database.db.select('SELECT year,month,revision FROM stats_counter_months WHERE scope=?', [
            scope,
          ]))
            Map<String, dynamic>.from(row),
        ];
      case 'counter_checkpoint':
        final checkpoint = args['checkpoint'] as Map;

        _database._transaction(() {
          final sequence = checkpoint['last_sequence'] as int;

          _database.db.execute(
            'INSERT INTO stats_counter_devices(scope,last_sequence,upgraded) VALUES (?,?,?) '
            'ON CONFLICT(scope) DO UPDATE SET last_sequence=MAX(last_sequence,excluded.last_sequence),upgraded=excluded.upgraded',
            [scope, sequence, checkpoint['upgraded'] == true ? 1 : 0],
          );

          final outstanding = _database.db.select('SELECT * FROM stats_counter_batch WHERE scope=?', [scope]);

          if (outstanding.isNotEmpty) {
            final payload = jsonDecode(outstanding.single['payload'] as String) as Map;

            if (sequence == payload['batch_sequence'] &&
                checkpoint['last_hash'] != null &&
                checkpoint['last_hash'] != _hash(payload)) {
              throw StateError('Device checkpoint conflicts with the frozen listening batch');
            }

            if ((payload['batch_sequence'] as int) > sequence &&
                (outstanding.single['canceled'] == 1 ||
                    payload['collection_revision'] != args['collection_revision'])) {
              moveBucket(scope, 'inflight', outstanding.single['canceled'] == 1 ? 'private' : 'pending');
              _database.db.execute('DELETE FROM stats_counter_batch WHERE scope=?', [scope]);
            }
          }
        });

        return null;
      case 'counter_compact_legacy':
        _database._transaction(() {
          if (_database.db.select('SELECT 1 FROM stats_events WHERE scope=? AND pending=1 LIMIT 1', [
            scope,
          ]).isNotEmpty) {
            throw StateError('Legacy uploads remain');
          }

          moveBucket(scope, 'legacy_private', 'private');
          moveBucket(scope, 'legacy_cache', 'cache');

          for (final table in ['stats_events', 'stats_sessions', 'stats_daily']) {
            _database.db.execute('DELETE FROM $table WHERE scope=?', [scope]);
          }
        });

        return null;
      case 'counter_snapshot':
        _database._transaction(() => _applyCounterPage(scope, args['page'] as Map, args['after'] as String));

        return null;
      default:
        throw ArgumentError('Unknown counter command: $command');
    }
  }

  void record(String scope, int generation, Map<String, dynamic> event) {
    final start = event['started_at_ms'] as int;
    final end = event['ended_at_ms'] as int;
    final listened = event['listened_ms'] as int;

    if (listened < 0 ||
        start < 0 ||
        end < start ||
        (event['session_started_at_ms'] as int) > start ||
        (event['rule_version'] as int? ?? 1) != 1 ||
        [
          'event_id',
          'session_id',
          'device_id',
          'track_id',
        ].any((key) => event[key] is! String || (event[key] as String).isEmpty)) {
      throw ArgumentError('Invalid listening interval');
    }

    final sessionId = event['session_id'] as String;
    final previous = _database.db.select('SELECT * FROM stats_counter_active WHERE scope=? AND id=?', [
      scope,
      sessionId,
    ]);
    final last = previous.isEmpty ? null : previous.single;
    final eventHash = _hash(event);
    final eventId = event['event_id'] as String;
    final sequence = eventId.startsWith('$sessionId:') ? int.tryParse(eventId.split(':').last) : null;

    if (last != null && last['event_id'] == eventId) {
      if (last['event_hash'] != eventHash) {
        throw StateError('Listening interval changed during retry');
      }

      return;
    }

    if (last != null && sequence != null && last['sequence'] != null && sequence <= (last['sequence'] as int)) {
      return;
    }

    final snapshot = jsonEncode(_canonical(_database._snapshot(event)));

    if (last != null && last['metadata'] != snapshot) {
      throw StateError('Listening session metadata changed');
    }

    if (last != null && last['ended'] == 1) {
      return;
    }

    final id = _saveMetadata(scope, _counterMetadata(event));
    final total = listened + (last?['listened_ms'] as int? ?? 0);
    final qualified = (last?['qualified'] == 1) || total >= _threshold(event);

    _counterDuration(scope, 'pending', id, event);

    if (qualified && last?['qualified'] != 1) {
      final at = DateTime.fromMillisecondsSinceEpoch(event['session_started_at_ms'] as int, isUtc: true);

      _addCounter(scope, 'pending', at.year, at.month, id, 0, 1, {});
    }

    _database.db.execute(
      'INSERT INTO stats_counter_active(scope,id,metadata,listened_ms,qualified,event_id,event_hash,sequence,touched,ended) '
      'VALUES (?,?,?,?,?,?,?,?,?,?) ON CONFLICT(scope,id) DO UPDATE SET listened_ms=excluded.listened_ms,'
      'qualified=excluded.qualified,event_id=excluded.event_id,event_hash=excluded.event_hash,sequence=excluded.sequence,'
      'touched=excluded.touched,ended=excluded.ended',
      [
        scope,
        sessionId,
        snapshot,
        total,
        qualified ? 1 : 0,
        eventId,
        eventHash,
        sequence,
        end,
        event['end_reason'] == null ? 0 : 1,
      ],
    );

    // Keep a bounded recent retry window, including gapless playback's overlap.
    _database.db.execute(
      'DELETE FROM stats_counter_active WHERE scope=? AND id NOT IN '
      '(SELECT id FROM stats_counter_active WHERE scope=? ORDER BY touched DESC,rowid DESC LIMIT 16)',
      [scope, scope],
    );
  }

  void disable() {
    for (final account in _database.db.select('SELECT scope FROM stats_accounts')) {
      final scope = account['scope'] as String;

      moveBucket(scope, 'pending', 'private');
      _database.db.execute('UPDATE stats_events SET rejected=1 WHERE scope=? AND pending=1', [scope]);
      _database.db.execute('UPDATE stats_events SET pending=0 WHERE scope=?', [scope]);
      rebuildLegacy(scope);
    }

    // The immutable upload may already be committed. A server preference
    // barrier followed by its checkpoint resolves that ambiguity on reconnect.
    _database.db.execute('UPDATE stats_counter_batch SET canceled=1');
  }

  void importLocal(String scope) {
    if (!_database.enabled || scope == 'local') {
      return;
    }

    final generation = _database._account(scope)['generation'];

    _database.db.execute(
      'INSERT INTO stats_counter_metadata(scope,id,payload) SELECT ?,id,payload FROM stats_counter_metadata WHERE scope=? '
      'ON CONFLICT(scope,id) DO NOTHING',
      [scope, 'local'],
    );
    _database.db.execute(
      'INSERT INTO stats_genre_metadata(scope,generation,track_id,genres) SELECT ?,?,track_id,genres '
      'FROM stats_genre_metadata g WHERE scope=? AND EXISTS (SELECT 1 FROM stats_counter_metadata m '
      "JOIN stats_counter_rows r ON r.scope=m.scope AND r.metadata_id=m.id WHERE m.scope=g.scope AND json_extract(m.payload,'\$.track_id')=g.track_id) "
      'ON CONFLICT(scope,generation,track_id) DO NOTHING',
      [scope, generation, 'local'],
    );

    for (final row in _database.db.select("SELECT * FROM stats_counter_rows WHERE scope='local'")) {
      _addCounter(
        scope,
        'pending',
        row['year'] as int,
        row['month'] as int,
        row['metadata_id'] as String,
        row['listened_ms'] as int,
        row['plays'] as int,
        Map<String, int>.from(jsonDecode(row['genre_ms'] as String) as Map),
      );
    }

    for (final table in [
      'stats_counter_rows',
      'stats_counter_metadata',
      'stats_counter_active',
      'stats_events',
      'stats_sessions',
      'stats_daily',
      'stats_genre_metadata',
    ]) {
      _database.db.execute("DELETE FROM $table WHERE scope='local'");
    }
  }

  /// Only the upgrade path uses v1 events. Rebuild their small aggregate view
  /// after acknowledgments; new listening never enters the legacy ledger.
  void rebuildLegacy(String scope) {
    _database.db.execute(
      "DELETE FROM stats_counter_rows WHERE scope=? AND bucket IN ('legacy','legacy_cache','legacy_private')",
      [scope],
    );
    final generation = _database._account(scope)['generation'];
    var after = 0;

    while (true) {
      final rows = _database.db.select(
        'SELECT e.rowid AS migration_id,e.*,s.metadata FROM stats_events e JOIN stats_sessions s '
        'ON s.scope=e.scope AND s.generation=e.generation AND s.id=e.session_id '
        'WHERE e.scope=? AND e.generation=? AND e.rowid>? ORDER BY e.rowid LIMIT 512',
        [scope, generation, after],
      );

      if (rows.isEmpty) {
        break;
      }

      for (final row in rows) {
        final event = _database._payload(row);
        final String bucket;

        if (scope == 'local' || row['rejected'] == 1) {
          bucket = 'legacy_private';
        } else {
          bucket = row['pending'] == 1 ? 'legacy' : 'legacy_cache';
        }

        _counterDuration(scope, bucket, _saveMetadata(scope, _counterMetadata(event)), event);
      }

      after = rows.last['migration_id'] as int;
    }

    for (final session in _database.db.select(
      'SELECT s.*,COALESCE(SUM(CASE WHEN e.pending=0 AND e.rejected=0 THEN e.listened_ms ELSE 0 END),0) accepted,'
      'COALESCE(SUM(CASE WHEN e.rejected=0 THEN e.listened_ms ELSE 0 END),0) uploadable '
      'FROM stats_sessions s JOIN stats_events e ON s.scope=e.scope AND s.generation=e.generation AND s.id=e.session_id '
      'WHERE s.scope=? AND s.generation=? AND s.qualified=1 GROUP BY s.id',
      [scope, generation],
    )) {
      final event = Map<String, dynamic>.from(jsonDecode(session['metadata'] as String) as Map);
      final String bucket;

      if (scope == 'local') {
        bucket = 'legacy_private';
      } else if ((session['accepted'] as int) >= _threshold(event)) {
        bucket = 'legacy_cache';
      } else {
        bucket = (session['uploadable'] as int) >= _threshold(event) ? 'legacy' : 'legacy_private';
      }

      final at = DateTime.fromMillisecondsSinceEpoch(event['session_started_at_ms'] as int, isUtc: true);

      _addCounter(scope, bucket, at.year, at.month, _saveMetadata(scope, _counterMetadata(event)), 0, 1, {});
    }
  }

  void moveBucket(String scope, String source, String target) {
    for (final row in _database.db.select('SELECT * FROM stats_counter_rows WHERE scope=? AND bucket=?', [
      scope,
      source,
    ])) {
      _addCounter(
        scope,
        target,
        row['year'] as int,
        row['month'] as int,
        row['metadata_id'] as String,
        row['listened_ms'] as int,
        row['plays'] as int,
        Map<String, int>.from(jsonDecode(row['genre_ms'] as String) as Map),
      );
    }

    _database.db.execute('DELETE FROM stats_counter_rows WHERE scope=? AND bucket=?', [scope, source]);
  }

  List<dynamic> metadataCandidates(String command, Map<String, dynamic> args) {
    final scope = args['scope'] as String;
    final values = _database.db.select(
      'SELECT m.payload FROM stats_counter_metadata m WHERE m.scope=? '
      "AND json_extract(m.payload,'\$.track_id')>? AND EXISTS (SELECT 1 FROM stats_counter_rows r WHERE r.scope=m.scope AND r.metadata_id=m.id AND r.listened_ms>0) "
      "AND NOT EXISTS (SELECT 1 FROM stats_genre_metadata g WHERE g.scope=m.scope AND g.generation=? AND g.track_id=json_extract(m.payload,'\$.track_id')) "
      "GROUP BY json_extract(m.payload,'\$.track_id') ORDER BY json_extract(m.payload,'\$.track_id') LIMIT ?",
      [scope, args['after_track_id'] ?? '', args['generation'], args['limit']],
    );

    return [
      for (final row in values)
        if (command == 'genre_metadata_candidates')
          (jsonDecode(row['payload'] as String) as Map)['track_id']
        else
          {
            ...Map<String, dynamic>.from(jsonDecode(row['payload'] as String) as Map),
            'event_id': 'metadata',
            'session_id': 'metadata',
            'device_id': _database._meta('device_id'),
            'session_started_at_ms': 0,
            'started_at_ms': 0,
            'ended_at_ms': 0,
            'listened_ms': 0,
            'rule_version': 1,
          },
    ];
  }

  void project(String scope) {
    final generation = _database._account(scope)['generation'] as int;

    _database._transaction(() {
      _database.db.execute('DELETE FROM stats_daily WHERE scope=?', [scope]);

      for (final row in _database.db.select(
        'SELECT r.year,r.month,r.metadata_id,SUM(r.listened_ms) AS listened_ms,SUM(r.plays) AS plays,'
        'json_group_array(r.genre_ms) AS genre_parts,m.payload,g.genres AS projected_genres FROM stats_counter_rows r '
        'JOIN stats_counter_metadata m ON m.scope=r.scope AND m.id=r.metadata_id '
        "LEFT JOIN stats_genre_metadata g ON g.scope=r.scope AND g.generation=? AND g.track_id=json_extract(m.payload,'\$.track_id') "
        'WHERE r.scope=? GROUP BY r.year,r.month,r.metadata_id ORDER BY r.year,r.month,r.metadata_id',
        [generation, scope],
      )) {
        final value = Map<String, dynamic>.from(jsonDecode(row['payload'] as String) as Map);
        final ms = row['listened_ms'] as int;
        final plays = row['plays'] as int;
        final at = DateTime.utc(row['year'] as int, row['month'] as int).millisecondsSinceEpoch;

        _database._summary(scope, generation, at, 'total', '', '', '', ms, 0);
        _database._summary(
          scope,
          generation,
          at,
          'track',
          value['track_id'] as String,
          value['title'] as String,
          value['artist_name'] as String,
          ms,
          plays,
        );

        final artist = listeningPrimaryArtist(value);

        if (artist != null) {
          _database._summary(
            scope,
            generation,
            at,
            'artist',
            artist.id.isEmpty ? artist.name : artist.id,
            artist.name,
            '',
            ms,
            0,
          );
        }

        final raw = _database._genres(value);
        final tags = row['projected_genres'] == null
            ? raw
            : _database._genres({'genres': jsonDecode(row['projected_genres'] as String)});
        final durations = <String, int>{};

        if (jsonEncode(raw) == jsonEncode(tags)) {
          for (final encoded in jsonDecode(row['genre_parts'] as String) as List) {
            for (final entry in (jsonDecode(encoded as String) as Map).entries) {
              durations.update(
                entry.key as String,
                (value) => value + (entry.value as int),
                ifAbsent: () => entry.value as int,
              );
            }
          }
        } else {
          durations.addAll(<String, int>{
            for (var i = 0; i < tags.length; i++) tags[i]: _database._genreShare(ms, tags.length, i),
          });
        }

        for (final entry in durations.entries) {
          if (entry.value > 0) {
            _database._summary(scope, generation, at, 'genre', entry.key, entry.key, '', entry.value, 0);
          }
        }
      }
    });
  }

  dynamic _canonical(dynamic value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList();
      keys.sort(_database._compareGenreKeys);

      return {for (final key in keys) key: _canonical(value[key])};
    }

    if (value is List) {
      return value.map(_canonical).toList();
    }

    return value;
  }

  String _hash(dynamic value) => sha256.convert(utf8.encode(jsonEncode(_canonical(value)))).toString();

  Map<String, dynamic> _counterMetadata(Map<String, dynamic> event) => {
    for (final key in [
      'track_id',
      'title',
      'artist_id',
      'artist_name',
      'album_id',
      'album_title',
      'genres',
      'artists',
      'track_duration_ms',
    ])
      key: _database._snapshot(event)[key],
  };

  String _saveMetadata(String scope, Map<String, dynamic> value, {String? expected}) {
    final id = _hash(value);

    if (expected != null && expected != id) {
      throw StateError('Invalid metadata hash');
    }

    _database.db.execute('INSERT OR IGNORE INTO stats_counter_metadata(scope,id,payload) VALUES (?,?,?)', [
      scope,
      id,
      jsonEncode(_canonical(value)),
    ]);

    return id;
  }

  void _addCounter(
    String scope,
    String bucket,
    int year,
    int month,
    String id,
    int listened,
    int plays,
    Map<String, int> genreMs,
  ) {
    if (listened == 0 && plays == 0) {
      return;
    }

    final previous = _database.db.select(
      'SELECT * FROM stats_counter_rows WHERE scope=? AND bucket=? '
      'AND year=? AND month=? AND metadata_id=?',
      [scope, bucket, year, month, id],
    );
    final genres = previous.isEmpty
        ? <String, int>{}
        : Map<String, int>.from(jsonDecode(previous.single['genre_ms'] as String) as Map);

    for (final entry in genreMs.entries) {
      genres.update(entry.key, (v) => v + entry.value, ifAbsent: () => entry.value);
    }

    _database.db.execute(
      'INSERT INTO stats_counter_rows(scope,bucket,year,month,metadata_id,listened_ms,plays,genre_ms) '
      'VALUES (?,?,?,?,?,?,?,?) ON CONFLICT(scope,bucket,year,month,metadata_id) DO UPDATE SET '
      'listened_ms=excluded.listened_ms,plays=excluded.plays,genre_ms=excluded.genre_ms',
      [
        scope,
        bucket,
        year,
        month,
        id,
        listened + (previous.isEmpty ? 0 : previous.single['listened_ms'] as int),
        plays + (previous.isEmpty ? 0 : previous.single['plays'] as int),
        jsonEncode(genres),
      ],
    );
  }

  void _counterDuration(String scope, String bucket, String id, Map<String, dynamic> event) {
    final start = event['started_at_ms'] as int;
    final end = event['ended_at_ms'] as int;
    final listened = event['listened_ms'] as int;

    if (listened == 0) {
      return;
    }

    final genres = _database._genres(event);
    var position = start;
    var allocated = 0;

    do {
      final at = DateTime.fromMillisecondsSinceEpoch(position, isUtc: true);
      final next = min(end, DateTime.utc(at.year, at.month + 1).millisecondsSinceEpoch);
      final cumulative = end == start ? listened : listened * (next - start) ~/ (end - start);

      _addCounter(scope, bucket, at.year, at.month, id, cumulative - allocated, 0, {
        for (var i = 0; i < genres.length; i++)
          genres[i]:
              _database._genreShare(cumulative, genres.length, i) - _database._genreShare(allocated, genres.length, i),
      });
      position = next;
      allocated = cumulative;
    } while (position < end);
  }

  int _threshold(Map<String, dynamic> event) {
    final duration = event['track_duration_ms'] as int? ?? 0;

    return duration > 0 ? min(30000, max(1, (duration + 1) ~/ 2)) : 30000;
  }

  Map<String, dynamic>? _prepareBatch(String scope, int collectionRevision) {
    final existing = _database.db.select('SELECT payload FROM stats_counter_batch WHERE scope=?', [scope]);

    if (existing.isNotEmpty) {
      return Map<String, dynamic>.from(jsonDecode(existing.single['payload'] as String) as Map);
    }

    if (!_database.enabled || scope == 'local') {
      return null;
    }

    final device = _database.db.select('SELECT * FROM stats_counter_devices WHERE scope=?', [scope]);

    if (device.isEmpty || device.single['upgraded'] != 1) {
      return null;
    }

    final rows = _database.db.select(
      'SELECT r.*,m.payload FROM stats_counter_rows r JOIN stats_counter_metadata m ON m.scope=r.scope AND m.id=r.metadata_id '
      "WHERE r.scope=? AND r.bucket='pending' ORDER BY year,month,metadata_id LIMIT 200",
      [scope],
    );

    if (rows.isEmpty) {
      return null;
    }

    final batch = <String, dynamic>{
      'device_id': _database._meta('device_id'),
      'history_generation': _database._account(scope)['generation'],
      'collection_revision': collectionRevision,
      'batch_sequence': (device.single['last_sequence'] as int) + 1,
      'rule_version': 3,
      'metadata': <String, dynamic>{},
      'contributions': <Map<String, dynamic>>[],
    };
    final metadata = batch['metadata'] as Map<String, dynamic>;
    final contributions = batch['contributions'] as List<Map<String, dynamic>>;

    for (final row in rows) {
      if (row['year'] != rows.first['year'] || row['month'] != rows.first['month']) {
        break;
      }

      final id = row['metadata_id'] as String;
      final contribution = <String, dynamic>{
        'year': row['year'],
        'month': row['month'],
        'metadata_id': id,
        'listened_ms': row['listened_ms'],
        'plays': row['plays'],
        'genre_ms': jsonDecode(row['genre_ms'] as String),
      };

      metadata[id] = jsonDecode(row['payload'] as String);
      contributions.add(contribution);

      if (utf8.encode(jsonEncode(batch)).length > 256 * 1024) {
        metadata.remove(id);
        contributions.removeLast();

        if (contributions.isEmpty) {
          _addCounter(
            scope,
            'private',
            row['year'] as int,
            row['month'] as int,
            id,
            row['listened_ms'] as int,
            row['plays'] as int,
            Map<String, int>.from(jsonDecode(row['genre_ms'] as String) as Map),
          );
          _database.db.execute(
            "DELETE FROM stats_counter_rows WHERE scope=? AND bucket='pending' AND year=? AND month=? AND metadata_id=?",
            [scope, row['year'], row['month'], id],
          );
          continue;
        }

        break;
      }

      _database.db.execute(
        "UPDATE stats_counter_rows SET bucket='inflight' WHERE scope=? AND bucket='pending' AND year=? AND month=? AND metadata_id=?",
        [scope, row['year'], row['month'], id],
      );
    }

    if (contributions.isEmpty) {
      return null;
    }

    _database.db.execute('INSERT INTO stats_counter_batch(scope,payload) VALUES (?,?)', [
      scope,
      jsonEncode(_canonical(batch)),
    ]);

    return batch;
  }

  void _applyCounterPage(String scope, Map page, String after) {
    if (page['history_generation'] != _database._account(scope)['generation']) {
      return;
    }

    final year = page['year'] as int;
    final month = page['month'] as int;
    final revision = page['revision'] as int;
    final previous = _database.db.select(
      'SELECT payload FROM stats_counter_stage WHERE scope=? AND year=? AND month=?',
      [scope, year, month],
    );
    final Map<String, dynamic> staged;

    if (after.isEmpty) {
      staged = <String, dynamic>{
        'revision': revision,
        'next_key': '',
        'contributions': <dynamic>[],
        'metadata': <String, dynamic>{},
        'genre_metadata': <String, dynamic>{},
        'checkpoint': page['checkpoint'],
      };
    } else {
      if (previous.isEmpty) {
        throw StateError('Missing staged snapshot');
      }

      staged = Map<String, dynamic>.from(jsonDecode(previous.single['payload'] as String) as Map);
    }

    if (staged['revision'] != revision ||
        staged['next_key'] != after ||
        (staged['checkpoint'] as Map)['last_sequence'] != (page['checkpoint'] as Map)['last_sequence']) {
      throw StateError('Snapshot changed while paging');
    }

    final entries = page['contributions'] as List;

    for (final entry in entries) {
      if ((entry as Map)['year'] != year ||
          entry['month'] != month ||
          (entry['listened_ms'] as int) < 0 ||
          (entry['plays'] as int) < 0) {
        throw StateError('Invalid snapshot contribution');
      }
    }

    (staged['contributions'] as List).addAll(entries);
    (staged['metadata'] as Map).addAll(Map<String, dynamic>.from(page['metadata'] as Map));
    (staged['genre_metadata'] as Map).addAll(Map<String, dynamic>.from(page['genre_metadata'] as Map? ?? {}));
    staged['next_key'] = page['next_key'];

    if (page['has_more'] == true) {
      if (page['next_key'] == after || entries.isEmpty) {
        throw StateError('Snapshot did not advance');
      }

      _database.db.execute(
        'INSERT INTO stats_counter_stage(scope,year,month,payload) VALUES (?,?,?,?) '
        'ON CONFLICT(scope,year,month) DO UPDATE SET payload=excluded.payload',
        [scope, year, month, jsonEncode(staged)],
      );

      return;
    }

    _database.db.execute(
      "DELETE FROM stats_counter_rows WHERE scope=? AND year=? AND month=? AND bucket IN ('cache','legacy_cache')",
      [scope, year, month],
    );

    for (final entry in staged['contributions'] as List) {
      final row = entry as Map;
      final id = row['metadata_id'] as String;

      _saveMetadata(scope, Map<String, dynamic>.from((staged['metadata'] as Map)[id] as Map), expected: id);
      _addCounter(
        scope,
        'cache',
        year,
        month,
        id,
        row['listened_ms'] as int,
        row['plays'] as int,
        Map<String, int>.from(row['genre_ms'] as Map),
      );
    }

    _database._applyGenreMetadata(
      scope,
      _database._account(scope)['generation'] as int,
      staged['genre_metadata'] as Map,
    );

    final outstanding = _database.db.select('SELECT payload FROM stats_counter_batch WHERE scope=?', [scope]);

    if (outstanding.isNotEmpty) {
      final batch = jsonDecode(outstanding.single['payload'] as String) as Map;
      final period = (batch['contributions'] as List).first as Map;

      if (period['year'] == year &&
          period['month'] == month &&
          ((page['checkpoint'] as Map)['last_sequence'] as int) >= (batch['batch_sequence'] as int)) {
        _database.db.execute("DELETE FROM stats_counter_rows WHERE scope=? AND bucket='inflight'", [scope]);
        _database.db.execute('DELETE FROM stats_counter_batch WHERE scope=?', [scope]);
      }
    }

    _database.db.execute(
      'INSERT INTO stats_counter_months(scope,year,month,revision) VALUES (?,?,?,?) '
      'ON CONFLICT(scope,year,month) DO UPDATE SET revision=excluded.revision',
      [scope, year, month, revision],
    );
    _database.db.execute('DELETE FROM stats_counter_stage WHERE scope=? AND year=? AND month=?', [scope, year, month]);
    _database.db.execute('UPDATE stats_accounts SET synced_at=? WHERE scope=?', [
      DateTime.now().toUtc().millisecondsSinceEpoch,
      scope,
    ]);
  }
}
