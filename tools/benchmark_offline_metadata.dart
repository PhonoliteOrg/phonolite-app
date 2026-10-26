// Synthetic comparison benchmark. Compile ahead of time to avoid measuring JIT:
// dart compile exe tools/benchmark_offline_metadata.dart -o /tmp/offline_metadata_bench
// /tmp/offline_metadata_bench
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/artist_credit.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/rules/library/offline_metadata_comparison.dart';

typedef Comparison = bool Function(Track, Track);
int _consumedResults = 0;

void main(List<String> args) {
  final count = args.isEmpty ? 250 : int.parse(args.single);
  if (count <= 0) throw ArgumentError('Track count must be positive');
  final results = <Map<String, Object>>[];
  for (final withProfiles in [false, true]) {
    final left = List.generate(count, (i) => _track(i, withProfiles));
    // Construct independent objects and strings before timing either method.
    final right = left.map(_independentCopy).toList();
    final changed = [...right];
    changed[count - 1] = withProfiles
        ? changed.last.copyWith(offlineArtist: changed.last.offlineArtist!.copyWith(summary: 'Updated bio'))
        : changed.last.copyWith(artistNames: ['Updated artist']);
    for (final scenario in ['unchanged', 'last_track_changed']) {
      final other = scenario == 'unchanged' ? right : changed;
      final legacy = _measure(left, other, _legacyComparison);
      final direct = _measure(left, other, sameTrackCreditMetadata);
      results.add({
        'metadata': withProfiles ? 'full_profiles' : 'credits_only',
        'scenario': scenario,
        'tracks_per_snapshot': count,
        'legacy_ms_per_snapshot': legacy,
        'direct_ms_per_snapshot': direct,
        'comparison_speedup': legacy / direct,
      });
    }
  }
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'synthetic_benchmark': true,
      'measurement': 'median of 7 rounds; excludes fixture creation and JSON decoding',
      'results': results,
      'consumed_results': _consumedResults,
    }),
  );
}

double _measure(List<Track> left, List<Track> right, Comparison same) {
  bool compareSnapshot() {
    for (var i = 0; i < left.length; i++) {
      if (!same(left[i], right[i])) return false;
    }
    return true;
  }

  final warmup = Stopwatch()..start();
  for (var i = 0; i < 10; i++) {
    if (compareSnapshot()) _consumedResults++;
  }
  warmup.stop();
  final perSnapshotUs = math.max(1, warmup.elapsedMicroseconds / 10);
  final iterations = (50000 / perSnapshotUs).ceil().clamp(1, 10000);
  final samples = <double>[];
  for (var round = 0; round < 7; round++) {
    final watch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      if (compareSnapshot()) _consumedResults++;
    }
    watch.stop();
    samples.add(watch.elapsedMicroseconds / iterations / 1000);
  }
  samples.sort();
  return samples[samples.length ~/ 2];
}

bool _legacyComparison(Track a, Track b) {
  Object metadata(Track track) => [
    track.artistIds,
    track.artistNames,
    track.artistCredits.map((credit) => credit.toJson()).toList(),
    track.offlineAlbum?.toJson(),
    track.offlineArtist?.toJson(),
    track.offlineArtists.map((artist) => artist.toJson()).toList(),
  ];
  return jsonEncode(metadata(a)) == jsonEncode(metadata(b));
}

Track _independentCopy(Track track) => Track.fromJson(
  jsonDecode(
        jsonEncode({
          ...track.toJson(),
          'offline_album': track.offlineAlbum?.toJson(),
          'offline_artist': track.offlineArtist?.toJson(),
        }),
      )
      as Map<String, dynamic>,
);

Track _track(int index, bool withProfiles) {
  const credits = [
    ArtistCredit(artistId: 'a', name: 'Artist A', joinPhrase: ' & '),
    ArtistCredit(artistId: 'b', name: 'Artist B', role: 'featured_artist'),
  ];
  Artist artist(String id) => Artist(
    id: id,
    name: 'Artist $id',
    albumCount: 12,
    collabAlbumCount: 3,
    releaseCount: 15,
    genres: ['ambient', 'rock'],
    summary: 'A "quoted" artist biography\n日本語 🎵. ' * 128,
    logoRef: 'logo-$id',
    bannerRef: 'banner-$id',
  );
  return Track(
    id: 'track-$index',
    title: 'Track $index',
    artist: 'Artist A & B',
    artistId: 'a',
    artistIds: ['a', 'b'],
    artistNames: ['Artist A', 'Artist B'],
    artistCredits: credits,
    album: 'Album ${index ~/ 10}',
    albumId: 'album-${index ~/ 10}',
    durationMs: 180000,
    liked: false,
    inPlaylists: false,
    offlineAlbum: withProfiles
        ? Album(
            id: 'album-${index ~/ 10}',
            title: 'Album ${index ~/ 10}',
            artist: 'Artist A & B',
            artistId: 'a',
            artistIds: ['a', 'b'],
            artistNames: ['Artist A', 'Artist B'],
            artistCredits: credits,
            trackCount: 10,
            year: 2026,
            genres: ['ambient', 'rock'],
            summary: 'An album description with quotes "and Unicode" 🎵. ' * 64,
          )
        : null,
    offlineArtist: withProfiles ? artist('a') : null,
    offlineArtists: withProfiles ? [artist('a'), artist('b')] : [],
  );
}
