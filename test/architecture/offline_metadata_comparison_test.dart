import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/entities/models.dart';
import 'package:phonolite_app/entities/offline_metadata_comparison.dart';

void main() {
  test('independently decoded and shared metadata compare equally', () {
    final first = Track.fromJson(_fixture());
    final decoded = Track.fromJson(_clone(_fixture()));
    expect(sameTrackCreditMetadata(first, first), isTrue);
    expect(sameTrackCreditMetadata(first, first.copyWith()), isTrue);
    expect(sameTrackCreditMetadata(first, decoded), isTrue);
    expect(_legacyComparison(first, decoded), isTrue);
  });

  // Check every serialized field, including nested profiles and credits. This
  // catches fields accidentally omitted from the allocation-free comparison.
  final sections = <List<Object>>[
    ['artist_credits', 0],
    ['offline_album'],
    ['offline_album', 'artist_credits', 0],
    ['offline_artist'],
    ['offline_artists', 0],
  ];
  for (final path in sections) {
    final fields = (_at(_fixture(), path) as Map).keys.cast<String>();
    for (final field in fields) {
      test('detects ${[...path, field].join('.')} changes', () {
        final before = _fixture();
        final after = _clone(before);
        final target = _at(after, path) as Map;
        target[field] = _different(target[field]);
        final a = Track.fromJson(before);
        final b = Track.fromJson(after);
        expect(_legacyComparison(a, b), isFalse);
        expect(sameTrackCreditMetadata(a, b), isFalse);
        expect(sameTrackCreditMetadata(b, a), isFalse);
      });
    }
  }

  for (final field in [
    'artist_ids',
    'artist_names',
    'artist_credits',
    'offline_artists',
  ]) {
    test('preserves $field order and length sensitivity', () {
      final before = _fixture();
      final reversed = _clone(before);
      reversed[field] = (reversed[field] as List).reversed.toList();
      final shortened = _clone(before);
      shortened[field] = (shortened[field] as List).skip(1).toList();
      final a = Track.fromJson(before);
      for (final changed in [reversed, shortened]) {
        final b = Track.fromJson(changed);
        expect(_legacyComparison(a, b), isFalse);
        expect(sameTrackCreditMetadata(a, b), isFalse);
      }
    });
  }

  for (final field in ['offline_album', 'offline_artist']) {
    test('detects $field being added or removed', () {
      final a = Track.fromJson(_fixture());
      final without = _fixture()..[field] = null;
      final b = Track.fromJson(without);
      expect(sameTrackCreditMetadata(a, b), isFalse);
      expect(sameTrackCreditMetadata(b, a), isFalse);
      expect(
        sameTrackCreditMetadata(b, Track.fromJson(_clone(without))),
        isTrue,
      );
    });
  }

  test('missing release count differs from an explicit identical total', () {
    final a = Track.fromJson(_fixture());
    final b = a.copyWith(
      offlineArtist: a.offlineArtist!.copyWith(releaseCount: null),
    );
    expect(a.offlineArtist!.releaseCount, b.offlineArtist!.releaseCount);
    expect(_legacyComparison(a, b), isFalse);
    expect(sameTrackCreditMetadata(a, b), isFalse);
  });

  test(
    'empty, null, Unicode, and escaped profile text retain JSON equality semantics',
    () {
      final variants = [
        null,
        '',
        'A "quoted" bio\n日本語 🎵',
        'A "quoted" bio\n日本語 🎵\n',
      ];
      for (final left in variants) {
        for (final right in variants) {
          final first = _fixture();
          final second = _clone(first);
          (first['offline_artist'] as Map)['summary'] = left;
          (second['offline_artist'] as Map)['summary'] = right;
          final a = Track.fromJson(first);
          final b = Track.fromJson(second);
          expect(sameTrackCreditMetadata(a, b), _legacyComparison(a, b));
        }
      }
    },
  );

  test('empty legacy metadata still compares equally', () {
    final first = Track.fromJson({
      'id': 'legacy',
      'title': 'Legacy',
      'duration_ms': 1,
    });
    final second = Track.fromJson(first.toJson());
    expect(sameTrackCreditMetadata(first, second), isTrue);
    expect(_legacyComparison(first, second), isTrue);
  });
}

Object? _at(Object? value, List<Object> path) {
  for (final key in path) {
    value = key is int ? (value as List)[key] : (value as Map)[key];
  }
  return value;
}

Object? _different(Object? value) => switch (value) {
  String text => '$text changed',
  int number => number + 1,
  List values => values.length > 1 ? values.reversed.toList() : [],
  _ => throw StateError('Add a mutation for ${value.runtimeType}'),
};

Map<String, dynamic> _clone(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

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

Map<String, dynamic> _fixture() {
  Map<String, dynamic> credit(String id) => {
    'artist_id': id,
    'name': 'Artist $id',
    'credited_name': 'Alias $id',
    'role': 'primary',
    'join_phrase': ' & ',
  };
  Map<String, dynamic> artist(String id) => {
    'id': id,
    'name': 'Artist $id',
    'album_count': 3,
    'collab_album_count': 2,
    'appearance_count': 4,
    'other_credit_count': 1,
    'release_count': 7,
    'genres': ['rock', 'ambient'],
    'summary': 'A "quoted" biography\n日本語 🎵',
    'logo_ref': 'logo-$id',
    'banner_ref': 'banner-$id',
  };
  return {
    'id': 'track',
    'title': 'Track',
    'artist': 'A & B',
    'artist_id': 'a',
    'artist_ids': ['a', 'b'],
    'artist_names': ['A', 'B'],
    'artist_credits': [credit('a'), credit('b')],
    'album': 'Album',
    'album_id': 'album',
    'duration_ms': 120000,
    'liked': false,
    'in_playlists': false,
    'offline_album': {
      'id': 'album',
      'title': 'Album',
      'artist': 'A & B',
      'artist_id': 'a',
      'artist_ids': ['a', 'b'],
      'artist_names': ['A', 'B'],
      'artist_credits': [credit('a'), credit('b')],
      'track_count': 10,
      'year': 1998,
      'genres': ['rock', 'ambient'],
      'summary': 'Album summary',
    },
    'offline_artist': artist('a'),
    'offline_artists': [artist('a'), artist('b')],
  };
}
