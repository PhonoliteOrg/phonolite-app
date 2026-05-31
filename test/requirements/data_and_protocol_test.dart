import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/entities/app_log.dart';
import 'package:phonolite_app/entities/custom_shuffle_settings.dart';
import 'package:phonolite_app/entities/models.dart';
import 'package:phonolite_opus/phonolite_opus.dart';

void main() {
  group('model contracts', () {
    test('artist parsing applies defaults for optional fields', () {
      final artist = Artist.fromJson(<String, dynamic>{
        'id': 'artist-1',
        'name': 'Boards of Canada',
      });

      expect(artist.id, 'artist-1');
      expect(artist.name, 'Boards of Canada');
      expect(artist.albumCount, 0);
      expect(artist.genres, isEmpty);
      expect(artist.summary, isNull);
      expect(artist.logoRef, isNull);
      expect(artist.bannerRef, isNull);
    });

    test('album parsing accepts metadata refresh payload variants', () {
      final rawRefreshAlbum = Album.fromJson(<String, dynamic>{
        'id': 'album-1',
        'title': 'Demon Days',
        'artist_id': 'artist-1',
        'artist_names': <String>['Gorillaz'],
        'year': '2005',
        'genres': <String>['Rock', 'Pop'],
      });
      final alternateCountAlbum = Album.fromJson(<String, dynamic>{
        'id': 'album-2',
        'title': 'Plastic Beach',
        'artist_id': 'artist-1',
        'artist': 'Gorillaz',
        'trackCount': '16',
        'year': 2010,
      });

      expect(rawRefreshAlbum.artist, 'Gorillaz');
      expect(rawRefreshAlbum.year, 2005);
      expect(rawRefreshAlbum.trackCount, 0);
      expect(rawRefreshAlbum.genres, <String>['Rock', 'Pop']);
      expect(alternateCountAlbum.trackCount, 16);
    });

    test('track copyWith preserves metadata while updating flags', () {
      final track = Track(
        id: 'track-1',
        title: 'Dayvan Cowboy',
        artist: 'Boards of Canada',
        album: 'The Campfire Headphase',
        albumId: 'album-1',
        genres: const <String>['ambient'],
        durationMs: 321000,
        liked: false,
        inPlaylists: false,
        trackNo: 2,
        discNo: 1,
      );

      final updated = track.copyWith(liked: true, inPlaylists: true);

      expect(updated.id, track.id);
      expect(updated.albumId, track.albumId);
      expect(updated.genres, <String>['ambient']);
      expect(updated.trackNo, track.trackNo);
      expect(updated.discNo, track.discNo);
      expect(updated.liked, isTrue);
      expect(updated.inPlaylists, isTrue);
    });

    test(
      'stats parsing accepts both structured and fallback item payloads',
      () {
        final stats = StatsResponse.fromJson(<String, dynamic>{
          'year': 2026,
          'month': 4,
          'total_minutes': 1234,
          'top_artists': <dynamic>[
            <String, dynamic>{
              'id': 'artist-1',
              'name': 'Aphex Twin',
              'minutes': 400,
            },
            'Fallback Artist',
          ],
          'top_tracks': <dynamic>[
            <String, dynamic>{
              'id': 'track-1',
              'title': 'Xtal',
              'artist': 'Aphex Twin',
              'minutes': 12,
              'plays': 3,
            },
            'Fallback Track',
          ],
          'top_genres': <dynamic>['Ambient'],
        });

        expect(stats.year, 2026);
        expect(stats.month, 4);
        expect(stats.totalMinutes, 1234);
        expect(stats.topArtists.first.name, 'Aphex Twin');
        expect(stats.topArtists.last.name, 'Fallback Artist');
        expect(stats.topTracks.first.title, 'Xtal');
        expect(stats.topTracks.last.title, 'Fallback Track');
        expect(stats.topGenres.single.name, 'Ambient');
      },
    );

    test('search result parsing falls back to name and artist fields', () {
      final result = SearchResult.fromJson(<String, dynamic>{
        'kind': 'album',
        'id': 'album-7',
        'name': 'Immunity',
        'artist': 'Jon Hopkins',
      });

      expect(result.kind, 'album');
      expect(result.id, 'album-7');
      expect(result.title, 'Immunity');
      expect(result.subtitle, 'Jon Hopkins');
      expect(result.score, isNull);
    });
  });

  group('custom shuffle settings', () {
    test('normalizes and deduplicates artist ids and genres', () {
      final settings = CustomShuffleSettings.fromJson(<String, dynamic>{
        'artistIds': <String>['artist-1', 'artist-1 ', 'artist-2', ''],
        'genres': <String>['Ambient', 'ambient', ' IDM ', ''],
      });

      expect(settings.artistIds, <String>['artist-1', 'artist-2']);
      expect(settings.genres, <String>['ambient', 'idm']);
    });

    test('copyWith preserves unspecified fields', () {
      const original = CustomShuffleSettings(
        artistIds: <String>['artist-1'],
        genres: <String>['ambient'],
      );

      final updated = original.copyWith(genres: <String>['idm']);

      expect(updated.artistIds, original.artistIds);
      expect(updated.genres, <String>['idm']);
    });
  });

  group('logging behavior', () {
    test('replays history to new listeners when requested', () {
      const uniqueMessage = 'requirements-history-entry';
      AppLogger.info(uniqueMessage);

      final replayed = <LogEntry>[];
      void listener(LogEntry entry) => replayed.add(entry);

      AppLogger.instance.attach(listener, includeHistory: true);
      AppLogger.instance.detach(listener);

      expect(replayed.any((entry) => entry.message == uniqueMessage), isTrue);
    });

    test('stops sending new entries after a listener is detached', () {
      final received = <LogEntry>[];
      void listener(LogEntry entry) => received.add(entry);

      AppLogger.instance.attach(listener, includeHistory: false);
      AppLogger.warning('listener-active');
      AppLogger.instance.detach(listener);
      AppLogger.warning('listener-detached');

      expect(
        received.any((entry) => entry.message == 'listener-active'),
        isTrue,
      );
      expect(
        received.any((entry) => entry.message == 'listener-detached'),
        isFalse,
      );
    });
  });

  group('raw opus header parsing', () {
    test('parses a valid header payload', () {
      final header = RawOpusHeader.parse(
        _buildHeader(
          sampleRate: 48000,
          channels: 2,
          frameMs: 20,
          bitrateBps: 128000,
          durationMs: 245000,
          preSkip: 312,
          trackId: 'track-1',
          title: 'Open Eye Signal',
          artist: 'Jon Hopkins',
          album: 'Immunity',
          codec: 'opus',
          container: 'raw',
        ),
      );

      expect(header.sampleRate, 48000);
      expect(header.channels, 2);
      expect(header.frameMs, 20);
      expect(header.bitrateBps, 128000);
      expect(header.durationMs, 245000);
      expect(header.preSkip, 312);
    });

    test('rejects invalid magic', () {
      final data = _buildHeader(
        sampleRate: 48000,
        channels: 2,
        frameMs: 20,
        bitrateBps: 128000,
        durationMs: 245000,
        preSkip: 312,
        trackId: 'track-1',
        title: '',
        artist: '',
        album: '',
        codec: '',
        container: '',
      );
      data[0] = 0x58;

      expect(
        () => RawOpusHeader.parse(data),
        throwsA(
          isA<OpusException>().having(
            (error) => error.message,
            'message',
            'invalid opus raw header',
          ),
        ),
      );
    });

    test('rejects unsupported header version', () {
      final data = _buildHeader(
        sampleRate: 48000,
        channels: 2,
        frameMs: 20,
        bitrateBps: 128000,
        durationMs: 245000,
        preSkip: 312,
        trackId: '',
        title: '',
        artist: '',
        album: '',
        codec: '',
        container: '',
      );
      data[8] = 2;

      expect(
        () => RawOpusHeader.parse(data),
        throwsA(
          isA<OpusException>().having(
            (error) => error.message,
            'message',
            'unsupported opus raw header version',
          ),
        ),
      );
    });

    test('rejects inconsistent metadata lengths', () {
      final data = _buildHeader(
        sampleRate: 48000,
        channels: 2,
        frameMs: 20,
        bitrateBps: 128000,
        durationMs: 245000,
        preSkip: 312,
        trackId: 'abc',
        title: '',
        artist: '',
        album: '',
        codec: '',
        container: '',
      );
      data[10] = 40;
      data[11] = 0;

      expect(
        () => RawOpusHeader.parse(data),
        throwsA(
          isA<OpusException>().having(
            (error) => error.message,
            'message',
            'invalid opus raw header lengths',
          ),
        ),
      );
    });
  });
}

