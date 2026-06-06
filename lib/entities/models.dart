import 'dart:typed_data';

class Artist {
  Artist({
    required this.id,
    required this.name,
    required this.albumCount,
    this.genres = const [],
    this.summary,
    this.logoRef,
    this.bannerRef,
  });

  final String id;
  final String name;
  final int albumCount;
  final List<String> genres;
  final String? summary;
  final String? logoRef;
  final String? bannerRef;

  factory Artist.fromJson(Map<String, dynamic> json) {
    return Artist(
      id: json['id'] as String,
      name: json['name'] as String,
      albumCount: _intFromJson(json, const ['album_count', 'albumCount']),
      genres:
          (json['genres'] as List?)?.map((item) => item.toString()).toList() ??
          const [],
      summary: json['summary'] as String?,
      logoRef: json['logo_ref'] as String?,
      bannerRef: json['banner_ref'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'album_count': albumCount,
    'genres': genres,
    'summary': summary,
    'logo_ref': logoRef,
    'banner_ref': bannerRef,
  };

  Artist copyWith({
    String? id,
    String? name,
    int? albumCount,
    List<String>? genres,
    Object? summary = _artistUnset,
    Object? logoRef = _artistUnset,
    Object? bannerRef = _artistUnset,
  }) {
    return Artist(
      id: id ?? this.id,
      name: name ?? this.name,
      albumCount: albumCount ?? this.albumCount,
      genres: genres ?? this.genres,
      summary: summary == _artistUnset ? this.summary : summary as String?,
      logoRef: logoRef == _artistUnset ? this.logoRef : logoRef as String?,
      bannerRef: bannerRef == _artistUnset
          ? this.bannerRef
          : bannerRef as String?,
    );
  }
}

const Object _artistUnset = Object();

class Album {
  Album({
    required this.id,
    required this.title,
    required this.artist,
    required this.artistId,
    required this.trackCount,
    this.year,
    this.genres = const [],
    this.summary,
  });

  final String id;
  final String title;
  final String artist;
  final String artistId;
  final int trackCount;
  final int? year;
  final List<String> genres;
  final String? summary;

  factory Album.fromJson(Map<String, dynamic> json) {
    return Album(
      id: json['id'] as String,
      title: json['title'] as String,
      artist: _albumArtistName(json),
      artistId: json['artist_id'] as String? ?? '',
      trackCount: _intFromJson(json, const [
        'track_count',
        'trackCount',
        'tracks_count',
        'track_total',
        'total_tracks',
      ]),
      year: _nullableIntFromJson(json['year']),
      genres:
          (json['genres'] as List?)?.map((item) => item.toString()).toList() ??
          const [],
      summary: json['summary'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'artist_id': artistId,
    'track_count': trackCount,
    'year': year,
    'genres': genres,
    'summary': summary,
  };

  Album copyWith({
    String? id,
    String? title,
    String? artist,
    String? artistId,
    int? trackCount,
    Object? year = _albumUnset,
    List<String>? genres,
    Object? summary = _albumUnset,
  }) {
    return Album(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      artistId: artistId ?? this.artistId,
      trackCount: trackCount ?? this.trackCount,
      year: year == _albumUnset ? this.year : year as int?,
      genres: genres ?? this.genres,
      summary: summary == _albumUnset ? this.summary : summary as String?,
    );
  }
}

const Object _albumUnset = Object();

String _albumArtistName(Map<String, dynamic> json) {
  final direct = _nonEmptyString(json['artist']);
  if (direct != null) {
    return direct;
  }
  final browseName = _nonEmptyString(json['artist_name']);
  if (browseName != null) {
    return browseName;
  }
  final names =
      (json['artist_names'] as List?)
          ?.map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList() ??
      const <String>[];
  return names.join(', ');
}

String? _nonEmptyString(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  return text;
}

int _intFromJson(Map<String, dynamic> json, Iterable<String> keys) {
  for (final key in keys) {
    final value = _nullableIntFromJson(json[key]);
    if (value != null) {
      return value;
    }
  }
  return 0;
}

int? _nullableIntFromJson(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim());
  }
  return null;
}

class Track {
  Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMs,
    required this.liked,
    required this.inPlaylists,
    this.artistId,
    this.albumId,
    this.localId,
    this.serverBaseUrl,
    this.serverTrackId,
    this.albumArtPath,
    this.artistArtPath,
    this.artistBannerPath,
    this.offlineAlbum,
    this.offlineArtist,
    this.genres = const [],
    this.trackNo,
    this.discNo,
  });

