import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:phonolite_app/entities/models.dart';
import 'package:phonolite_app/entities/server_connection.dart';

import '../support/source_test_helpers.dart';

void main() {
  group('server connection behavior', () {
    test('constructor sanitizes trailing separators from baseUrl', () {
      final connection = ServerConnection(
        baseUrl: 'http://example.test/api/v1///?#',
      );

      expect(connection.baseUrl, 'http://example.test/api/v1');
    });

    test('resolveBaseUrl accepts api health when root health fails', () async {
      final requested = <String>[];
      final connection = ServerConnection(
        baseUrl: 'http://placeholder.test/api/v1',
        client: MockClient((request) async {
          requested.add(request.url.toString());
          if (request.url.toString().contains('/api/v1/health')) {
            return http.Response('ok', 200);
          }
          return http.Response('missing', 404);
        }),
      );

      final resolved = await connection.resolveBaseUrl('example.test');

      expect(resolved, 'http://example.test/api/v1');
      expect(requested.any((url) => url.endsWith('/health')), isTrue);
      expect(
        requested.any((url) => url.contains('/api/v1/health')),
        isTrue,
        reason: 'Expected an API health probe. Requests: $requested',
      );
    });

    test('cover url builders encode identifiers and optional query params', () {
      final connection = ServerConnection(
        baseUrl: 'http://example.test/api/v1',
      );

      final albumUrl = connection.buildAlbumCoverUrl('album/id with spaces');
      final artistUrl = connection.buildArtistCoverUrl(
        'artist/id with spaces',
        kind: 'banner art',
      );
      final playlistUrl = connection.buildPlaylistCoverUrl(
        'playlist/id with spaces',
        imageRef: 'rev 1',
      );

      expect(
        albumUrl,
        'http://example.test/api/v1/library/albums/album%2Fid%20with%20spaces/cover',
      );
      expect(
        artistUrl,
        'http://example.test/api/v1/library/artists/artist%2Fid%20with%20spaces/cover?kind=banner%20art',
      );
      expect(
        playlistUrl,
        'http://example.test/api/v1/library/playlists/playlist%2Fid%20with%20spaces/cover?v=rev%201',
      );
    });

    test('uploads and deletes protected playlist artwork bytes', () async {
      final requested = <String>[];
      final methods = <String>[];
      final contentTypes = <String?>[];
      final bodies = <List<int>>[];
      final authHeaders = <String?>[];
      final connection = ServerConnection(
        baseUrl: 'http://example.test/api/v1',
        client: MockClient((request) async {
          requested.add(request.url.toString());
          methods.add(request.method);
          contentTypes.add(
            request.headers['content-type'] ?? request.headers['Content-Type'],
          );
          bodies.add(request.bodyBytes);
          authHeaders.add(request.headers['authorization']);
          return http.Response(
            '{"id":"playlist/id","name":"Mix","track_ids":[],"image_ref":"rev-1"}',
            200,
          );
        }),
      );
      connection.setToken('token-1');

      final uploaded = await connection.uploadPlaylistCover(
        'playlist/id',
        <int>[1, 2, 3],
        'image/png',
      );
      final deleted = await connection.deletePlaylistCover('playlist/id');

      expect(requested, <String>[
        'http://example.test/api/v1/library/playlists/playlist%2Fid/cover',
        'http://example.test/api/v1/library/playlists/playlist%2Fid/cover',
      ]);
      expect(methods, <String>['PUT', 'DELETE']);
      expect(contentTypes.first, 'image/png');
      expect(bodies.first, <int>[1, 2, 3]);
      expect(authHeaders, <String?>['Bearer token-1', 'Bearer token-1']);
      expect(uploaded.imageRef, 'rev-1');
      expect(deleted.id, 'playlist/id');
    });

    test('fetches protected album and artist artwork bytes', () async {
      final requested = <Uri>[];
      final authHeaders = <String?>[];
      final connection = ServerConnection(
        baseUrl: 'http://example.test/api/v1',
        client: MockClient((request) async {
          requested.add(request.url);
          authHeaders.add(request.headers['authorization']);
          return http.Response.bytes(
            request.url.path.contains('/albums/')
                ? <int>[1, 2, 3]
                : <int>[4, 5, 6],
            200,
            headers: {'content-type': 'image/png'},
          );
        }),
      );
      connection.setToken('token-1');

      final album = await connection.fetchAlbumCoverBytes('album/id');
      final artist = await connection.fetchArtistCoverBytes(
        'artist/id',
        kind: 'banner',
      );

      expect(requested.map((uri) => uri.toString()), <String>[
        'http://example.test/api/v1/library/albums/album%2Fid/cover',
        'http://example.test/api/v1/library/artists/artist%2Fid/cover?kind=banner',
      ]);
      expect(authHeaders, <String?>['Bearer token-1', 'Bearer token-1']);
      expect(album?.bytes, <int>[1, 2, 3]);
      expect(album?.contentType, 'image/png');
      expect(artist?.bytes, <int>[4, 5, 6]);
    });

    test(
      'streams metadata update events from authenticated SSE endpoint',
      () async {
        late Uri requested;
        String? authHeader;
        final first = jsonEncode({
          'revision': 1,
          'kind': 'artist',
          'id': 'artist/id',
          'artist_id': 'artist/id',
          'updated_at': 123,
        });
        final second = jsonEncode({
          'revision': 2,
          'kind': 'album',
          'id': 'album/id',
          'album_id': 'album/id',
          'artist_id': 'artist/id',
          'updated_at': 124,
        });
        final connection = ServerConnection(
          baseUrl: 'http://example.test/api/v1',
          client: MockClient((request) async {
            requested = request.url;
            authHeader = request.headers['authorization'];
            return http.Response(
              'event: metadata\nid: 1\ndata: $first\n\n'
              ': keepalive\n\n'
              'data: not-json\n\n'
              'event: metadata\nid: 2\ndata: $second\n\n',
              200,
              headers: {'content-type': 'text/event-stream'},
            );
          }),
        );
        connection.setToken('token-1');

        final events = await connection.streamMetadataEvents().toList();

        expect(
          requested.toString(),
          'http://example.test/api/v1/library/metadata-events',
        );
        expect(authHeader, 'Bearer token-1');
        expect(events.map((event) => event.kind), <String>['artist', 'album']);
        expect(events.first.artistId, 'artist/id');
        expect(events.last.albumId, 'album/id');
      },
    );

    test('encodes identifiers used as URL path segments', () async {
      final requested = <String>[];
      final playlistBodies = <Map<String, dynamic>>[];
      final connection = ServerConnection(
        baseUrl: 'http://example.test/api/v1',
        client: MockClient((request) async {
          requested.add(request.url.toString());
          final path = request.url.path;
          if (path.contains('/library/playlists/') &&
              request.method == 'POST' &&
              request.body.isNotEmpty) {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            if (body.containsKey('name')) {
              playlistBodies.add(body);
            }
          }
          if (path.endsWith('/albums')) {
            return http.Response(
              '[{"id":"album/id","title":"Album","artist":"Artist","artist_id":"artist/id","track_count":1}]',
              200,
            );
          }
          if (path.endsWith('/tracks')) {
            return http.Response(
              '[{"id":"track/id","title":"Track","artist":"Artist","artist_id":"artist/id","album":"Album","album_id":"album/id","duration_ms":1}]',
              200,
            );
          }
          if (path.contains('/library/albums/')) {
            return http.Response(
              '{"id":"album/id","title":"Album","artist":"Artist","artist_id":"artist/id","track_count":1}',
              200,
            );
          }
          if (path.contains('/browse/artists/')) {
            return http.Response(
              '{"id":"artist/id","name":"Artist","album_count":1}',
              200,
            );
          }
          if (path.contains('/browse/tracks/')) {
            return http.Response(
              '{"id":"track/id","title":"Track","artist":"Artist","artist_id":"artist/id","album":"Album","album_id":"album/id","duration_ms":1}',
              200,
            );
          }
          if (path.contains('/library/playlists/')) {
            return http.Response(
              '{"id":"playlist/id","name":"Playlist","track_ids":[]}',
              200,
            );
          }
          return http.Response('', 200);
        }),
      );

      await connection.fetchAlbums('artist/id with spaces');
      await connection.fetchTracks('album/id with spaces');
      await connection.fetchAlbumById('album/id with spaces');
      await connection.fetchArtistById('artist/id with spaces');
      await connection.fetchTrackById('track/id with spaces');
      await connection.fetchPlaylistTracks('playlist/id with spaces');
      await connection.likeTrack('track/id with spaces');
      await connection.unlikeTrack('track/id with spaces');
      await connection.renamePlaylist(
        'playlist/id with spaces',
        'New name',
        description: 'New description',
      );
      await connection.deletePlaylist('playlist/id with spaces');
      await connection.updatePlaylistTracks('playlist/id with spaces', []);

      expect(requested, <String>[
        'http://example.test/api/v1/browse/artists/artist%2Fid%20with%20spaces/albums',
        'http://example.test/api/v1/browse/albums/album%2Fid%20with%20spaces/tracks',
        'http://example.test/api/v1/library/albums/album%2Fid%20with%20spaces',
        'http://example.test/api/v1/browse/artists/artist%2Fid%20with%20spaces',
        'http://example.test/api/v1/browse/tracks/track%2Fid%20with%20spaces',
        'http://example.test/api/v1/browse/playlists/playlist%2Fid%20with%20spaces/tracks',
        'http://example.test/api/v1/library/likes/track%2Fid%20with%20spaces',
        'http://example.test/api/v1/library/likes/track%2Fid%20with%20spaces',
        'http://example.test/api/v1/library/playlists/playlist%2Fid%20with%20spaces',
        'http://example.test/api/v1/library/playlists/playlist%2Fid%20with%20spaces',
        'http://example.test/api/v1/library/playlists/playlist%2Fid%20with%20spaces',
      ]);
      expect(playlistBodies.single, <String, dynamic>{
        'name': 'New name',
        'description': 'New description',
      });
    });

    test('fetchArtists paginates until the last page is short', () async {
      final offsets = <String>[];
      final connection = ServerConnection(
        baseUrl: 'http://example.test/api/v1',
        client: MockClient((request) async {
          offsets.add(request.url.queryParameters['offset'] ?? '');
          final offset = int.parse(
            request.url.queryParameters['offset'] ?? '0',
          );
          if (offset == 0) {
            return http.Response(
              '[{"id":"artist-1","name":"A","album_count":1},'
              '{"id":"artist-2","name":"B","album_count":2}]',
              200,
            );
          }
          return http.Response(
            '[{"id":"artist-3","name":"C","album_count":3}]',
            200,
          );
        }),
      );

      final artists = await connection.fetchArtists(limit: 2);

      expect(offsets, <String>['0', '2']);
      expect(artists.map((artist) => artist.id), <String>[
        'artist-1',
        'artist-2',
        'artist-3',
      ]);
    });

    test('search filters results client side by kind', () async {
      final connection = ServerConnection(
        baseUrl: 'http://example.test/api/v1',
        client: MockClient((_) async {
          return http.Response(
            '[{"kind":"track","id":"track-1","title":"One"},'
            '{"kind":"album","id":"album-1","title":"Album One"},'
            '{"kind":"track","id":"track-2","title":"Two"}]',
            200,
          );
        }),
      );

      final results = await connection.search('one', filter: 'track');

      expect(results.map((item) => item.id), <String>['track-1', 'track-2']);
    });

    test('fetchShuffleTracks encodes scope parameters', () async {
      late Uri capturedUri;
      final connection = ServerConnection(
        baseUrl: 'http://example.test/api/v1',
        client: MockClient((request) async {
          capturedUri = request.url;
          return http.Response('[]', 200);
        }),
      );

      await connection.fetchShuffleTracks(
        mode: 'custom',
        artistId: 'artist/id',
        albumId: 'album id',
        artistIds: <String>['artist-1', 'artist-2'],
        genres: <String>['ambient', 'drum and bass'],
      );

      expect(capturedUri.path, '/api/v1/library/shuffle');
      expect(capturedUri.queryParameters['mode'], 'custom');
      expect(capturedUri.queryParameters['artist_id'], 'artist/id');
      expect(capturedUri.queryParameters['album_id'], 'album id');
      expect(capturedUri.queryParameters['artist_ids'], 'artist-1,artist-2');
      expect(capturedUri.queryParameters['genres'], 'ambient,drum and bass');
    });

    test(
      'openTrackDownload requests the protected download endpoint',
      () async {
        late Uri capturedUri;
        String? capturedRange;
        String? capturedIfRange;
        String? capturedAuth;
        final connection = ServerConnection(
          baseUrl: 'http://example.test/api/v1',
          client: MockClient((request) async {
            capturedUri = request.url;
            capturedRange = request.headers['range'];
            capturedIfRange = request.headers['if-range'];
            capturedAuth = request.headers['authorization'];
            return http.Response(
              'abc',
              206,
              headers: {
                'content-length': '3',
                'content-range': 'bytes 5-7/8',
                'content-type': 'audio/mpeg',
                'etag': '"track-1-8"',
              },
            );
          }),
        );
        connection.setToken('token-1');

        final download = await connection.openTrackDownload(
          'track/id',
          startByte: 5,
          ifRange: '"track-1-8"',
        );
        final body = utf8.decode(
          await download.stream.expand((chunk) => chunk).toList(),
        );

        expect(
          capturedUri.toString(),
          'http://example.test/api/v1/download/tracks/track%2Fid',
        );
        expect(capturedRange, 'bytes=5-');
        expect(capturedIfRange, '"track-1-8"');
        expect(capturedAuth, 'Bearer token-1');
        expect(download.statusCode, 206);
        expect(download.contentLength, 3);
        expect(download.contentRange, 'bytes 5-7/8');
        expect(download.contentType, 'audio/mpeg');
        expect(download.etag, '"track-1-8"');
        expect(body, 'abc');
      },
    );

    test(
      'createDownloadBatch posts track ids and parses unavailable items',
      () async {
        late Uri capturedUri;
        String? capturedAuth;
        Map<String, dynamic>? payload;
        final connection = ServerConnection(
          baseUrl: 'http://example.test/api/v1',
          client: MockClient((request) async {
            capturedUri = request.url;
            capturedAuth = request.headers['authorization'];
            payload = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode({
                'schema_version': 1,
                'batch_id': 'batch-1',
                'created_at': 123,
                'items': [
                  {
                    'track_id': 'track/id',
                    'download_url': '/api/v1/download/tracks/track%2Fid',
                    'byte_length': 3,
                    'content_type': 'audio/mpeg',
                    'etag': '"track-1-3"',
                    'sha256':
                        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
                    'offline_metadata': {
                      'schema_version': 1,
                      'track': {
                        'id': 'track/id',
                        'title': 'Track',
                        'artist': 'Artist',
                        'artist_id': 'artist/id',
                        'album': 'Album',
                        'album_id': 'album/id',
                        'duration_ms': 120000,
                        'liked': false,
                        'in_playlists': false,
                      },
                      'album': {
                        'id': 'album/id',
                        'title': 'Album',
                        'artist': 'Artist',
                        'artist_id': 'artist/id',
                        'track_count': 1,
                      },
                      'artist': {
                        'id': 'artist/id',
                        'name': 'Artist',
                        'album_count': 1,
                      },
                    },
                  },
                ],
                'unavailable': [
                  {'track_id': 'missing', 'reason': 'track not found'},
                ],
              }),
              200,
            );
          }),
        );
        connection.setToken('token-1');

        final manifest = await connection.createDownloadBatch(<String>[
          'track/id',
          'missing',
        ], clientBatchId: 'client-batch');

        expect(
          capturedUri.toString(),
          'http://example.test/api/v1/download/batches',
        );
        expect(capturedAuth, 'Bearer token-1');
        expect(payload?['client_batch_id'], 'client-batch');
        expect(payload?['track_ids'], <String>['track/id', 'missing']);
        expect(manifest.batchId, 'batch-1');
        expect(manifest.items.single.trackId, 'track/id');
        expect(manifest.items.single.byteLength, 3);
        expect(manifest.items.single.offlineMetadata.track.albumId, 'album/id');
        expect(manifest.unavailable.single.reason, 'track not found');
      },
    );

    test('matchTracks posts descriptors and parses strict matches', () async {
      late Uri capturedUri;
      Map<String, dynamic>? payload;
      final connection = ServerConnection(
        baseUrl: 'http://example.test/api/v1',
        client: MockClient((request) async {
          capturedUri = request.url;
          payload = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'matches': [
                {
                  'local_track_id': 'local-1',
                  'server_track_id': 'server-1',
                  'confidence': 1.0,
                  'match_kind': 'exact_server_track_id',
                  'server_liked': true,
                  'server_updated_at': 123,
                },
              ],
            }),
            200,
          );
        }),
      );

      final matches = await connection.matchTracks([
        TrackMatchDescriptor(
          localTrackId: 'local-1',
          title: 'Song',
          artist: 'Artist',
          album: 'Album',
          durationMs: 120000,
          serverTrackId: 'server-1',
        ),
      ]);

      expect(
        capturedUri.toString(),
        'http://example.test/api/v1/library/match-tracks',
      );
      expect((payload?['tracks'] as List).single['local_track_id'], 'local-1');
      expect(matches.single.serverTrackId, 'server-1');
      expect(matches.single.serverLiked, isTrue);
      expect(matches.single.serverUpdatedAt, 123);
    });

    test(
      'updateLikeStates posts batch likes and parses state timestamps',
      () async {
        late Uri capturedUri;
        Map<String, dynamic>? payload;
        final connection = ServerConnection(
          baseUrl: 'http://example.test/api/v1',
          client: MockClient((request) async {
            capturedUri = request.url;
            payload = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode([
                {'track_id': 'server-1', 'liked': false, 'updated_at': 456},
              ]),
              200,
            );
          }),
        );

        final states = await connection.updateLikeStates(
          {'server-1': false},
          updatedAtByTrack: {'server-1': 123},
        );

        expect(
          capturedUri.toString(),
          'http://example.test/api/v1/library/likes/batch',
        );
        expect((payload?['items'] as List).single['liked'], isFalse);
        expect((payload?['items'] as List).single['updated_at'], 123);
        expect(states.single.trackId, 'server-1');
        expect(states.single.liked, isFalse);
        expect(states.single.updatedAt, 456);
      },
    );

    test('fetchOfflineMetadata hydrates the local download fragment', () async {
      late Uri capturedUri;
      final connection = ServerConnection(
        baseUrl: 'http://example.test/api/v1',
        client: MockClient((request) async {
          capturedUri = request.url;
          return http.Response(
            jsonEncode({
              'schema_version': 1,
              'track': {
                'id': 'track/id',
                'title': 'Track',
                'artist': 'Artist',
                'artist_id': 'artist/id',
                'album': 'Album',
                'album_id': 'album/id',
                'duration_ms': 120000,
                'liked': true,
                'in_playlists': false,
              },
              'album': {
                'id': 'album/id',
                'title': 'Album',
                'artist': 'Artist',
                'artist_id': 'artist/id',
                'track_count': 1,
              },
              'artist': {'id': 'artist/id', 'name': 'Artist', 'album_count': 1},
            }),
            200,
          );
        }),
      );

      final metadata = await connection.fetchOfflineMetadata('track/id');

      expect(
        capturedUri.toString(),
        'http://example.test/api/v1/library/tracks/track%2Fid/offline-metadata',
      );
      expect(metadata.schemaVersion, 1);
      expect(metadata.track.albumId, 'album/id');
      expect(metadata.album.artistId, 'artist/id');
      expect(metadata.artist.name, 'Artist');
    });

    test(
      'fetchServerPorts retries retryable failures before succeeding',
      () async {
        var attempts = 0;
        final connection = ServerConnection(
          baseUrl: 'http://example.test/api/v1',
          client: MockClient((_) async {
            attempts += 1;
            if (attempts < 3) {
              return http.Response('server error', 503);
            }
            return http.Response(
              '{"http_port":3000,"quic_port":3001,"quic_enabled":true}',
              200,
            );
          }),
        );

        final ports = await connection.fetchServerPorts();

        expect(attempts, 3);
        expect(ports.httpPort, 3000);
        expect(ports.quicPort, 3001);
        expect(ports.quicEnabled, isTrue);
      },
    );
  });

  group('server connection source contracts', () {
    final source = readProjectFile('lib/entities/server_connection.dart');

    test('defines expected endpoints, timeouts, and retry behavior', () {
      expectContainsAll(source, const [
        'static const Duration _defaultRequestTimeout = Duration(seconds: 8);',
        'static const Duration _healthRequestTimeout = Duration(seconds: 2);',
        'static const int _maxGetAttempts = 3;',
        "'/auth/login'",
        "'/auth/logout'",
        "'/browse/artists?limit=\$limit&offset=\$offset'",
        "'/library/playlists'",
        "'/browse/likes'",
        "'/library/shuffle?mode=\$mode'",
        "'/library/search?query=\$encoded&limit=50'",
        "'/library/tracks/\$encoded/offline-metadata'",
        "'/download/batches'",
        "return '\$_baseUrl/download/tracks/\$encoded';",
        'Future<ServerArtwork?> fetchAlbumCoverBytes',
        'Future<ServerArtwork?> fetchArtistCoverBytes',
        'Future<ServerArtwork?> _fetchArtworkUrl',
        "'/player/settings'",
        "'/server/ports'",
        "headers['Authorization'] = 'Bearer \$_token';",
        "request.headers[HttpHeaders.rangeHeader] = 'bytes=\$startByte-';",
        "request.headers[HttpHeaders.ifRangeHeader] = ifRange.trim();",
        'final maxAttempts = retryable ? _maxGetAttempts : 1;',
      ]);
    });
  });
}
