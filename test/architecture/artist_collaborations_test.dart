import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phonolite_app/data/models/library/artist_credit.dart';
import 'package:phonolite_app/data/models/library/artist_releases.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/downloads/offline_track_metadata.dart';
import 'package:phonolite_app/data/models/library/local_library_selection.dart';
import 'package:phonolite_app/data/projections/library/offline_library_views.dart';
import 'package:phonolite_app/data/storage/offline/library/offline_library.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';
import 'package:phonolite_app/ui/features/library/widgets/artist_release_sections.dart';

import '../support/offline_library_test_helpers.dart';

void main() {
  final album = Album(
    id: 'shared-album',
    title: 'Joint release',
    artist: 'A & B',
    artistId: 'a',
    trackCount: 2,
    artistIds: ['a', 'b'],
    artistNames: ['A', 'B'],
    artistCredits: const [
      ArtistCredit(
        artistId: 'a',
        name: 'A',
        role: 'album_artist',
        joinPhrase: ' & ',
      ),
      ArtistCredit(artistId: 'b', name: 'B', role: 'album_artist'),
      ArtistCredit(artistId: 'composer', name: 'Composer', role: 'composer'),
    ],
  );
  Track song(String id, {bool featured = false}) => Track(
    id: id,
    title: id,
    artist: featured ? 'A feat. Guest' : 'A',
    artistId: 'a',
    album: album.title,
    albumId: album.id,
    offlineAlbum: album,
    durationMs: 120000,
    liked: false,
    inPlaylists: false,
    artistIds: ['a', if (featured) 'guest'],
    artistNames: ['A', if (featured) 'Guest'],
    artistCredits: [
      ArtistCredit(
        artistId: 'a',
        name: 'A',
        role: 'track_artist',
        joinPhrase: featured ? ' feat. ' : '',
      ),
      if (featured)
        const ArtistCredit(
          artistId: 'guest',
          name: 'Guest',
          creditedName: 'Guest alias',
          role: 'featured_artist',
        ),
    ],
  );

  test(
    'browse counts work immediately with current and legacy responses',
    () async {
      final requests = <String>[];
      final connection = ServerConnection(
        baseUrl: 'http://unused.test/api/v1',
        client: MockClient((request) async {
          requests.add(request.url.path);
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'id': 'guest',
                  'name': 'Guest',
                  'album_count': 0,
                  'collab_album_count': 2,
                  'appearance_count': 1,
                  'other_credit_count': 2,
                  'release_count': 2,
                },
                {
                  'id': 'legacy',
                  'name': 'Legacy',
                  'album_count': '3',
                  'collab_album_count': '2',
                  'appearance_count': 2,
                  'other_credit_count': 1,
                },
                {
                  'id': 'composer',
                  'name': 'Composer',
                  'album_count': 0,
                  'other_credit_count': 1,
                },
              ],
            }),
            200,
          );
        }),
      );
      final artists = await connection.fetchArtistsPage(
        includeContributors: true,
      );
      expect(artists.map((artist) => artist.releaseCount), [2, 5, 0]);
      expect(artists.first.albumCount, 0);
      expect(requests, ['/api/v1/browse/artists']);
      final renamed = artists.first.copyWith(name: 'New name');
      expect(Artist.fromJson(renamed.toJson()).releaseCount, 2);
      expect(artists[1].toJson().containsKey('release_count'), isFalse);
      expect(artists.first.copyWith(releaseCount: 0).releaseCount, 0);
      expect(artists.first.copyWith(releaseCount: null).releaseCount, 2);
    },
  );

  test(
    'release totals deduplicate overlapping collaboration and credit lists',
    () {
      final contribution = ArtistReleaseContribution(
        album: album,
        roles: const ['album_artist'],
      );
      final releases = ArtistReleases(
        albums: [album],
        collabAlbums: [contribution, contribution],
        appearsOn: [contribution],
        otherCredits: [contribution],
      );
      expect(releases.releaseCount, 1);
      expect(releases.albums, isEmpty);
      expect(releases.collabAlbums, hasLength(1));
      final groups = offlineArtistGroups([
        song('one', featured: true),
        song('two'),
      ]);
      expect(
        groups.every((group) => group.toArtist().releaseCount == 1),
        isTrue,
      );
    },
  );

  test('legacy JSON remains readable and copyWith preserves full credits', () {
    final legacy = Track.fromJson({
      'id': 'legacy',
      'title': 'Legacy song',
      'artist': 'Earth, Wind & Fire',
      'artist_id': 'band',
    });
    expect(legacy.credits, hasLength(1));
    expect(legacy.credits.single.name, 'Earth, Wind & Fire');
    final original = song('one', featured: true);
    final restored = Track.fromJson(original.copyWith(liked: true).toJson());
    expect(restored.artistIds, ['a', 'guest']);
    expect(restored.credits.last.displayName, 'Guest alias');
    expect(restored.credits.first.joinPhrase, ' feat. ');
    expect(restored.credits.last.role, 'featured_artist');
    expect(
      Album.fromJson(album.copyWith(year: 2026).toJson()).credits,
      hasLength(3),
    );
  });

  test('offline fragments retain collaboration identities and roles', () {
    final metadata = OfflineTrackMetadata(
      schemaVersion: 1,
      track: song('one', featured: true),
      album: album,
      artist: Artist(id: 'a', name: 'A', albumCount: 1),
    );
    final restored = OfflineTrackMetadata.fromJson(
      jsonDecode(jsonEncode(metadata.toJson())) as Map<String, dynamic>,
    );
    expect(restored.track.credits.last.artistId, 'guest');
    expect(restored.album.credits.last.role, 'composer');
    expect(restored.album.artistIds, ['a', 'b']);
    expect(
      offlineTrackSearchText(song('one', featured: true)),
      contains('composer'),
    );
    expect(
      offlineTrackSearchText(song('one', featured: true)),
      contains('guest alias'),
    );
  });

  test(
    'solo albums and collab albums remain distinct and merge song roles',
    () {
      final solo = Album(
        id: 'solo',
        title: 'Solo release',
        artist: 'A',
        artistId: 'a',
        trackCount: 3,
      );
      final releases = ArtistReleases.fromJson({
        'albums': [solo.toJson(), album.toJson()],
        'collab_albums': [
          {
            'album': album.toJson(),
            'track_ids': ['one', 'two'],
            'track_titles': ['One', 'Two'],
            'roles': ['album_artist'],
          },
        ],
        'appears_on': [
          {
            'album': album.toJson(),
            'track_ids': ['one'],
            'track_titles': ['One'],
            'roles': ['featured_artist'],
          },
        ],
        'other_credits': [
          {
            'album': album.toJson(),
            'track_ids': ['two'],
            'track_titles': ['Two'],
            'roles': ['composer'],
          },
          {
            'album': solo.toJson(),
            'track_ids': ['solo-one'],
            'roles': ['composer'],
          },
        ],
      });
      expect(releases.albums.map((album) => album.id), ['solo']);
      expect(releases.collabAlbums, hasLength(1));
      final joint = releases.collabAlbums.single;
      expect(joint.trackIds, ['one', 'two']);
      expect(joint.trackTitles, ['One', 'Two']);
      expect(joint.roles, ['album_artist']);
      expect(releases.headlineAlbums.map((album) => album.id), [
        'solo',
        'shared-album',
      ]);
    },
  );

  test(
    'individual contributor metadata survives offline storage reload',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'phonolite_collab_metadata_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: temp);
      final primary = Artist(
        id: 'a',
        name: 'A',
        albumCount: 0,
        collabAlbumCount: 1,
        summary: 'Primary biography',
      );
      final guest = Artist(
        id: 'guest',
        name: 'Guest canonical name',
        albumCount: 0,
        collabAlbumCount: 1,
        genres: ['Jazz'],
        summary: 'Guest biography',
        logoRef: 'guest/logo.png',
      );
      final composer = Artist(
        id: 'composer',
        name: 'Composer',
        albumCount: 0,
        collabAlbumCount: 1,
        summary: 'Composer biography',
      );
      final metadata = OfflineTrackMetadata.fromJson(
        jsonDecode(
              jsonEncode(
                OfflineTrackMetadata(
                  schemaVersion: OfflineTrackMetadata.currentSchemaVersion,
                  track: song('one', featured: true).copyWith(
                    artistArtPath: 'primary/logo.png',
                    artistBannerPath: 'primary/banner.png',
                  ),
                  album: album,
                  artist: primary,
                  artists: [primary, guest, composer],
                ).toJson(),
              ),
            )
            as Map<String, dynamic>,
      );
      final file = await offlineTestMediaFile(temp, 'one.mp3');
      final prepared = await storage.prepareDownload(
        offlineTestDownload(
          serverBaseUrl: 'https://server.test/api/v1',
          track: metadata.track,
          filePath: file.path,
        ).copyWith(offlineMetadata: metadata),
      );
      await storage.upsertDownload(prepared);
      final restored = await storage.readLocalDownloadedTracks();
      expect(restored.single.offlineArtists.map((artist) => artist.id), [
        'a',
        'guest',
        'composer',
      ]);
      expect(
        offlineArtistGroups(restored).map((group) => group.id),
        isNot(contains('composer')),
      );
      final groups = offlineArtistGroups(restored, includeContributors: true);
      final guestGroup = groups.firstWhere((group) => group.id == 'guest');
      expect(guestGroup.name, 'Guest canonical name');
      expect(guestGroup.toArtist().summary, 'Guest biography');
      expect(guestGroup.toArtist().genres, ['Jazz']);
      expect(guestGroup.toArtist().logoRef, 'guest/logo.png');
      expect(guestGroup.coverPath, isNull);
      expect(guestGroup.bannerPath, isNull);
      expect(
        groups.firstWhere((group) => group.id == 'a').coverPath,
        'primary/logo.png',
      );
      expect(guestGroup.toArtist().collabAlbumCount, 0);
      expect(guestGroup.toArtist().appearanceCount, 1);
      expect(
        groups.firstWhere((group) => group.id == 'composer').toArtist().summary,
        'Composer biography',
      );
    },
  );

  test('offline credits without album metadata use individual artists', () {
    final legacyStructured = song('one').copyWith(
      offlineAlbum: null,
      artist: 'A, B',
      artistIds: ['a', 'b'],
      artistNames: ['A', 'B'],
      artistCredits: const [],
    );
    final groups = offlineArtistGroups([legacyStructured]);
    expect(groups.map((group) => group.name), ['A', 'B']);
    expect(groups.every((group) => group.soloAlbums.isEmpty), isTrue);
    expect(groups.every((group) => group.collabAlbums.length == 1), isTrue);
  });

  test(
    'one shared offline album is classified for joint artists, guest and composer',
    () {
      final groups = offlineArtistGroups([
        song('one', featured: true),
        song('two'),
      ], includeContributors: true);
      OfflineArtistGroup group(String id) =>
          groups.firstWhere((group) => group.id == id);
      expect(group('a').headlineAlbums.single.id, 'shared-album');
      expect(group('b').headlineAlbums.single.id, 'shared-album');
      expect(group('a').soloAlbums, isEmpty);
      expect(group('b').releases.albums, isEmpty);
      expect(group('a').collabAlbums.single.id, 'shared-album');
      expect(group('a').releases.collabAlbums.single.trackIds, ['one', 'two']);
      expect(group('a').releases.collabAlbums.single.isAlbumArtist, isTrue);
      expect(group('a').toArtist().albumCount, 0);
      expect(group('a').toArtist().collabAlbumCount, 1);
      expect(group('guest').headlineAlbums, isEmpty);
      expect(group('guest').releases.appearsOn.single.trackIds, ['one']);
      expect(group('guest').releases.appearsOn.single.roles, [
        'featured_artist',
      ]);
      expect(group('guest').albums.single.tracks, hasLength(2));
      expect(group('guest').tracksForArtist.map((track) => track.id), ['one']);
      expect(group('composer').tracksForArtist, isEmpty);
      expect(group('composer').releases.otherCredits.single.roles, [
        'composer',
      ]);
      expect(group('composer').toArtist().albumCount, 0);
      expect(group('composer').toArtist().otherCreditCount, 1);
      expect(
        groups
            .where((group) => group.headlineAlbums.isNotEmpty)
            .map((g) => g.id),
        ['a', 'b'],
      );
    },
  );

  test(
    'artists exclude supporting contributors by default and parse legacy collaborations',
    () async {
      final requests = <Uri>[];
      final connection = ServerConnection(
        baseUrl: 'https://server.test/api/v1',
        client: MockClient((request) async {
          requests.add(request.url);
          if (request.url.path.endsWith('/releases')) {
            return http.Response(
              jsonEncode({
                'albums': [album.toJson()],
                'appears_on': [
                  {
                    'album': album.toJson(),
                    'track_ids': ['one'],
                    'track_titles': ['one'],
                    'roles': ['featured_artist'],
                  },
                ],
                'other_credits': [],
              }),
              200,
            );
          }
          return http.Response('[]', 200);
        }),
      );
      await connection.fetchArtistsPage();
      await connection.fetchArtistsPage(includeContributors: true, offset: 60);
      final releases = await connection.fetchArtistReleases('guest/id');
      expect(requests[0].queryParameters['include_contributors'], 'false');
      expect(requests[1].queryParameters['include_contributors'], 'true');
      expect(requests[1].queryParameters['offset'], '60');
      expect(requests.last.path, contains('guest%2Fid'));
      expect(releases.appearsOn.single.trackIds, ['one']);
      expect(releases.albums, isEmpty);
      expect(releases.collabAlbums.single.album.artistIds, ['a', 'b']);
      expect(releases.headlineAlbums.single.id, 'shared-album');
    },
  );

  for (final isJoint in [false, true]) {
    test(
      'offline ${isJoint ? 'joint' : 'solo'} albums stay out of other credits',
      () {
        final mainAlbum = album.copyWith(
          artistIds: ['a', if (isJoint) 'b'],
          artistCredits: [
            ...album.credits.where(
              (credit) => isJoint || credit.artistId != 'b',
            ),
            const ArtistCredit(artistId: 'a', name: 'A', role: 'producer'),
          ],
        );
        final first = song('first').copyWith(
          offlineAlbum: mainAlbum,
          artistCredits: const [
            ArtistCredit(artistId: 'a', name: 'A', role: 'track_artist'),
            ArtistCredit(artistId: 'a', name: 'A', role: 'composer'),
            ArtistCredit(
              artistId: 'composer',
              name: 'Composer',
              role: 'composer',
            ),
            ArtistCredit(artistId: 'guest', name: 'Guest', role: 'performer'),
          ],
        );
        final second = song(
          'second',
          featured: true,
        ).copyWith(offlineAlbum: mainAlbum);
        final groups = offlineArtistGroups([
          first,
          second,
        ], includeContributors: true);
        final main = groups.firstWhere((group) => group.id == 'a');
        expect(main.releases.albums, hasLength(isJoint ? 0 : 1));
        expect(main.releases.collabAlbums, hasLength(isJoint ? 1 : 0));
        expect(main.releases.headlineAlbums.single.id, album.id);
        expect(main.tracksForArtist.map((track) => track.id), [
          'first',
          'second',
        ]);
        if (isJoint) {
          expect(main.releases.collabAlbums.single.trackIds, [
            'first',
            'second',
          ]);
        }
        expect(main.releases.appearsOn, isEmpty);
        expect(main.releases.otherCredits, isEmpty);
        expect(main.toArtist().otherCreditCount, 0);
        expect(
          main.releases.headlineAlbums.single.credits
              .where((credit) => credit.artistId == 'a')
              .map((credit) => credit.role),
          ['album_artist', 'producer'],
        );
        expect(
          main.tracksForArtist.first.credits
              .where((credit) => credit.artistId == 'a')
              .map((credit) => credit.role),
          ['track_artist', 'composer'],
        );
        final guest = groups.firstWhere((group) => group.id == 'guest');
        expect(guest.releases.appearsOn.single.trackIds, ['second']);
        expect(guest.releases.appearsOn.single.roles, ['featured_artist']);
        expect(guest.releases.otherCredits.single.trackIds, ['first']);
        expect(guest.releases.otherCredits.single.roles, ['performer']);
        expect(guest.tracksForArtist.map((track) => track.id), ['second']);
        expect(guest.releases.collabAlbums, isEmpty);
        final composer = groups.firstWhere((group) => group.id == 'composer');
        expect(composer.releases.otherCredits.single.trackIds, ['first']);
        expect(composer.tracksForArtist, isEmpty);
        expect(composer.releases.collabAlbums, isEmpty);
        final selection = LocalLibrarySelection(
          tracks: [first, second],
          artists: groups,
        );
        expect(
          selection.matchesCustomShuffle(
            first,
            artistIds: {'composer'},
            genres: {},
          ),
          isFalse,
        );
        expect(
          selection.matchesCustomShuffle(
            second,
            artistIds: {'composer'},
            genres: {},
          ),
          isFalse,
        );
      },
    );
  }

  for (final legacy in [false, true]) {
    test(
      '${legacy ? 'legacy' : 'current'} responses exclude headline albums from other credits',
      () {
        final solo = album.copyWith(
          id: 'solo',
          artistIds: ['a'],
          artistCredits: const [
            ArtistCredit(artistId: 'a', name: 'A', role: 'album_artist'),
          ],
        );
        final supporting = album.copyWith(id: 'supporting');
        Map<String, dynamic> contribution(Album release, String role) => {
          'album': release.toJson(),
          'track_ids': ['credited-song'],
          'track_titles': ['Credited song'],
          'roles': [role],
        };
        final releases = ArtistReleases.fromJson({
          'albums': [solo.toJson(), if (legacy) album.toJson()],
          'collab_albums': [
            if (!legacy) contribution(album, 'album_artist'),
            if (legacy) ...[
              contribution(solo, 'producer'),
              contribution(album, 'composer'),
              contribution(supporting, 'performer'),
            ],
          ],
          'other_credits': [
            contribution(solo, 'composer'),
            contribution(album, 'producer'),
            if (!legacy) contribution(supporting, 'performer'),
          ],
        });
        expect(releases.albums.single.id, solo.id);
        expect(releases.collabAlbums.single.album.id, album.id);
        expect(releases.otherCredits.single.album.id, supporting.id);
        expect(releases.otherCredits.single.trackIds, ['credited-song']);
        expect(releases.otherCredits.single.roles, ['performer']);
        expect(releases.releaseCount, 2);
      },
    );
  }

  test(
    'legacy collaboration payloads preserve appearances without merging supporting songs',
    () {
      final solo = album.copyWith(
        artistIds: ['a'],
        artistCredits: const [
          ArtistCredit(artistId: 'a', name: 'A', role: 'album_artist'),
        ],
      );
      final appearance = ArtistReleaseContribution(
        album: solo,
        trackIds: const ['feature'],
        roles: const ['featured_artist'],
      );
      final supporting = ArtistReleaseContribution(
        album: solo,
        trackIds: const ['session'],
        roles: const ['performer'],
      );
      final legacy = ArtistReleases(
        collabAlbums: [
          ArtistReleaseContribution(
            album: solo,
            trackIds: const ['feature', 'session'],
            roles: const ['featured_artist', 'performer'],
          ),
        ],
        appearsOn: [appearance],
        otherCredits: [supporting],
      );
      expect(legacy.collabAlbums, isEmpty);
      expect(legacy.appearsOn.single.trackIds, ['feature']);
      expect(legacy.appearsOn.single.roles, ['featured_artist']);
      expect(legacy.otherCredits.single.trackIds, ['session']);
      expect(legacy.releaseCount, 1);
      final contributorOnly = ArtistReleases(collabAlbums: [supporting]);
      expect(contributorOnly.collabAlbums, isEmpty);
      expect(contributorOnly.appearsOn, isEmpty);
      expect(contributorOnly.otherCredits.single.trackIds, ['session']);
      expect(contributorOnly.releaseCount, 0);
    },
  );

  test(
    'offline browsing requires billing even when one artist has several roles',
    () {
      final track = song('mixed').copyWith(
        artistCredits: const [
          ArtistCredit(artistId: 'a', name: 'A', role: 'track_artist'),
          ArtistCredit(artistId: 'a', name: 'A', role: 'producer'),
          ArtistCredit(
            artistId: 'producer',
            name: 'Producer',
            role: 'producer',
          ),
          ArtistCredit(artistId: 'player', name: 'Player', role: 'performer'),
        ],
      );
      final groups = offlineArtistGroups([track]);
      expect(groups.map((group) => group.id), ['a', 'b']);
      expect(groups.first.releases.otherCredits, isEmpty);
      expect(track.credits.map((credit) => credit.role), [
        'track_artist',
        'producer',
        'producer',
        'performer',
      ]);
    },
  );

  testWidgets('appearance row opens the shared album without credit details', (
    tester,
  ) async {
    Album? opened;
    final contribution = ArtistReleaseContribution(
      album: album,
      trackIds: const ['one'],
      trackTitles: const ['One song'],
      roles: const ['featured_artist'],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              ArtistContributionSliver(
                title: 'Appears on',
                entries: [contribution],
                isListView: true,
                coverFor: (_) => '',
                onOpen: (album) => opened = album,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Appears on (1)'), findsOneWidget);
    expect(
      find.text('Featured · 1 song: One song · Open full album'),
      findsNothing,
    );
    await tester.tap(find.text('Joint release'));
    expect(opened?.id, 'shared-album');
    expect(tester.takeException(), isNull);
  });
}