  final String id;
  final String title;
  final String artist;
  final String? artistId;
  final String album;
  final String? albumId;
  final String? localId;
  final String? serverBaseUrl;
  final String? serverTrackId;
  final String? albumArtPath;
  final String? artistArtPath;
  final String? artistBannerPath;
  final Album? offlineAlbum;
  final Artist? offlineArtist;
  final List<String> genres;
  final int durationMs;
  final bool liked;
  final bool inPlaylists;
  final int? trackNo;
  final int? discNo;

  factory Track.fromJson(Map<String, dynamic> json) {
    return Track(
      id: json['id'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String? ?? '',
      artistId: json['artist_id'] as String?,
      album: json['album'] as String? ?? '',
      albumId: json['album_id'] as String?,
      localId: json['local_id'] as String?,
      serverBaseUrl: json['server_base_url'] as String?,
      serverTrackId: json['server_track_id'] as String?,
      albumArtPath: (json['album_art_path'] ?? json['albumArtPath']) as String?,
      artistArtPath:
          (json['artist_art_path'] ?? json['artistArtPath']) as String?,
      artistBannerPath:
          (json['artist_banner_path'] ?? json['artistBannerPath']) as String?,
      offlineAlbum: _offlineAlbumFromJson(json['offline_album']),
      offlineArtist: _offlineArtistFromJson(json['offline_artist']),
      genres:
          (json['genres'] as List?)?.map((item) => item.toString()).toList() ??
          const [],
      durationMs: (json['duration_ms'] as num?)?.toInt() ?? 0,
      liked: json['liked'] as bool? ?? false,
      inPlaylists: json['in_playlists'] as bool? ?? false,
      trackNo: (json['track_no'] as num?)?.toInt(),
      discNo: (json['disc_no'] as num?)?.toInt(),
    );
  }

  Track copyWith({
    String? id,
    String? title,
    String? artist,
    Object? artistId = _trackUnset,
    String? album,
    Object? albumId = _trackUnset,
    Object? localId = _trackUnset,
    Object? serverBaseUrl = _trackUnset,
    Object? serverTrackId = _trackUnset,
    Object? albumArtPath = _trackUnset,
    Object? artistArtPath = _trackUnset,
    Object? artistBannerPath = _trackUnset,
    Object? offlineAlbum = _trackUnset,
    Object? offlineArtist = _trackUnset,
    List<String>? genres,
    int? durationMs,
    bool? liked,
    bool? inPlaylists,
    Object? trackNo = _trackUnset,
    Object? discNo = _trackUnset,
  }) {
    return Track(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      artistId: artistId == _trackUnset ? this.artistId : artistId as String?,
      album: album ?? this.album,
      albumId: albumId == _trackUnset ? this.albumId : albumId as String?,
      localId: localId == _trackUnset ? this.localId : localId as String?,
      serverBaseUrl: serverBaseUrl == _trackUnset
          ? this.serverBaseUrl
          : serverBaseUrl as String?,
      serverTrackId: serverTrackId == _trackUnset
          ? this.serverTrackId
          : serverTrackId as String?,
      albumArtPath: albumArtPath == _trackUnset
          ? this.albumArtPath
          : albumArtPath as String?,
      artistArtPath: artistArtPath == _trackUnset
          ? this.artistArtPath
          : artistArtPath as String?,
      artistBannerPath: artistBannerPath == _trackUnset
          ? this.artistBannerPath
          : artistBannerPath as String?,
      offlineAlbum: offlineAlbum == _trackUnset
          ? this.offlineAlbum
          : offlineAlbum as Album?,
      offlineArtist: offlineArtist == _trackUnset
          ? this.offlineArtist
          : offlineArtist as Artist?,
      genres: genres ?? this.genres,
      durationMs: durationMs ?? this.durationMs,
      liked: liked ?? this.liked,
      inPlaylists: inPlaylists ?? this.inPlaylists,
      trackNo: trackNo == _trackUnset ? this.trackNo : trackNo as int?,
      discNo: discNo == _trackUnset ? this.discNo : discNo as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'artist_id': artistId,
    'album': album,
    'album_id': albumId,
    'local_id': localId,
    'server_base_url': serverBaseUrl,
    'server_track_id': serverTrackId,
    'album_art_path': albumArtPath,
    'artist_art_path': artistArtPath,
    'artist_banner_path': artistBannerPath,
    'genres': genres,
    'duration_ms': durationMs,
    'liked': liked,
    'in_playlists': inPlaylists,
    'track_no': trackNo,
    'disc_no': discNo,
  };
}

const Object _trackUnset = Object();

Album? _offlineAlbumFromJson(Object? value) {
  if (value is Map) {
    return Album.fromJson(Map<String, dynamic>.from(value));
  }
  return null;
}

Artist? _offlineArtistFromJson(Object? value) {
  if (value is Map) {
    return Artist.fromJson(Map<String, dynamic>.from(value));
  }
  return null;
}

enum PlaylistImageEditKind { keep, clear, replace }

class PlaylistImageEdit {
  const PlaylistImageEdit.keep()
    : kind = PlaylistImageEditKind.keep,
      bytes = null,
      contentType = null;

  const PlaylistImageEdit.clear()
    : kind = PlaylistImageEditKind.clear,
      bytes = null,
      contentType = null;

  const PlaylistImageEdit.replace({
    required this.bytes,
    required this.contentType,
  }) : kind = PlaylistImageEditKind.replace;

  final PlaylistImageEditKind kind;
  final Uint8List? bytes;
  final String? contentType;
}

class Playlist {
  Playlist({
    required this.id,
    required this.name,
    required this.trackIds,
    this.description,
    this.imageRef,
    this.imagePath,
  });

  final String id;
  final String name;
  final List<String> trackIds;
  final String? description;
  final String? imageRef;
  final String? imagePath;

  factory Playlist.fromJson(Map<String, dynamic> json) {
    final ids =
        (json['track_ids'] as List?)?.map((item) => item.toString()).toList() ??
        <String>[];
    return Playlist(
      id: json['id'] as String,
      name: json['name'] as String,
      trackIds: ids,
      description: _nonEmptyString(json['description'] ?? json['summary']),
      imageRef: _nonEmptyString(json['image_ref'] ?? json['imageRef']),
      imagePath: _nonEmptyString(json['image_path'] ?? json['imagePath']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'track_ids': trackIds,
    if (description != null) 'description': description,
    if (imageRef != null) 'image_ref': imageRef,
    if (imagePath != null) 'image_path': imagePath,
  };

  Playlist copyWith({
    String? id,
    String? name,
    List<String>? trackIds,
    Object? description = _playlistUnset,
    Object? imageRef = _playlistUnset,
    Object? imagePath = _playlistUnset,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      trackIds: trackIds ?? this.trackIds,
      description: description == _playlistUnset
          ? this.description
          : description as String?,
      imageRef: imageRef == _playlistUnset
          ? this.imageRef
          : imageRef as String?,
      imagePath: imagePath == _playlistUnset
          ? this.imagePath
          : imagePath as String?,
    );
  }
}

const Object _playlistUnset = Object();

class MetadataUpdateEvent {
  MetadataUpdateEvent({
    required this.revision,
    required this.kind,
    required this.id,
    required this.updatedAt,
    this.albumId,
    this.artistId,
  });

  final int revision;
  final String kind;
  final String id;
  final String? albumId;
  final String? artistId;
  final int updatedAt;

  factory MetadataUpdateEvent.fromJson(Map<String, dynamic> json) {
    return MetadataUpdateEvent(
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      kind: json['kind']?.toString() ?? '',
      id: json['id']?.toString() ?? '',
      albumId: _nonEmptyString(json['album_id']),
      artistId: _nonEmptyString(json['artist_id']),
      updatedAt: (json['updated_at'] as num?)?.toInt() ?? 0,
    );
  }
}

class StatsResponse {
  StatsResponse({
    required this.year,
    required this.month,
    required this.totalMinutes,
    required this.topArtists,
    required this.topTracks,
    required this.topGenres,
  });

  final int year;
  final int? month;
  final int totalMinutes;
  final List<StatsItem> topArtists;
  final List<StatsTrack> topTracks;
  final List<StatsItem> topGenres;

  factory StatsResponse.fromJson(Map<String, dynamic> json) {
    return StatsResponse(
      year: (json['year'] as num?)?.toInt() ?? DateTime.now().year,
      month: (json['month'] as num?)?.toInt(),
      totalMinutes: (json['total_minutes'] as num?)?.toInt() ?? 0,
      topArtists:
          (json['top_artists'] as List?)?.map(StatsItem.parse).toList() ??
          <StatsItem>[],
      topTracks:
          (json['top_tracks'] as List?)?.map(StatsTrack.parse).toList() ??
          <StatsTrack>[],
      topGenres:
          (json['top_genres'] as List?)?.map(StatsItem.parse).toList() ??
          <StatsItem>[],
    );
  }
}

class StatsItem {
  StatsItem({required this.id, required this.name, required this.minutes});

  final String id;
  final String name;
  final int minutes;

  factory StatsItem.fromJson(Map<String, dynamic> json) {
    return StatsItem(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      minutes: (json['minutes'] as num?)?.toInt() ?? 0,
    );
  }

  static StatsItem parse(dynamic item) {
    if (item is Map) {
      return StatsItem.fromJson(Map<String, dynamic>.from(item));
    }
    final text = item?.toString() ?? '';
    return StatsItem(id: text, name: text, minutes: 0);
  }
}

class StatsTrack {
  StatsTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.minutes,
    required this.plays,
  });

  final String id;
  final String title;
  final String artist;
  final int minutes;
  final int plays;

  factory StatsTrack.fromJson(Map<String, dynamic> json) {
    return StatsTrack(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      artist: json['artist']?.toString() ?? '',
      minutes: (json['minutes'] as num?)?.toInt() ?? 0,
      plays: (json['plays'] as num?)?.toInt() ?? 0,
    );
  }

  static StatsTrack parse(dynamic item) {
    if (item is Map) {
      return StatsTrack.fromJson(Map<String, dynamic>.from(item));
    }
    final text = item?.toString() ?? '';
    return StatsTrack(id: '', title: text, artist: '', minutes: 0, plays: 0);
  }
}

class SearchResult {
  SearchResult({
    required this.kind,
    required this.id,
    required this.title,
    this.subtitle,
    this.score,
  });

  final String kind;
  final String id;
  final String title;
  final String? subtitle;
  final int? score;

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      kind: json['kind'] as String? ?? 'track',
      id: json['id'] as String,
      title: json['title'] as String? ?? json['name'] as String? ?? '',
      subtitle: json['subtitle'] as String? ?? json['artist'] as String?,
      score: (json['score'] as num?)?.toInt(),
    );
  }
}

