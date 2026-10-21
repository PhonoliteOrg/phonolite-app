import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/data/models/library/local_library_selection.dart';
import 'package:phonolite_app/data/models/library/artist_credit.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/projections/library/offline_library_views.dart';

void main() {
  final local =
      Track.fromJson({
        'id': 'download',
        'title': 'Song',
        'artist': 'Artist',
        'album': 'Album',
      }).copyWith(
        localId: ' local ',
        serverTrackId: ' server ',
        artistId: 'track-artist',
      );
  final album = OfflineAlbumGroup(
    id: 'album',
    title: 'Album',
    artist: 'Artist',
    artistId: 'group-artist',
    tracks: [local],
  );
  final artist = OfflineArtistGroup(
    id: 'group-artist',
    name: 'Artist',
    albums: [album],
  );
  final selection = LocalLibrarySelection(tracks: [local], artists: [artist]);

  test('local lookups accept trimmed local and server aliases', () {
    for (final alias in ['download', ' local ', 'server']) {
      expect(selection.track(alias), same(local));
      expect(selection.artistForTrackId(alias), same(artist));
      expect(selection.albumForTrackId(alias), same(album));
    }
    expect(selection.artist(' group-artist '), same(artist));
    expect(selection.album(' album '), same(album));
    expect(selection.track(null), isNull);
    expect(selection.track(' '), isNull);
    expect(selection.artistForTrackId('unknown'), isNull);
    expect(selection.albumForTrackId('unknown'), isNull);
  });

  test(
    'group lookup recognizes track aliases without matching empty identities',
    () {
      expect(
        selection.artistForTrack(
          local.copyWith(id: 'server', localId: null, serverTrackId: null),
        ),
        same(artist),
      );
      expect(
        selection.albumForTrack(
          local.copyWith(id: 'local', localId: null, serverTrackId: null),
        ),
        same(album),
      );
      expect(
        selection.artistForTrack(
          local.copyWith(id: '', localId: null, serverTrackId: null),
        ),
        isNull,
      );
    },
  );

  test('custom shuffle matches artist OR genre across stored metadata', () {
    final track = local.copyWith(
      genres: [' ROCK '],
      offlineAlbum: Album(
        id: 'album',
        title: 'Album',
        artist: 'Artist',
        artistId: 'a',
        trackCount: 1,
        genres: [' Jazz '],
      ),
      offlineArtist: Artist(
        id: 'stored-artist',
        name: 'Artist',
        albumCount: 1,
        genres: [' Ambient '],
      ),
    );
    for (final id in ['group-artist', 'track-artist', 'stored-artist']) {
      expect(
        selection.matchesCustomShuffle(track, artistIds: {id}, genres: {}),
        isTrue,
      );
    }
    for (final genre in ['rock', 'jazz', 'ambient']) {
      expect(
        selection.matchesCustomShuffle(
          track,
          artistIds: {'unrelated'},
          genres: {genre},
        ),
        isTrue,
      );
    }
    expect(
      selection.matchesCustomShuffle(track, artistIds: {}, genres: {}),
      isFalse,
    );
    expect(
      selection.matchesCustomShuffle(
        track,
        artistIds: {'unknown'},
        genres: {'metal'},
      ),
      isFalse,
    );
  });

  test('ambiguous aliases preserve first-match behavior within a snapshot', () {
    final other = local.copyWith(id: 'second');
    final lookup = LocalLibrarySelection(tracks: [other, local], artists: []);
    expect(lookup.track('server'), same(other));
  });

  test('artist lookup skips unrelated songs on a contributor album', () {
    final shared = Album(
      id: 'shared',
      title: 'Shared album',
      artist: 'Z Main',
      artistId: 'main',
      trackCount: 2,
    );
    final appearance = local.copyWith(
      id: 'appearance',
      localId: null,
      serverTrackId: null,
      artistId: null,
      offlineAlbum: shared,
      artistCredits: const [
        ArtistCredit(artistId: 'main', name: 'Z Main', role: 'track_artist'),
        ArtistCredit(
          artistId: 'guest',
          name: 'A Guest',
          role: 'featured_artist',
        ),
      ],
    );
    final unrelated = appearance.copyWith(
      id: 'solo-song',
      artistCredits: const [
        ArtistCredit(artistId: 'main', name: 'Z Main', role: 'track_artist'),
      ],
    );
    final tracks = [appearance, unrelated];
    final groups = offlineArtistGroups(tracks);
    expect(groups.first.id, 'guest');
    expect(groups.first.albums.single.tracks, hasLength(2));
    final lookup = LocalLibrarySelection(tracks: tracks, artists: groups);
    expect(lookup.artistForTrack(unrelated)?.id, 'main');
    expect(
      lookup.matchesCustomShuffle(unrelated, artistIds: {'guest'}, genres: {}),
      isFalse,
    );
    expect(
      lookup.matchesCustomShuffle(appearance, artistIds: {'guest'}, genres: {}),
      isTrue,
    );
  });

  test('offline collaborator genres stay scoped to their credited songs', () {
    final shared = Album(
      id: 'shared',
      title: 'Shared album',
      artist: 'Main',
      artistId: 'main',
      trackCount: 2,
      artistCredits: const [
        ArtistCredit(artistId: 'main', name: 'Main', role: 'album_artist'),
        ArtistCredit(artistId: 'joint', name: 'Joint', role: 'joint'),
        ArtistCredit(artistId: 'composer', name: 'Composer', role: 'composer'),
      ],
    );
    final appearance = local.copyWith(
      id: 'appearance',
      localId: null,
      serverTrackId: null,
      artistId: 'main',
      offlineAlbum: shared,
      offlineArtists: [
        Artist(id: 'guest', name: 'Guest', albumCount: 0, genres: ['Jazz']),
        Artist(id: 'joint', name: 'Joint', albumCount: 0, genres: ['Rock']),
        Artist(
          id: 'composer',
          name: 'Composer',
          albumCount: 0,
          genres: ['Classical'],
        ),
      ],
      artistCredits: const [
        ArtistCredit(artistId: 'main', name: 'Main', role: 'track_artist'),
        ArtistCredit(artistId: 'guest', name: 'Guest', role: 'featured_artist'),
      ],
    );
    final unrelated = appearance.copyWith(
      id: 'unrelated',
      artistCredits: const [
        ArtistCredit(artistId: 'main', name: 'Main', role: 'track_artist'),
      ],
    );
    final lookup = LocalLibrarySelection(
      tracks: [appearance, unrelated],
      artists: [],
    );
    expect(
      lookup.matchesCustomShuffle(appearance, artistIds: {}, genres: {'jazz'}),
      isTrue,
    );
    expect(
      lookup.matchesCustomShuffle(unrelated, artistIds: {}, genres: {'jazz'}),
      isFalse,
    );
    for (final track in [appearance, unrelated]) {
      expect(
        lookup.matchesCustomShuffle(
          track,
          artistIds: {},
          genres: {'classical'},
        ),
        isFalse,
      );
      expect(
        lookup.matchesCustomShuffle(track, artistIds: {}, genres: {'rock'}),
        isTrue,
      );
    }
  });
}
