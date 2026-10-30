import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/playlists/playlist_detail_controller.dart';
import 'package:phonolite_app/application/downloads/offline_download_manager.dart';
import 'package:phonolite_app/data/models/collections/account_collection_event.dart';
import 'package:phonolite_app/data/models/auth/account_state.dart';
import 'package:phonolite_app/data/models/collections/account_collection_snapshot.dart';
import 'package:phonolite_app/data/models/collections/like_state.dart';
import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/data/models/library/metadata_update_event.dart';
import 'package:phonolite_app/data/models/library/artist_summary.dart';
import 'package:phonolite_app/data/models/library/search_result.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/playback/custom_shuffle_settings.dart';
import 'package:phonolite_app/data/models/playback/account_last_track.dart';
import 'package:phonolite_app/data/models/playback/shuffle_preset.dart';
import 'package:phonolite_app/data/models/playback/shuffle_preset_snapshot.dart';
import 'package:phonolite_app/data/models/playback/native_now_playing_snapshot.dart';
import 'package:phonolite_app/data/models/preferences/offline_storage_locations.dart';
import 'package:phonolite_app/data/models/server/server_capabilities.dart';
import 'package:phonolite_app/data/models/server/revision_event.dart';
import 'package:phonolite_app/data/repositories/listening_stats_service.dart';
import 'package:phonolite_app/data/storage/offline/library/offline_library.dart';
import 'package:phonolite_app/data/storage/preferences/custom_shuffle_settings_storage.dart';
import 'package:phonolite_app/data/storage/preferences/playback_preferences.dart';
import 'package:phonolite_app/infrastructure/audio/engine/audio_engine.dart';
import 'package:phonolite_app/infrastructure/platform/connectivity/connectivity_signal_source.dart';
import 'package:phonolite_app/infrastructure/platform/media/now_playing_platform_service.dart';
import 'package:phonolite_app/infrastructure/platform/media/vehicle_surface_service.dart';
import 'package:phonolite_app/infrastructure/platform/permissions/local_network_permission_service.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';

