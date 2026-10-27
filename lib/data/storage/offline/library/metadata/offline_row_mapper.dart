part of '../offline_library.dart';

class _OfflineRowMapper {
  OfflineTrackDownload _downloadFromRow(Row row) {
    final localTrackId = OfflineLibraryStorage._readString(row, 'local_track_id');
    final serverBaseUrl = OfflineLibraryStorage._readString(row, 'server_base_url');
    final serverTrackId = OfflineLibraryStorage._readString(row, 'server_track_id');
    final fallbackTrack = Track(
      id: serverTrackId,
      title: OfflineLibraryStorage._readString(row, 'title'),
      artist: OfflineLibraryStorage._readString(row, 'artist'),
      artistId: OfflineLibraryStorage._readNullableString(row, 'artist_id'),
      album: OfflineLibraryStorage._readString(row, 'album'),
      albumId: OfflineLibraryStorage._readNullableString(row, 'album_id'),
      localId: localTrackId,
      serverBaseUrl: serverBaseUrl,
      serverTrackId: serverTrackId,
      albumArtPath: OfflineLibraryStorage._readNullableString(row, 'album_art_path'),
      artistArtPath: OfflineLibraryStorage._readNullableString(row, 'artist_art_path'),
      artistBannerPath: OfflineLibraryStorage._readNullableString(row, 'artist_banner_path'),
      genres: _genresFromRow(row),
      durationMs: OfflineLibraryStorage._readInt(row, 'duration_ms'),
      liked: OfflineLibraryStorage._readBool(row, 'local_liked'),
      inPlaylists: OfflineLibraryStorage._readBool(row, 'local_in_playlists'),
      trackNo: OfflineLibraryStorage._readNullableInt(row, 'track_no'),
      discNo: OfflineLibraryStorage._readNullableInt(row, 'disc_no'),
    );

    final offlineMetadata = _offlineMetadataFromRow(row);
    final track = _trackWithOfflineMetadata(
      fallbackTrack,
      offlineMetadata,
      id: serverTrackId,
      localId: localTrackId,
      serverBaseUrl: serverBaseUrl,
      serverTrackId: serverTrackId,
      liked: OfflineLibraryStorage._readBool(row, 'local_liked'),
      inPlaylists: OfflineLibraryStorage._readBool(row, 'local_in_playlists'),
    );

    return OfflineTrackDownload(
      serverBaseUrl: serverBaseUrl,
      batchId: OfflineLibraryStorage._readNullableString(row, 'batch_id'),
      localTrackId: localTrackId,
      track: track,
      offlineMetadata: offlineMetadata?.copyWith(track: track),
      status: OfflineLibraryStorage._parseStatus(OfflineLibraryStorage._readString(row, 'status')),
      createdAt: OfflineLibraryStorage._dateFromMs(OfflineLibraryStorage._readInt(row, 'created_at')),
      updatedAt: OfflineLibraryStorage._dateFromMs(OfflineLibraryStorage._readInt(row, 'updated_at')),
      downloadUrl: OfflineLibraryStorage._readNullableString(row, 'download_url'),
      filePath: OfflineLibraryStorage._readNullableString(row, 'file_path'),
      partialPath: OfflineLibraryStorage._readNullableString(row, 'partial_path'),
      bytesDownloaded: OfflineLibraryStorage._readInt(row, 'bytes_downloaded'),
      bytesTotal: OfflineLibraryStorage._readNullableInt(row, 'bytes_total'),
      etag: OfflineLibraryStorage._readNullableString(row, 'etag'),
      expectedSha256: OfflineLibraryStorage._readNullableString(row, 'expected_sha256'),
      contentType: OfflineLibraryStorage._readNullableString(row, 'content_type'),
      error: OfflineLibraryStorage._readNullableString(row, 'error'),
      retryCount: OfflineLibraryStorage._readInt(row, 'retry_count'),
      priority: OfflineLibraryStorage._readInt(row, 'priority'),
    );
  }

