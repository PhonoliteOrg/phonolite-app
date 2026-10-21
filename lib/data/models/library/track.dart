import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/library/artist_credit.dart';
import 'package:phonolite_app/data/structures/serialization/json_values.dart';

const Object _trackUnset = Object();

class Track {
  final String id;
  final String title;
  final String artist;
  final String? artistId;
  final List<String> artistIds;
  final List<String> artistNames;
  final List<ArtistCredit> artistCredits;
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
  final List<Artist> offlineArtists;
  final List<String> genres;

  /// Album-first genre projection for statistics, separate from song tags.
  final List<String> listeningGenres;
  final int durationMs;
  final bool liked;
  final bool inPlaylists;
  final int? trackNo;
  final int? discNo;

  Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMs,
    required this.liked,
    required this.inPlaylists,
    this.artistId,
    this.artistIds = const [],
    this.artistNames = const [],
    this.artistCredits = const [],
    this.albumId,
    this.localId,
    this.serverBaseUrl,
    this.serverTrackId,
    this.albumArtPath,
    this.artistArtPath,
    this.artistBannerPath,
    this.offlineAlbum,
    this.offlineArtist,
    this.offlineArtists = const [],
    this.genres = const [],
    this.listeningGenres = const [],
    this.trackNo,
    this.discNo,
  });

  factory Track.fromJson(Map<String, dynamic> json) {
    return Track(
      id: json['id'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String? ?? '',
      artistId: json['artist_id'] as String?,
      artistIds: JsonValues.strings(json['artist_ids']),
      artistNames: JsonValues.strings(json['artist_names']),
      artistCredits: ArtistCredit.listFromJson(json['artist_credits']),
      album: json['album'] as String? ?? '',
      albumId: json['album_id'] as String?,
      localId: json['local_id'] as String?,
      serverBaseUrl: json['server_base_url'] as String?,
      serverTrackId: json['server_track_id'] as String?,
      albumArtPath: (json['album_art_path'] ?? json['albumArtPath']) as String?,
      artistArtPath: (json['artist_art_path'] ?? json['artistArtPath']) as String?,
      artistBannerPath: (json['artist_banner_path'] ?? json['artistBannerPath']) as String?,
      offlineAlbum: _offlineAlbumFromJson(json['offline_album']),
      offlineArtist: _offlineArtistFromJson(json['offline_artist']),
      offlineArtists: _artistsFromJson(json['offline_artists']),
      genres: (json['genres'] as List?)?.map((item) => item.toString()).toList() ?? const [],
      listeningGenres: (json['listening_genres'] as List?)?.map((item) => item.toString()).toList() ?? const [],
      durationMs: (json['duration_ms'] as num?)?.toInt() ?? 0,
      liked: json['liked'] as bool? ?? false,
      inPlaylists: json['in_playlists'] as bool? ?? false,
      trackNo: (json['track_no'] as num?)?.toInt(),
      discNo: (json['disc_no'] as num?)?.toInt(),
    );
  }

  List<ArtistCredit> get credits => ArtistCredit.resolve(
    credits: artistCredits,
    ids: artistIds,
    names: artistNames,
    primaryId: artistId,
    primaryName: artist,
  );

  /// Artist scope for reusing artwork; an identified artist takes precedence.
  String get artistArtworkIdentity {
    final id = artistId?.trim();

    return id != null && id.isNotEmpty ? 'id:$id' : 'name:${artist.trim().toLowerCase()}';
  }

  Track copyWith({
    String? id,
    String? title,
    String? artist,
    Object? artistId = _trackUnset,
    List<String>? artistIds,
    List<String>? artistNames,
    List<ArtistCredit>? artistCredits,
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
    List<Artist>? offlineArtists,
    List<String>? genres,
    List<String>? listeningGenres,
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
      artistId: identical(artistId, _trackUnset) ? this.artistId : artistId as String?,
      artistIds: artistIds ?? this.artistIds,
      artistNames: artistNames ?? this.artistNames,
      artistCredits: artistCredits ?? this.artistCredits,
      album: album ?? this.album,
      albumId: identical(albumId, _trackUnset) ? this.albumId : albumId as String?,
      localId: identical(localId, _trackUnset) ? this.localId : localId as String?,
      serverBaseUrl: identical(serverBaseUrl, _trackUnset) ? this.serverBaseUrl : serverBaseUrl as String?,
      serverTrackId: identical(serverTrackId, _trackUnset) ? this.serverTrackId : serverTrackId as String?,
      albumArtPath: identical(albumArtPath, _trackUnset) ? this.albumArtPath : albumArtPath as String?,
      artistArtPath: identical(artistArtPath, _trackUnset) ? this.artistArtPath : artistArtPath as String?,
      artistBannerPath: identical(artistBannerPath, _trackUnset) ? this.artistBannerPath : artistBannerPath as String?,
      offlineAlbum: identical(offlineAlbum, _trackUnset) ? this.offlineAlbum : offlineAlbum as Album?,
      offlineArtist: identical(offlineArtist, _trackUnset) ? this.offlineArtist : offlineArtist as Artist?,
      offlineArtists: offlineArtists ?? this.offlineArtists,
      genres: genres ?? this.genres,
      listeningGenres: listeningGenres ?? this.listeningGenres,
      durationMs: durationMs ?? this.durationMs,
      liked: liked ?? this.liked,
      inPlaylists: inPlaylists ?? this.inPlaylists,
      trackNo: identical(trackNo, _trackUnset) ? this.trackNo : trackNo as int?,
      discNo: identical(discNo, _trackUnset) ? this.discNo : discNo as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'artist_id': artistId,
    'artist_ids': artistIds,
    'artist_names': artistNames,
    'artist_credits': artistCredits.map((credit) => credit.toJson()).toList(),
    'album': album,
    'album_id': albumId,
    'local_id': localId,
    'server_base_url': serverBaseUrl,
    'server_track_id': serverTrackId,
    'album_art_path': albumArtPath,
    'artist_art_path': artistArtPath,
    'artist_banner_path': artistBannerPath,
    if (offlineArtists.isNotEmpty) 'offline_artists': offlineArtists.map((artist) => artist.toJson()).toList(),
    'genres': genres,
    'listening_genres': listeningGenres,
    'duration_ms': durationMs,
    'liked': liked,
    'in_playlists': inPlaylists,
    'track_no': trackNo,
    'disc_no': discNo,
  };
}

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

List<Artist> _artistsFromJson(Object? value) => value is List
    ? [
        for (final item in value)
          if (item is Map) Artist.fromJson(Map<String, dynamic>.from(item)),
      ]
    : const [];