import '../support/auth_test_helpers.dart';
import '../support/offline_library_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('two playing apps receive live hearts, playlist edits and deletion without restarting audio', () async {
    final server = _AccountServer();
    final first = _Harness(_Connection(server));
    final second = _Harness(_Connection(server));
    addTearDown(first.close);
    addTearDown(second.close);
    await Future.wait([first.start(), second.start()]);
    await Future.wait([first.playAndOpenPlaylist(), second.playAndOpenPlaylist()]);
    final detail = PlaylistDetailController(second.app, 'mix', false);
    addTearDown(detail.dispose);
    final positions = [first.app.playbackState.position, second.app.playbackState.position];
    final stops = [first.audio.stops, second.audio.stops];

    await first.app.toggleLike(first.app.playbackState.track!);
    expect(server.account('alice').liked['track'], isTrue);
    await _until(() => second.app.liked.any((track) => track.id == 'track'), 'remote like');

    expect(second.app.tracks.first.liked, isTrue);
    expect(second.app.playlistTracks.first.liked, isTrue);
    expect(second.app.playbackState.track!.liked, isTrue);
    expect(second.nowPlaying.snapshots.last.liked, isTrue);
    expect(second.app.localLiked.single.id, 'local');
    expect(second.app.localLiked.single.liked, isTrue);

    await first.app.addTrackToPlaylist(first.app.playlists.single, _track('other'));
    await _until(() => second.app.playlistTracks.length == 2, 'remote playlist addition');
    expect(server.atomicAdds, 1);
    expect(second.app.playlists.single.trackIds, ['track', 'other']);
    expect(second.app.playlistTracks.map((track) => track.id), ['track', 'other']);

    await first.app.renamePlaylist('mix', 'Changed elsewhere', description: 'Shared update');
    await _until(() => second.app.playlists.single.name == 'Changed elsewhere', 'remote playlist rename');
    expect(second.app.playlists.single.description, 'Shared update');

    await first.app.toggleLike(first.app.playbackState.track!);
    await _until(() => second.app.liked.isEmpty && !second.app.playbackState.track!.liked, 'remote unlike');
    expect(second.app.tracks.first.liked, isFalse);
    expect(second.app.playlistTracks.first.liked, isFalse);
    expect(second.nowPlaying.snapshots.last.liked, isFalse);

    await first.app.deletePlaylist('mix');
    await _until(() => second.app.playlists.isEmpty, 'remote playlist deletion');
    expect(second.app.playlistTracks, isEmpty);
    expect(detail.playlistDeleted, isTrue);
    expect(second.app.tracks.first.inPlaylists, isFalse);

    for (final (index, harness) in [first, second].indexed) {
      expect(harness.audio.starts, 1);
      expect(harness.audio.seeks, 0);
      expect(harness.audio.stops, stops[index]);
      expect(harness.app.playbackState.track!.id, 'track');
      expect(harness.app.playbackState.isPlaying, isTrue);
      expect(harness.app.playbackState.position, positions[index]);
      expect(harness.app.playbackState.bufferRatio, 0.8);
    }
  });

  test('a failed capability request retries without requiring a new login', () async {
    final connection = _Connection(_AccountServer())..capabilityFailures = 1;
    final harness = _Harness(connection);
    addTearDown(harness.close);

    await harness.start();

    expect(harness.app.authState.isAuthorized, isTrue);
    expect(harness.app.serverCollectionsLoaded, isTrue);
    expect(connection.capabilityReads, 2);
    expect(connection.eventSubscriptions, 1);
  });

  test('an unsupported stream releases authoritative mode and explicit loading still works', () async {
    final server = _AccountServer();
    final connection = _Connection(server);
    final harness = _Harness(connection);
    addTearDown(harness.close);
    await harness.start();

    server.fail('alice', ApiException(404, 'Events unsupported'));
    await _until(() => !harness.app.serverCollectionsLoaded, 'unsupported stream fallback');
    server.account('alice').liked['other'] = true;
    server.account('alice').playlists = [_mix().copyWith(name: 'Loaded explicitly')];
    await harness.app.loadLikedTracks();
    await harness.app.loadPlaylists();

    expect(harness.app.liked.map((track) => track.id), ['other']);
    expect(harness.app.playlists.single.name, 'Loaded explicitly');
    expect(harness.app.authState.isAuthorized, isTrue);
    expect(connection.eventSubscriptions, 1);
    expect(connection.snapshotReads, 1);
  });

  for (final addingFirst in [true, false]) {
    test('an older ${addingFirst ? 'add' : 'remove'} reply cannot undo a newer playlist operation', () async {
      final server = _AccountServer();
      if (!addingFirst) {
        server.account('alice').playlists = [
          _mix().copyWith(trackIds: ['track', 'other']),
        ];
      }

      final connection = _Connection(server);
      final harness = _Harness(connection);
      addTearDown(harness.close);
      await harness.start();
      await harness.app.loadPlaylistTracks('mix');
      final delayed = Completer<Playlist>();
      if (addingFirst) {
        connection.nextAddReply = delayed.future;
      } else {
        connection.nextRemoveReply = delayed.future;
      }

      final first = addingFirst
          ? harness.app.addTrackToPlaylist(harness.app.playlists.single, _track('other'))
          : harness.app.removeTrackFromPlaylist(harness.app.playlists.single, _track('other'));
      await _until(() => server.account('alice').playlists.single.revision == 2, 'first committed operation');
      final older = server.account('alice').playlists.single;
      if (addingFirst) {
        await harness.app.removeTrackFromPlaylist(harness.app.playlists.single, _track('other'));
      } else {
        await harness.app.addTrackToPlaylist(harness.app.playlists.single, _track('other'));
      }

      final observed = <List<String>>[];
      final subscription = harness.app.playlistTracksStream.listen(
        (tracks) => observed.add(tracks.map((track) => track.id).toList()),
      );
      addTearDown(subscription.cancel);
      delayed.complete(older);
      await first;
      await Future<void>.delayed(Duration.zero);
      final expected = addingFirst ? ['track'] : ['track', 'other'];

      expect(harness.app.playlists.single.revision, 3);
      expect(harness.app.playlists.single.trackIds, expected);
      expect(harness.app.playlistTracks.map((track) => track.id), expected);
      for (final ids in observed) {
        expect(ids, expected);
      }
    });
  }

  test('an account switch rejects a late snapshot from the previous account', () async {
    final server = _AccountServer();
    server.accounts['bob'] = _Account(liked: {'other': true}, playlists: []);
    final connection = _Connection(server);
    final harness = _Harness(connection);
    addTearDown(harness.close);
    await harness.start();
    final stale = Completer<AccountCollectionSnapshot>();
    connection.nextSnapshot = stale.future;
    server.account('alice').revision++;
    server.notify('alice');
    await _until(() => connection.snapshotReads == 2, 'old account snapshot request');

    harness.app.loginWithToken(baseUrl: connection.baseUrl, token: 'bob');
    stale.complete(
      AccountCollectionSnapshot(
        userId: 'alice',
        revision: 2,
        likes: [ServerLikeState(trackId: 'track', liked: true, updatedAt: 2)],
        playlists: [_mix()],
      ),
    );
    await _until(() => harness.app.liked.any((track) => track.id == 'other'), 'new account snapshot');

    expect(harness.app.liked.map((track) => track.id), ['other']);
    expect(harness.app.playlists, isEmpty);
    expect(
      connection.applied.where((entry) => entry.token == 'bob').map((entry) => entry.snapshot.userId),
      everyElement('bob'),
    );
    expect(
      connection.applied.where((entry) => entry.snapshot.userId == 'alice').map((entry) => entry.snapshot.revision),
      [1],
    );
    expect(server.cancelledSubscriptions, greaterThanOrEqualTo(1));
  });

  test('a local write supersedes a snapshot already in flight', () async {
    final server = _AccountServer();
    final connection = _Connection(server);
    final harness = _Harness(connection);
    addTearDown(harness.close);
    await harness.start();
    await harness.app.loadTracks('album');
    final stale = Completer<AccountCollectionSnapshot>();
    connection.nextSnapshot = stale.future;
    server.account('alice').revision = 2;
    server.notify('alice');
    await _until(() => connection.snapshotReads == 2, 'stale snapshot request');

    await harness.app.toggleLike(harness.app.tracks.first);
    expect(harness.app.tracks.first.liked, isTrue);
    stale.complete(AccountCollectionSnapshot(userId: 'alice', revision: 2, likes: [], playlists: [_mix()]));
    await _until(() => connection.applied.any((entry) => entry.snapshot.revision == 3), 'post-write reconciliation');

    expect(harness.app.tracks.first.liked, isTrue);
    expect(harness.app.liked.map((track) => track.id), ['track']);
    expect(connection.applied.map((entry) => entry.snapshot.revision), isNot(contains(2)));
  });

  test('an older server keeps explicit collection loading and legacy playlist writes', () async {
    final server = _AccountServer();
    server.account('alice').liked['track'] = true;
    final connection = _Connection(server, supportsSync: false);
    final harness = _Harness(connection);
    addTearDown(harness.close);
    await harness.start();
    await harness.app.loadLikedTracks();
    await harness.app.loadPlaylists();

    expect(harness.app.serverCollectionsLoaded, isFalse);
    expect(harness.app.liked.single.id, 'track');
    expect(harness.app.playlists.single.revision, isNull);
    expect(connection.eventSubscriptions, 0);
    expect(connection.snapshotReads, 0);

    await harness.app.addTrackToPlaylist(harness.app.playlists.single, _track('other'));

    expect(connection.legacyReplacements, 1);
    expect(server.atomicAdds, 0);
    expect(harness.app.playlists.single.trackIds, ['track', 'other']);
  });

  test('a remembered account track is paused at zero until this device starts playback', () async {
    final server = _AccountServer();
    server.account('alice').lastTrackId = 'other';
    final connection = _Connection(server, supportsV2: true);
    final harness = _Harness(connection);
    addTearDown(harness.close);

    await harness.start();
    await _until(() => harness.app.playbackState.track?.id == 'other', 'remembered starting track');

    expect(connection.accountEventSubscriptions, 1);
    expect(harness.audio.starts, 0);
    expect(harness.audio.hasActivePlayer, isFalse);
    expect(harness.app.playbackState.isPlaying, isFalse);
    expect(harness.app.playbackState.isLoading, isFalse);
    expect(harness.app.playbackState.position, Duration.zero);
    expect(connection.reports, isEmpty);

    await harness.app.pause(false);
    await _until(() => harness.audio.starts == 1, 'explicit play');
    expect(harness.audio.startOffsets, [Duration.zero]);
    harness._onStarted!();
    await _until(() => connection.reports.length == 1, 'successful start report');
    expect(connection.reports.single.trackId, 'other');
  });

  test('a late starting-track lookup cannot replace an explicit track selection', () async {
    final server = _AccountServer();
    final connection = _Connection(server, supportsV2: true);
    final pending = Completer<AccountLastTrack>();
    connection.nextLastTrack = pending.future;
    final harness = _Harness(connection);
    addTearDown(harness.close);
    await harness.start();
    await _until(() => connection.lastTrackReads == 1, 'pending starting-track request');

    await harness.app.queueAlbum('album', startTrackId: 'other');
    await _until(() => harness.audio.starts == 1, 'explicit selection');
    pending.complete(const AccountLastTrack(trackId: 'track', revision: 8));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(harness.app.playbackState.track!.id, 'other');
    expect(harness.audio.starts, 1);
    expect(harness.app.playbackState.isPlaying, isTrue);
  });

  test('late starting-track metadata cannot replace playback chosen while it was loading', () async {
    final server = _AccountServer();
    server.account('alice').lastTrackId = 'remembered';
    final connection = _Connection(server, supportsV2: true);
    final metadata = Completer<Track>();
    connection.nextTrackMetadata = metadata.future;
    final harness = _Harness(connection);
    addTearDown(harness.close);
    await harness.start();
    await _until(() => connection.nextTrackMetadata == null, 'starting-track metadata request');

    await harness.app.queueAlbum('album', startTrackId: 'other');
    await _until(() => harness.audio.starts == 1, 'explicit selection');
    metadata.complete(_track('remembered'));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(harness.app.playbackState.track!.id, 'other');
    expect(harness.audio.starts, 1);
  });

  test('an account switch rejects the previous account starting-track response', () async {
    final server = _AccountServer();
    server.account('bob').lastTrackId = 'bob-track';
    final connection = _Connection(server, supportsV2: true);
    final pending = Completer<AccountLastTrack>();
    connection.nextLastTrack = pending.future;
    final harness = _Harness(connection);
    addTearDown(harness.close);
    await harness.start();
    await _until(() => connection.lastTrackReads == 1, 'Alice starting-track request');

    harness.app.loginWithToken(baseUrl: connection.baseUrl, token: 'bob');
    await _until(() => harness.app.playbackState.track?.id == 'bob-track', 'Bob remembered track');
    pending.complete(const AccountLastTrack(trackId: 'alice-track', revision: 9));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(harness.app.playbackState.track!.id, 'bob-track');
    expect(harness.audio.starts, 0);
    expect(harness.app.playbackState.isPlaying, isFalse);
    expect(connection.reports, isEmpty);
  });

  test('only successful starts report a remembered track; pause, seek and repeated callbacks do not', () async {
    final connection = _Connection(_AccountServer(), supportsV2: true);
    final harness = _Harness(connection);
    addTearDown(harness.close);
    await harness.start();
    await _until(() => connection.lastTrackReads == 1, 'starting-track lookup');
    await harness.app.queueAlbum('album');
    await _until(() => harness.audio.starts == 1, 'first audio request');
    expect(connection.reports, isEmpty);

    harness._onStarted!();
    harness._onStarted!();
    await _until(() => connection.reports.length == 1, 'first successful start');
    await harness.app.pause(true);
    await harness.app.pause(false);
    await harness.app.seekTo(const Duration(seconds: 30));
    harness._onStarted!();

    expect(connection.reports, hasLength(1));
    expect(harness.audio.starts, 1);
    expect(harness.audio.seeks, 1);
    await harness.app.nextTrack();
    await _until(() => harness.audio.starts == 2, 'next audio request');
    expect(connection.reports, hasLength(1));
    harness._onStarted!();
    await _until(() => connection.reports.length == 2, 'next successful start');
    expect(connection.reports.map((report) => report.trackId), ['track', 'other']);
    expect(connection.reports.map((report) => report.sequence), [1, 2]);
    expect(connection.reports.map((report) => report.requestId).toSet(), hasLength(2));
    expect(connection.reports.map((report) => report.sessionId).toSet(), hasLength(1));
  });

  for (final failures in [1, 5]) {
    test(
      'a transient track-start report ${failures == 1 ? 'retries the same identity' : 'stops after one retry'}',
      () async {
        final connection = _Connection(_AccountServer(), supportsV2: true);
        connection.reportFailures = failures;
        final harness = _Harness(connection);
        addTearDown(harness.close);
        await harness.start();
        await _until(() => harness.app.accountState?.userId == 'alice', 'account identity');
        await harness.app.queueAlbum('album');
        await _until(() => harness.audio.starts == 1, 'audio request');
        harness._onStarted!();
        await _until(() => connection.reports.length == 2, 'one idempotent retry');

        expect(connection.reports[1], connection.reports[0]);
        expect(connection.reports.first.trackId, 'track');
        expect(connection.reports.first.sequence, 1);
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        expect(connection.reports, hasLength(2));
        expect(connection.server.account('alice').lastTrackId, failures == 1 ? 'track' : isNull);
        expect(harness.audio.starts, 1);
        expect(harness.audio.seeks, 0);
      },
    );
  }

  test('selecting a new track retires a pending report retry for the previous selection', () async {
    final connection = _Connection(_AccountServer(), supportsV2: true);
    connection.reportFailures = 1;
    final harness = _Harness(connection);
    addTearDown(harness.close);
    await harness.start();
    await _until(() => harness.app.accountState?.userId == 'alice', 'account identity');
    await harness.app.queueAlbum('album');
    await _until(() => harness.audio.starts == 1, 'first audio request');
    harness._onStarted!();
    await _until(() => connection.reports.length == 1, 'failed first report');
    await Future<void>.delayed(Duration.zero);

    await harness.app.nextTrack();
    await _until(() => harness.audio.starts == 2, 'next audio request');
    harness._onStarted!();
    await _until(() => connection.reports.length == 2, 'new selection report');
    await Future<void>.delayed(const Duration(milliseconds: 1200));

    expect(connection.reports, hasLength(2));
    expect(connection.reports.map((report) => report.trackId), ['track', 'other']);
    expect(connection.reports.map((report) => report.sequence), [1, 2]);
    expect(connection.server.account('alice').lastTrackId, 'other');
  });

  for (final accountSwitch in [false, true]) {
    test(
      '${accountSwitch ? 'switching accounts' : 'stopping playback'} retires a pending track-start report retry',
      () async {
        final connection = _Connection(_AccountServer(), supportsV2: true);
        connection.reportFailures = 1;
        final harness = _Harness(connection);
        addTearDown(harness.close);
        await harness.start();
        await _until(() => harness.app.accountState?.userId == 'alice', 'account identity');
        await harness.app.queueAlbum('album');
        await _until(() => harness.audio.starts == 1, 'audio request');
        harness._onStarted!();
        await _until(() => connection.reports.length == 1, 'failed report');
        await Future<void>.delayed(Duration.zero);

        if (accountSwitch) {
          harness.app.loginWithToken(baseUrl: connection.baseUrl, token: 'bob');
          await _until(() => harness.app.accountState?.userId == 'bob', 'new account identity');
        } else {
          await harness.app.stop();
        }
        await Future<void>.delayed(const Duration(milliseconds: 1200));

        expect(connection.reports, hasLength(1));
        expect(connection.reports.single.userId, 'alice');
        expect(connection.server.account('alice').lastTrackId, isNull);
        expect(connection.server.account('bob').lastTrackId, isNull);
      },
    );
  }

  test('downloaded playback never reports a remembered account track', () async {
    final directory = await Directory.systemTemp.createTemp('phonolite-start-report-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/download.opus');
    await file.writeAsBytes([0]);
    final connection = _Connection(_AccountServer(), supportsV2: true);
    final harness = _Harness(connection, localFilePath: file.path);
    addTearDown(harness.close);
    await harness.start();

    await harness.app.playOfflineTrack('local');
    await _until(() => harness.audio.localStarts == 1, 'fake local audio start');
    harness._onStarted!();
    await Future<void>.delayed(Duration.zero);

    expect(harness.app.playbackState.isLocalPlayback, isTrue);
    expect(connection.reports, isEmpty);
    expect(connection.server.account('alice').lastTrackId, isNull);
  });

  test('two playing apps receive account preset events without changing their active rules or audio', () async {
    final server = _AccountServer();
    final first = _Harness(_Connection(server, supportsV2: true));
    final second = _Harness(_Connection(server, supportsV2: true));
    addTearDown(first.close);
    addTearDown(second.close);
    await Future.wait([first.start(), second.start()]);
    await _until(() => first.app.shufflePresetsAvailable && second.app.shufflePresetsAvailable, 'preset capabilities');
    await Future.wait([first.playAndOpenPlaylist(), second.playAndOpenPlaylist()]);
    await first.app.updateCustomShuffleSettings(artistIds: ['first-device'], genres: ['jazz']);
    await second.app.updateCustomShuffleSettings(artistIds: ['second-device'], genres: ['rock']);
    final secondPosition = second.app.playbackState.position;
    final secondStops = second.audio.stops;

    await first.app.saveShufflePreset(name: 'Shared rules', artistIds: ['shared'], genres: ['ambient']);
    await _until(() => second.app.shufflePresets.any((preset) => preset.name == 'Shared rules'), 'remote preset event');

    expect(first.app.customShuffleSettings.artistIds, ['first-device']);
    expect(second.app.customShuffleSettings.artistIds, ['second-device']);
    expect(second.app.customShuffleSettings.genres, ['rock']);
    expect(first.audio.starts, 1);
    expect(second.audio.starts, 1);
    expect(second.audio.stops, secondStops);
    expect(second.audio.seeks, 0);
    expect(second.app.playbackState.position, secondPosition);
    expect(second.app.playbackState.isPlaying, isTrue);

    await first.app.applyShufflePreset(first.app.shufflePresets.single);
    expect(first.app.customShuffleSettings.artistIds, ['shared']);
    expect(second.app.customShuffleSettings.artistIds, ['second-device']);
    expect(second.audio.starts, 1);
    expect(second.app.playbackState.position, secondPosition);
  });

  test('statistics account events refresh statistics without reloading unchanged presets', () async {
    final server = _AccountServer();
    server.account('alice').presetRevision = 1;
    server.account('alice').presets = [
      ShufflePreset(id: 'initial', name: 'Initial rules', artistIds: ['artist'], genres: [], revision: 1),
    ];
    final connection = _Connection(server, supportsV2: true);
    final harness = _Harness(connection);
    addTearDown(harness.close);
    await harness.start();
    await _until(() => harness.app.shufflePresets.any((preset) => preset.id == 'initial'), 'initial account snapshot');
    final presetsBefore = connection.presetReads;
    final countersBefore = connection.counterReads;
    final collectionsBefore = connection.snapshotReads;

    server.account('alice').statisticsRevision++;
    server.notifyAccount('alice');
    await _until(() => connection.counterReads > countersBefore, 'remote statistics refresh');

    expect(connection.presetReads, presetsBefore);
    expect(connection.snapshotReads, collectionsBefore);
    expect(harness.audio.starts, 0);
    expect(harness.app.playbackState.track, isNull);
  });

  test('catalogue background refresh retains tracks and search without loading or restarting playback', () async {
    final server = _AccountServer();
    final connection = _Connection(server, supportsV2: true);
    final harness = _Harness(connection);
    addTearDown(harness.close);
    await harness.start();
    await harness.app.loadArtists();
    await harness.playAndOpenPlaylist();
    await harness.app.search('track', filter: 'track');
    expect(harness.app.searchResults.single.title, 'track');
    final position = harness.app.playbackState.position;
    final stops = harness.audio.stops;
    final trackReads = connection.trackReads;
    final searchReads = connection.searchReads;
    final artistReads = connection.artistReads;
    final artistPage = Completer<ArtistSummaryPage>();
    final trackPage = Completer<List<Track>>();
    final searchPage = Completer<List<SearchResult>>();
    connection.nextArtistSummariesPage = artistPage.future;
    connection.nextTracks = trackPage.future;
    connection.nextSearch = searchPage.future;
    addTearDown(() {
      if (!artistPage.isCompleted) {
        artistPage.complete(ArtistSummaryPage(items: [], total: 0, browseRevision: server.catalogueRevision));
      }
      if (!trackPage.isCompleted) trackPage.complete([]);
      if (!searchPage.isCompleted) searchPage.complete([]);
    });
    final trackSnapshots = <List<Track>>[];
    final searchSnapshots = <List<SearchResult>>[];
    final loading = <bool>[];
    final subscriptions = [
      harness.app.tracksStream.listen(trackSnapshots.add),
      harness.app.searchStream.listen(searchSnapshots.add),
      harness.app.artistsLoadingStream.listen(loading.add),
      harness.app.tracksLoadingStream.listen(loading.add),
      harness.app.searchLoadingStream.listen(loading.add),
    ];
    addTearDown(() => Future.wait(subscriptions.map((subscription) => subscription.cancel())));

    void expectPreviousContent() {
      expect(harness.app.tracks.first.title, 'track');
      expect(harness.app.searchResults.single.title, 'track');
      expect(harness.app.artistsLoading, isFalse);
      expect(harness.app.tracksLoading, isFalse);
      expect(harness.app.searchLoading, isFalse);
    }

    server.catalogueTitle = 'Rescanned ';
    server.catalogueRevision = 'rescan-2';
    connection.metadataEvents.add(MetadataUpdateEvent(revision: 1, kind: 'catalogue', id: 'rescan-2', updatedAt: 1));
    await _until(() => connection.artistReads > artistReads, 'pending catalogue artist refresh');
    expectPreviousContent();
    artistPage.complete(ArtistSummaryPage(items: [], total: 0, browseRevision: server.catalogueRevision));
    await _until(() => connection.trackReads > trackReads, 'pending catalogue track refresh');
    expectPreviousContent();
    trackPage.complete([connection._remoteTrack('track'), connection._remoteTrack('other')]);
    await _until(() => connection.searchReads > searchReads, 'pending catalogue search refresh');
    expect(harness.app.tracks.first.title, 'Rescanned track');
    expect(harness.app.searchResults.single.title, 'track');
    expect(harness.app.searchLoading, isFalse);
    searchPage.complete([SearchResult(kind: 'track', id: 'track', title: 'Rescanned track', albumId: 'album')]);
    await _until(
      () =>
          harness.app.tracks.isNotEmpty &&
          harness.app.searchResults.isNotEmpty &&
          harness.app.tracks.first.title == 'Rescanned track' &&
          harness.app.searchResults.single.title == 'Rescanned track',
      'catalogue refresh',
    );

    expect(connection.trackReads, greaterThan(trackReads));
    expect(connection.searchReads, greaterThan(searchReads));
    expect(connection.artistReads, greaterThanOrEqualTo(1));
    expect(trackSnapshots, isNotEmpty);
    expect(trackSnapshots.every((tracks) => tracks.isNotEmpty), isTrue);
    expect(searchSnapshots, isNotEmpty);
    expect(searchSnapshots.every((results) => results.isNotEmpty), isTrue);
    expect(loading, isNot(contains(true)));
    expect(harness.audio.starts, 1);
    expect(harness.audio.stops, stops);
    expect(harness.audio.seeks, 0);
    expect(harness.app.playbackState.isPlaying, isTrue);
    expect(harness.app.playbackState.track!.id, 'track');
    expect(harness.app.playbackState.position, position);
  });

  test('failed catalogue track refresh retains visible tracks and the next marker retries them', () async {
    final server = _AccountServer();
    final connection = _Connection(server, supportsV2: true);
    final harness = _Harness(connection);
    addTearDown(harness.close);
    await harness.start();
    await harness.app.loadArtists();
    await harness.app.loadTracks('album');
    await harness.app.search('track', filter: 'track');
    final trackReads = connection.trackReads;
    final searchReads = connection.searchReads;
    final response = Completer<List<Track>>();
    connection.nextTracks = response.future;
    addTearDown(() {
      if (!response.isCompleted) response.complete([]);
    });
    final snapshots = <List<Track>>[];
    final subscription = harness.app.tracksStream.listen(snapshots.add);
    addTearDown(subscription.cancel);
    server.catalogueTitle = 'Recovered ';
    server.catalogueRevision = 'rescan-2';
    connection.metadataEvents.add(MetadataUpdateEvent(revision: 1, kind: 'catalogue', id: 'rescan-2', updatedAt: 1));
    await _until(() => connection.trackReads > trackReads, 'pending failed catalogue refresh');
    expect(harness.app.tracks.first.title, 'track');
    expect(harness.app.tracksLoading, isFalse);
    response.completeError(StateError('Temporary catalogue read failure'));
    await _until(() => connection.searchReads > searchReads, 'catalogue refresh after failed track read');

    expect(harness.app.tracks.first.title, 'track');
    expect(harness.app.tracksLoading, isFalse);
    expect(harness.app.searchResults.single.title, 'Recovered track');
    connection.metadataEvents.add(MetadataUpdateEvent(revision: 2, kind: 'catalogue', id: 'rescan-2', updatedAt: 2));
    await _until(() => harness.app.tracks.first.title == 'Recovered track', 'catalogue retry replacement');
    expect(snapshots.every((tracks) => tracks.isNotEmpty), isTrue);
    expect(harness.app.tracksLoading, isFalse);
  });

  test('authorized account switches immediately clear presets even when revision clocks are equal', () async {
    final server = _AccountServer();
    server.account('alice').presetRevision = 3;
    server.account('alice').presets = [_rules('alice')];
    server.account('bob').presetRevision = 3;
    server.account('bob').presets = [_rules('bob')];
    final connection = _Connection(server, supportsV2: true);
    final harness = _Harness(connection);
    addTearDown(harness.close);
    await harness.start();
    await _until(() => harness.app.accountState?.userId == 'alice', 'Alice account state');
    expect(harness.app.shufflePresets.single.id, 'alice');
    final pending = Completer<ShufflePresetSnapshot>();
    connection.nextPresetSnapshot = pending.future;
    final reads = connection.presetReads;

    harness.app.loginWithToken(baseUrl: connection.baseUrl, token: 'bob');
    expect(harness.app.shufflePresets, isEmpty);
    expect(harness.app.accountState, isNull);
    expect(harness.app.shufflePresetsAvailable, isFalse);
    await _until(() => connection.presetReads > reads, 'Bob preset request at equal revision');
    pending.complete(ShufflePresetSnapshot(revision: 3, items: server.account('bob').presets));
    await _until(() => harness.app.accountState?.userId == 'bob', 'Bob account state');

    expect(harness.app.shufflePresets.single.id, 'bob');
    expect(harness.app.authState.isAuthorized, isTrue);
  });

  test('a new ready event reloads presets at unchanged account clocks', () async {
    final server = _AccountServer();
    server.account('alice').presetRevision = 3;
    server.account('alice').presets = [_rules('rules', name: 'Before reconnect')];
    final connection = _Connection(server, supportsV2: true);
    final harness = _Harness(connection);
    addTearDown(harness.close);
    await harness.start();
    await _until(() => harness.app.accountState?.userId == 'alice', 'initial account snapshot');
    final reads = connection.presetReads;
    server.account('alice').presets = [_rules('rules', name: 'Recovered snapshot')];

    server.notifyAccount('alice', kind: RevisionEventKind.ready);
    await _until(() => harness.app.shufflePresets.single.name == 'Recovered snapshot', 'ready snapshot reconciliation');

    expect(connection.presetReads, greaterThan(reads));
    expect(harness.audio.starts, 0);
    expect(harness.app.accountState!.revisions.presets, 3);
  });

  test('an account change with unchanged clocks refreshes username and role', () async {
    final server = _AccountServer();
    final connection = _Connection(server, supportsV2: true);
    final harness = _Harness(connection);
    addTearDown(harness.close);
    await harness.start();
    await _until(() => harness.app.accountState?.userId == 'alice', 'initial account identity');
    final seen = <AccountState?>[];
    final subscription = harness.app.accountStateStream.listen(seen.add);
    addTearDown(subscription.cancel);
    final reads = connection.accountStateReads;
    server.account('alice').username = 'renamed-alice';
    server.account('alice').role = 'admin';

    server.notifyAccount('alice');
    await _until(() => harness.app.accountState?.username == 'renamed-alice', 'same-clock profile change');

    expect(connection.accountStateReads, greaterThan(reads));
    expect(harness.app.accountState!.role, 'admin');
    expect(harness.app.accountState!.revisions.presets, 0);
    expect(seen.whereType<AccountState>().last.role, 'admin');
    expect(harness.audio.starts, 0);
  });

  test('a pending preset write from the old account cannot block or overwrite the next account', () async {
    final server = _AccountServer();
    server.account('alice').presetRevision = 3;
    server.account('alice').presets = [_rules('alice')];
    server.account('bob').presetRevision = 3;
    server.account('bob').presets = [_rules('bob')];
    final connection = _Connection(server, supportsV2: true);
    final harness = _Harness(connection);
    addTearDown(harness.close);
    await harness.start();
    await _until(() => harness.app.accountState?.userId == 'alice', 'Alice account snapshot');
    final reply = Completer<ShufflePreset>();
    connection.nextPresetWrite = reply.future;
    final oldWrite = harness.app.saveShufflePreset(name: 'Alice pending', artistIds: ['alice'], genres: []);
    await _until(() => connection.nextPresetWrite == null, 'old account write');
    final savedAlice = server.account('alice').presets.last;

    harness.app.loginWithToken(baseUrl: connection.baseUrl, token: 'bob');
    await _until(() => harness.app.accountState?.userId == 'bob', 'new account while old write is pending');
    expect(harness.app.shufflePresets.single.id, 'bob');
    await harness.app.saveShufflePreset(name: 'Bob new rules', artistIds: ['bob-new'], genres: []);
    expect(harness.app.shufflePresets.any((preset) => preset.name == 'Bob new rules'), isTrue);
    reply.complete(savedAlice);
    await oldWrite;
    await Future<void>.delayed(Duration.zero);

    expect(harness.app.accountState!.userId, 'bob');
    expect(harness.app.shufflePresets.any((preset) => preset.name == 'Alice pending'), isFalse);
    expect(harness.app.shufflePresets.any((preset) => preset.id == 'alice'), isFalse);
  });

  test(
    'scoped filter loads clear immediately on account change and late loads cannot bleed into the next account',
    () async {
      final storage = _ScopedShuffleSettings();
      final connection = _Connection(_AccountServer(), supportsV2: true);
      final harness = _Harness(connection, shuffleStorage: storage);
      addTearDown(harness.close);
      await harness.start();
      await _until(() => harness.app.customShuffleArtistIds.contains('alice-artist'), 'Alice scoped filters');
      expect(harness.app.localCustomShuffleArtistIds, ['downloaded-artist']);
      expect(harness.app.customShuffleArtistIds, isNot(contains('legacy-unscoped')));
      final delayed = Completer<CustomShuffleSettings>();
      storage.nextReads['alice'] = delayed.future;
      final loading = harness.app.loadCustomShuffleSettings();
      await _until(() => !storage.nextReads.containsKey('alice'), 'pending Alice scoped reload');

      harness.app.loginWithToken(baseUrl: connection.baseUrl, token: 'bob');
      expect(harness.app.customShuffleArtistIds, isEmpty);
      expect(harness.app.localCustomShuffleArtistIds, ['downloaded-artist']);
      await _until(() => harness.app.customShuffleArtistIds.contains('bob-artist'), 'Bob scoped filters');
      delayed.complete(const CustomShuffleSettings(artistIds: ['late-alice'], genres: ['late']));
      await loading;

      expect(harness.app.customShuffleArtistIds, ['bob-artist']);
      expect(harness.app.customShuffleGenres, ['ambient']);
      expect(harness.app.localCustomShuffleArtistIds, ['downloaded-artist']);
      expect(harness.app.localCustomShuffleGenres, ['rock']);
      expect(storage.reads.any((scope) => scope.endsWith('/alice')), isTrue);
      expect(storage.reads.any((scope) => scope.endsWith('/bob')), isTrue);
    },
  );

  for (final stillPlaying in [true, false]) {
    test(
      'opening a new app remembers the ${stillPlaying ? 'current' : 'ended'} track with independent position',
      () async {
        final server = _AccountServer();
        final first = _Harness(_Connection(server, supportsV2: true));
        final second = _Harness(_Connection(server, supportsV2: true));
        addTearDown(first.close);
        addTearDown(second.close);
        await first.start();
        await _until(() => first.app.accountState?.userId == 'alice', 'first account identity');
        await first.playAndOpenPlaylist();
        await _until(() => server.account('alice').lastTrackId == 'track', 'remember current track');
        if (!stillPlaying) {
          await first.app.stop();
        }
        final position = first.app.playbackState.position;
        final stops = first.audio.stops;

        await second.start();
        await _until(() => second.app.playbackState.track?.id == 'track', 'new device remembered track');
        expect(second.audio.starts, 0);
        expect(second.app.playbackState.isPlaying, isFalse);
        expect(second.app.playbackState.position, Duration.zero);
        await second.app.pause(false);
        await _until(() => second.audio.starts == 1, 'new device explicit start');

        expect(second.audio.startOffsets.single, Duration.zero);
        expect(first.audio.starts, 1);
        expect(first.audio.stops, stops);
        expect(first.audio.seeks, 0);
        expect(first.app.playbackState.position, position);
        expect(first.app.playbackState.isPlaying, stillPlaying);
      },
    );
  }
}

