import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/data/models/auth/auth_state.dart';
import 'package:phonolite_app/data/models/playback/native_now_playing_snapshot.dart';
import 'package:phonolite_app/data/models/playback/native_remote_command.dart';
import 'package:phonolite_app/data/models/playback/playback_state.dart';
import 'package:phonolite_app/data/models/playback/vehicle_item.dart';
import 'package:phonolite_app/data/models/playback/vehicle_request.dart';
import 'package:phonolite_app/data/models/playback/vehicle_response.dart';
import 'package:phonolite_app/infrastructure/platform/media/now_playing_codec.dart';
import 'package:phonolite_app/infrastructure/platform/media/vehicle_surface_codec.dart';

void main() {
  test('vehicle method names retain their operations and default server scope', () {
    final methods = <String, VehicleOperation>{
      'getCarPlayState': VehicleOperation.getState,
      'getHomeActions': VehicleOperation.getHomeActions,
      'getAuthState': VehicleOperation.getAuthorization,
      'getArtists': VehicleOperation.getArtists,
      'getAlbums': VehicleOperation.getAlbums,
      'getPlaylists': VehicleOperation.getPlaylists,
      'getLibraryStatus': VehicleOperation.getLibraryStatus,
      'playAlbum': VehicleOperation.playAlbum,
      'playPlaylist': VehicleOperation.playPlaylist,
      'playLiked': VehicleOperation.playLiked,
      'startShuffle': VehicleOperation.startShuffle,
      'unrecognized': VehicleOperation.unknown,
    };

    for (final entry in methods.entries) {
      final request = VehicleSurfaceCodec.decodeRequest(entry.key, {});

      expect(request.operation, entry.value);
      expect(request.scope, ActionScope.server);
      expect(request.shuffleKind, VehicleShuffleKind.library);
    }
  });

  test('vehicle shuffle decoding preserves local scope and legacy server defaults', () {
    final local = VehicleSurfaceCodec.decodeRequest('startShuffle', {
      'scope': 'local',
      'kind': 'playlist',
      'artistId': 42,
      'albumId': 'album',
      'playlistId': 'playlist',
    });

    expect(local.operation, VehicleOperation.startShuffle);
    expect(local.scope, ActionScope.local);
    expect(local.shuffleKind, VehicleShuffleKind.playlist);
    expect(local.artistId, '42');
    expect(local.albumId, 'album');
    expect(local.playlistId, 'playlist');

    final methods = <String, VehicleShuffleKind>{
      'startLibraryShuffle': VehicleShuffleKind.library,
      'startLikedShuffle': VehicleShuffleKind.liked,
      'startCustomShuffle': VehicleShuffleKind.custom,
    };

    for (final entry in methods.entries) {
      final request = VehicleSurfaceCodec.decodeRequest(entry.key, {'scope': 'local', 'kind': 'album'});

      expect(request.operation, VehicleOperation.startShuffle);
      expect(request.scope, ActionScope.server);
      expect(request.shuffleKind, entry.value);
    }
  });

  test('vehicle response envelopes retain their exact native keys and error codes', () {
    expect(VehicleSurfaceCodec.encodeResponse(const VehicleCommandResult.ok()), {'ok': true});
    expect(VehicleSurfaceCodec.encodeResponse(const VehicleSourceState(serverAvailable: false, localAvailable: true)), {
      'serverAvailable': false,
      'localAvailable': true,
      'hasAnySource': true,
    });
    expect(
      VehicleSurfaceCodec.encodeResponse(
        const VehicleAuthorizationState(authorized: false, hasSession: true, status: SessionStatus.serverUnavailable),
      ),
      {'authorized': false, 'hasSession': true, 'status': 'serverUnavailable'},
    );
    expect(
      VehicleSurfaceCodec.encodeResponse(
        const VehicleLibraryStatus(likedAvailable: false, failure: VehicleFailure.serverUnavailable),
      ),
      {'likedAvailable': false, 'error': 'server_unavailable'},
    );

    final codes = <VehicleFailure, String>{
      VehicleFailure.unauthorized: 'unauthorized',
      VehicleFailure.serverUnavailable: 'server_unavailable',
      VehicleFailure.missingArtist: 'missing_artist',
      VehicleFailure.missingAlbum: 'missing_album',
      VehicleFailure.missingPlaylist: 'missing_playlist',
      VehicleFailure.likedEmpty: 'liked_empty',
      VehicleFailure.customEmpty: 'custom_empty',
    };

    for (final entry in codes.entries) {
      expect(VehicleSurfaceCodec.encodeResponse(VehicleCommandResult.failure(entry.key)), {
        'error': entry.value,
        'items': [],
      });
    }
  });

  test('vehicle items encode local file URLs and preserve conditional authentication fields', () {
    final response = VehicleItems([
      const VehicleItem(id: 'local', title: 'Local', subtitle: '', artworkPath: ' /music/Cover Art.png '),
      const VehicleItem(
        id: 'remote',
        title: 'Remote',
        subtitle: 'Album',
        artworkUrl: 'https://server.test/cover',
        artworkPath: '/unused/local.png',
        token: 'session-token',
        serverPin: 'server-pin',
      ),
      const VehicleItem(id: 'plain', title: 'Plain', subtitle: '', serverPin: 'unused-pin'),
      const VehicleItem.action(
        action: VehicleHomeAction.likedShuffle,
        title: 'Liked',
        subtitle: 'Shuffle',
        enabled: false,
      ),
    ]);

    expect(VehicleSurfaceCodec.encodeResponse(response), {
      'items': [
        {'id': 'local', 'title': 'Local', 'subtitle': '', 'artworkUrl': 'file:///music/Cover%20Art.png'},
        {
          'id': 'remote',
          'title': 'Remote',
          'subtitle': 'Album',
          'artworkUrl': 'https://server.test/cover',
          'token': 'session-token',
          'serverPin': 'server-pin',
        },
        {'id': 'plain', 'title': 'Plain', 'subtitle': ''},
        {'id': 'startLikedShuffle', 'title': 'Liked', 'subtitle': 'Shuffle', 'enabled': false},
      ],
    });
  });

  test('now-playing commands decode known actions and parse only seek positions', () {
    final actions = <String, NativeRemoteAction>{
      'play': NativeRemoteAction.play,
      'pause': NativeRemoteAction.pause,
      'next': NativeRemoteAction.next,
      'prev': NativeRemoteAction.previous,
      'toggleLike': NativeRemoteAction.toggleLike,
      'startLibraryShuffle': NativeRemoteAction.startLibraryShuffle,
      'audioInterruptionBegan': NativeRemoteAction.audioInterruptionBegan,
      'audioInterruptionEnded': NativeRemoteAction.audioInterruptionEnded,
      'audioInterruptionEndedPaused': NativeRemoteAction.audioInterruptionEndedPaused,
      'audioServicesReset': NativeRemoteAction.audioServicesReset,
      'unrecognized': NativeRemoteAction.unknown,
    };

    for (final entry in actions.entries) {
      final command = NowPlayingCodec.decodeCommand({'type': entry.key, 'position': double.infinity});

      expect(command.action, entry.value);
      expect(command.position, isNull);
    }

    expect(
      NowPlayingCodec.decodeCommand({'type': 'seek', 'position': 1.25}).position,
      const Duration(milliseconds: 1250),
    );
    expect(
      NowPlayingCodec.decodeCommand({'type': 'seek', 'position': '2.3455'}).position,
      const Duration(milliseconds: 2346),
    );
    expect(NowPlayingCodec.decodeCommand({'type': 'seek', 'position': 'invalid'}).position, isNull);
    expect(NowPlayingCodec.decodeCommand({'type': 'seek'}).position, isNull);
    for (final invalid in [double.nan, double.infinity, -1, 1.0e20]) {
      expect(NowPlayingCodec.decodeCommand({'type': 'seek', 'position': invalid}).position, isNull);
    }
  });

  test('now-playing snapshots preserve seconds, artwork keys and conditional payloads', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final snapshot = NativeNowPlayingSnapshot(
      epoch: 4,
      trackId: 'track',
      title: 'Title',
      artist: 'Artist',
      album: 'Album',
      duration: const Duration(milliseconds: 12500),
      position: const Duration(milliseconds: 1250),
      isPlaying: true,
      liked: false,
      artworkKey: 'artwork',
      artworkUrl: 'https://server.test/cover',
      token: 'session-token',
      serverPin: 'server-pin',
      artworkPath: '/local/cover.png',
      artworkBytes: bytes,
    );

    expect(NowPlayingCodec.encodeSnapshot(snapshot), {
      'epoch': 4,
      'trackId': 'track',
      'title': 'Title',
      'artist': 'Artist',
      'album': 'Album',
      'duration': 12.5,
      'position': 1.25,
      'isPlaying': true,
      'liked': false,
      'artworkKey': 'artwork',
      'artworkUrl': 'https://server.test/cover',
      'token': 'session-token',
      'serverPin': 'server-pin',
      'artworkPath': '/local/cover.png',
      'artworkBytes': bytes,
    });

    final local = NowPlayingCodec.encodeSnapshot(
      const NativeNowPlayingSnapshot(
        epoch: 0,
        trackId: '',
        title: '',
        artist: '',
        album: '',
        duration: Duration.zero,
        position: Duration.zero,
        isPlaying: false,
        liked: false,
        artworkKey: '',
        token: 'unused-token',
        serverPin: 'unused-pin',
      ),
    );

    expect(local.keys, isNot(contains('artworkUrl')));
    expect(local.keys, isNot(contains('token')));
    expect(local.keys, isNot(contains('serverPin')));
    expect(local.keys, isNot(contains('artworkPath')));
    expect(local.keys, isNot(contains('artworkBytes')));
  });
}