class OfflineTrackMetadata {
  static const int currentSchemaVersion = 4;

  OfflineTrackMetadata({
    required this.schemaVersion,
    required this.track,
    required this.album,
    required this.artist,
  });

  final int schemaVersion;
  final Track track;
  final Album album;
  final Artist artist;

  factory OfflineTrackMetadata.fromJson(Map<String, dynamic> json) {
    return OfflineTrackMetadata(
      schemaVersion: (json['schema_version'] as num?)?.toInt() ?? 1,
      track: Track.fromJson(
        Map<String, dynamic>.from(json['track'] as Map? ?? const {}),
      ),
      album: Album.fromJson(
        Map<String, dynamic>.from(json['album'] as Map? ?? const {}),
      ),
      artist: Artist.fromJson(
        Map<String, dynamic>.from(json['artist'] as Map? ?? const {}),
      ),
    );
  }

  OfflineTrackMetadata copyWith({Track? track, Album? album, Artist? artist}) {
    return OfflineTrackMetadata(
      schemaVersion: schemaVersion,
      track: track ?? this.track,
      album: album ?? this.album,
      artist: artist ?? this.artist,
    );
  }

  Map<String, dynamic> toJson() => {
    'schema_version': schemaVersion,
    'track': track.toJson(),
    'album': album.toJson(),
    'artist': artist.toJson(),
  };
}

