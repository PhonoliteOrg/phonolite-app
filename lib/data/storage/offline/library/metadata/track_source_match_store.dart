part of '../offline_library.dart';

class _TrackSourceMatchStore {
  final OfflineLibraryStorage _host;

  _TrackSourceMatchStore(this._host);

  Future<List<TrackSourceMatch>> readServerTrackMatches(String serverBaseUrl, String localTrackId) =>
      _host._withDatabase(
        (db) => db
            .select(
              '''SELECT * FROM local_track_server_matches
        WHERE server_base_url = ? AND local_track_id = ? ORDER BY verified_at DESC''',
              [serverBaseUrl, localTrackId],
            )
            .map(_matchFromRow)
            .toList(growable: false),
      );

  Future<void> saveTrackSourceMatch(TrackSourceMatch match) => _host._withDatabase((db) => _saveMatch(db, match));

  Future<void> removeTrackSourceMatch(SourceTrackRef source) => _host._withDatabase(
    (db) => db.execute('DELETE FROM local_track_server_matches WHERE server_base_url = ? AND server_track_id = ?', [
      source.serverBaseUrl,
      source.serverTrackId,
    ]),
  );

  Future<String?> findLocalIdForSource(SourceTrackRef source) =>
      _host._withDatabase((db) => _findLocalIdForSource(db, source));

  Future<String?> localTrackIdForSource(SourceTrackRef source) => findLocalIdForSource(source);

  Future<String?> resolveDownloadedLocalSource(Track track, SourceTrackRef source) => _host._withDatabase((db) {
    String? localId;

    _host._transaction(db, () {
      localId = _resolveKnownLocalSource(db, track, source) ?? _resolveDownloadedLocalSource(db, track, source);
    });

    return localId;
  });

  String? _resolveKnownLocalSource(Database db, Track track, SourceTrackRef source) {
    final downloaded = db.select(
      'SELECT local_track_id FROM source_tracks WHERE server_base_url = ? AND server_track_id = ?',
      [source.serverBaseUrl, source.serverTrackId],
    );

    if (downloaded.isNotEmpty) {
      return downloaded.single['local_track_id'] as String;
    }

    final matched = db.select(
      '''SELECT t.*, m.match_kind, NULL AS server_base_url, NULL AS server_track_id
      FROM local_track_server_matches m JOIN tracks t ON t.id = m.local_track_id
      WHERE m.server_base_url = ? AND m.server_track_id = ?''',
      [source.serverBaseUrl, source.serverTrackId],
    );

    if (matched.isEmpty) {
      return null;
    }

    final row = matched.single;
    final local = _host._trackFromRow(row, liked: false, inPlaylists: false);
    final compatible = row['match_kind'] == 'metadata_local_exact'
        ? TrackMatching.uniqueLocalCandidate(track, [local]) != null
        : TrackMatching.acceptsServerCandidate(local, track);

    if (compatible) {
      return local.localId ?? local.id;
    }

    db.execute('DELETE FROM local_track_server_matches WHERE server_base_url = ? AND server_track_id = ?', [
      source.serverBaseUrl,
      source.serverTrackId,
    ]);

    return null;
  }

  String? _resolveDownloadedLocalSource(Database db, Track track, SourceTrackRef source) {
    final rows = db.select(
      '''SELECT t.*, NULL AS server_base_url, NULL AS server_track_id FROM tracks t
      WHERE t.match_key = ? AND EXISTS (
        SELECT 1 FROM source_tracks s WHERE s.local_track_id = t.id
          AND s.status = ? AND s.file_path IS NOT NULL
      )''',
      [TrackMatching.metadataKey(track), OfflineDownloadStatus.downloaded.name],
    );
    final candidates = <Track>[];

    for (final row in rows) {
      final candidate = _host._trackFromRow(row, liked: false, inPlaylists: false);

      try {
        _host._requireDownloadedLocalTrack(db, candidate.id);
        candidates.add(candidate);
      } on StateError {
        // A missing file cannot fulfill a playlist addition without downloading.
      }
    }

    final candidate = TrackMatching.uniqueLocalCandidate(track, candidates);

    if (candidate == null) {
      return null;
    }

    final localId = candidate.localId ?? candidate.id;
    _saveMatch(
      db,
      TrackSourceMatch(
        localTrackId: localId,
        source: source,
        matchKind: 'metadata_local_exact',
        score: 1,
        metadataSignature: TrackMatching.metadataSignature(candidate),
        verifiedAt: DateTime.now(),
      ),
    );

    return localId;
  }

