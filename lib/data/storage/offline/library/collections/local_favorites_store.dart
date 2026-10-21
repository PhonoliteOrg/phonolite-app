part of 'package:phonolite_app/data/storage/offline/library/offline_library.dart';

class _LocalFavoritesStore {
  final OfflineLibraryStorage _host;

  _LocalFavoritesStore(this._host);

  Future<List<Track>> readLocalLikedTracks() async {
    if (kIsWeb) {
      return const [];
    }

    return await _host._withDatabase(
      (db) {
        final rows = db.select(
          '''
        SELECT t.*, s.server_base_url, s.server_track_id
        FROM tracks t
        JOIN local_likes l ON l.local_track_id = t.id
        LEFT JOIN source_tracks s ON s.local_track_id = t.id
          AND s.status = ?
          AND s.file_path IS NOT NULL
        WHERE EXISTS (
          SELECT 1 FROM source_tracks ds
          WHERE ds.local_track_id = t.id
            AND ds.status = ?
            AND ds.file_path IS NOT NULL
        )
        GROUP BY t.id
        ORDER BY l.created_at DESC, t.artist, t.album, t.disc_no, t.track_no, t.title
      ''',
          [OfflineDownloadStatus.downloaded.name, OfflineDownloadStatus.downloaded.name],
        );

        return rows
            .map(
              (row) => _host._trackFromRow(
                row,
                liked: true,
                inPlaylists: _host._trackInLocalPlaylists(db, OfflineLibraryStorage._readString(row, 'id')),
              ),
            )
            .toList(growable: false);
      },
      onError: (err, stackTrace) {
        AppLogger.warning('Failed to read local liked tracks: $err');

        return const [];
      },
    );
  }

  Future<List<LocalLikeState>> readLocalLikeStates() async {
    if (kIsWeb) {
      return const [];
    }

    return await _host._withDatabase(
      (db) {
        final rows = db.select(
          '''
        SELECT s.local_track_id, s.liked, s.updated_at
        FROM local_like_states s
        WHERE EXISTS (
          SELECT 1 FROM source_tracks ds
          WHERE ds.local_track_id = s.local_track_id
            AND ds.status = ?
            AND ds.file_path IS NOT NULL
        )
      ''',
          [OfflineDownloadStatus.downloaded.name],
        );

        return rows
            .map(
              (row) => LocalLikeState(
                localTrackId: OfflineLibraryStorage._readString(row, 'local_track_id'),
                liked: OfflineLibraryStorage._readBool(row, 'liked'),
                updatedAt: OfflineLibraryStorage._readInt(row, 'updated_at'),
              ),
            )
            .toList(growable: false);
      },
      onError: (err, stackTrace) {
        AppLogger.warning('Failed to read local like states: $err');

        return const [];
      },
    );
  }

  Future<void> setLocalLike(String localTrackId, bool liked) async {
    return await _host._withDatabase((db) {
      _host._requireDownloadedLocalTrack(db, localTrackId);

      final now = DateTime.now().millisecondsSinceEpoch;

      _host._transaction(db, () {
        _writeLocalLikeState(db, localTrackId, liked, now);
      });
    });
  }

  bool _trackIsLocallyLiked(Database db, String localTrackId) {
    return db.select('SELECT 1 FROM local_likes WHERE local_track_id = ? LIMIT 1', [localTrackId]).isNotEmpty;
  }

  void _writeLocalLikeState(Database db, String localTrackId, bool liked, int updatedAt) {
    db.execute(
      '''
      INSERT OR REPLACE INTO local_like_states (
        local_track_id,
        liked,
        updated_at
      ) VALUES (?, ?, ?)
    ''',
      [localTrackId, liked ? 1 : 0, updatedAt],
    );

    if (liked) {
      db.execute('INSERT OR REPLACE INTO local_likes (local_track_id, created_at) VALUES (?, ?)', [
        localTrackId,
        updatedAt,
      ]);
    } else {
      db.execute('DELETE FROM local_likes WHERE local_track_id = ?', [localTrackId]);
    }
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _LocalFavoritesStoreFacade {
  _LocalFavoritesStore get _ownerFavorites;

  Future<List<Track>> readLocalLikedTracks() => _ownerFavorites.readLocalLikedTracks();

  Future<List<LocalLikeState>> readLocalLikeStates() => _ownerFavorites.readLocalLikeStates();

  Future<void> setLocalLike(String localTrackId, bool liked) => _ownerFavorites.setLocalLike(localTrackId, liked);

  bool _trackIsLocallyLiked(Database db, String localTrackId) => _ownerFavorites._trackIsLocallyLiked(db, localTrackId);
}