class DownloadBatchManifest {
  DownloadBatchManifest({
    required this.schemaVersion,
    required this.batchId,
    required this.createdAt,
    required this.items,
    required this.unavailable,
  });

  final int schemaVersion;
  final String batchId;
  final DateTime createdAt;
  final List<DownloadBatchItem> items;
  final List<DownloadBatchUnavailable> unavailable;

  factory DownloadBatchManifest.fromJson(Map<String, dynamic> json) {
    final items =
        (json['items'] as List?)
            ?.whereType<Map>()
            .map(
              (item) =>
                  DownloadBatchItem.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList(growable: false) ??
        const <DownloadBatchItem>[];
    final unavailable =
        (json['unavailable'] as List?)
            ?.whereType<Map>()
            .map(
              (item) => DownloadBatchUnavailable.fromJson(
                Map<String, dynamic>.from(item),
              ),
            )
            .toList(growable: false) ??
        const <DownloadBatchUnavailable>[];
    return DownloadBatchManifest(
      schemaVersion: (json['schema_version'] as num?)?.toInt() ?? 1,
      batchId: json['batch_id']?.toString() ?? '',
      createdAt: _parseManifestDate(json['created_at']),
      items: items,
      unavailable: unavailable,
    );
  }

  static DateTime _parseManifestDate(Object? value) {
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    final text = value?.toString();
    if (text == null || text.isEmpty) {
      return DateTime.now();
    }
    return DateTime.tryParse(text) ??
        DateTime.fromMillisecondsSinceEpoch(int.tryParse(text) ?? 0);
  }
}

class DownloadBatchItem {
  DownloadBatchItem({
    required this.trackId,
    required this.downloadUrl,
    required this.offlineMetadata,
    required this.byteLength,
    required this.contentType,
    required this.etag,
    required this.sha256,
  });