  OfflineDownloadJob _downloadJobFromRow(Row row) {
    return OfflineDownloadJob(
      jobId: OfflineLibraryStorage._readString(row, 'job_id'),
      kind: OfflineLibraryStorage._readString(row, 'kind'),
      serverBaseUrl: OfflineLibraryStorage._readString(row, 'server_base_url'),
      status: OfflineLibraryStorage._parseStatus(OfflineLibraryStorage._readString(row, 'status')),
      createdAt: OfflineLibraryStorage._dateFromMs(OfflineLibraryStorage._readInt(row, 'created_at')),
      updatedAt: OfflineLibraryStorage._dateFromMs(OfflineLibraryStorage._readInt(row, 'updated_at')),
      totalCount: OfflineLibraryStorage._readInt(row, 'total_count'),
      discoveredCount: OfflineLibraryStorage._readInt(row, 'discovered_count'),
      completedCount: OfflineLibraryStorage._readInt(row, 'completed_count'),
      failedCount: OfflineLibraryStorage._readInt(row, 'failed_count'),
      materializedCount: OfflineLibraryStorage._readInt(row, 'materialized_count'),
      sourceCursor: OfflineLibraryStorage._readInt(row, 'source_cursor'),
      label: OfflineLibraryStorage._readNullableString(row, 'label'),
      sourceId: OfflineLibraryStorage._tryReadNullableString(row, 'source_id'),
      error: OfflineLibraryStorage._readNullableString(row, 'error'),
    );
  }

