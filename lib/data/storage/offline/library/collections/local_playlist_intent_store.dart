part of '../offline_library.dart';

class _LocalPlaylistIntentStore {
  final OfflineLibraryStorage _host;

  _LocalPlaylistIntentStore(this._host);

  Future<List<LocalPlaylistEntry>> readLocalPlaylistEntries(String playlistId) =>
      _host._withDatabase((db) => _readEntries(db, playlistId));

  Future<List<LocalPlaylistEntry>> readPendingPlaylistEntries({String? serverBaseUrl}) =>
      _host._withDatabase((db) => _readPendingEntries(db, serverBaseUrl: serverBaseUrl));

  /// Completion means the destination is saved, independently of network work.
  Future<LocalPlaylistEntry> addSourceToLocalPlaylist(String playlistId, Track track, SourceTrackRef source) async {
    if (!source.isValid) {
      throw ArgumentError('A playlist addition requires its source server and track ID.');
    }

    return _host._withDatabase((db) {
      var position = -1;

      _host._transaction(db, () {
        if (db.select('SELECT 1 FROM local_playlists WHERE id = ?', [playlistId]).isEmpty) {
          throw StateError('The local playlist no longer exists.');
        }

        final localId =
            _host._resolveKnownLocalSource(db, track, source) ??
            _existingLocalId(db, track.localId) ??
            _host._resolveDownloadedLocalSource(db, track, source);
        final existing = _readEntries(
          db,
          playlistId,
        ).where((entry) => entry.source == source || (localId != null && entry.localTrackId == localId));

        if (existing.isNotEmpty) {
          position = existing.first.position;

          return;
        }

        position = _nextPosition(db, playlistId);
        final now = DateTime.now().millisecondsSinceEpoch;
        final snapshot = track.copyWith(
          id: source.serverTrackId,
          serverBaseUrl: source.serverBaseUrl,
          serverTrackId: source.serverTrackId,
          inPlaylists: true,
        );

        if (localId != null && _hasDownloadedLocalTrack(db, localId)) {
          db.execute('INSERT INTO local_playlist_tracks (playlist_id, local_track_id, position) VALUES (?, ?, ?)', [
            playlistId,
            localId,
            position,
          ]);
        } else {
          db.execute(
            '''INSERT INTO pending_playlist_tracks
            (playlist_id, position, server_base_url, server_track_id, track_json, local_track_id,
              entry_kind, request_status, created_at)
            VALUES (?, ?, ?, ?, ?, ?, 'manual', 'queued', ?)''',
            [
              playlistId,
              position,
              source.serverBaseUrl,
              source.serverTrackId,
              jsonEncode(snapshot.toJson()),
              localId,
              now,
            ],
          );
          _registerDemand(db, source, 'playlist', '$playlistId:$position');
        }

        db.execute('UPDATE local_playlists SET updated_at = ? WHERE id = ?', [now, playlistId]);
      });

      return _readEntries(db, playlistId).firstWhere((entry) => entry.position == position);
    });
  }

  /// Releases this membership before deciding which unfinished source is unused.
  Future<List<SourceTrackRef>> removeSourceFromLocalPlaylist(
    String playlistId,
    SourceTrackRef source, {
    String? localTrackId,
  }) => _host._withDatabase((db) {
    final candidates = <SourceTrackRef>{};

    _host._transaction(db, () {
      final localId = localTrackId ?? _knownLocalId(db, source);
      final pending = db.select(
        '''SELECT position, server_base_url, server_track_id
        FROM pending_playlist_tracks
        WHERE playlist_id = ? AND ((server_base_url = ? AND server_track_id = ?)
          OR (? IS NOT NULL AND local_track_id = ?))''',
        [playlistId, source.serverBaseUrl, source.serverTrackId, localId, localId],
      );

      for (final row in pending) {
        final pendingSource = _sourceFromRow(row);
        final ownerId = '$playlistId:${row['position']}';

        candidates.add(pendingSource);
        db.execute('DELETE FROM download_demands WHERE owner_kind = ? AND owner_id = ?', ['playlist', ownerId]);
        db.execute('DELETE FROM pending_playlist_tracks WHERE playlist_id = ? AND position = ?', [
          playlistId,
          row['position'],
        ]);
      }

      if (localId != null) {
        final completed = db.select(
          'SELECT position FROM local_playlist_tracks WHERE playlist_id = ? AND local_track_id = ?',
          [playlistId, localId],
        );

        for (final row in completed) {
          db.execute('DELETE FROM download_demands WHERE owner_kind = ? AND owner_id = ?', [
            'playlist',
            '$playlistId:${row['position']}',
          ]);
        }

        db.execute('DELETE FROM local_playlist_tracks WHERE playlist_id = ? AND local_track_id = ?', [
          playlistId,
          localId,
        ]);
      }

      candidates.add(source);
      db.execute('UPDATE local_playlists SET updated_at = ? WHERE id = ?', [
        DateTime.now().millisecondsSinceEpoch,
        playlistId,
      ]);
    });

    return candidates.toList(growable: false);
  });