  final String trackId;
  final String downloadUrl;
  final OfflineTrackMetadata offlineMetadata;
  final int byteLength;
  final String contentType;
  final String etag;
  final String sha256;

  factory DownloadBatchItem.fromJson(Map<String, dynamic> json) {
    return DownloadBatchItem(
      trackId: json['track_id']?.toString() ?? '',
      downloadUrl: json['download_url']?.toString() ?? '',
      offlineMetadata: OfflineTrackMetadata.fromJson(
        Map<String, dynamic>.from(json['offline_metadata'] as Map? ?? const {}),
      ),
      byteLength: (json['byte_length'] as num?)?.toInt() ?? 0,
      contentType:
          json['content_type']?.toString() ?? 'application/octet-stream',
      etag: json['etag']?.toString() ?? '',
      sha256: json['sha256']?.toString() ?? '',
    );
  }
}

class DownloadBatchUnavailable {
  DownloadBatchUnavailable({required this.trackId, required this.reason});

  final String trackId;
  final String reason;

  factory DownloadBatchUnavailable.fromJson(Map<String, dynamic> json) {
    return DownloadBatchUnavailable(
      trackId: json['track_id']?.toString() ?? '',
      reason: json['reason']?.toString() ?? 'unavailable',
    );
  }
}

class ServerCapabilities {
  ServerCapabilities({
    required this.downloadJobsV2,
    required this.metadataSnapshotsV2,
    required this.eventReplayV2,
    required this.trackFileContractV2,
  });