Uint8List _buildHeader({
  required int sampleRate,
  required int channels,
  required int frameMs,
  required int bitrateBps,
  required int durationMs,
  required int preSkip,
  required String trackId,
  required String title,
  required String artist,
  required String album,
  required String codec,
  required String container,
}) {
  final trackIdBytes = Uint8List.fromList(trackId.codeUnits);
  final titleBytes = Uint8List.fromList(title.codeUnits);
  final artistBytes = Uint8List.fromList(artist.codeUnits);
  final albumBytes = Uint8List.fromList(album.codeUnits);
  final codecBytes = Uint8List.fromList(codec.codeUnits);
  final containerBytes = Uint8List.fromList(container.codeUnits);
  final headerLength =
      40 +
      trackIdBytes.length +
      titleBytes.length +
      artistBytes.length +
      albumBytes.length +
      codecBytes.length +
      containerBytes.length;
  final bytes = BytesBuilder();
  bytes.add('OPUSR01\u0000'.codeUnits);
  bytes.add(<int>[1, 0]);
  bytes.add(_u16(headerLength));
  bytes.add(_u32(sampleRate));
  bytes.add(<int>[channels, frameMs]);
  bytes.add(_u32(bitrateBps));
  bytes.add(_u32(durationMs));
  bytes.add(_u16(preSkip));
  bytes.add(_u16(trackIdBytes.length));
  bytes.add(_u16(titleBytes.length));
  bytes.add(_u16(artistBytes.length));
  bytes.add(_u16(albumBytes.length));
  bytes.add(_u16(codecBytes.length));
  bytes.add(_u16(containerBytes.length));
  bytes.add(trackIdBytes);
  bytes.add(titleBytes);
  bytes.add(artistBytes);
  bytes.add(albumBytes);
  bytes.add(codecBytes);
  bytes.add(containerBytes);
  return bytes.toBytes();
}

List<int> _u16(int value) => <int>[value & 0xff, (value >> 8) & 0xff];

List<int> _u32(int value) => <int>[
  value & 0xff,
  (value >> 8) & 0xff,
  (value >> 16) & 0xff,
  (value >> 24) & 0xff,
];