  Future<void> registerDownloadDemand(SourceTrackRef source, {required String ownerKind, required String ownerId}) =>
      _host._withDatabase((db) => _registerDemand(db, source, ownerKind, ownerId));

  Future<void> releaseDownloadDemand(SourceTrackRef source, {required String ownerKind, required String ownerId}) =>
      _host._withDatabase(
        (db) => db.execute(
          '''DELETE FROM download_demands
        WHERE server_base_url = ? AND server_track_id = ? AND owner_kind = ? AND owner_id = ?''',
          [source.serverBaseUrl, source.serverTrackId, ownerKind, ownerId],
        ),
      );

  Future<bool> hasDownloadDemand(SourceTrackRef source) => _host._withDatabase((db) => _hasDemand(db, source));

  Future<List<SourceTrackRef>> readDownloadDemandSources() => _host._withDatabase(
    (db) => db
        .select('SELECT DISTINCT server_base_url, server_track_id FROM download_demands')
        .map(_sourceFromRow)
        .toList(growable: false),
  );

  Future<List<SourceTrackRef>> releasePlaylistDownloadDemands(String playlistId) => _host._withDatabase((db) {
    final rows = db.select(
      '''SELECT DISTINCT d.server_base_url, d.server_track_id
      FROM download_demands d
      WHERE d.owner_kind = 'playlist' AND substr(d.owner_id, 1, length(?) + 1) = ? || ':' ''',
      [playlistId, playlistId],
    );

    db.execute(
      "DELETE FROM download_demands WHERE owner_kind = 'playlist' AND substr(owner_id, 1, length(?) + 1) = ? || ':'",
      [playlistId, playlistId],
    );

    return rows.map(_sourceFromRow).toList(growable: false);
  });

  Future<void> updatePendingPlaylistRequest(SourceTrackRef source, OfflineDownloadStatus status, {String? error}) =>
      _host._withDatabase(
        (db) => db.execute(
          '''UPDATE pending_playlist_tracks
        SET request_status = ?, request_error = ? WHERE server_base_url = ? AND server_track_id = ?''',
          [status.name, error, source.serverBaseUrl, source.serverTrackId],
        ),
      );

  Future<bool> canRemoveUnclaimedDownload(SourceTrackRef source) => _host._withDatabase((db) {
    if (_hasDemand(db, source)) {
      return false;
    }

    final rows = db.select('SELECT status FROM source_tracks WHERE server_base_url = ? AND server_track_id = ?', [
      source.serverBaseUrl,
      source.serverTrackId,
    ]);

    return rows.isNotEmpty && rows.single['status'] != OfflineDownloadStatus.downloaded.name;
  });

