import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/data/models/listening_stats/listening_event.dart';
import 'package:phonolite_app/data/models/library/artist_credit.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/storage/offline/library/offline_library.dart';

import '../support/offline_library_test_helpers.dart';

final _track = Track(
  id: 'song',
  title: 'Song',
  artist: 'Performer',
  artistId: 'performer',
  album: 'Release',
  albumId: 'release',
  durationMs: 180000,
  liked: false,
  inPlaylists: false,
);

Album _album({String id = 'release', List<String> genres = const []}) => Album(
  id: id,
  title: 'Release',
  artist: 'Performer',
  artistId: 'performer',
  trackCount: 1,
  genres: genres,
);

Artist _artist(String id, List<String> genres) =>
    Artist(id: id, name: id, albumCount: 1, genres: genres);

ListeningEvent _snapshot(
  Track track, {
  List<Album> cachedAlbums = const [],
  List<Artist> cachedArtists = const [],
}) => ListeningEvent.fromTrack(
  track: track,
  eventId: 'interval',
  sessionId: 'session',
  deviceId: 'device',
  sessionStartedAtMs: 0,
  startedAtMs: 0,
  endedAtMs: 60000,
  listenedMs: 60000,
  cachedAlbums: cachedAlbums,
  cachedArtists: cachedArtists,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('listening snapshots retain only the identified main artist', () {
    final event = _snapshot(
      _track.copyWith(
        artist: 'Jamiroquai, Jason Kay, Sola Akingbola',
        artistId: 'jamiroquai',
        artistCredits: const [
          ArtistCredit(
            artistId: 'jason-kay',
            name: 'Jason Kay',
            role: 'composer',
          ),
          ArtistCredit(artistId: 'jamiroquai', name: 'Jamiroquai'),
          ArtistCredit(
            artistId: 'sola-akingbola',
            name: 'Sola Akingbola',
            role: 'performer',
          ),
        ],
      ),
    );
    expect(event.artistId, 'jamiroquai');
    expect(event.artists.single.toJson(), {
      'id': 'jamiroquai',
      'name': 'Jamiroquai',
    });
    expect(() => event.artists.clear(), throwsUnsupportedError);
  });

  test('missing primary ID retains main name before contributor fallbacks', () {
    final track = _track.copyWith(
      artist: 'Jamiroquai',
      artistId: null,
      artistCredits: const [
        ArtistCredit(artistId: 'jason-kay', name: 'Jason Kay'),
      ],
    );
    expect(_snapshot(track).artists.single.toJson(), {
      'id': '',
      'name': 'Jamiroquai',
    });
    expect(_snapshot(track.copyWith(artist: '')).artists.single.toJson(), {
      'id': 'jason-kay',
      'name': 'Jason Kay',
    });
    expect(
      _snapshot(_track.copyWith(artist: '', artistId: null)).artists,
      isEmpty,
    );
  });

  test(
    'song tags remain a normalized immutable fallback without album genres',
    () {
      final genres = <String>[' Jazz ', 'jazz', ' ', 'Soul'];
      final event = _snapshot(
        _track.copyWith(
          genres: genres,
          offlineAlbum: _album(),
          offlineArtist: _artist('performer', ['Ambient']),
        ),
      );
      expect(event.genres, ['Jazz', 'Soul']);
      genres.add('Pop');
      expect(event.genres, ['Jazz', 'Soul']);
      expect(() => event.genres.add('Pop'), throwsUnsupportedError);
    },
  );

  test('release genres replace broad Jamiroquai file tags for statistics', () {
    final track = _track.copyWith(
      title: 'Virtual Insanity',
      artist: 'Jamiroquai',
      genres: ['Rock', 'Pop'],
      offlineAlbum: _album(genres: ['acid jazz', 'Electronic', 'funk']),
      offlineArtist: _artist('performer', [
        'acid jazz',
        'disco',
        'funk',
        'house',
        'r&b',
      ]),
    );
    expect(_snapshot(track).genres, ['acid jazz', 'Electronic', 'funk']);
    expect(track.genres, ['Rock', 'Pop']);
    expect(
      _snapshot(
        _track.copyWith(genres: ['Rock', 'Pop']),
        cachedAlbums: [
          _album(genres: ['acid jazz', 'Electronic', 'funk']),
        ],
      ).genres,
      ['acid jazz', 'Electronic', 'funk'],
    );
  });

  test('server listening projection wins over stale cached metadata', () {
    final projected = <String>[' acid jazz ', 'Electronic', 'funk', 'FUNK'];
    final event = _snapshot(
      _track.copyWith(
        genres: ['Rock', 'Pop'],
        listeningGenres: projected,
        offlineAlbum: _album(genres: ['Pop']),
      ),
      cachedAlbums: [
        _album(genres: ['Rock']),
      ],
    );
    expect(event.genres, ['acid jazz', 'Electronic', 'funk']);
    projected.add('disco');
    expect(event.genres, ['acid jazz', 'Electronic', 'funk']);
    expect(() => event.genres.add('house'), throwsUnsupportedError);
  });

  test(
    'additive listening projection parses older JSON and survives copies',
    () {
      final oldJson = _track.toJson()..remove('listening_genres');
      expect(Track.fromJson(oldJson).listeningGenres, isEmpty);
      final track = Track.fromJson({
        ...oldJson,
        'genres': ['Rock', 'Pop'],
        'listening_genres': ['acid jazz', 'Electronic', 'funk'],
      });
      final restored = Track.fromJson(track.copyWith(liked: true).toJson());
      expect(restored.listeningGenres, ['acid jazz', 'Electronic', 'funk']);
      expect(restored.genres, ['Rock', 'Pop']);
      expect(restored.liked, isTrue);
      expect(_snapshot(restored).genres, ['acid jazz', 'Electronic', 'funk']);
    },
  );

  test(
    'download storage retains release genres for disconnected listening',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'phonolite_listening_genres_',
      );
      final storage = OfflineLibraryStorage(baseDirectory: temp);
      addTearDown(() async {
        await storage.close();
        await temp.delete(recursive: true);
      });
      final media = await offlineTestMediaFile(temp, 'virtual-insanity.flac');
      final original = offlineTestOfflineMetadata(
        trackId: 'virtual-insanity',
        trackTitle: 'Virtual Insanity',
        artistName: 'Jamiroquai',
        albumTitle: 'Travelling Without Moving',
        albumGenres: ['acid jazz', 'Electronic', 'funk'],
        artistGenres: ['acid jazz', 'disco', 'funk', 'house', 'r&b'],
      );
      final metadata = original.copyWith(
        track: original.track.copyWith(
          genres: ['Rock', 'Pop'],
          listeningGenres: ['acid jazz', 'Electronic', 'funk'],
        ),
      );
      final prepared = await storage.prepareDownload(
        offlineTestDownload(
          serverBaseUrl: 'http://server-one.test/api',
          track: metadata.track,
          filePath: media.path,
        ).copyWith(offlineMetadata: metadata),
      );
      await storage.upsertDownload(prepared);
      await storage.close();
      final restored = OfflineLibraryStorage(baseDirectory: temp);
      addTearDown(restored.close);
      final downloaded = (await restored.readDownloads()).single.track;
      final local = (await restored.readLocalDownloadedTracks()).single;
      for (final track in [downloaded, local]) {
        expect(track.genres, ['Rock', 'Pop']);
        expect(track.listeningGenres, ['acid jazz', 'Electronic', 'funk']);
        expect(_snapshot(track).genres, ['acid jazz', 'Electronic', 'funk']);
      }
    },
  );

  test('older downloaded tracks inherit embedded album genres', () {
    final event = _snapshot(
      _track.copyWith(
        genres: [' '],
        offlineAlbum: _album(genres: [' Electronic ', 'Downtempo']),
        offlineArtist: _artist('performer', ['Ambient']),
      ),
    );
    expect(event.genres, ['Electronic', 'Downtempo']);
  });

  test('older server tracks use only a matching cached album', () {
    final event = _snapshot(
      _track,
      cachedAlbums: [
        _album(id: 'other-release', genres: ['Wrong genre']),
        _album(genres: ['Rock', 'rock', 'Pop']),
      ],
      cachedArtists: [
        _artist('performer', ['Ambient']),
      ],
    );
    expect(event.genres, ['Rock', 'Pop']);
  });

  test(
    'performer profiles supply genres without supporting credit leakage',
    () {
      final event = _snapshot(
        _track.copyWith(
          artistCredits: const [
            ArtistCredit(artistId: 'performer', name: 'Performer'),
            ArtistCredit(
              artistId: 'guest',
              name: 'Guest',
              role: 'featured_artist',
            ),
            ArtistCredit(
              artistId: 'producer',
              name: 'Producer',
              role: 'producer',
            ),
          ],
          offlineArtist: _artist('performer', ['Jazz']),
          offlineArtists: [
            _artist('guest', ['Soul', 'jazz']),
          ],
        ),
        cachedArtists: [
          _artist('producer', ['Metal']),
          _artist('unrelated', ['Classical']),
        ],
      );
      expect(event.genres, ['Jazz', 'Soul']);
    },
  );

  test(
    'artist fallback can use cached profiles when embedded tags are empty',
    () {
      final event = _snapshot(
        _track.copyWith(offlineArtist: _artist('performer', [])),
        cachedArtists: [
          _artist('performer', ['Ambient', 'Drone']),
        ],
      );
      expect(event.genres, ['Ambient', 'Drone']);
    },
  );

  test('missing genre metadata stays empty without inventing a category', () {
    final event = _snapshot(
      _track.copyWith(
        offlineAlbum: _album(id: 'other', genres: ['Rock']),
      ),
      cachedArtists: [
        _artist('unrelated', ['Jazz']),
      ],
    );
    expect(event.genres, isEmpty);
  });
}