  final bool downloadJobsV2;
  final bool metadataSnapshotsV2;
  final bool eventReplayV2;
  final bool trackFileContractV2;

  factory ServerCapabilities.fromJson(Map<String, dynamic> json) {
    return ServerCapabilities(
      downloadJobsV2: _capabilityEnabled(json['download_jobs_v2']),
      metadataSnapshotsV2: _capabilityEnabled(json['metadata_snapshots_v2']),
      eventReplayV2: _capabilityEnabled(json['event_replay_v2']),
      trackFileContractV2: _capabilityEnabled(json['track_file_contract_v2']),
    );
  }

  static bool _capabilityEnabled(Object? value) {
    final text = value?.toString().trim().toLowerCase();
    return text == '1' || text == 'true' || text == 'yes';
  }
}

class DownloadJobScopeV2 {
  DownloadJobScopeV2({required this.kind, this.id, this.trackIds = const []});

  final String kind;
  final String? id;
  final List<String> trackIds;

  Map<String, dynamic> toJson() => {
    'kind': kind,
    if (id != null && id!.trim().isNotEmpty) 'id': id,
    if (trackIds.isNotEmpty) 'track_ids': trackIds,
  };
}

class DownloadJobV2 {
  DownloadJobV2({
    required this.jobId,
    required this.clientId,
    required this.clientRequestId,
    required this.scope,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.totalCount,
    required this.readyCount,
    required this.completedCount,
    required this.failedCount,
    required this.eventCursor,
    required this.items,
  });

  final String jobId;
  final String clientId;
  final String clientRequestId;
  final DownloadJobScopeV2 scope;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int totalCount;
  final int readyCount;
  final int completedCount;
  final int failedCount;
  final int eventCursor;
  final List<DownloadJobItemV2> items;

  factory DownloadJobV2.fromJson(Map<String, dynamic> json) {
    final rawScope = json['scope'];
    final scopeJson = rawScope is Map
        ? Map<String, dynamic>.from(rawScope)
        : const <String, dynamic>{};
    return DownloadJobV2(
      jobId: json['job_id']?.toString() ?? '',
      clientId: json['client_id']?.toString() ?? '',
      clientRequestId: json['client_request_id']?.toString() ?? '',
      scope: DownloadJobScopeV2(
        kind: scopeJson['kind']?.toString() ?? '',
        id: scopeJson['id']?.toString(),
        trackIds:
            (scopeJson['track_ids'] as List?)
                ?.map((item) => item.toString())
                .toList(growable: false) ??
            const <String>[],
      ),
      status: json['status']?.toString() ?? 'queued',
      createdAt: _parseV2Date(json['created_at']),
      updatedAt: _parseV2Date(json['updated_at']),
      totalCount: _parseV2Int(json['total_count']),
      readyCount: _parseV2Int(json['ready_count']),
      completedCount: _parseV2Int(json['completed_count']),
      failedCount: _parseV2Int(json['failed_count']),
      eventCursor: _parseV2Int(json['event_cursor']),
      items:
          (json['items'] as List?)
              ?.whereType<Map>()
              .map(
                (item) =>
                    DownloadJobItemV2.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList(growable: false) ??
          const <DownloadJobItemV2>[],
    );
  }
}

class DownloadJobItemV2 {
  DownloadJobItemV2({
    required this.position,
    required this.trackId,
    required this.status,
    this.downloadUrl,
    this.offlineMetadata,
    this.byteLength,
    this.contentType,
    this.etag,
    this.sha256,
    this.error,
  });