  List<LocalPlaylistEntry> _readEntries(Database db, String playlistId) {
    final rows = db.select(
      '''SELECT t.*, pt.position, s.server_base_url, s.server_track_id
      FROM local_playlist_tracks pt
      JOIN tracks t ON t.id = pt.local_track_id
      JOIN source_tracks s ON s.local_track_id = t.id AND s.status = ? AND s.file_path IS NOT NULL
      WHERE pt.playlist_id = ? GROUP BY pt.rowid ORDER BY pt.position, pt.rowid''',
      [OfflineDownloadStatus.downloaded.name, playlistId],
    );
    final entries = rows.map((row) {
      final localId = OfflineLibraryStorage._readString(row, 'id');
      final position = OfflineLibraryStorage._readInt(row, 'position');

      return LocalPlaylistEntry(
        entryKey: '$playlistId:$position',
        playlistId: playlistId,
        position: position,
        track: _host._trackFromRow(row, liked: _host._trackIsLocallyLiked(db, localId), inPlaylists: true),
        source: _sourceFromRow(row),
        localTrackId: localId,
        status: OfflineDownloadStatus.downloaded,
        isPending: false,
      );
    }).toList();

    entries.addAll(_readPendingEntries(db, playlistId: playlistId));
    entries.sort((left, right) => left.position.compareTo(right.position));

    return List.unmodifiable(entries);
  }

  List<LocalPlaylistEntry> _readPendingEntries(Database db, {String? playlistId, String? serverBaseUrl}) {
    final rows = db.select(
      '''SELECT p.*, s.status AS download_status, s.error AS download_error,
        s.local_track_id AS source_local_track_id,
        COALESCE(p.track_json, f.track_json) AS snapshot_json
      FROM pending_playlist_tracks p
      LEFT JOIN source_tracks s ON s.server_base_url = p.server_base_url AND s.server_track_id = p.server_track_id
      LEFT JOIN offline_metadata_fragments f
        ON f.server_base_url = p.server_base_url AND f.server_track_id = p.server_track_id
      WHERE (? IS NULL OR p.playlist_id = ?) AND (? IS NULL OR p.server_base_url = ?)
      ORDER BY p.playlist_id, p.position''',
      [playlistId, playlistId, serverBaseUrl, serverBaseUrl],
    );

    return rows
        .map((row) {
          final source = _sourceFromRow(row);
          final id = OfflineLibraryStorage._readString(row, 'playlist_id');
          final position = OfflineLibraryStorage._readInt(row, 'position');
          final requested = OfflineLibraryStorage._parseStatus(
            OfflineLibraryStorage._readString(row, 'request_status'),
          );
          final sourceStatus = OfflineLibraryStorage._readNullableString(row, 'download_status');
          final localId =
              OfflineLibraryStorage._readNullableString(row, 'source_local_track_id') ??
              OfflineLibraryStorage._readNullableString(row, 'local_track_id');
          final stopped = requested == OfflineDownloadStatus.canceled;
          final status = stopped || sourceStatus == null ? requested : OfflineLibraryStorage._parseStatus(sourceStatus);
          final track = _trackSnapshot(OfflineLibraryStorage._readNullableString(row, 'snapshot_json'), source);

          return LocalPlaylistEntry(
            entryKey: '$id:$position',
            playlistId: id,
            position: position,
            track: track.copyWith(localId: localId, inPlaylists: true),
            source: source,
            localTrackId: localId,
            status: status,
            isPending: true,
            error:
                OfflineLibraryStorage._readNullableString(row, 'request_error') ??
                OfflineLibraryStorage._readNullableString(row, 'download_error'),
          );
        })
        .toList(growable: false);
  }

  Track _trackSnapshot(String? snapshot, SourceTrackRef source) {
    if (snapshot != null) {
      try {
        final json = jsonDecode(snapshot);

        if (json is Map) {
          return Track.fromJson(
            Map<String, dynamic>.from(json),
          ).copyWith(serverBaseUrl: source.serverBaseUrl, serverTrackId: source.serverTrackId);
        }
      } catch (err) {
        AppLogger.warning('Failed to restore pending playlist metadata: $err');
      }
    }

    return Track(
      id: source.serverTrackId,
      title: 'Unavailable track',
      artist: '',
      album: '',
      durationMs: 0,
      liked: false,
      inPlaylists: true,
      serverBaseUrl: source.serverBaseUrl,
      serverTrackId: source.serverTrackId,
    );
  }

  String? _existingLocalId(Database db, String? localId) {
    if (localId == null || db.select('SELECT 1 FROM tracks WHERE id = ?', [localId]).isEmpty) {
      return null;
    }

    return localId;
  }

  String? _knownLocalId(Database db, SourceTrackRef source) {
    return _host._findLocalIdForSource(db, source);
  }

