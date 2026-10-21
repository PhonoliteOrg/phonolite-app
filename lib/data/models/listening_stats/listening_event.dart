import 'dart:math';

import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/listening_stats/listening_artist.dart';
import 'package:phonolite_app/data/rules/listening_stats/listening_primary_artist.dart';

export 'package:phonolite_app/data/models/listening_stats/listening_artist.dart';

/// An opaque ID carries no hardware, filesystem, or network identity.
String newListeningId() {
  final random = Random.secure();

  return List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

/// A small immutable interval of audio actually consumed by the output device.
/// Metadata is normalized to one snapshot per session in the local database.
class ListeningEvent {
  final String eventId;
  final String sessionId;
  final String deviceId;
  final String trackId;
  final String title;
  final String artistId;
  final String artistName;
  final String albumId;
  final String albumTitle;
  final List<String> genres;
  final List<ListeningArtist> artists;
  final int trackDurationMs;
  final int sessionStartedAtMs;
  final int startedAtMs;
  final int endedAtMs;
  final int listenedMs;
  final int ruleVersion;
  final String? endReason;

  const ListeningEvent({
    required this.eventId,
    required this.sessionId,
    required this.deviceId,
    required this.trackId,
    required this.title,
    required this.artistName,
    required this.albumTitle,
    required this.trackDurationMs,
    required this.sessionStartedAtMs,
    required this.startedAtMs,
    required this.endedAtMs,
    required this.listenedMs,
    this.artistId = '',
    this.albumId = '',
    this.genres = const [],
    this.artists = const [],
    this.ruleVersion = 1,
    this.endReason,
  });

  factory ListeningEvent.fromTrack({
    required Track track,
    required String sessionId,
    required String deviceId,
    required int sessionStartedAtMs,
    required int startedAtMs,
    required int endedAtMs,
    required int listenedMs,
    String? eventId,
    String? endReason,
    Iterable<Album> cachedAlbums = const [],
    Iterable<Artist> cachedArtists = const [],
  }) => ListeningEvent(
    eventId: eventId ?? newListeningId(),
    sessionId: sessionId,
    deviceId: deviceId,
    trackId: track.serverTrackId ?? track.id,
    title: track.title,
    artistId: track.artistId ?? '',
    artistName: track.artist,
    albumId: track.albumId ?? '',
    albumTitle: track.album,
    genres: _snapshotGenres(track, cachedAlbums: cachedAlbums, cachedArtists: cachedArtists),
    artists: _snapshotArtists(track),
    trackDurationMs: track.durationMs,
    sessionStartedAtMs: sessionStartedAtMs,
    startedAtMs: startedAtMs,
    endedAtMs: endedAtMs,
    listenedMs: listenedMs,
    endReason: endReason,
  );

  factory ListeningEvent.fromJson(Map<String, dynamic> json) => ListeningEvent(
    eventId: json['event_id'] as String,
    sessionId: json['session_id'] as String,
    deviceId: json['device_id'] as String,
    trackId: json['track_id'] as String,
    title: json['title'] as String? ?? '',
    artistId: json['artist_id'] as String? ?? '',
    artistName: json['artist_name'] as String? ?? '',
    albumId: json['album_id'] as String? ?? '',
    albumTitle: json['album_title'] as String? ?? '',
    genres: (json['genres'] as List? ?? const []).cast<String>(),
    artists: [
      for (final artist in json['artists'] as List? ?? const [])
        ListeningArtist.fromJson(Map<String, dynamic>.from(artist as Map)),
    ],
    trackDurationMs: (json['track_duration_ms'] as num?)?.toInt() ?? 0,
    sessionStartedAtMs: (json['session_started_at_ms'] as num).toInt(),
    startedAtMs: (json['started_at_ms'] as num).toInt(),
    endedAtMs: (json['ended_at_ms'] as num).toInt(),
    listenedMs: (json['listened_ms'] as num).toInt(),
    ruleVersion: (json['rule_version'] as num?)?.toInt() ?? 1,
    endReason: json['end_reason'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'event_id': eventId,
    'session_id': sessionId,
    'device_id': deviceId,
    'track_id': trackId,
    'title': title,
    'artist_id': artistId,
    'artist_name': artistName,
    'album_id': albumId,
    'album_title': albumTitle,
    'genres': genres,
    'artists': artists.map((artist) => artist.toJson()).toList(),
    'track_duration_ms': trackDurationMs,
    'session_started_at_ms': sessionStartedAtMs,
    'started_at_ms': startedAtMs,
    'ended_at_ms': endedAtMs,
    'listened_ms': listenedMs,
    'rule_version': ruleVersion,
    if (endReason != null) 'end_reason': endReason,
  };
}

List<ListeningArtist> _snapshotArtists(Track track) {
  final artist = listeningPrimaryArtist({
    'artist_id': track.artistId,
    'artist_name': track.artist,
    'artists': [
      for (final credit in track.credits) {'id': credit.artistId, 'name': credit.displayName},
    ],
  });

  return List.unmodifiable([if (artist != null) artist]);
}

/// Capture known genre metadata once at session start, without network work.
/// Statistics use release genres first, then song tags and performer profiles.
/// The server supplies this projection explicitly when its catalog is richer
/// than broad file tags; older clients' downloads can use embedded album data.
List<String> _snapshotGenres(
  Track track, {
  Iterable<Album> cachedAlbums = const [],
  Iterable<Artist> cachedArtists = const [],
}) {
  List<String> normalize(Iterable<String> genres) {
    final values = <String, String>{};

    for (final genre in genres) {
      final value = genre.trim();

      if (value.isNotEmpty) {
        values.putIfAbsent(value.toLowerCase(), () => value);
      }
    }

    return List.unmodifiable(values.values);
  }

  final projected = normalize(track.listeningGenres);

  if (projected.isNotEmpty) {
    return projected;
  }

  final albums = <Album>[
    if (track.offlineAlbum != null && (track.albumId == null || track.offlineAlbum!.id == track.albumId))
      track.offlineAlbum!,
    for (final album in cachedAlbums)
      if (track.albumId?.isNotEmpty == true && album.id == track.albumId) album,
  ];

  for (final album in albums) {
    final genres = normalize(album.genres);

    if (genres.isNotEmpty) {
      return genres;
    }
  }

  final tagged = normalize(track.genres);

  if (tagged.isNotEmpty) {
    return tagged;
  }

  var performerIds = <String>{
    for (final credit in track.credits)
      if (credit.isPerformingArtist && credit.artistId.isNotEmpty) credit.artistId,
  };

  if (performerIds.isEmpty) {
    performerIds = {
      for (final album in albums)
        for (final credit in album.credits)
          if (credit.isAlbumArtist && credit.artistId.isNotEmpty) credit.artistId,
    };
  }

  final profiles = [...track.offlineArtists, if (track.offlineArtist != null) track.offlineArtist!, ...cachedArtists];

  return normalize([
    for (final id in performerIds)
      for (final artist in profiles)
        if (artist.id == id) ...artist.genres,
  ]);
}