Future<void> _until(bool Function() predicate, String operation) async {
  final timeout = DateTime.now().add(const Duration(seconds: 5));

  while (!predicate()) {
    if (DateTime.now().isAfter(timeout)) {
      fail('Timed out waiting for $operation');
    }

    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Track _track(String id) => offlineTestTrack(id: id, title: id);

Playlist _mix({int? revision = 1}) => Playlist(id: 'mix', name: 'Mix', trackIds: ['track'], revision: revision);

ShufflePreset _rules(String id, {String? name, int revision = 3}) =>
    ShufflePreset(id: id, name: name ?? '$id rules', artistIds: ['$id-artist'], genres: [], revision: revision);

class _Account {
  final Map<String, bool> liked;
  List<Playlist> playlists;
  int revision = 1;
  int presetRevision = 0;
  int statisticsRevision = 0;
  List<ShufflePreset> presets = [];
  String? lastTrackId;
  int lastTrackRevision = 0;
  String? username;
  String role = 'user';

  _Account({Map<String, bool>? liked, List<Playlist>? playlists})
    : liked = liked ?? {'track': false},
      playlists = playlists ?? [_mix()];

  AccountRevisions get revisions =>
      AccountRevisions(collections: revision, presets: presetRevision, statistics: statisticsRevision);

  AccountCollectionSnapshot snapshot(String userId) => AccountCollectionSnapshot(
    userId: userId,
    revision: revision,
    likes: liked.entries.map((entry) => ServerLikeState(trackId: entry.key, liked: entry.value, updatedAt: revision)),
    playlists: playlists,
  );
}

class _AccountServer {
  final Map<String, _Account> accounts = {'alice': _Account()};
  final Map<String, Set<StreamController<AccountCollectionEvent>>> _subscribers = {};
  final Map<String, Set<StreamController<RevisionEvent<AccountRevisions>>>> _accountSubscribers = {};
  int atomicAdds = 0;
  int cancelledSubscriptions = 0;
  String catalogueTitle = '';
  String catalogueRevision = 'initial';

  Stream<RevisionEvent<AccountRevisions>> subscribeAccount(String userId) {
    late final StreamController<RevisionEvent<AccountRevisions>> controller;
    controller = StreamController<RevisionEvent<AccountRevisions>>(
      onListen: () {
        _accountSubscribers.putIfAbsent(userId, () => {}).add(controller);
        controller.add(RevisionEvent(kind: RevisionEventKind.ready, revision: account(userId).revisions));
      },
      onCancel: () => _accountSubscribers[userId]?.remove(controller),
    );

    return controller.stream;
  }

  void notifyAccount(String userId, {RevisionEventKind kind = RevisionEventKind.changed}) {
    for (final subscriber in _accountSubscribers[userId] ?? <StreamController<RevisionEvent<AccountRevisions>>>{}) {
      subscriber.add(RevisionEvent(kind: kind, revision: account(userId).revisions));
    }
  }

  _Account account(String userId) => accounts.putIfAbsent(userId, _Account.new);

  Stream<AccountCollectionEvent> subscribe(String userId) {
    late final StreamController<AccountCollectionEvent> controller;
    controller = StreamController<AccountCollectionEvent>(
      onListen: () {
        _subscribers.putIfAbsent(userId, () => {}).add(controller);
        controller.add(
          AccountCollectionEvent(kind: AccountCollectionEventKind.ready, revision: account(userId).revision),
        );
      },
      onCancel: () {
        _subscribers[userId]?.remove(controller);
        cancelledSubscriptions++;
      },
    );

    return controller.stream;
  }

  void fail(String userId, Object error) {
    for (final subscriber in _subscribers[userId] ?? <StreamController<AccountCollectionEvent>>{}) {
      subscriber.addError(error);
    }
  }

  void notify(String userId) {
    final revision = account(userId).revision;

    for (final subscriber in _subscribers[userId] ?? <StreamController<AccountCollectionEvent>>{}) {
      subscriber.add(AccountCollectionEvent(kind: AccountCollectionEventKind.collectionsChanged, revision: revision));
    }

    notifyAccount(userId);
  }
}

class _Connection extends ServerConnection {
  final _AccountServer server;
  final bool supportsSync;
  final bool supportsV2;
  final metadataEvents = StreamController<MetadataUpdateEvent>.broadcast();
  final reports = <({String userId, String trackId, String sessionId, int sequence, String requestId})>[];
  Future<AccountLastTrack>? nextLastTrack;
  Future<Track>? nextTrackMetadata;
  Future<ArtistSummaryPage>? nextArtistSummariesPage;
  Future<List<Track>>? nextTracks;
  Future<List<SearchResult>>? nextSearch;
  Future<AccountState>? nextAccountState;
  Future<ShufflePresetSnapshot>? nextPresetSnapshot;
  Future<ShufflePreset>? nextPresetWrite;
  int accountEventSubscriptions = 0;
  int accountStateReads = 0;
  int presetReads = 0;
  int lastTrackReads = 0;
  int counterReads = 0;
  int searchReads = 0;
  int trackReads = 0;
  int artistReads = 0;
  int reportFailures = 0;
  Future<AccountCollectionSnapshot>? nextSnapshot;
  Future<Playlist>? nextAddReply;
  Future<Playlist>? nextRemoveReply;
  int capabilityFailures = 0;
  int capabilityReads = 0;
  final applied = <({String token, AccountCollectionSnapshot snapshot})>[];
  int snapshotReads = 0;
  int eventSubscriptions = 0;
  int legacyReplacements = 0;

  _Connection(this.server, {this.supportsSync = true, this.supportsV2 = false})
    : super(baseUrl: 'https://music.test/api', client: MockClient((_) async => http.Response('unsupported', 404))) {
    setTrust(testServerTrust);
  }

  String get _userId => token ?? 'alice';

  @override
  Future<ServerCapabilities> fetchCapabilities() async {
    capabilityReads++;

    if (capabilityFailures > 0) {
      capabilityFailures--;

      throw StateError('Temporary capability failure');
    }

    return ServerCapabilities(
      downloadJobsV2: false,
      metadataSnapshotsV2: false,
      eventReplayV2: false,
      trackFileContractV2: false,
      accountCollectionsSync: supportsSync,
      atomicPlaylistTracks: supportsSync,
      accountEventsV2: supportsV2,
      shufflePresets: supportsV2,
      lastTrack: supportsV2,
      catalogueEvents: supportsV2,
    );
  }

  @override
  Stream<AccountCollectionEvent> streamCollectionEvents() {
    eventSubscriptions++;

    return server.subscribe(_userId);
  }

  @override
  Future<AccountCollectionSnapshot> fetchCollectionSnapshot() {
    snapshotReads++;
    final pending = nextSnapshot;
    nextSnapshot = null;

    return pending ?? Future.value(server.account(_userId).snapshot(_userId));
  }

  @override
  void applyCollectionSnapshot(AccountCollectionSnapshot snapshot) {
    applied.add((token: _userId, snapshot: snapshot));
    super.applyCollectionSnapshot(snapshot);
  }

  @override
  Stream<MetadataUpdateEvent> streamMetadataEvents() => supportsV2 ? metadataEvents.stream : const Stream.empty();

  @override
  Stream<RevisionEvent<AccountRevisions>> streamAccountEvents() {
    accountEventSubscriptions++;

    return server.subscribeAccount(_userId);
  }

  @override
  Future<AccountState> fetchAccountState() {
    accountStateReads++;
    final pending = nextAccountState;
    nextAccountState = null;

    return pending ??
        Future.value(
          AccountState(
            userId: _userId,
            username: server.account(_userId).username ?? _userId,
            role: server.account(_userId).role,
            revisions: server.account(_userId).revisions,
          ),
        );
  }

  @override
  Future<ShufflePresetSnapshot> fetchShufflePresets() async {
    presetReads++;
    final pending = nextPresetSnapshot;
    nextPresetSnapshot = null;
    final account = server.account(_userId);

    return pending ?? ShufflePresetSnapshot(revision: account.presetRevision, items: account.presets);
  }

  @override
  Future<ShufflePreset> createShufflePreset({
    required String name,
    required List<String> artistIds,
    required List<String> genres,
  }) async {
    final account = server.account(_userId);
    final revision = ++account.presetRevision;
    final preset = ShufflePreset(
      id: 'preset-$revision',
      name: name,
      artistIds: artistIds,
      genres: genres,
      revision: revision,
    );
    account.presets = [...account.presets, preset];
    server.notifyAccount(_userId);
    final pending = nextPresetWrite;
    nextPresetWrite = null;

    return pending ?? preset;
  }

  @override
  Future<AccountLastTrack> fetchAccountLastTrack() async {
    lastTrackReads++;
    final pending = nextLastTrack;
    nextLastTrack = null;
    final account = server.account(_userId);

    return pending ?? AccountLastTrack(trackId: account.lastTrackId, revision: account.lastTrackRevision);
  }

  @override
  Future<AccountLastTrack> reportAccountTrackStart({
    required String trackId,
    required String sessionId,
    required int sequence,
    required String requestId,
  }) async {
    reports.add((userId: _userId, trackId: trackId, sessionId: sessionId, sequence: sequence, requestId: requestId));

    if (reportFailures > 0) {
      reportFailures--;

      throw const SocketException('Temporary report transport failure');
    }

    final account = server.account(_userId);
    account.lastTrackId = trackId;

    return AccountLastTrack(trackId: trackId, revision: ++account.lastTrackRevision);
  }

  @override
  Future<Map<String, dynamic>> fetchListeningCounterState({required String deviceId}) async {
    if (!supportsV2) {
      return super.fetchListeningCounterState(deviceId: deviceId);
    }

    counterReads++;

    return {
      'server_id': 'in-process-server',
      'user_id': _userId,
      'history_generation': 1,
      'collection_enabled': false,
      'device_enabled': true,
      'preference_revision': 0,
      'checkpoint': {'upgraded': true, 'last_sequence': 0},
      'months': <Object>[],
    };
  }

  @override
  Future<Map<String, dynamic>> updateListeningPreference({
    required String deviceId,
    required bool enabled,
    required int revision,
  }) async => supportsV2
      ? {'enabled': enabled, 'revision': revision}
      : await super.updateListeningPreference(deviceId: deviceId, enabled: enabled, revision: revision);

  @override
  Future<ArtistSummaryPage> fetchArtistSummariesPage({int limit = 60, int offset = 0, String? revision}) async {
    artistReads++;
    final pending = nextArtistSummariesPage;
    nextArtistSummariesPage = null;

    return pending ?? ArtistSummaryPage(items: [], total: 0, browseRevision: server.catalogueRevision);
  }

  @override
  Future<List<SearchResult>> search(String query, {String filter = 'all'}) async {
    searchReads++;
    final pending = nextSearch;
    nextSearch = null;

    return pending ??
        [SearchResult(kind: 'track', id: 'track', title: '${server.catalogueTitle}track', albumId: 'album')];
  }

  @override
  Future<PlaybackSettingsResponse> fetchPlaybackSettings({
    Duration timeout = const Duration(seconds: 8),
    bool retryable = true,
  }) async => PlaybackSettingsResponse(repeatMode: 'off');

  @override
  Future<ServerPortsResponse> fetchServerPorts({
    Duration timeout = const Duration(seconds: 8),
    bool retryable = true,
  }) async => ServerPortsResponse(httpPort: 8000, quicPort: 8001, quicEnabled: true);

  @override
  Future<int?> pingHealthMs({Duration timeout = const Duration(seconds: 3)}) async => 1;

  @override
  Future<List<Track>> fetchTracks(String albumId) async {
    trackReads++;
    final pending = nextTracks;
    nextTracks = null;

    return pending ?? [_remoteTrack('track'), _remoteTrack('other')];
  }

  @override
  Future<Track> fetchTrackById(String trackId) async {
    final pending = nextTrackMetadata;
    nextTrackMetadata = null;

    return pending ?? _remoteTrack(trackId);
  }

  @override
  Future<List<Track>> fetchLikedTracks() async => [
    for (final entry in server.account(_userId).liked.entries)
      if (entry.value) _remoteTrack(entry.key),
  ];

  @override
  Future<List<Playlist>> fetchPlaylists() async => [
    for (final playlist in server.account(_userId).playlists)
      supportsSync ? playlist : playlist.copyWith(revision: null),
  ];

  @override
  Future<List<Track>> fetchPlaylistTracks(String playlistId) async => [
    for (final playlist in server.account(_userId).playlists)
      if (playlist.id == playlistId)
        for (final trackId in playlist.trackIds) _remoteTrack(trackId),
  ];

  @override
  Future<ServerLikeState?> setLikeState(String trackId, bool liked) async {
    final userId = _userId;
    final account = server.account(userId);
    account.liked[trackId] = liked;
    account.revision++;
    server.notify(userId);

    return ServerLikeState(trackId: trackId, liked: liked, updatedAt: account.revision);
  }

  @override
  Future<Playlist> addPlaylistTracks(String playlistId, List<String> trackIds) async {
    server.atomicAdds++;
    final current = server.account(_userId).playlists.singleWhere((playlist) => playlist.id == playlistId);
    final updated = _writePlaylist(
      current.copyWith(trackIds: [...current.trackIds, ...trackIds.where((id) => !current.trackIds.contains(id))]),
    );
    final pending = nextAddReply;
    nextAddReply = null;

    return pending ?? updated;
  }

  @override
  Future<Playlist> removePlaylistTracks(String playlistId, List<String> trackIds) async {
    final current = server.account(_userId).playlists.singleWhere((playlist) => playlist.id == playlistId);
    final updated = _writePlaylist(
      current.copyWith(trackIds: current.trackIds.where((id) => !trackIds.contains(id)).toList()),
    );
    final pending = nextRemoveReply;
    nextRemoveReply = null;

    return pending ?? updated;
  }

  @override
  Future<Playlist> updatePlaylistTracks(String playlistId, List<String> trackIds) async {
    legacyReplacements++;
    final current = server.account(_userId).playlists.singleWhere((playlist) => playlist.id == playlistId);
    final updated = _writePlaylist(current.copyWith(trackIds: trackIds));

    return supportsSync ? updated : updated.copyWith(revision: null);
  }

  @override
  Future<Playlist> renamePlaylist(String playlistId, String name, {String? description}) async {
    final current = server.account(_userId).playlists.singleWhere((playlist) => playlist.id == playlistId);

    return _writePlaylist(current.copyWith(name: name, description: description));
  }

  @override
  Future<void> deletePlaylist(String playlistId) async {
    final account = server.account(_userId);
    account.playlists = account.playlists.where((playlist) => playlist.id != playlistId).toList();
    account.revision++;
    server.notify(_userId);
  }

  Track _remoteTrack(String id) {
    final account = server.account(_userId);

    return _track(id).copyWith(
      title: '${server.catalogueTitle}$id',
      liked: account.liked[id] ?? false,
      inPlaylists: account.playlists.any((playlist) => playlist.trackIds.contains(id)),
    );
  }

  Playlist _writePlaylist(Playlist playlist) {
    final account = server.account(_userId);
    final updated = playlist.copyWith(revision: (playlist.revision ?? 0) + 1);
    account.playlists = [for (final current in account.playlists) current.id == playlist.id ? updated : current];
    account.revision++;
    server.notify(_userId);

    return updated;
  }
}

class _Harness {
  final _Connection connection;
  final audio = _Audio();
  final nowPlaying = _NowPlaying();
  final _Downloads downloads;
  late final AppController app;
  void Function()? _onStarted;
  void Function(Duration, Duration, double?, int?, bool)? _onStats;

  _Harness(this.connection, {String? localFilePath, CustomShuffleSettingsStorage? shuffleStorage})
    : downloads = _Downloads(localFilePath) {
    app = AppController(
      connection: connection,
      audioEngineFactory: ({onMessage, onStats, onComplete, onStarted, onState}) {
        _onStarted = onStarted;
        _onStats = onStats;

        return audio;
      },
      offlineDownloadManager: downloads,
      offlineStorage: _Storage(),
      customShuffleStorage: shuffleStorage ?? _ShuffleSettings(),
      playbackPreferencesStorage: _Preferences(),
      connectivitySignalSource: _Connectivity(),
      nowPlayingPlatformService: nowPlaying,
      vehicleSurfaceService: _Vehicle(),
      localNetworkPermissionService: _Permissions(),
      listeningStatsService: ListeningStatsService(inMemory: true),
    );
  }

  Future<void> start() async {
    await app.initialize();
    app.loginWithToken(baseUrl: connection.baseUrl, token: 'alice');

    if (connection.supportsSync) {
      await _until(() => app.serverCollectionsLoaded, 'initial snapshot');
    } else {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> playAndOpenPlaylist() async {
    await app.loadTracks('album');
    await app.loadPlaylistTracks('mix');
    await app.queueAlbum('album');
    await _until(() => audio.starts == 1, 'initial playback');
    _onStarted!();
    _onStats!(const Duration(seconds: 42), const Duration(seconds: 102), 192, 20, false);
  }

  Future<void> close() async {
    await app.close();
    await connection.metadataEvents.close();
    connection.close();
  }
}

class _Audio extends Fake implements AudioEngine {
  @override
  void Function(int)? onGaplessTransition;
  @override
  void Function(bool)? onGaplessBuffering;
  @override
  void acknowledgeGaplessTransition(int preparationId) {}
  @override
  void setGaplessResampling(bool enabled) {}
  @override
  void Function(int)? onGaplessPreparationFailed;
  @override
  Future<void> prepareNext({
    required int preparationId,
    int? afterPreparationId,
    required Track track,
    required ServerConnection connection,
    required StreamSettings settings,
    String? filePath,
    int? quicPort,
    Map<String, dynamic>? listeningContext,
  }) async {}
  @override
  void cancelPreparedNext({int? preparationId}) {}
  @override
  Future<void> releasePreparedNext({int? preparationId}) async {}

  @override
  void Function(Map<String, dynamic>)? onListeningSegment;
  bool _active = false;
  bool _paused = false;
  int starts = 0;
  int localStarts = 0;
  int stops = 0;
  int seeks = 0;
  final startOffsets = <Duration>[];

  @override
  bool get hasActivePlayer => _active;

  @override
  bool get isPaused => _paused;

  @override
  bool get sourceRejected => false;

  @override
  Future<void> initialize() async {}

  @override
  void configureListening(Map<String, dynamic>? context, {bool updateActive = false, bool discardPending = true}) {}

  @override
  Future<void> playTrack({
    required Track track,
    required ServerConnection connection,
    required StreamSettings settings,
    Duration startOffset = Duration.zero,
    List<String> queueTrackIds = const [],
    int? quicPort,
    bool quickStart = true,
    bool initialPaused = false,
  }) async {
    _active = true;
    _paused = initialPaused;
    starts++;
    startOffsets.add(startOffset);
  }

  @override
  Future<void> playLocalFile({
    required Track track,
    required String filePath,
    String? contentType,
    Duration startOffset = Duration.zero,
    bool initialPaused = false,
  }) async {
    _active = true;
    _paused = initialPaused;
    localStarts++;
    startOffsets.add(startOffset);
  }

  @override
  void pause() => _paused = true;

  @override
  void resume() => _paused = false;

  @override
  Future<bool> seekTo(Duration position) async {
    seeks++;

    return _active;
  }

  @override
  void setVolume(double value) {}

  @override
  Future<void> stop({bool waitForRelease = false}) async {
    _active = false;
    stops++;
  }

  @override
  Future<void> dispose() async {}
}

class _Downloads extends Fake implements OfflineDownloadManager {
  final _local = _track('local').copyWith(localId: 'local', liked: true);
  final String? localFilePath;

  _Downloads([this.localFilePath]);

  @override
  List<OfflineTrackDownload> get downloads => [
    if (localFilePath != null)
      offlineTestDownload(serverBaseUrl: 'https://music.test/api', track: _local, filePath: localFilePath),
  ];

  @override
  List<Track> get localLiked => [_local];

  @override
  List<Track> get localPlaylistTracks => const [];

  @override
  List<Playlist> get localPlaylists => const [];

  @override
  OfflineLibrarySnapshot get librarySnapshot => OfflineLibrarySnapshot(
    tracks: [_local],
    artistGroups: const [],
    liked: [_local],
    playlists: const [],
    playlistTracks: const [],
    revision: 0,
  );

  @override
  Stream<OfflineLibrarySnapshot> get librarySnapshotStream => const Stream.empty();

  @override
  Stream<List<Track>> get localLikedStream => const Stream.empty();

  @override
  Stream<List<Playlist>> get localPlaylistsStream => const Stream.empty();

  @override
  List<Track> localDownloadedTracks() => [_local];

  @override
  OfflineTrackDownload? findForCurrentServer(String trackId) =>
      trackId == 'local' && downloads.isNotEmpty ? downloads.single : null;

  @override
  OfflineTrackDownload? findLocal(String trackId) =>
      trackId == 'local' && downloads.isNotEmpty ? downloads.single : null;

  @override
  Future<void> load() async {}

  @override
  Future<void> resumePausedForCurrentServer() async {}

  @override
  Future<void> repairOfflineMetadataFragments() async {}

  @override
  Future<void> pauseDownloadsForServer(String serverBaseUrl) async {}

  @override
  Future<void> dispose() async {}
}

class _NowPlaying extends NowPlayingPlatformService {
  final snapshots = <NativeNowPlayingSnapshot>[];

  @override
  bool get isSupported => true;

  @override
  bool get loadsArtworkNatively => true;

  @override
  void setRemoteCommandHandler(Future<void> Function(NativeRemoteCommand) handler) {}

  @override
  Future<void> publish(NativeNowPlayingSnapshot snapshot) async => snapshots.add(snapshot);

  @override
  Future<void> clearNowPlaying() async {}

  @override
  void dispose() {}
}

class _Storage extends OfflineLibraryStorage {
  @override
  Future<OfflineStorageLocations> resolveStorageLocations() async => const OfflineStorageLocations(
    metadataDirectory: 'metadata',
    downloadsDirectory: 'downloads',
    metadataDirectoryIsDefault: true,
    downloadsDirectoryIsDefault: true,
  );
}

class _Preferences extends PlaybackPreferencesStorage {
  @override
  Future<bool?> readGaplessResampling() async => null;
  @override
  Future<void> writeGaplessResampling(bool enabled) async {}
  @override
  Future<PlaybackRepeatMode?> readRepeatMode() async => null;

  @override
  Future<void> writeRepeatMode(PlaybackRepeatMode mode) async {}

  @override
  Future<bool?> readCollectionListMode() async => true;

  @override
  Future<double?> readVolume() async => 0.5;
}

class _ShuffleSettings extends CustomShuffleSettingsStorage {
  @override
  Future<CustomShuffleSettings> read() async => const CustomShuffleSettings();

  @override
  Future<CustomShuffleSettings> readForAccount(String scope) async => const CustomShuffleSettings();

  @override
  Future<void> writeLocal(CustomShuffleSettings settings) async {}

  @override
  Future<void> writeForAccount(String scope, CustomShuffleSettings settings) async {}
}

class _ScopedShuffleSettings extends _ShuffleSettings {
  final values = <String, CustomShuffleSettings>{
    'alice': const CustomShuffleSettings(artistIds: ['alice-artist'], genres: ['jazz']),
    'bob': const CustomShuffleSettings(artistIds: ['bob-artist'], genres: ['ambient']),
  };
  final nextReads = <String, Future<CustomShuffleSettings>>{};
  final reads = <String>[];

  @override
  Future<CustomShuffleSettings> read() async => const CustomShuffleSettings(
    artistIds: ['legacy-unscoped'],
    localArtistIds: ['downloaded-artist'],
    localGenres: ['rock'],
  );

  @override
  Future<CustomShuffleSettings> readForAccount(String scope) async {
    reads.add(scope);
    final account = scope.split('/').last;

    return nextReads.remove(account) ?? values[account] ?? const CustomShuffleSettings();
  }
}

class _Connectivity extends ConnectivitySignalSource {
  @override
  Stream<bool> get availabilityStream => const Stream.empty();

  @override
  Future<bool> hasConnectivity() async => true;
}

class _Vehicle extends VehicleSurfaceService {
  @override
  bool get isSupported => false;

  @override
  void dispose() {}
}

class _Permissions extends LocalNetworkPermissionService {
  @override
  bool get isSupported => false;

  @override
  void dispose() {}
}