  bool _hasDownloadedLocalTrack(Database db, String localId) {
    try {
      _host._requireDownloadedLocalTrack(db, localId);

      return true;
    } on StateError catch (_) {
      return false;
    }
  }

  int _nextPosition(Database db, String playlistId) =>
      db
              .select(
                '''SELECT COALESCE(MAX(position), -1) + 1 AS next_position
    FROM (SELECT position FROM local_playlist_tracks WHERE playlist_id = ?
      UNION ALL SELECT position FROM pending_playlist_tracks WHERE playlist_id = ?)''',
                [playlistId, playlistId],
              )
              .single['next_position']
          as int;

  SourceTrackRef _sourceFromRow(Row row) => SourceTrackRef(
    serverBaseUrl: OfflineLibraryStorage._readString(row, 'server_base_url'),
    serverTrackId: OfflineLibraryStorage._readString(row, 'server_track_id'),
  );

  void _registerDemand(Database db, SourceTrackRef source, String ownerKind, String ownerId) {
    if (!source.isValid || ownerKind.trim().isEmpty || ownerId.trim().isEmpty) {
      throw ArgumentError('A download demand requires a source and an owner.');
    }

    db.execute(
      '''INSERT OR IGNORE INTO download_demands
      (server_base_url, server_track_id, owner_kind, owner_id, created_at) VALUES (?, ?, ?, ?, ?)''',
      [source.serverBaseUrl, source.serverTrackId, ownerKind, ownerId, DateTime.now().millisecondsSinceEpoch],
    );
  }

  bool _hasDemand(Database db, SourceTrackRef source) => db
      .select(
        '''SELECT 1 FROM download_demands
    WHERE server_base_url = ? AND server_track_id = ? LIMIT 1''',
        [source.serverBaseUrl, source.serverTrackId],
      )
      .isNotEmpty;
}

mixin _LocalPlaylistIntentStoreFacade {
  _LocalPlaylistIntentStore get _ownerPlaylistIntents;

  Future<List<LocalPlaylistEntry>> readLocalPlaylistEntries(String playlistId) =>
      _ownerPlaylistIntents.readLocalPlaylistEntries(playlistId);

  Future<List<LocalPlaylistEntry>> readPendingPlaylistEntries({String? serverBaseUrl}) =>
      _ownerPlaylistIntents.readPendingPlaylistEntries(serverBaseUrl: serverBaseUrl);

  Future<LocalPlaylistEntry> addSourceToLocalPlaylist(String playlistId, Track track, SourceTrackRef source) =>
      _ownerPlaylistIntents.addSourceToLocalPlaylist(playlistId, track, source);

  Future<List<SourceTrackRef>> removeSourceFromLocalPlaylist(
    String playlistId,
    SourceTrackRef source, {
    String? localTrackId,
  }) => _ownerPlaylistIntents.removeSourceFromLocalPlaylist(playlistId, source, localTrackId: localTrackId);

  Future<void> registerDownloadDemand(SourceTrackRef source, {required String ownerKind, required String ownerId}) =>
      _ownerPlaylistIntents.registerDownloadDemand(source, ownerKind: ownerKind, ownerId: ownerId);

  Future<void> releaseDownloadDemand(SourceTrackRef source, {required String ownerKind, required String ownerId}) =>
      _ownerPlaylistIntents.releaseDownloadDemand(source, ownerKind: ownerKind, ownerId: ownerId);

  Future<bool> hasDownloadDemand(SourceTrackRef source) => _ownerPlaylistIntents.hasDownloadDemand(source);

  Future<List<SourceTrackRef>> readDownloadDemandSources() => _ownerPlaylistIntents.readDownloadDemandSources();

  Future<List<SourceTrackRef>> releasePlaylistDownloadDemands(String playlistId) =>
      _ownerPlaylistIntents.releasePlaylistDownloadDemands(playlistId);

  Future<void> updatePendingPlaylistRequest(SourceTrackRef source, OfflineDownloadStatus status, {String? error}) =>
      _ownerPlaylistIntents.updatePendingPlaylistRequest(source, status, error: error);

  Future<bool> canRemoveUnclaimedDownload(SourceTrackRef source) =>
      _ownerPlaylistIntents.canRemoveUnclaimedDownload(source);
}