  final int position;
  final String trackId;
  final String status;
  final String? downloadUrl;
  final OfflineTrackMetadata? offlineMetadata;
  final int? byteLength;
  final String? contentType;
  final String? etag;
  final String? sha256;
  final String? error;

  bool get readyToDownload =>
      status == 'ready_to_download' && offlineMetadata != null;

  factory DownloadJobItemV2.fromJson(Map<String, dynamic> json) {
    final rawMetadata = json['offline_metadata'];
    return DownloadJobItemV2(
      position: _parseV2Int(json['position']),
      trackId: json['track_id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'queued',
      downloadUrl: _optionalV2String(json['download_url']),
      offlineMetadata: rawMetadata is Map
          ? OfflineTrackMetadata.fromJson(
              Map<String, dynamic>.from(rawMetadata),
            )
          : null,
      byteLength: _parseNullableV2Int(json['byte_length']),
      contentType: _optionalV2String(json['content_type']),
      etag: _optionalV2String(json['etag']),
      sha256: _optionalV2String(json['sha256']),
      error: _optionalV2String(json['error']),
    );
  }
}

DateTime _parseV2Date(Object? value) {
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  final text = value?.toString();
  if (text == null || text.isEmpty) {
    return DateTime.now();
  }
  return DateTime.tryParse(text) ??
      DateTime.fromMillisecondsSinceEpoch(int.tryParse(text) ?? 0);
}

int _parseV2Int(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _parseNullableV2Int(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value.toString());
}

String? _optionalV2String(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  return text;
}

class TrackMatchDescriptor {
  TrackMatchDescriptor({
    required this.localTrackId,
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMs,
    this.trackNo,
    this.discNo,
    this.serverTrackId,
  });

  final String localTrackId;
  final String title;
  final String artist;
  final String album;
  final int durationMs;
  final int? trackNo;
  final int? discNo;
  final String? serverTrackId;

  Map<String, dynamic> toJson() => {
    'local_track_id': localTrackId,
    'title': title,
    'artist': artist,
    'album': album,
    'duration_ms': durationMs,
    'track_no': trackNo,
    'disc_no': discNo,
    if (serverTrackId != null && serverTrackId!.trim().isNotEmpty)
      'server_track_id': serverTrackId,
  };
}

class TrackMatchResult {
  TrackMatchResult({
    required this.localTrackId,
    required this.serverTrackId,
    required this.confidence,
    required this.matchKind,
    required this.serverLiked,
    required this.serverUpdatedAt,
  });

  final String localTrackId;
  final String serverTrackId;
  final double confidence;
  final String matchKind;
  final bool serverLiked;
  final int serverUpdatedAt;

  factory TrackMatchResult.fromJson(Map<String, dynamic> json) {
    return TrackMatchResult(
      localTrackId: json['local_track_id']?.toString() ?? '',
      serverTrackId: json['server_track_id']?.toString() ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      matchKind: json['match_kind']?.toString() ?? 'metadata_strict',
      serverLiked: json['server_liked'] as bool? ?? false,
      serverUpdatedAt: (json['server_updated_at'] as num?)?.toInt() ?? 0,
    );
  }
}

class ServerLikeState {
  ServerLikeState({
    required this.trackId,
    required this.liked,
    required this.updatedAt,
  });

  final String trackId;
  final bool liked;
  final int updatedAt;

  factory ServerLikeState.fromJson(Map<String, dynamic> json) {
    return ServerLikeState(
      trackId: json['track_id']?.toString() ?? '',
      liked: json['liked'] as bool? ?? false,
      updatedAt: (json['updated_at'] as num?)?.toInt() ?? 0,
    );
  }
}

class OutputDevice {
  OutputDevice({required this.id, required this.name});

  final int id;
  final String name;
}