  OfflineDownloadJobItem _downloadJobItemFromRow(Row row) {
    Track? track;
    OfflineTrackMetadata? offlineMetadata;
    final rawMetadata = OfflineLibraryStorage._readNullableString(row, 'metadata_json');

    if (rawMetadata != null && rawMetadata.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawMetadata);

        if (decoded is Map) {
          offlineMetadata = OfflineTrackMetadata.fromJson(Map<String, dynamic>.from(decoded));
          track = offlineMetadata.track;
        }
      } catch (_) {}
    }

    final rawTrack = OfflineLibraryStorage._readNullableString(row, 'track_json');

    if (track == null && rawTrack != null && rawTrack.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawTrack);

        if (decoded is Map) {
          track = Track.fromJson(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {}
    }

    return OfflineDownloadJobItem(
      jobId: OfflineLibraryStorage._readString(row, 'job_id'),
      position: OfflineLibraryStorage._readInt(row, 'position'),
      serverTrackId: OfflineLibraryStorage._readString(row, 'server_track_id'),
      status: OfflineLibraryStorage._parseStatus(OfflineLibraryStorage._readString(row, 'status')),
      materialized: OfflineLibraryStorage._readBool(row, 'materialized'),
      createdAt: OfflineLibraryStorage._dateFromMs(OfflineLibraryStorage._readInt(row, 'created_at')),
      updatedAt: OfflineLibraryStorage._dateFromMs(OfflineLibraryStorage._readInt(row, 'updated_at')),
      track: track,
      offlineMetadata: offlineMetadata,
      error: OfflineLibraryStorage._readNullableString(row, 'error'),
    );
  }

  OfflineDownloadJobSource _downloadJobSourceFromRow(Row row) {
    return OfflineDownloadJobSource(
      jobId: OfflineLibraryStorage._readString(row, 'job_id'),
      position: OfflineLibraryStorage._readInt(row, 'position'),
      sourceId: OfflineLibraryStorage._readString(row, 'source_id'),
      status: OfflineLibraryStorage._parseStatus(OfflineLibraryStorage._readString(row, 'status')),
      createdAt: OfflineLibraryStorage._dateFromMs(OfflineLibraryStorage._readInt(row, 'created_at')),
      updatedAt: OfflineLibraryStorage._dateFromMs(OfflineLibraryStorage._readInt(row, 'updated_at')),
      label: OfflineLibraryStorage._readNullableString(row, 'label'),
      error: OfflineLibraryStorage._readNullableString(row, 'error'),
    );
  }

  List<String> _genresFromRow(Row row) {
    final raw = OfflineLibraryStorage._tryReadNullableString(row, 'genres_json');

    if (raw == null || raw.isEmpty) {
      return const [];
    }

    try {
      final decoded = jsonDecode(raw);

      if (decoded is List) {
        return decoded.map((item) => item.toString().trim()).where((item) => item.isNotEmpty).toList(growable: false);
      }
    } catch (_) {}

    return const [];
  }

  Track _trackFromRow(Row row, {required bool liked, required bool inPlaylists}) {
    final localId = OfflineLibraryStorage._readString(row, 'id');
    final serverBaseUrl = OfflineLibraryStorage._readNullableString(row, 'server_base_url');
    final serverTrackId = OfflineLibraryStorage._readNullableString(row, 'server_track_id');
    final fallbackTrack = Track(
      id: localId,
      title: OfflineLibraryStorage._readString(row, 'title'),
      artist: OfflineLibraryStorage._readString(row, 'artist'),
      artistId: OfflineLibraryStorage._readNullableString(row, 'artist_id'),
      album: OfflineLibraryStorage._readString(row, 'album'),
      albumId: OfflineLibraryStorage._readNullableString(row, 'album_id'),
      localId: localId,
      serverBaseUrl: serverBaseUrl,
      serverTrackId: serverTrackId,
      albumArtPath: OfflineLibraryStorage._readNullableString(row, 'album_art_path'),
      artistArtPath: OfflineLibraryStorage._readNullableString(row, 'artist_art_path'),
      artistBannerPath: OfflineLibraryStorage._readNullableString(row, 'artist_banner_path'),
      genres: _genresFromRow(row),
      durationMs: OfflineLibraryStorage._readInt(row, 'duration_ms'),
      liked: liked,
      inPlaylists: inPlaylists,
      trackNo: OfflineLibraryStorage._readNullableInt(row, 'track_no'),
      discNo: OfflineLibraryStorage._readNullableInt(row, 'disc_no'),
    );

    return _trackWithOfflineMetadata(
      fallbackTrack,
      _offlineMetadataFromRow(row),
      id: localId,
      localId: localId,
      serverBaseUrl: serverBaseUrl,
      serverTrackId: serverTrackId,
      liked: liked,
      inPlaylists: inPlaylists,
    );
  }

  OfflineTrackMetadata? _offlineMetadataFromRow(Row row) {
    final trackJson = OfflineLibraryStorage._tryReadNullableString(row, 'offline_track_json');
    final albumJson = OfflineLibraryStorage._tryReadNullableString(row, 'offline_album_json');
    final artistJson = OfflineLibraryStorage._tryReadNullableString(row, 'offline_artist_json');

    if (trackJson == null || albumJson == null || artistJson == null) {
      return null;
    }

    try {
      final rawTrack = jsonDecode(trackJson);
      final rawAlbum = jsonDecode(albumJson);
      final rawArtist = jsonDecode(artistJson);

      if (rawTrack is! Map || rawAlbum is! Map || rawArtist is! Map) {
        return null;
      }

      return OfflineTrackMetadata(
        schemaVersion: OfflineLibraryStorage._tryReadNullableInt(row, 'offline_schema_version') ?? 1,
        track: Track.fromJson(Map<String, dynamic>.from(rawTrack)),
        album: Album.fromJson(Map<String, dynamic>.from(rawAlbum)),
        artist: Artist.fromJson(Map<String, dynamic>.from(rawArtist)),
      );
    } catch (_) {
      return null;
    }
  }

  Track _trackWithOfflineMetadata(
    Track fallback,
    OfflineTrackMetadata? metadata, {
    required String id,
    required String? localId,
    required String? serverBaseUrl,
    required String? serverTrackId,
    required bool liked,
    required bool inPlaylists,
  }) {
    final source = metadata?.track ?? fallback;
    final sameArtist = source.artistArtworkIdentity == fallback.artistArtworkIdentity;

    return source.copyWith(
      id: id,
      artist: source.artist.trim().isEmpty ? fallback.artist : source.artist,
      artistId: source.artistId ?? fallback.artistId,
      artistIds: source.artistIds.isEmpty && sameArtist ? fallback.artistIds : source.artistIds,
      artistNames: source.artistNames.isEmpty && sameArtist ? fallback.artistNames : source.artistNames,
      artistCredits: source.artistCredits.isEmpty && sameArtist ? fallback.artistCredits : source.artistCredits,
      album: source.album.trim().isEmpty ? fallback.album : source.album,
      albumId: source.albumId ?? fallback.albumId,
      localId: localId,
      serverBaseUrl: serverBaseUrl,
      serverTrackId: serverTrackId,
      albumArtPath: fallback.albumArtPath ?? source.albumArtPath,
      artistArtPath: sameArtist ? fallback.artistArtPath ?? source.artistArtPath : source.artistArtPath,
      artistBannerPath: sameArtist ? fallback.artistBannerPath ?? source.artistBannerPath : source.artistBannerPath,
      durationMs: source.durationMs > 0 ? source.durationMs : fallback.durationMs,
      genres: source.genres.isEmpty ? fallback.genres : source.genres,
      liked: liked,
      inPlaylists: inPlaylists,
      trackNo: source.trackNo ?? fallback.trackNo,
      discNo: source.discNo ?? fallback.discNo,
      offlineAlbum: metadata?.album ?? fallback.offlineAlbum,
      offlineArtist: metadata?.artist ?? fallback.offlineArtist,
      offlineArtists: metadata?.allArtists ?? fallback.offlineArtists,
    );
  }

  OfflineTrackDownload _withLocalTrack(OfflineTrackDownload download, String localTrackId) {
    final serverTrackId = download.track.serverTrackId ?? download.track.id;
    final track = _trackWithOfflineMetadata(
      download.track,
      download.offlineMetadata,
      id: download.track.id,
      localId: localTrackId,
      serverBaseUrl: download.serverBaseUrl,
      serverTrackId: serverTrackId,
      liked: download.track.liked,
      inPlaylists: download.track.inPlaylists,
    );

    return download.copyWith(
      localTrackId: localTrackId,
      track: track,
      offlineMetadata: download.offlineMetadata?.copyWith(track: track),
    );
  }

  static OfflineDownloadStatus _parseStatus(String value) {
    for (final status in OfflineDownloadStatus.values) {
      if (status.name == value) {
        return status;
      }
    }

    return OfflineDownloadStatus.queued;
  }

  static DateTime _dateFromMs(int value) {
    if (value <= 0) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    return DateTime.fromMillisecondsSinceEpoch(value);
  }

  static String _readString(Row row, String key) {
    return row[key]?.toString() ?? '';
  }

  static String? _readNullableString(Row row, String key) => JsonValues.nonEmptyString(row[key]);

  static String? _normalizeOptionalText(String? value) => JsonValues.nonEmptyString(value);

  static String? _tryReadNullableString(Row row, String key) {
    try {
      return OfflineLibraryStorage._readNullableString(row, key);
    } catch (_) {
      return null;
    }
  }

  static int _readInt(Row row, String key) {
    final value = row[key];

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int? _readNullableInt(Row row, String key) {
    final value = row[key];
    if (value == null) {
      return null;
    }

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value.toString());
  }

  static int? _tryReadNullableInt(Row row, String key) {
    try {
      return OfflineLibraryStorage._readNullableInt(row, key);
    } catch (_) {
      return null;
    }
  }

  static bool _readBool(Row row, String key) {
    final value = row[key];

    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    return value?.toString() == 'true';
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _OfflineRowMapperFacade {
  _OfflineRowMapper get _ownerMapper;

  OfflineTrackDownload _downloadFromRow(Row row) => _ownerMapper._downloadFromRow(row);

  OfflineDownloadJob _downloadJobFromRow(Row row) => _ownerMapper._downloadJobFromRow(row);

  OfflineDownloadJobItem _downloadJobItemFromRow(Row row) => _ownerMapper._downloadJobItemFromRow(row);

  OfflineDownloadJobSource _downloadJobSourceFromRow(Row row) => _ownerMapper._downloadJobSourceFromRow(row);

  Track _trackFromRow(Row row, {required bool liked, required bool inPlaylists}) =>
      _ownerMapper._trackFromRow(row, liked: liked, inPlaylists: inPlaylists);

  OfflineTrackDownload _withLocalTrack(OfflineTrackDownload download, String localTrackId) =>
      _ownerMapper._withLocalTrack(download, localTrackId);
}