  void _saveMatch(Database db, TrackSourceMatch match) {
    if (!match.source.isValid) {
      throw ArgumentError('A source match requires its server and track ID.');
    }

    db.execute(
      '''INSERT INTO local_track_server_matches
      (server_base_url, server_track_id, local_track_id, match_kind, score, metadata_signature, verified_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(server_base_url, server_track_id) DO UPDATE SET
        local_track_id = excluded.local_track_id, match_kind = excluded.match_kind, score = excluded.score,
        metadata_signature = excluded.metadata_signature, verified_at = excluded.verified_at''',
      [
        match.source.serverBaseUrl,
        match.source.serverTrackId,
        match.localTrackId,
        match.matchKind,
        match.score,
        match.metadataSignature,
        match.verifiedAt.millisecondsSinceEpoch,
      ],
    );
  }

  String? _findLocalIdForSource(Database db, SourceTrackRef source) {
    final known = db.select(
      'SELECT local_track_id FROM source_tracks WHERE server_base_url = ? AND server_track_id = ?',
      [source.serverBaseUrl, source.serverTrackId],
    );

    if (known.isNotEmpty) {
      return known.single['local_track_id'] as String;
    }

    final matched = db.select(
      '''SELECT local_track_id FROM local_track_server_matches
      WHERE server_base_url = ? AND server_track_id = ?''',
      [source.serverBaseUrl, source.serverTrackId],
    );

    return matched.isEmpty ? null : matched.single['local_track_id'] as String;
  }

  TrackSourceMatch _matchFromRow(Row row) => TrackSourceMatch(
    localTrackId: row['local_track_id'] as String,
    source: SourceTrackRef(
      serverBaseUrl: row['server_base_url'] as String,
      serverTrackId: row['server_track_id'] as String,
    ),
    matchKind: row['match_kind'] as String,
    score: (row['score'] as num).toDouble(),
    metadataSignature: row['metadata_signature'] as String,
    verifiedAt: DateTime.fromMillisecondsSinceEpoch(row['verified_at'] as int),
  );
}

mixin _TrackSourceMatchStoreFacade {
  _TrackSourceMatchStore get _ownerSourceMatches;

  Future<List<TrackSourceMatch>> readServerTrackMatches(String serverBaseUrl, String localTrackId) =>
      _ownerSourceMatches.readServerTrackMatches(serverBaseUrl, localTrackId);

  Future<void> saveTrackSourceMatch(TrackSourceMatch match) => _ownerSourceMatches.saveTrackSourceMatch(match);

  Future<void> removeTrackSourceMatch(SourceTrackRef source) => _ownerSourceMatches.removeTrackSourceMatch(source);

  Future<String?> findLocalIdForSource(SourceTrackRef source) => _ownerSourceMatches.findLocalIdForSource(source);

  Future<String?> localTrackIdForSource(SourceTrackRef source) => _ownerSourceMatches.localTrackIdForSource(source);

  Future<String?> resolveDownloadedLocalSource(Track track, SourceTrackRef source) =>
      _ownerSourceMatches.resolveDownloadedLocalSource(track, source);

  String? _findLocalIdForSource(Database db, SourceTrackRef source) =>
      _ownerSourceMatches._findLocalIdForSource(db, source);

  String? _resolveDownloadedLocalSource(Database db, Track track, SourceTrackRef source) =>
      _ownerSourceMatches._resolveDownloadedLocalSource(db, track, source);

  String? _resolveKnownLocalSource(Database db, Track track, SourceTrackRef source) =>
      _ownerSourceMatches._resolveKnownLocalSource(db, track, source);
}
