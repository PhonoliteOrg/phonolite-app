import 'package:phonolite_app/data/models/downloads/offline_track_download.dart';
import 'package:phonolite_app/data/models/library/source_track_ref.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/library/track_match.dart';
import 'package:phonolite_app/data/models/library/track_source_match.dart';
import 'package:phonolite_app/data/rules/library/track_matching.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';

typedef ReadTrackSourceMatches = Future<List<TrackSourceMatch>> Function(String serverBaseUrl, String localTrackId);
typedef SaveTrackSourceMatch = Future<void> Function(TrackSourceMatch match);
typedef RemoveTrackSourceMatch = Future<void> Function(SourceTrackRef source);

/// Resolves recording associations without changing files or playlist ownership.
class TrackSourceResolver {
  final ServerConnection connection;
  final ReadTrackSourceMatches readMatches;
  final SaveTrackSourceMatch saveMatch;
  final RemoveTrackSourceMatch removeMatch;

  const TrackSourceResolver({
    required this.connection,
    required this.readMatches,
    required this.saveMatch,
    required this.removeMatch,
  });

  Future<Track?> resolveServerTrack(Track track, {Iterable<OfflineTrackDownload> downloads = const []}) async {
    final origin = connection.baseUrl;
    final revision = connection.sessionRevision;
    bool isCurrent() => connection.baseUrl == origin && connection.sessionRevision == revision;

    if (connection.token?.isNotEmpty != true) {
      return null;
    }

    final direct = knownServerTrack(track, serverBaseUrl: origin, downloads: downloads);

    if (direct != null) {
      return direct;
    }

    final localId = track.localId ?? (track.serverBaseUrl == null ? track.id : null);

    if (localId == null || localId.isEmpty) {
      return null;
    }

    try {
      final signature = TrackMatching.metadataSignature(track);
      final cached = await readMatches(origin, localId);

      if (!isCurrent()) {
        return null;
      }

      final validCached = cached.where(
        (match) =>
            match.source.serverBaseUrl == origin &&
            match.localTrackId == localId &&
            match.metadataSignature == signature,
      );
      final cachedIds = validCached.map((match) => match.source.serverTrackId).toSet();

      if (cachedIds.length == 1) {
        final cachedSource = SourceTrackRef(serverBaseUrl: origin, serverTrackId: cachedIds.single);

        try {
          final resolved = await connection.fetchTrackById(cachedSource.serverTrackId);

          if (!isCurrent()) {
            return null;
          }

          final savedLocalExact = validCached.any((match) => match.matchKind == 'metadata_local_exact');
          final compatible = savedLocalExact
              ? TrackMatching.uniqueLocalCandidate(track, [resolved]) != null
              : TrackMatching.acceptsServerCandidate(track, resolved);

          if (compatible) {
            return _withSource(resolved, origin, localId);
          }

          await removeMatch(cachedSource);
        } on ApiException catch (error) {
          if (!isCurrent()) {
            return null;
          }

          if (error.statusCode != 404 && error.statusCode != 410) {
            return null;
          }

          await removeMatch(cachedSource);
        }
      }

      if (!isCurrent()) {
        return null;
      }

      // A foreign source ID is not an exact-ID hint for the current server.
      final matches = await connection.matchTracks([
        TrackMatchDescriptor(
          localTrackId: localId,
          title: track.title,
          artist: track.artist,
          album: track.album,
          durationMs: track.durationMs,
          trackNo: track.trackNo,
          discNo: track.discNo,
        ),
      ]);

      if (!isCurrent()) {
        return null;
      }

      final candidates = matches
          .where((match) => match.localTrackId == localId && match.confidence >= 0.94 && match.serverTrackId.isNotEmpty)
          .toList(growable: false);

      if (candidates.length != 1) {
        return null;
      }

      final matched = candidates.single;
      final resolved = await connection.fetchTrackById(matched.serverTrackId);

      if (!isCurrent() || !TrackMatching.acceptsServerCandidate(track, resolved)) {
        return null;
      }

      await saveMatch(
        TrackSourceMatch(
          localTrackId: localId,
          source: SourceTrackRef(serverBaseUrl: origin, serverTrackId: matched.serverTrackId),
          matchKind: matched.matchKind,
          score: matched.confidence,
          metadataSignature: signature,
          verifiedAt: DateTime.now(),
        ),
      );

      return isCurrent() ? _withSource(resolved, origin, localId) : null;
    } catch (_) {
      // Transport or cache unavailability must not erase an accepted association.
      return null;
    }
  }

  /// Exact provenance is useful synchronously and never crosses source origins.
  static Track? knownServerTrack(
    Track track, {
    required String serverBaseUrl,
    Iterable<OfflineTrackDownload> downloads = const [],
  }) {
    final sourceId = track.serverTrackId;

    if (track.serverBaseUrl == serverBaseUrl && sourceId?.isNotEmpty == true) {
      return track.copyWith(id: sourceId);
    }

    if (track.localId == null && track.serverBaseUrl == null) {
      return track;
    }

    final localId = track.localId ?? track.id;
    final sources = <String, Track>{};

    for (final download in downloads) {
      if (download.serverBaseUrl != serverBaseUrl) {
        continue;
      }

      final downloadedLocalId = download.localTrackId ?? download.track.localId;

      if (downloadedLocalId == null || downloadedLocalId != localId) {
        continue;
      }

      final id = download.track.serverTrackId ?? download.track.id;
      sources[id] = download.track.copyWith(id: id, localId: localId, serverBaseUrl: serverBaseUrl, serverTrackId: id);
    }

    return sources.length == 1 ? sources.values.single : null;
  }

  static Track _withSource(Track track, String origin, String localId) =>
      track.copyWith(localId: localId, serverBaseUrl: origin, serverTrackId: track.id);
}
