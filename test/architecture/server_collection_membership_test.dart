import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/data/models/collections/account_collection_snapshot.dart';
import 'package:phonolite_app/data/models/collections/like_state.dart';
import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/data/structures/collections/server_collection_membership.dart';

import '../support/offline_library_test_helpers.dart';

void main() {
  test('authoritative replacement clears removed likes and playlist membership', () {
    final membership = ServerCollectionMembership();
    final track = offlineTestTrack(id: 'track').copyWith(liked: true, inPlaylists: true);

    membership.replace(
      _snapshot(
        liked: ['track'],
        playlists: [
          _playlist('mix', ['track']),
        ],
      ),
    );
    expect(membership.project(track), same(track));

    membership.replace(_snapshot());
    final updated = membership.project(track);

    expect(updated.liked, isFalse);
    expect(updated.inPlaylists, isFalse);
    expect(updated.title, track.title);
    expect(updated.albumId, track.albumId);
    expect(updated.durationMs, track.durationMs);
  });

  test('successful local writes override older metadata without clearing unknown state', () {
    final membership = ServerCollectionMembership();
    final track = offlineTestTrack(id: 'track');
    final unknown = offlineTestTrack(id: 'unknown').copyWith(liked: true, inPlaylists: true);

    membership.recordLike('track', true);
    membership.recordPlaylist(_playlist('mix', ['track']));

    expect(membership.project(track).liked, isTrue);
    expect(membership.project(track).inPlaylists, isTrue);
    expect(membership.project(unknown), same(unknown));
  });

  test('deleting one playlist preserves membership in another playlist', () {
    final membership = ServerCollectionMembership();
    final track = offlineTestTrack(id: 'track');

    membership.replace(
      _snapshot(
        playlists: [
          _playlist('first', ['track']),
          _playlist('second', ['track']),
        ],
      ),
    );
    membership.recordPlaylistDeleted('first');
    expect(membership.project(track).inPlaylists, isTrue);

    membership.recordPlaylist(_playlist('second', []));
    expect(membership.project(track).inPlaylists, isFalse);
  });

  test('server aliases use server identity and local collection flags stay local', () {
    final membership = ServerCollectionMembership();
    final alias = offlineTestTrack(id: 'alias').copyWith(serverTrackId: 'track');
    final local = alias.copyWith(id: 'local-track', localId: 'local-track');

    membership.replace(
      _snapshot(
        liked: ['track'],
        playlists: [
          _playlist('mix', ['track']),
        ],
      ),
    );

    expect(membership.project(alias).liked, isTrue);
    expect(membership.project(alias).inPlaylists, isTrue);
    expect(membership.project(local), same(local));
  });

  test('streamed tracks carrying download references receive server membership updates', () {
    final membership = ServerCollectionMembership();
    final track = offlineTestTrack(id: 'track').copyWith(localId: 'local-track');
    final alias = track.copyWith(id: 'alias', serverTrackId: 'track');

    membership.replace(
      _snapshot(
        liked: ['track'],
        playlists: [
          _playlist('mix', ['track']),
        ],
      ),
    );

    for (final streamed in [track, alias]) {
      final projected = membership.project(streamed);

      expect(projected.liked, isTrue);
      expect(projected.inPlaylists, isTrue);
      expect(projected.id, streamed.id);
      expect(projected.localId, 'local-track');
      expect(projected.serverTrackId, streamed.serverTrackId);
    }

    final likedTrack = membership.project(track);
    membership.replace(_snapshot());
    expect(membership.project(likedTrack).liked, isFalse);
    expect(membership.project(likedTrack).inPlaylists, isFalse);
  });

  test('tracks using local identity keep local flags even with a server alias', () {
    final membership = ServerCollectionMembership();
    final local = offlineTestTrack(
      id: 'local-track',
    ).copyWith(localId: 'local-track', serverTrackId: 'server-track', liked: true, inPlaylists: true);
    final localOnly = local.copyWith(serverTrackId: null);

    membership.replace(_snapshot());

    expect(membership.project(local), same(local));
    expect(membership.project(localOnly), same(localOnly));
  });

  test('clearing account membership restores server response values', () {
    final membership = ServerCollectionMembership();
    final track = offlineTestTrack(id: 'track');

    membership.replace(_snapshot(liked: ['track']));
    expect(membership.project(track).liked, isTrue);

    membership.clear();
    expect(membership.hasSnapshot, isFalse);
    expect(membership.project(track), same(track));
  });

  test('playlist server revisions round trip and support explicit clearing', () {
    final legacy = Playlist.fromJson({'id': 'mix', 'name': 'Mix', 'track_ids': <String>[]});
    final versioned = legacy.copyWith(revision: 4);

    expect(legacy.revision, isNull);
    expect(Playlist.fromJson(versioned.toJson()).revision, 4);
    expect(versioned.copyWith(name: 'Renamed').revision, 4);
    expect(versioned.copyWith(revision: null).revision, isNull);
  });
}

AccountCollectionSnapshot _snapshot({List<String> liked = const [], List<Playlist> playlists = const []}) =>
    AccountCollectionSnapshot(
      userId: 'account',
      revision: 1,
      likes: liked.map((id) => ServerLikeState(trackId: id, liked: true, updatedAt: 1)),
      playlists: playlists,
    );

Playlist _playlist(String id, List<String> trackIds) => Playlist(id: id, name: id, trackIds: trackIds, revision: 1);
