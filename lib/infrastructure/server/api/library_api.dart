import 'dart:async';

import 'package:phonolite_app/data/models/downloads/offline_track_metadata.dart';
import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/library/artist_releases.dart';
import 'package:phonolite_app/data/models/library/search_result.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/library/track_match.dart';
import 'package:phonolite_app/infrastructure/server/api/json_api_endpoint.dart';
import 'package:phonolite_app/infrastructure/server/transport/api_transport.dart';

typedef ArtistPageFetcher =
    Future<List<Artist>> Function({required int limit, required int offset, required bool includeContributors});

class LibraryApi extends JsonApiEndpoint {
  final ArtistPageFetcher _fetchArtistsPage;

  LibraryApi(super.transport, {required ArtistPageFetcher fetchArtistsPage}) : _fetchArtistsPage = fetchArtistsPage;

  Future<List<Artist>> fetchArtistsPage({
    int limit = ApiTransport.artistsPageSize,
    int offset = 0,
    bool includeContributors = false,
  }) async {
    return getValues(
      '/browse/artists?limit=$limit&offset=$offset&include_contributors=$includeContributors',
      Artist.fromJson,
    );
  }

  Future<List<Artist>> fetchArtists({
    int limit = ApiTransport.artistsPageSize,
    bool includeContributors = false,
  }) async {
    var offset = 0;
    final artists = <Artist>[];

    while (true) {
      final page = await _fetchArtistsPage(limit: limit, offset: offset, includeContributors: includeContributors);

      artists.addAll(page);

      if (page.length < limit) {
        break;
      }

      offset += page.length;
    }

    return artists;
  }

  Future<List<Album>> fetchAlbums(String artistId) async {
    final encoded = ApiTransport.encodePathSegment(artistId);

    return getValues('/browse/artists/$encoded/albums', Album.fromJson);
  }

  Future<ArtistReleases> fetchArtistReleases(String artistId) async {
    final encoded = ApiTransport.encodePathSegment(artistId);

    return getValue('/browse/artists/$encoded/releases', ArtistReleases.fromJson);
  }

  Future<List<Track>> fetchTracks(String albumId) async {
    final encoded = ApiTransport.encodePathSegment(albumId);

    return getValues('/browse/albums/$encoded/tracks', Track.fromJson);
  }

  Future<List<SearchResult>> search(String query, {String filter = 'all'}) async {
    if (query.trim().isEmpty) {
      return <SearchResult>[];
    }

    final encoded = Uri.encodeComponent(query);
    final path = '/library/search?query=$encoded&limit=50';

    final response = await getValues(path, SearchResult.fromJson);

    return response.where((item) => filter == 'all' ? true : item.kind == filter).toList();
  }

  Future<Album> fetchAlbumById(String albumId) async {
    final encoded = ApiTransport.encodePathSegment(albumId);

    return getMetadataValue('/library/albums/$encoded', Album.fromJson);
  }

  Future<Artist> fetchArtistById(String artistId) async {
    final encoded = ApiTransport.encodePathSegment(artistId);

    return getMetadataValue('/browse/artists/$encoded', Artist.fromJson);
  }

  Future<Track> fetchTrackById(String trackId) async {
    final encoded = ApiTransport.encodePathSegment(trackId);

    return getMetadataValue('/browse/tracks/$encoded', Track.fromJson);
  }

  Future<OfflineTrackMetadata> fetchOfflineMetadata(String trackId) async {
    final encoded = ApiTransport.encodePathSegment(trackId);

    return getMetadataValue('/library/tracks/$encoded/offline-metadata', OfflineTrackMetadata.fromJson);
  }

  Future<List<TrackMatchResult>> matchTracks(List<TrackMatchDescriptor> tracks) async {
    if (tracks.isEmpty) {
      return const <TrackMatchResult>[];
    }

    final response = await transport.post('/library/match-tracks', {
      'tracks': tracks.map((track) => track.toJson()).toList(growable: false),
    });

    final rawMatches = response['matches'];

    if (rawMatches is! List) {
      return const <TrackMatchResult>[];
    }

    return rawMatches
        .whereType<Map>()
        .map((item) => TrackMatchResult.fromJson(Map<String, dynamic>.from(item)))
        .where((item) => item.localTrackId.trim().isNotEmpty && item.serverTrackId.trim().isNotEmpty)
        .toList(growable: false);
  }
}
