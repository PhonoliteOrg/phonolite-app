import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/data/models/artwork/artwork_preloader.dart';
import 'package:phonolite_app/data/models/artwork/artwork_request.dart';
import 'package:phonolite_app/data/models/diagnostics/log_entry.dart';
import 'package:phonolite_app/data/storage/logs/app_log.dart';
import 'package:phonolite_app/infrastructure/audio/engine/audio_engine.dart';
import 'package:phonolite_app/data/models/auth/auth_credentials.dart';
import 'package:phonolite_app/data/models/auth/account_state.dart';
import 'package:phonolite_app/data/models/auth/server_trust.dart';
import 'package:phonolite_app/data/storage/auth/auth_storage.dart';
import 'package:phonolite_app/data/storage/auth/server_trust_store.dart';
import 'package:phonolite_app/infrastructure/security/server_trust.dart' show ServerTrustRegistry;
import 'package:phonolite_app/data/models/auth/auth_state.dart';
import 'package:phonolite_app/infrastructure/platform/connectivity/connectivity_signal_source.dart';
import 'package:phonolite_app/data/models/playback/custom_shuffle_settings.dart';
import 'package:phonolite_app/data/models/playback/account_playback_snapshot.dart';
import 'package:phonolite_app/data/models/playback/device_playback_snapshot.dart';
import 'package:phonolite_app/data/models/playback/playback_resume_checkpoint.dart';
import 'package:phonolite_app/data/models/playback/playback_source_context.dart';
import 'package:phonolite_app/data/storage/playback/playback_resume_storage.dart';
import 'package:phonolite_app/data/storage/preferences/custom_shuffle_settings_storage.dart';
import 'package:phonolite_app/data/models/library/artist_credit.dart';
import 'package:phonolite_app/data/models/library/artist_releases.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/library/artist_summary.dart';
import 'package:phonolite_app/data/projections/library/offline_library_views.dart' as offline_views;
import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/data/models/library/metadata_update_event.dart';
import 'package:phonolite_app/data/models/library/search_result.dart';
import 'package:phonolite_app/data/models/downloads/offline_track_metadata.dart';
import 'package:phonolite_app/data/models/server/download_batch_manifest.dart';
import 'package:phonolite_app/data/models/server/server_capabilities.dart';
import 'package:phonolite_app/data/models/server/shuffle_session_page.dart';
import 'package:phonolite_app/data/models/library/track_match.dart';
import 'package:phonolite_app/data/models/collections/like_state.dart';
import 'package:phonolite_app/data/models/playback/output_device.dart';
import 'package:phonolite_app/application/downloads/offline_download_manager.dart';
import 'package:phonolite_app/data/storage/offline/library/offline_library.dart';
import 'package:phonolite_app/data/models/preferences/offline_storage_locations.dart';
import 'package:phonolite_app/data/storage/preferences/playback_preferences.dart';
import 'package:phonolite_app/data/storage/preferences/settings_files.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';
import 'package:phonolite_app/infrastructure/platform/permissions/local_network_permission_service.dart';
import 'package:phonolite_app/infrastructure/artwork/now_playing_artwork_loader.dart';
import 'package:phonolite_app/infrastructure/platform/media/now_playing_platform_service.dart';
import 'package:phonolite_app/infrastructure/platform/media/vehicle_surface_service.dart';
import '../support/auth_test_helpers.dart';
import '../support/offline_library_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final knownUser in <String?>['resume-user', 'other-user', null]) {
    test('resume offline cache requires the saved verified account UUID: $knownUser', () async {
      _mockTrustVault();
      final directory = await Directory.systemTemp.createTemp('resume_offline_account_');
      final library = await _seedResumeLibrary(directory, 1);
      final files = SettingsFiles(directoryProvider: () async => directory);
      final resume = PlaybackResumeStorage(files: files);
      final auth = AuthStorage(files: files);
      final connection = _ResumeConnection()..playbackSettingsFailure = true;
      final origin = ServerTrust.origin(Uri.parse(connection.baseUrl));
      final scope = '$origin/${testServerTrust.spki}/${testServerTrust.opaqueKey}/resume-user';
      final source = PlaybackSourceContext(kind: 'playlist', id: 'offline-origin');
      await resume.writeAccount(
        scope,
        AccountPlaybackSnapshot(
          revision: 4,
          generation: 'offline-generation',
          checkpoint: PlaybackResumeCheckpoint(
            trackId: 'server-0',
            source: source,
            shuffleMode: ShuffleMode.off,
            shuffleContext: source,
          ),
        ),
      );
      await auth.write(
        AuthCredentials(
          baseUrl: connection.baseUrl,
          token: 'saved-token',
          username: 'Listener',
          trust: testServerTrust,
          userId: knownUser,
        ),
      );
      final harness = _Harness(
        connection: connection,
        authStorage: auth,
        offlineStorage: library,
        offlineDownloadManager: OfflineDownloadManager(connection: connection, storage: library),
        playbackResumeStorage: resume,
      );
      addTearDown(() async {
        await harness.controller.close();
        await library.close();
        await directory.delete(recursive: true);
      });

      await harness.controller.initialize();
      await harness.controller.restoreSession();

      expect(harness.controller.authState.status, SessionStatus.serverUnavailable);
      if (knownUser == 'resume-user') {
        await _resumeUntil(() => harness.controller.playbackState.track != null);
        expect(harness.controller.playbackState.track!.id, 'server-0');
        expect(harness.controller.playbackState.queueSourcePlaylistId, 'offline-origin');
        expect(harness.controller.playbackState.isPlaying, isFalse);
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        expect(harness.controller.playbackState.track, isNull);
      }
      expect(connection.reads, 0);
      expect(connection.saved, isEmpty);
      expect(harness.audio.starts, isEmpty);
      expect(harness.audio.localStarts, isEmpty);
      expect((await resume.readAccount(scope))!.checkpoint!.trackId, 'server-0');
    });
  }

  test('resume late server acknowledgement cannot replace a newer local bookmark', () async {
    final directory = await Directory.systemTemp.createTemp('resume_local_wins_');
    final library = await _seedResumeLibrary(directory, 1);
    final localTrack = (await library.readLocalDownloadedTracks()).single;
    final resume = PlaybackResumeStorage(files: SettingsFiles(directoryProvider: () async => directory));
    final pending = Completer<AccountPlaybackSnapshot>();
    final connection = _ResumeConnection()
      ..trackResponse = [offlineTestTrack(id: 'server-playing')]
      ..pendingSave = pending.future;
    final harness = _Harness(
      authenticated: true,
      connection: connection,
      offlineStorage: library,
      offlineDownloadManager: OfflineDownloadManager(connection: connection, storage: library),
      playbackResumeStorage: resume,
    );
    addTearDown(() async {
      await harness.controller.close();
      await library.close();
      await directory.delete(recursive: true);
    });
    await harness.controller.initialize();
    await harness.controller.restoreSession();
    await _resumeUntil(() => connection.reads > 0);
    await harness.controller.queueAlbum('remote-album');
    harness.onStarted!();
    await _resumeUntil(() => connection.saved.isNotEmpty);
    await harness.controller.playOfflineTrack(localTrack.id);
    harness.onStarted!();
    await _resumeUntil(() => File('${directory.path}/playback_resume.json').existsSync());
    expect(await resume.readActiveScope(), 'local');

    pending.complete(connection.snapshot);
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(await resume.readActiveScope(), 'local');
    expect((await resume.readLocal())!.checkpoint!.trackId, localTrack.id);
    expect(harness.controller.playbackState.track!.id, localTrack.id);
  });

  test('resume account changes detach private server sources while downloaded audio continues', () async {
    final directory = await Directory.systemTemp.createTemp('resume_private_source_switch_');
    final library = await _seedResumeLibrary(directory, 1);
    final localTrack = (await library.readLocalDownloadedTracks()).single;
    final resume = PlaybackResumeStorage(files: SettingsFiles(directoryProvider: () async => directory));
    final connection = _ResumeConnection()..trackResponse = [offlineTestTrack(id: 'server-0')];
    final harness = _Harness(
      authenticated: true,
      connection: connection,
      offlineStorage: library,
      offlineDownloadManager: OfflineDownloadManager(connection: connection, storage: library),
      playbackResumeStorage: resume,
    );
    addTearDown(() async {
      await harness.controller.close();
      await library.close();
      await directory.delete(recursive: true);
    });
    await harness.controller.initialize();
    await harness.controller.restoreSession();
    await _resumeUntil(() => connection.reads > 0);
    await harness.controller.queuePlaylist('first-users-private-list');
    harness.onStarted!();
    await _resumeUntil(() => connection.saved.isNotEmpty);
    harness.onStats!(const Duration(seconds: 5), Duration.zero, null, null, true);
    final starts = harness.audio.starts.length;
    final stops = harness.audio.stops;
    final reports = connection.saved.length;
    connection.userId = 'second-user';
    connection.snapshot = const AccountPlaybackSnapshot(revision: 0);
    harness.controller.loginWithToken(baseUrl: connection.baseUrl, token: 'second-token');
    await _resumeUntil(() => harness.controller.playbackState.queueSource == PlaybackQueueSource.offline);
    await harness.controller.pause(true);
    await _resumeUntil(() async => (await resume.readLocal())?.checkpoint?.source.kind == 'standalone');

    expect(harness.controller.playbackState.queueSourcePlaylistId, isNull);
    expect(harness.controller.playbackState.track!.localId, localTrack.id);
    expect(harness.audio.starts, hasLength(starts));
    expect(harness.audio.stops, stops);
    expect(connection.saved, hasLength(reports));
    expect((await resume.readLocal())!.checkpoint!.source.kind, 'standalone');
    expect((await resume.readLocal())!.checkpoint!.trackId, localTrack.id);
  });

  test('resume an account switch rejects old checkpoint replies and namespaces cached data', () async {
    final directory = await Directory.systemTemp.createTemp('resume_account_switch_');
    final resume = PlaybackResumeStorage(files: SettingsFiles(directoryProvider: () async => directory));
    final pending = Completer<AccountPlaybackSnapshot>();
    final connection = _ResumeConnection()
      ..pendingSnapshot = pending.future
      ..trackResponse = [offlineTestTrack(id: 'second-account-track')];
    final harness = _Harness(authenticated: true, connection: connection, playbackResumeStorage: resume);
    addTearDown(() async {
      await harness.controller.close();
      await directory.delete(recursive: true);
    });
    await harness.controller.initialize();
    await harness.controller.restoreSession();
    await _resumeUntil(() => connection.reads > 0);
    final source = PlaybackSourceContext(kind: 'standalone');
    PlaybackResumeCheckpoint checkpoint(String id) =>
        PlaybackResumeCheckpoint(trackId: id, source: source, shuffleMode: ShuffleMode.off, shuffleContext: source);

    connection.userId = 'second-user';
    connection.snapshot = AccountPlaybackSnapshot(
      revision: 2,
      generation: 'second-generation',
      checkpoint: checkpoint('second-account-track'),
    );
    harness.controller.loginWithToken(baseUrl: connection.baseUrl, token: 'second-token');
    await _resumeUntil(() => harness.controller.playbackState.track?.id == 'second-account-track');
    pending.complete(
      AccountPlaybackSnapshot(revision: 1, generation: 'old-generation', checkpoint: checkpoint('old-track')),
    );
    await Future<void>.delayed(const Duration(milliseconds: 40));
    final origin = ServerTrust.origin(Uri.parse(connection.baseUrl));
    final prefix = '$origin/${testServerTrust.spki}/${testServerTrust.opaqueKey}';

    expect(harness.controller.playbackState.track!.id, 'second-account-track');
    expect(await resume.readAccount('$prefix/resume-user'), isNull);
    expect((await resume.readAccount('$prefix/second-user'))!.checkpoint!.trackId, 'second-account-track');
    expect(connection.saved, isEmpty);
    expect(harness.audio.starts, isEmpty);
  });

  test('resume mode edits after Stop retain the bookmark and apply the new mode on restart', () async {
    final directory = await Directory.systemTemp.createTemp('resume_stop_mode_');
    final library = await _seedResumeLibrary(directory, 3);
    final tracks = await library.readLocalDownloadedTracks();
    final resume = PlaybackResumeStorage(files: SettingsFiles(directoryProvider: () async => directory));
    final source = PlaybackSourceContext(kind: 'library');
    await resume.writeLocal(
      DevicePlaybackSnapshot(
        checkpoint: PlaybackResumeCheckpoint(
          trackId: tracks[1].id,
          source: source,
          shuffleMode: ShuffleMode.all,
          shuffleContext: source,
          cursor: 1,
        ),
        queueTrackIds: tracks.reversed.map((track) => track.id).toList(),
        localShuffleMode: ShuffleMode.all,
      ),
    );
    final first = _resumeHarness(library, resume);
    await first.controller.initialize();
    await first.controller.stop();
    first.controller.updateShuffleMode(ShuffleMode.off, scope: ActionScope.local);
    await first.controller.close();
    final saved = (await resume.readLocal())!;
    expect(saved.checkpoint!.trackId, tracks[1].id);
    expect(saved.queueTrackIds, tracks.reversed.map((track) => track.id));
    expect(saved.localShuffleMode, ShuffleMode.off);

    final second = _resumeHarness(library, resume);
    addTearDown(() async {
      await second.controller.close();
      await library.close();
      await directory.delete(recursive: true);
    });
    await second.controller.initialize();

    expect(second.controller.playbackState.track!.id, tracks[1].id);
    expect(second.controller.playbackState.shuffleMode, ShuffleMode.off);
    expect(second.audio.starts, isEmpty);
    expect(second.audio.localStarts, isEmpty);
  });

  test('resume paused custom filter edits commit the applied rules without an audio start', () async {
    final directory = await Directory.systemTemp.createTemp('resume_custom_filters_');
    final library = await _seedResumeLibrary(directory, 2);
    final tracks = await library.readLocalDownloadedTracks();
    final resume = PlaybackResumeStorage(files: SettingsFiles(directoryProvider: () async => directory));
    final source = PlaybackSourceContext(kind: 'custom', artistIds: ['artist-1']);
    await resume.writeLocal(
      DevicePlaybackSnapshot(
        checkpoint: PlaybackResumeCheckpoint(
          trackId: tracks[0].id,
          source: source,
          shuffleMode: ShuffleMode.custom,
          shuffleContext: source,
        ),
        queueTrackIds: tracks.map((track) => track.id).toList(),
        localShuffleMode: ShuffleMode.custom,
      ),
    );
    final harness = _resumeHarness(library, resume);
    addTearDown(() async {
      await harness.controller.close();
      await library.close();
      await directory.delete(recursive: true);
    });
    await harness.controller.initialize();
    await harness.controller.updateCustomShuffleSettings(localArtistIds: ['artist-1'], localGenres: ['newgenre']);
    await _resumeUntil(
      () async => (await resume.readLocal())?.checkpoint?.shuffleContext.genres.contains('newgenre') ?? false,
    );
    final checkpoint = (await resume.readLocal())!.checkpoint!;

    expect(checkpoint.shuffleContext.genres, ['newgenre']);
    expect(checkpoint.shuffleContext.artistIds, ['artist-1']);
    expect(harness.controller.playbackState.isPlaying, isFalse);
    expect(harness.audio.localStarts, isEmpty);
    expect(harness.audio.starts, isEmpty);
  });

  test('resume local shuffle includes additions in the next cycle and avoids an immediate repeat', () async {
    final directory = await Directory.systemTemp.createTemp('resume_next_cycle_');
    final library = await _seedResumeLibrary(directory, 4);
    final tracks = await library.readLocalDownloadedTracks();
    final resume = PlaybackResumeStorage(files: SettingsFiles(directoryProvider: () async => directory));
    final source = PlaybackSourceContext(kind: 'library');
    await resume.writeLocal(
      DevicePlaybackSnapshot(
        checkpoint: PlaybackResumeCheckpoint(
          trackId: tracks[2].id,
          source: source,
          shuffleMode: ShuffleMode.all,
          shuffleContext: source,
          cursor: 2,
        ),
        queueTrackIds: tracks.take(3).map((track) => track.id).toList(),
        localShuffleMode: ShuffleMode.all,
      ),
    );
    final harness = _resumeHarness(library, resume);
    addTearDown(() async {
      await harness.controller.close();
      await library.close();
      await directory.delete(recursive: true);
    });
    await harness.controller.initialize();
    expect(harness.controller.playbackState.track!.id, tracks[2].id);
    await harness.controller.nextTrack();
    expect(harness.controller.playbackState.track!.id, isNot(tracks[2].id));
    harness.onStarted!();
    await harness.controller.pause(true);
    await harness.controller.close();

    expect((await resume.readLocal())!.queueTrackIds.toSet(), tracks.map((track) => track.id).toSet());
  });

  for (final scenario in ['ordered', 'shuffle', 'deleted-source']) {
    test('resume offline source reconnect keeps its own session after the account head advances: $scenario', () async {
      _mockTrustVault();
      final directory = await Directory.systemTemp.createTemp('resume_reconnected_source_');
      final library = await _seedResumeLibrary(directory, 3);
      final files = SettingsFiles(directoryProvider: () async => directory);
      final resume = PlaybackResumeStorage(files: files);
      final auth = AuthStorage(files: files);
      final tracks = [for (var index = 0; index < 3; index++) offlineTestTrack(id: 'server-$index')];
      final connection = _ResumeConnection()
        ..playbackSettingsFailure = true
        ..trackResponse = tracks;
      connection.durableDecks['offline-deck'] = tracks;
      final origin = ServerTrust.origin(Uri.parse(connection.baseUrl));
      final scope = '$origin/${testServerTrust.spki}/${testServerTrust.opaqueKey}/resume-user';
      final source = PlaybackSourceContext(kind: 'playlist', id: 'original-list');
      final shuffled = scenario != 'ordered';
      await resume.writeAccount(
        scope,
        AccountPlaybackSnapshot(
          revision: 4,
          generation: 'offline-generation',
          checkpoint: PlaybackResumeCheckpoint(
            trackId: tracks[0].id,
            source: source,
            shuffleMode: shuffled ? ShuffleMode.currentPlaylist : ShuffleMode.off,
            shuffleContext: source,
            deckId: shuffled ? 'offline-deck' : null,
          ),
        ),
      );
      await auth.write(
        AuthCredentials(
          baseUrl: connection.baseUrl,
          token: 'saved-token',
          username: 'Listener',
          trust: testServerTrust,
          userId: 'resume-user',
        ),
      );
      final harness = _Harness(
        connection: connection,
        authStorage: auth,
        offlineStorage: library,
        offlineDownloadManager: OfflineDownloadManager(connection: connection, storage: library),
        playbackResumeStorage: resume,
      );
      addTearDown(() async {
        await harness.controller.close();
        await library.close();
        await directory.delete(recursive: true);
      });
      await harness.controller.initialize();
      await harness.controller.restoreSession();
      await _resumeUntil(() => harness.controller.playbackState.track != null);
      final elsewhere = PlaybackSourceContext(kind: 'standalone');
      connection.snapshot = AccountPlaybackSnapshot(
        revision: 100,
        generation: 'other-device',
        checkpoint: PlaybackResumeCheckpoint(
          trackId: 'another-devices-track',
          source: elsewhere,
          shuffleMode: ShuffleMode.off,
          shuffleContext: elsewhere,
        ),
      );
      connection.playbackSettingsFailure = false;
      connection.pendingHealth = Future.value(2);
      if (scenario == 'deleted-source') {
        connection.missingPlaylists.add('original-list');
      }
      await harness.controller.refreshServerAvailability();
      await _resumeUntil(() => connection.reads > 0);
      expect(harness.controller.playbackState.track!.id, tracks[0].id);
      expect(harness.audio.starts, isEmpty);

      await harness.controller.nextTrack();

      if (scenario == 'deleted-source') {
        expect(harness.controller.playbackState.queueSourcePlaylistId, isNull);
        expect(harness.controller.playbackState.shuffleMode, ShuffleMode.off);
        expect(harness.controller.playbackState.track!.id, tracks[0].id);
      } else {
        expect(harness.controller.playbackState.track!.id, tracks[1].id);
        expect(harness.controller.playbackState.queueSourcePlaylistId, 'original-list');
        if (shuffled) {
          expect(connection.deckReads, contains('offline-deck'));
        }
      }
    });
  }

  test('resume modes load independently of the last active account and without a selected track', () async {
    final directory = await Directory.systemTemp.createTemp('resume_modes_');
    addTearDown(() => directory.delete(recursive: true));
    final resume = PlaybackResumeStorage(files: SettingsFiles(directoryProvider: () async => directory));
    await resume.writeLocal(
      DevicePlaybackSnapshot(localShuffleMode: ShuffleMode.liked, serverShuffleMode: ShuffleMode.all),
    );
    await resume.writeAccount('other-account', const AccountPlaybackSnapshot(revision: 0));
    final harness = _Harness(playbackResumeStorage: resume);
    addTearDown(harness.controller.close);

    await harness.controller.initialize();

    expect(harness.controller.playbackState.localShuffleMode, ShuffleMode.liked);
    expect(harness.controller.playbackState.serverShuffleMode, ShuffleMode.all);
    expect(harness.controller.playbackState.track, isNull);
    expect(harness.audio.localStarts, isEmpty);
  });

  test('local shuffle resumes its exact order and seek position paused after a restart and Stop', () async {
    final directory = await Directory.systemTemp.createTemp('resume_shuffle_');
    addTearDown(() => directory.delete(recursive: true));
    final storage = await _seedResumeLibrary(directory, 3);
    final resume = PlaybackResumeStorage(files: SettingsFiles(directoryProvider: () async => directory));
    final first = _resumeHarness(storage, resume);
    await first.controller.initialize();
    first.controller.updateShuffleMode(ShuffleMode.all, scope: ActionScope.local);
    await first.controller.queueLocalShuffle();
    first.onStarted!();
    first.onStats!(const Duration(seconds: 24), Duration.zero, null, null, true);
    await first.controller.pause(true);
    await first.controller.stop();
    await first.controller.close();
    final saved = (await resume.readLocal())!;
    expect(saved.queueTrackIds, hasLength(3));
    expect(saved.checkpoint!.shuffleMode, ShuffleMode.all);
    expect(saved.checkpoint!.source.kind, 'library');

    final second = _resumeHarness(storage, resume);
    try {
      await second.controller.initialize();
      expect(second.controller.playbackState.track!.localId, saved.checkpoint!.trackId);
      expect(second.controller.playbackState.shuffleMode, ShuffleMode.all);
      expect(second.controller.playbackState.position, const Duration(seconds: 24));
      expect(second.controller.playbackState.isPlaying, isFalse);
      expect(second.audio.localStarts, isEmpty);
      await second.controller.pause(false);
      expect(second.audio.localStarts.single.offset, const Duration(seconds: 24));
      await second.controller.nextTrack();
      expect(second.controller.playbackState.track!.localId, saved.queueTrackIds[1]);
      second.onStarted!();
    } finally {
      await second.controller.close();
      await storage.close();
    }
    expect((await resume.readLocal())!.queueTrackIds, saved.queueTrackIds);
  });

  test('a deleted local playlist detaches to one track and cannot expand on a second restart', () async {
    final directory = await Directory.systemTemp.createTemp('resume_deleted_playlist_');
    addTearDown(() => directory.delete(recursive: true));
    final storage = await _seedResumeLibrary(directory, 3);
    final tracks = await storage.readLocalDownloadedTracks();
    final playlist = await storage.createLocalPlaylist('Saved queue');
    await storage.addLocalTrackToPlaylist(playlist.id, tracks[0].id);
    final resume = PlaybackResumeStorage(files: SettingsFiles(directoryProvider: () async => directory));
    await resume.writeLocal(
      DevicePlaybackSnapshot(
        checkpoint: PlaybackResumeCheckpoint(
          trackId: tracks[0].id,
          source: PlaybackSourceContext(kind: 'playlist', id: playlist.id),
          shuffleMode: ShuffleMode.currentPlaylist,
          shuffleContext: PlaybackSourceContext(kind: 'playlist', id: playlist.id),
        ),
        queueTrackIds: [tracks[0].id],
        localShuffleMode: ShuffleMode.currentPlaylist,
      ),
    );
    await storage.deleteLocalPlaylist(playlist.id);
    for (var run = 0; run < 2; run++) {
      final harness = _resumeHarness(storage, resume);
      try {
        await harness.controller.initialize();
        expect(harness.controller.playbackState.track!.id, tracks[0].id);
        expect(harness.controller.playbackState.shuffleMode, ShuffleMode.off);
        expect(harness.controller.playbackState.queueSourcePlaylistId, isNull);
        await harness.controller.nextTrack();
        expect(harness.controller.playbackState.track!.id, tracks[0].id);
        harness.onStarted!();
      } finally {
        await harness.controller.close();
      }
    }
    await storage.close();
    expect((await resume.readLocal())!.checkpoint!.source.kind, 'standalone');
  });

  test('local restore skips a missing current file without inserting new tracks into its saved shuffle pass', () async {
    final directory = await Directory.systemTemp.createTemp('resume_pruned_shuffle_');
    addTearDown(() => directory.delete(recursive: true));
    final storage = await _seedResumeLibrary(directory, 4);
    final tracks = await storage.readLocalDownloadedTracks();
    final downloads = await storage.readDownloads();
    final resume = PlaybackResumeStorage(files: SettingsFiles(directoryProvider: () async => directory));
    await resume.writeLocal(
      DevicePlaybackSnapshot(
        checkpoint: PlaybackResumeCheckpoint(
          trackId: tracks[1].id,
          source: PlaybackSourceContext(kind: 'library'),
          shuffleMode: ShuffleMode.all,
          shuffleContext: PlaybackSourceContext(kind: 'library'),
          cursor: 1,
        ),
        queueTrackIds: tracks.take(3).map((track) => track.id).toList(),
        localShuffleMode: ShuffleMode.all,
      ),
    );
    final missing = downloads.firstWhere((item) => item.localTrackId == tracks[1].id);
    await File(missing.filePath!).delete();
    final harness = _resumeHarness(storage, resume);
    try {
      await harness.controller.initialize();
      expect(harness.controller.playbackState.track!.id, tracks[2].id);
      expect(harness.controller.playbackState.position, Duration.zero);
      expect(harness.audio.localStarts, isEmpty);
    } finally {
      await harness.controller.close();
      await storage.close();
    }
    expect((await resume.readLocal())!.queueTrackIds, [tracks[0].id, tracks[2].id]);
  });

  test('account shuffle restores a durable deck and playlist context paused at its absolute cursor', () async {
    final connection = _ResumeConnection();
    final tracks = [for (var i = 0; i < 4; i++) offlineTestTrack(id: 'resume-$i')];
    connection.trackResponse = tracks;
    connection.snapshot = AccountPlaybackSnapshot(
      revision: 7,
      generation: 'saved-generation',
      checkpoint: PlaybackResumeCheckpoint(
        trackId: tracks[2].id,
        source: PlaybackSourceContext(kind: 'playlist', id: 'saved-list'),
        shuffleMode: ShuffleMode.currentPlaylist,
        shuffleContext: PlaybackSourceContext(kind: 'playlist', id: 'saved-list'),
        deckId: 'durable',
        cursor: 2,
      ),
    );
    final harness = _Harness(authenticated: true, connection: connection);
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    await harness.controller.restoreSession();
    await _resumeUntil(() => harness.controller.playbackState.track?.id == tracks[2].id);

    expect(harness.controller.playbackState.isPlaying, isFalse);
    expect(harness.controller.playbackState.queueSourcePlaylistId, 'saved-list');
    expect(harness.audio.starts, isEmpty);
    expect(connection.saved, isEmpty);
    await harness.controller.nextTrack();
    expect(harness.controller.playbackState.track!.id, tracks[3].id);
    harness.onStarted!();
    await _resumeUntil(() => connection.saved.isNotEmpty);
    expect(connection.saved.last.cursor, 3);
    expect(connection.saved.last.deckId, 'durable');
    expect(connection.saved.last.source.id, 'saved-list');
  });

  test('a delayed account resume cannot replace an explicit album selection or lose its album source', () async {
    final connection = _ResumeConnection()..trackResponse = [offlineTestTrack(id: 'chosen')];
    final pending = Completer<AccountPlaybackSnapshot>();
    connection.pendingSnapshot = pending.future;
    final harness = _Harness(authenticated: true, connection: connection);
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    await harness.controller.restoreSession();
    await _resumeUntil(() => connection.reads > 0);
    await harness.controller.queueAlbum('chosen-album');
    harness.onStarted!();
    pending.complete(const AccountPlaybackSnapshot(revision: 1));
    await _resumeUntil(() => connection.saved.isNotEmpty);

    expect(harness.controller.playbackState.track!.id, 'chosen');
    expect(connection.saved.single.source.kind, 'album');
    expect(connection.saved.single.source.id, 'chosen-album');
    expect(harness.audio.starts, hasLength(1));
  });

  test('resume retains duplicate local queue occurrences when advancing after a restart', () async {
    final directory = await Directory.systemTemp.createTemp('resume_duplicate_');
    addTearDown(() => directory.delete(recursive: true));
    final storage = await _seedResumeLibrary(directory, 2);
    final tracks = await storage.readLocalDownloadedTracks();
    final order = [tracks[0].id, tracks[1].id, tracks[0].id, tracks[1].id];
    final resume = PlaybackResumeStorage(files: SettingsFiles(directoryProvider: () async => directory));
    await resume.writeLocal(
      DevicePlaybackSnapshot(
        checkpoint: PlaybackResumeCheckpoint(
          trackId: tracks[0].id,
          source: PlaybackSourceContext(kind: 'library'),
          shuffleMode: ShuffleMode.all,
          shuffleContext: PlaybackSourceContext(kind: 'library'),
          cursor: 2,
        ),
        queueTrackIds: order,
        localShuffleMode: ShuffleMode.all,
      ),
    );
    final harness = _resumeHarness(storage, resume);
    try {
      await harness.controller.initialize();
      await harness.controller.nextTrack();
      harness.onStarted!();
    } finally {
      await harness.controller.close();
      await storage.close();
    }
    expect((await resume.readLocal())!.checkpoint!.cursor, 3);
  });

  test('resume keeps an existing empty local playlist source and its shuffle mode without autoplay', () async {
    final directory = await Directory.systemTemp.createTemp('resume_empty_source_');
    addTearDown(() => directory.delete(recursive: true));
    final storage = await _seedResumeLibrary(directory, 1);
    final track = (await storage.readLocalDownloadedTracks()).single;
    final playlist = await storage.createLocalPlaylist('Now empty');
    final resume = PlaybackResumeStorage(files: SettingsFiles(directoryProvider: () async => directory));
    final source = PlaybackSourceContext(kind: 'playlist', id: playlist.id);
    await resume.writeLocal(
      DevicePlaybackSnapshot(
        checkpoint: PlaybackResumeCheckpoint(
          trackId: track.id,
          source: source,
          shuffleMode: ShuffleMode.currentPlaylist,
          shuffleContext: source,
        ),
        queueTrackIds: [track.id],
        localShuffleMode: ShuffleMode.currentPlaylist,
      ),
    );
    final harness = _resumeHarness(storage, resume);
    try {
      await harness.controller.initialize();
      expect(harness.controller.playbackState.track, isNull);
      expect(harness.controller.playbackState.queueSourcePlaylistId, playlist.id);
      expect(harness.controller.playbackState.shuffleMode, ShuffleMode.currentPlaylist);
      expect(harness.audio.localStarts, isEmpty);
      harness.controller.updateShuffleMode(ShuffleMode.currentPlaylist, scope: ActionScope.local);
      await resume.flush();
    } finally {
      await harness.controller.close();
      await storage.close();
    }
    expect((await resume.readLocal())!.checkpoint!.source, source);
  });

  test('resume persists a paused restored-account shuffle toggle without starting audio', () async {
    final connection = _ResumeConnection()..trackResponse = [offlineTestTrack(id: 'paused')];
    final source = PlaybackSourceContext(kind: 'album', id: 'album-1');
    connection.snapshot = AccountPlaybackSnapshot(
      revision: 4,
      generation: 'old-generation',
      checkpoint: PlaybackResumeCheckpoint(
        trackId: 'paused',
        source: source,
        shuffleMode: ShuffleMode.off,
        shuffleContext: source,
      ),
    );
    final harness = _Harness(authenticated: true, connection: connection);
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    await harness.controller.restoreSession();
    await _resumeUntil(() => harness.controller.playbackState.track != null);
    harness.controller.updateShuffleMode(ShuffleMode.all, scope: ActionScope.server);
    await _resumeUntil(() => connection.saved.isNotEmpty);

    expect(connection.intents.single, 'update');
    expect(connection.saved.single.shuffleMode, ShuffleMode.all);
    expect(connection.saved.single.deckId, isNotNull);
    expect(harness.audio.starts, isEmpty);
  });

  test('resume close cancels waiting account writes and a late response cannot activate an old account', () async {
    final directory = await Directory.systemTemp.createTemp('resume_late_write_');
    addTearDown(() => directory.delete(recursive: true));
    final connection = _ResumeConnection()..trackResponse = [offlineTestTrack(id: 'server-playing')];
    final resume = PlaybackResumeStorage(files: SettingsFiles(directoryProvider: () async => directory));
    final pending = Completer<AccountPlaybackSnapshot>();
    connection.pendingSave = pending.future;
    final harness = _Harness(authenticated: true, connection: connection, playbackResumeStorage: resume);
    await harness.controller.initialize();
    await harness.controller.restoreSession();
    await _resumeUntil(() => connection.reads > 0);
    await harness.controller.queueAlbum('album-1');
    harness.onStarted!();
    await _resumeUntil(() => connection.saved.isNotEmpty);
    await harness.controller.close().timeout(const Duration(seconds: 2));
    pending.complete(connection.snapshot);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(await resume.readActiveScope(), isNull);
  });

  test('resume progress checkpoints device state every fifteen seconds and on background', () async {
    final directory = await Directory.systemTemp.createTemp('resume_progress_');
    addTearDown(() => directory.delete(recursive: true));
    final storage = await _seedResumeLibrary(directory, 1);
    final resume = PlaybackResumeStorage(files: SettingsFiles(directoryProvider: () async => directory));
    final harness = _resumeHarness(storage, resume);
    try {
      await harness.controller.initialize();
      await harness.controller.playOfflineTrack(harness.controller.offlineTracks.single.id);
      harness.onStarted!();
      harness.onStats!(const Duration(seconds: 2), Duration.zero, null, null, true);
      await _resumeUntil(() async => (await resume.readLocal())?.checkpoint != null);
      harness.playbackTime = harness.playbackTime.add(const Duration(seconds: 16));
      harness.onStats!(const Duration(seconds: 18), Duration.zero, null, null, true);
      await _resumeUntil(() async => (await resume.readLocal())?.positionMs == 18000);
      expect((await resume.readLocal())!.positionMs, 18000);
      harness.onStats!(const Duration(seconds: 20), Duration.zero, null, null, true);
      harness.controller.handleAppLifecycleState(AppLifecycleState.inactive);
      await _resumeUntil(() async => (await resume.readLocal())?.positionMs == 20000);
      expect((await resume.readLocal())!.positionMs, 20000);
    } finally {
      await harness.controller.close();
      await storage.close();
    }
  });

  test('server shuffle warms the current and next two album covers without delaying audio', () async {
    final connection = _WindowShuffleConnection()..distinctAlbumIds = true;
    final artwork = _RecordingArtworkPreloader();
    final harness = _Harness(authenticated: true, connection: connection, shuffleArtworkPreloader: artwork);
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    await harness.controller.restoreSession();
    harness.controller.updateShuffleMode(ShuffleMode.all, scope: ActionScope.server);

    await harness.controller.queueShuffle(scope: 'library');

    expect(harness.audio.starts.single.trackId, 'deck-track-0');
    expect(artwork.current.map((request) => request.source), [
      for (var i = 0; i < 3; i++) connection.buildAlbumCoverUrl('album-$i'),
    ]);
    expect(
      artwork.current.every((request) => request.headers['Authorization'] == 'Bearer ${connection.token}'),
      isTrue,
    );
    expect(connection.pageOffsets, isEmpty);

    await harness.controller.nextTrack();

    expect(harness.controller.playbackState.track?.id, 'deck-track-1');
    expect(artwork.current.map((request) => request.source), [
      for (var i = 1; i < 4; i++) connection.buildAlbumCoverUrl('album-$i'),
    ]);
  });

  test('server shuffle warms each album once when upcoming tracks share a cover', () async {
    final connection = _Connection()
      ..trackResponse = [
        offlineTestTrack(id: 'first', albumId: 'shared-album'),
        offlineTestTrack(id: 'second', albumId: 'shared-album'),
        offlineTestTrack(id: 'third', albumId: 'other-album'),
        offlineTestTrack(id: 'fourth', albumId: 'later-album'),
      ];
    final artwork = _RecordingArtworkPreloader();
    final harness = _Harness(authenticated: true, connection: connection, shuffleArtworkPreloader: artwork);
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    await harness.controller.restoreSession();
    harness.controller.updateShuffleMode(ShuffleMode.all, scope: ActionScope.server);

    await harness.controller.queueShuffle(scope: 'library');

    expect(artwork.current.map((request) => request.source), [
      connection.buildAlbumCoverUrl('shared-album'),
      connection.buildAlbumCoverUrl('other-album'),
    ]);
    expect(harness.audio.starts.single.trackId, 'first');
  });

  test('server shuffle preloads the local cover selected by playback widgets', () async {
    final connection = _Connection()
      ..trackResponse = [
        offlineTestTrack(id: 'first', albumArtPath: ' C:/covers/album.png '),
        offlineTestTrack(id: 'second', albumId: 'remote-album'),
      ];
    final artwork = _RecordingArtworkPreloader();
    final harness = _Harness(authenticated: true, connection: connection, shuffleArtworkPreloader: artwork);
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    await harness.controller.restoreSession();
    harness.controller.updateShuffleMode(ShuffleMode.all, scope: ActionScope.server);

    await harness.controller.queueShuffle(scope: 'library');

    expect(artwork.current.map((request) => request.source), [
      'C:/covers/album.png',
      connection.buildAlbumCoverUrl('remote-album'),
    ]);
    expect(artwork.current.first.headers, isEmpty);
    expect(artwork.current.last.headers, harness.controller.artworkHeaders);
  });

  test('a delayed shuffle refill warms the next page as it enters the artwork window', () async {
    final connection = _WindowShuffleConnection()..distinctAlbumIds = true;
    final artwork = _RecordingArtworkPreloader();
    final harness = _Harness(authenticated: true, connection: connection, shuffleArtworkPreloader: artwork);
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    await harness.controller.restoreSession();
    harness.controller.updateShuffleMode(ShuffleMode.all, scope: ActionScope.server);
    await harness.controller.queueShuffle(scope: 'library');
    final reply = Completer<ShuffleSessionPage>();
    connection.pendingPage = reply.future;
    for (var i = 0; i < 8; i++) {
      await harness.controller.nextTrack();
    }
    expect(connection.pageOffsets, [10]);
    expect(artwork.current.map((request) => request.source), [
      connection.buildAlbumCoverUrl('album-8'),
      connection.buildAlbumCoverUrl('album-9'),
    ]);
    final starts = harness.audio.starts.length;

    reply.complete(connection.page('window-1', 10));
    await _resumeUntil(
      () => artwork.current.any((request) => request.source == connection.buildAlbumCoverUrl('album-10')),
    );

    expect(artwork.current.map((request) => request.source), [
      for (var i = 8; i < 11; i++) connection.buildAlbumCoverUrl('album-$i'),
    ]);
    expect(harness.controller.playbackState.track?.id, 'deck-track-8');
    expect(harness.audio.starts, hasLength(starts));

    await harness.controller.nextTrack();

    expect(artwork.current.map((request) => request.source), [
      for (var i = 9; i < 12; i++) connection.buildAlbumCoverUrl('album-$i'),
    ]);
  });

  test('stopping shuffle clears artwork warming and rejects a late page refill', () async {
    final connection = _WindowShuffleConnection()..distinctAlbumIds = true;
    final artwork = _RecordingArtworkPreloader();
    final harness = _Harness(authenticated: true, connection: connection, shuffleArtworkPreloader: artwork);
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    await harness.controller.restoreSession();
    harness.controller.updateShuffleMode(ShuffleMode.all, scope: ActionScope.server);
    await harness.controller.queueShuffle(scope: 'library');
    final reply = Completer<ShuffleSessionPage>();
    connection.pendingPage = reply.future;
    for (var i = 0; i < 6; i++) {
      await harness.controller.nextTrack();
    }
    expect(connection.pageOffsets, [10]);
    final clears = artwork.clears;

    await harness.controller.stop();
    final updates = artwork.updates.length;
    expect(artwork.clears, greaterThan(clears));
    expect(artwork.current, isEmpty);
    reply.complete(connection.page('window-1', 10));
    await Future<void>.delayed(Duration.zero);

    expect(artwork.updates, hasLength(updates));
    expect(artwork.current, isEmpty);
    expect(harness.controller.playbackState.track, isNull);
  });

  test('a paused restored shuffle deck warms artwork around its absolute cursor', () async {
    final connection = _ResumeConnection();
    final tracks = [for (var i = 0; i < 20; i++) offlineTestTrack(id: 'resume-$i', albumId: 'album-$i')];
    connection.trackResponse = tracks;
    connection.snapshot = AccountPlaybackSnapshot(
      revision: 7,
      generation: 'saved-generation',
      checkpoint: PlaybackResumeCheckpoint(
        trackId: tracks[12].id,
        source: PlaybackSourceContext(kind: 'playlist', id: 'saved-list'),
        shuffleMode: ShuffleMode.currentPlaylist,
        shuffleContext: PlaybackSourceContext(kind: 'playlist', id: 'saved-list'),
        deckId: 'durable',
        cursor: 12,
      ),
    );
    final artwork = _RecordingArtworkPreloader();
    final harness = _Harness(authenticated: true, connection: connection, shuffleArtworkPreloader: artwork);
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    await harness.controller.restoreSession();
    await _resumeUntil(() => harness.controller.playbackState.track?.id == tracks[12].id);

    expect(artwork.current.map((request) => request.source), [
      for (var i = 12; i < 15; i++) connection.buildAlbumCoverUrl('album-$i'),
    ]);
    expect(harness.controller.playbackState.isPlaying, isFalse);
    expect(harness.audio.starts, isEmpty);
    expect(connection.saved, isEmpty);
  });

  test('rapid initial Next actions share one server shuffle deck and retain both steps', () async {
    final connection = _WindowShuffleConnection();
    final harness = _Harness(authenticated: true, connection: connection);
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    await harness.controller.restoreSession();
    final initial = Completer<ShuffleSessionPage>();
    connection.pendingCreate = initial.future;
    harness.controller.updateShuffleMode(ShuffleMode.all, scope: ActionScope.server);
    final firstNext = harness.controller.nextTrack();
    await connection.createStarted.future;
    final secondNext = harness.controller.nextTrack();
    initial.complete(connection.page('window-1', 0));
    await Future.wait([firstNext, secondNext]);
    expect(connection.creates, 1);
    expect(harness.audio.starts.map((start) => start.trackId), ['deck-track-0', 'deck-track-1']);
    expect(harness.controller.playbackState.track?.id, 'deck-track-1');
  });

  test('a stale initial Next action cannot advance a replacement ordinary queue', () async {
    final connection = _WindowShuffleConnection();
    final harness = _Harness(authenticated: true, connection: connection);
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    await harness.controller.restoreSession();
    final initial = Completer<ShuffleSessionPage>();
    connection.pendingCreate = initial.future;
    harness.controller.updateShuffleMode(ShuffleMode.all, scope: ActionScope.server);
    final next = harness.controller.nextTrack();
    await connection.createStarted.future;
    harness.controller.updateShuffleMode(ShuffleMode.off, scope: ActionScope.server);
    await harness.controller.queueAlbum('album');
    initial.complete(connection.page('window-1', 0));
    await next;
    expect(harness.audio.starts.map((start) => start.trackId), ['track']);
    expect(harness.controller.playbackState.track?.id, 'track');
  });

  for (final creating in [true, false]) {
    test('Stop cancels pending server shuffle ${creating ? 'creation' : 'prefetch'}', () async {
      final connection = _WindowShuffleConnection();
      final harness = _Harness(authenticated: true, connection: connection);
      addTearDown(harness.controller.close);
      await harness.controller.initialize();
      await harness.controller.restoreSession();
      harness.controller.updateShuffleMode(ShuffleMode.all, scope: ActionScope.server);
      final reply = Completer<ShuffleSessionPage>();
      Future<void>? starting;
      if (creating) {
        connection.pendingCreate = reply.future;
        starting = harness.controller.queueShuffle(scope: 'library');
        await connection.createStarted.future;
      } else {
        await harness.controller.queueShuffle(scope: 'library');
        connection.pendingPage = reply.future;
        for (var i = 0; i < 6; i++) {
          await harness.controller.nextTrack();
        }
      }
      await harness.controller.stop();
      final starts = harness.audio.starts.length;
      reply.complete(connection.page('window-1', creating ? 0 : 10));
      await starting;
      await Future<void>.delayed(Duration.zero);
      expect(harness.controller.playbackState.track, isNull);
      expect(harness.controller.playbackState.isPlaying, isFalse);
      expect(harness.audio.starts, hasLength(starts));
      expect(connection.released, contains('window-1'));
    });
  }

  test('failed shuffle initialization releases its session and cannot reuse an uninitialized deck', () async {
    final connection = _WindowShuffleConnection();
    final harness = _Harness(authenticated: true, connection: connection);
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    await harness.controller.restoreSession();
    await harness.controller.queueAlbum('album');
    harness.controller.updateShuffleMode(ShuffleMode.all, scope: ActionScope.server);
    connection.initialPageEmpty = true;
    connection.pageFailure = ApiException(503, 'Temporary initialization failure');
    await harness.controller.queueServerShuffle(scope: 'library', play: false, startTrackId: 'track');
    expect(connection.released, contains('window-1'));
    connection.initialPageEmpty = false;
    connection.pageFailure = null;
    await harness.controller.nextTrack();
    expect(connection.creates, 2);
    expect(harness.controller.playbackState.track?.id, 'deck-track-0');
  });

  test('Repeat One preserves a current track outside a refreshed shuffle deck', () async {
    final connection = _WindowShuffleConnection();
    final harness = _Harness(authenticated: true, connection: connection);
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    await harness.controller.restoreSession();
    await harness.controller.queueAlbum('album');
    harness.controller.updateShuffleMode(ShuffleMode.all, scope: ActionScope.server);
    await harness.controller.queueServerShuffle(scope: 'library', play: false, startTrackId: 'track');
    harness.controller.toggleRepeatMode();
    await Future<void>.delayed(const Duration(milliseconds: 1250));
    harness.audio.active = false;
    harness.onComplete!();
    await Future<void>.delayed(Duration.zero);
    expect(harness.controller.playbackState.track?.id, 'track');
    expect(harness.audio.starts.last.trackId, 'track');
    await harness.controller.nextTrack();
    expect(harness.controller.playbackState.track?.id, 'deck-track-0');
  });

  test('server shuffle preserves order across windows and begins a new pass only at true deck end', () async {
    final connection = _WindowShuffleConnection();
    final harness = _Harness(authenticated: true, connection: connection);
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    await harness.controller.restoreSession();
    harness.controller.updateShuffleMode(ShuffleMode.all, scope: ActionScope.server);
    await harness.controller.queueShuffle(scope: 'library');
    expect(harness.controller.playbackState.track?.id, 'deck-track-0');
    expect(connection.pageOffsets, isEmpty);
    for (var i = 1; i < 35; i++) {
      await harness.controller.nextTrack();
      expect(harness.controller.playbackState.track?.id, 'deck-track-$i');
      expect(connection.creates, 1);
    }
    expect(connection.pageOffsets, [10, 20, 30]);
    expect(harness.audio.queueIds.last, ['deck-track-34']);
    await harness.controller.prevTrack();
    expect(harness.controller.playbackState.track?.id, 'deck-track-33');
    await harness.controller.nextTrack();
    expect(harness.controller.playbackState.track?.id, 'deck-track-34');
    await harness.controller.nextTrack(fromAutoAdvance: true);
    expect(connection.creates, 2);
    expect(harness.controller.playbackState.track?.id, 'deck-track-0');
    expect(connection.released, contains('window-1'));
  });

  test('all server shuffle rules use the paged session API', () async {
    final connection = _WindowShuffleConnection();
    final harness = _Harness(authenticated: true, connection: connection);
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    await harness.controller.restoreSession();
    for (final mode in [
      ShuffleMode.all,
      ShuffleMode.artist,
      ShuffleMode.album,
      ShuffleMode.custom,
      ShuffleMode.liked,
      ShuffleMode.currentPlaylist,
    ]) {
      harness.controller.updateShuffleMode(mode, scope: ActionScope.server);
      await harness.controller.queueServerShuffle(
        scope: mode == ShuffleMode.currentPlaylist ? 'playlist' : 'library',
        artistId: mode == ShuffleMode.artist ? 'artist' : null,
        albumId: mode == ShuffleMode.album ? 'album' : null,
        playlistId: mode == ShuffleMode.currentPlaylist ? 'playlist' : null,
      );
    }
    expect(connection.modes, ['all', 'artist', 'album', 'custom', 'liked', 'playlist']);
    expect(connection.requestIds.toSet(), hasLength(6));
    expect(connection.clientIds.toSet(), hasLength(1));
    expect(connection.pageOffsets, isEmpty);
  });

  test('shuffle navigation preserves updated likes and current track metadata', () async {
    final connection = _WindowShuffleConnection();
    final harness = _Harness(authenticated: true, connection: connection);
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    await harness.controller.restoreSession();
    harness.controller.updateShuffleMode(ShuffleMode.all, scope: ActionScope.server);
    await harness.controller.queueShuffle(scope: 'library');
    await harness.controller.toggleLike(harness.controller.playbackState.track!);
    expect(harness.controller.playbackState.track?.liked, isTrue);
    await harness.controller.nextTrack();
    await harness.controller.prevTrack();
    expect(harness.controller.playbackState.track?.id, 'deck-track-0');
    expect(harness.controller.playbackState.track?.liked, isTrue);
  });

  test(
    'expired shuffle sessions recover with a new deck while transient page errors retain the existing deck',
    () async {
      final connection = _WindowShuffleConnection();
      final harness = _Harness(authenticated: true, connection: connection);
      addTearDown(harness.controller.close);
      await harness.controller.initialize();
      await harness.controller.restoreSession();
      harness.controller.updateShuffleMode(ShuffleMode.all, scope: ActionScope.server);
      await harness.controller.queueShuffle(scope: 'library');
      connection.pageFailure = ApiException(503, 'Temporarily unavailable');
      for (var i = 0; i < 10; i++) {
        await harness.controller.nextTrack();
      }
      expect(connection.creates, 1);
      expect(harness.controller.playbackState.track?.id, 'deck-track-9');
      connection.pageFailure = ApiException(404, 'Session expired');
      await harness.controller.nextTrack();
      expect(connection.creates, 2);
      expect(harness.controller.playbackState.track?.id, 'deck-track-0');
    },
  );

  test('switching queues or accounts discards pending server shuffle pages', () async {
    final connection = _WindowShuffleConnection();
    final harness = _Harness(authenticated: true, connection: connection);
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    await harness.controller.restoreSession();
    harness.controller.updateShuffleMode(ShuffleMode.all, scope: ActionScope.server);
    await harness.controller.queueShuffle(scope: 'library');
    final page = Completer<ShuffleSessionPage>();
    connection.pendingPage = page.future;
    for (var i = 0; i < 6; i++) {
      await harness.controller.nextTrack();
    }
    expect(connection.pageOffsets, [10]);
    harness.controller.updateShuffleMode(ShuffleMode.off, scope: ActionScope.server);
    await harness.controller.queueAlbum('album');
    final ordinary = harness.controller.playbackState.track?.id;
    page.complete(connection.page('window-1', 10));
    await Future<void>.delayed(Duration.zero);
    expect(harness.controller.playbackState.track?.id, ordinary);
    expect(connection.released, contains('window-1'));
    harness.controller.loginWithToken(baseUrl: connection.baseUrl, token: 'other-account');
    expect(harness.controller.playbackState.track, isNull);
  });

  test('account switches clear personal server caches and stale reads cannot refill them', () async {
    final connection = _IsolationConnection();
    final harness = _Harness(authenticated: true, connection: connection);
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    await harness.controller.restoreSession();
    final oldTrack = offlineTestTrack(id: 'old').copyWith(liked: true, inPlaylists: true);
    final oldPlaylist = Playlist(id: 'old', name: 'Old private list', trackIds: ['old']);
    connection.trackResponse = [oldTrack];
    connection.playlistResponse = [oldPlaylist];
    await Future.wait([
      harness.controller.loadLikedTracks(),
      harness.controller.loadPlaylists(),
      harness.controller.loadPlaylistTracks('old'),
      harness.controller.loadTracks('album'),
    ]);
    expect(harness.controller.liked.single.id, 'old');
    expect(harness.controller.playlists.single.id, 'old');
    expect(harness.controller.tracks.single.liked, isTrue);

    final liked = Completer<List<Track>>();
    final lists = Completer<List<Playlist>>();
    final tracks = Completer<List<Track>>();
    connection.pendingLiked = liked.future;
    connection.pendingPlaylists = lists.future;
    connection.pendingCollectionTracks = tracks.future;
    final stale = Future.wait([
      harness.controller.loadLikedTracks(),
      harness.controller.loadPlaylists(),
      harness.controller.loadPlaylistTracks('old'),
      harness.controller.loadTracks('album'),
    ]);
    harness.controller.loginWithToken(baseUrl: connection.baseUrl, token: 'second-account');
    expect(harness.controller.liked, isEmpty);
    expect(harness.controller.playlists, isEmpty);
    expect(harness.controller.playlistTracks, isEmpty);
    expect(harness.controller.tracks, isEmpty);

    connection.pendingLiked = null;
    connection.pendingPlaylists = null;
    connection.pendingCollectionTracks = null;
    connection.trackResponse = [offlineTestTrack(id: 'new')];
    connection.playlistResponse = [
      Playlist(id: 'new', name: 'New list', trackIds: ['new']),
    ];
    await Future.wait([
      harness.controller.loadLikedTracks(),
      harness.controller.loadPlaylists(),
      harness.controller.loadPlaylistTracks('new'),
      harness.controller.loadTracks('album'),
    ]);
    liked.complete([oldTrack]);
    lists.complete([oldPlaylist]);
    tracks.complete([oldTrack]);
    await stale;
    expect(harness.controller.liked.single.id, 'new');
    expect(harness.controller.playlists.single.id, 'new');
    expect(harness.controller.playlistTracks.single.id, 'new');
    expect(harness.controller.tracks.single.id, 'new');
  });

  test('account switches discard stale like writes and stop follow-up playlist artwork writes', () async {
    final connection = _IsolationConnection();
    final harness = _Harness(authenticated: true, connection: connection);
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    await harness.controller.restoreSession();
    final liking = Completer<ServerLikeState?>();
    final creating = Completer<Playlist>();
    connection.pendingLikeWrite = liking.future;
    connection.pendingCreate = creating.future;
    final oldLike = harness.controller.toggleLike(offlineTestTrack(id: 'old'));
    final oldCreate = harness.controller.createPlaylist('Old list', imageEdit: const PlaylistImageEdit.clear());
    harness.controller.loginWithToken(baseUrl: connection.baseUrl, token: 'second-account');
    liking.complete(ServerLikeState(trackId: 'old', liked: true, updatedAt: 1));
    creating.complete(Playlist(id: 'old', name: 'Old list', trackIds: [], imageRef: 'old-cover'));
    await Future.wait([oldLike, oldCreate]);
    expect(harness.controller.liked, isEmpty);
    expect(harness.controller.playlists, isEmpty);
    expect(connection.coverDeletes, 0);
  });

  test('stale personal playlist queues cannot start playback after an account switch', () async {
    final connection = _IsolationConnection();
    final harness = _Harness(authenticated: true, connection: connection);
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    await harness.controller.restoreSession();
    final tracks = Completer<List<Track>>();
    connection.pendingCollectionTracks = tracks.future;
    final queued = harness.controller.queuePlaylist('old-private-list');
    harness.controller.loginWithToken(baseUrl: connection.baseUrl, token: 'second-account');
    tracks.complete([offlineTestTrack(id: 'old')]);
    await queued;
    expect(harness.audio.starts, isEmpty);
    expect(harness.controller.playbackState.track, isNull);
  });

  test('an older account playback settings reply cannot replace the current repeat mode', () async {
    final connection = _IsolationConnection();
    final harness = _Harness(connection: connection);
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    final old = Completer<PlaybackSettingsResponse>();
    connection.settingsByToken['first-account'] = old.future;
    harness.controller.loginWithToken(baseUrl: connection.baseUrl, token: 'first-account');
    await connection.waitForSettings('first-account');
    expect(connection.settingsRequested, contains('first-account'));
    harness.controller.loginWithToken(baseUrl: connection.baseUrl, token: 'second-account');
    await connection.waitForSettings('second-account');
    old.complete(PlaybackSettingsResponse(repeatMode: 'one'));
    await Future<void>.delayed(Duration.zero);
    expect(harness.controller.playbackState.repeatMode, PlaybackRepeatMode.off);
  });

  test('saved device repeat mode skips account settings and remains unchanged across accounts', () async {
    final connection = _IsolationConnection();
    final harness = _Harness(connection: connection);
    harness.preferences.repeatMode = PlaybackRepeatMode.one;
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    expect(harness.controller.playbackState.repeatMode, PlaybackRepeatMode.one);

    harness.controller.loginWithToken(baseUrl: connection.baseUrl, token: 'first-account');
    await Future<void>.delayed(Duration.zero);
    harness.controller.loginWithToken(baseUrl: connection.baseUrl, token: 'second-account');
    await Future<void>.delayed(Duration.zero);
    expect(connection.settingsRequested, isEmpty);
    expect(harness.controller.playbackState.repeatMode, PlaybackRepeatMode.one);
  });

  test('an offline repeat toggle wins over a late device preference load', () async {
    final harness = _Harness();
    final stored = Completer<PlaybackRepeatMode?>();
    harness.preferences.pendingRepeat = stored.future;
    addTearDown(harness.controller.close);
    final initialization = harness.controller.initialize();
    await Future<void>.delayed(Duration.zero);

    harness.controller.toggleRepeatMode();
    stored.complete(PlaybackRepeatMode.off);
    await initialization;
    expect(harness.controller.playbackState.repeatMode, PlaybackRepeatMode.one);
    expect(harness.preferences.repeatWrites, [PlaybackRepeatMode.one]);
    expect(harness.connection.repeatUpdates, isEmpty);
  });

  test('legacy server repeat migrates once and never follows a different account', () async {
    final connection = _IsolationConnection();
    connection.settingsByToken['first-account'] = Future.value(PlaybackSettingsResponse(repeatMode: 'one'));
    final harness = _Harness(connection: connection);
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    harness.controller.loginWithToken(baseUrl: connection.baseUrl, token: 'first-account');
    await connection.waitForSettings('first-account');
    await Future<void>.delayed(Duration.zero);
    expect(harness.controller.playbackState.repeatMode, PlaybackRepeatMode.one);
    expect(harness.preferences.repeatWrites, [PlaybackRepeatMode.one]);

    harness.controller.loginWithToken(baseUrl: connection.baseUrl, token: 'second-account');
    await Future<void>.delayed(Duration.zero);
    expect(connection.settingsRequested, ['first-account']);
    expect(harness.controller.playbackState.repeatMode, PlaybackRepeatMode.one);
    expect(connection.repeatUpdates, isEmpty);
  });

  test('a local repeat toggle wins over late legacy server settings', () async {
    final connection = _IsolationConnection();
    final stored = Completer<PlaybackSettingsResponse>();
    connection.settingsByToken['first-account'] = stored.future;
    final harness = _Harness(connection: connection);
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    harness.controller.loginWithToken(baseUrl: connection.baseUrl, token: 'first-account');
    await connection.waitForSettings('first-account');

    harness.controller.toggleRepeatMode();
    stored.complete(PlaybackSettingsResponse(repeatMode: 'off'));
    await Future<void>.delayed(Duration.zero);
    expect(harness.controller.playbackState.repeatMode, PlaybackRepeatMode.one);
    expect(harness.preferences.repeatWrites, [PlaybackRepeatMode.one]);
    expect(connection.repeatUpdates, isEmpty);
  });

  test('local filter edits win over late settings and legacy server filters stay inactive', () async {
    final harness = _Harness();
    final stored = Completer<CustomShuffleSettings>();
    harness.shuffle.pending = stored.future;
    addTearDown(harness.controller.close);
    final initialization = harness.controller.initialize();
    await Future<void>.delayed(Duration.zero);

    await harness.controller.updateCustomShuffleSettings(localArtistIds: ['chosen-local'], localGenres: ['Jazz']);
    stored.complete(
      const CustomShuffleSettings(
        artistIds: ['legacy-server'],
        genres: ['rock'],
        localArtistIds: ['old-local'],
        localGenres: ['pop'],
      ),
    );
    await initialization;
    expect(harness.controller.customShuffleArtistIds, isEmpty);
    expect(harness.controller.customShuffleGenres, isEmpty);
    expect(harness.controller.localCustomShuffleArtistIds, ['chosen-local']);
    expect(harness.controller.localCustomShuffleGenres, ['jazz']);
  });

  test('a superseded local settings load cannot replace a newer load', () async {
    final harness = _Harness();
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    final first = Completer<CustomShuffleSettings>();
    harness.shuffle.pending = first.future;
    final old = harness.controller.loadCustomShuffleSettings();
    harness.shuffle.pending = Future.value(const CustomShuffleSettings(localArtistIds: ['latest']));
    await harness.controller.loadCustomShuffleSettings();
    first.complete(const CustomShuffleSettings(localArtistIds: ['stale']));
    await old;
    expect(harness.controller.localCustomShuffleArtistIds, ['latest']);
  });

  test('disconnect removes the server address, session and identity while retaining other origins', () async {
    _mockTrustVault();
    final connection = _PasswordConnection();
    final harness = _Harness(authenticated: true, connection: connection);
    addTearDown(harness.controller.close);
    await harness.startRemote();
    const target = 'https://unused.test';
    const other = 'https://another-remembered.test:3000/api';
    await ServerTrustStore.write(target, testServerTrust);
    await ServerTrustStore.write(other, testServerTrust);
    ServerTrustRegistry.register(other, testServerTrust);
    final revision = harness.connection.sessionRevision;

    await harness.controller.logout();

    expect(harness.connection.sessionRevision, greaterThan(revision));
    expect(harness.connection.token, isNull);
    expect(harness.connection.trust, isNull);
    expect(harness.connection.baseUrl, isEmpty);
    expect(harness.controller.authState.baseUrl, isEmpty);
    expect(ServerTrustRegistry.lookup(target), isNull);
    expect(await ServerTrustStore.read(target), isNull);
    expect(await harness.controller.loadSavedCredentials(), isNull);
    expect(harness.auth.clears, 1);
    expect(harness.controller.authState.isAuthorized, isFalse);
    expect(harness.controller.playbackState.track, isNull);
    expect(connection.logoutRequests, 1);
    expect(harness.downloads.pausedServers, contains(target));
    expect((await ServerTrustStore.read(other))?.opaqueKey, testServerTrust.opaqueKey);
    expect(ServerTrustRegistry.lookup(other), testServerTrust);
  });

  test('session restoration cannot reinstate an identity while disconnecting', () async {
    _mockTrustVault();
    final connection = _PasswordConnection();
    final harness = _Harness(authenticated: true, connection: connection);
    addTearDown(harness.controller.close);
    await harness.startRemote();
    final clearing = Completer<void>();
    final finishClear = Completer<void>();
    harness.auth.clearingServer = clearing;
    harness.auth.clearServerResponse = finishClear.future;

    final disconnecting = harness.controller.logout();
    await clearing.future;
    await harness.controller.restoreSession();
    await harness.controller.loginWithPassword(
      baseUrl: 'https://unused.test',
      username: 'test',
      password: 'secret',
      rememberMe: true,
    );
    expect(harness.connection.trust, isNull);
    expect(harness.connection.token, isNull);
    expect(harness.controller.authState.isAuthorized, isFalse);

    finishClear.complete();
    await disconnecting;
    expect(harness.connection.trust, isNull);
    expect(ServerTrustRegistry.lookup('https://unused.test'), isNull);
    expect(harness.connection.baseUrl, isEmpty);
    expect(await harness.controller.loadSavedCredentials(), isNull);
    expect(connection.logoutRequests, 1);
  });

  test('disconnect during post-login port discovery cannot authorize or remember the old identity', () async {
    _mockTrustVault();
    final connection = _DelayedLoginConnection();
    final harness = _Harness(connection: connection);
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    final login = harness.controller.loginWithPassword(
      baseUrl: 'https://unused.test',
      username: 'test',
      password: 'secret',
      rememberMe: true,
    );
    await connection.portsRequested.future;

    await harness.controller.logout();
    connection.portsResponse.complete(ServerPortsResponse(httpPort: 3000, quicPort: 3001, quicEnabled: true));
    await login;

    expect(harness.connection.token, isNull);
    expect(harness.connection.trust, isNull);
    expect(ServerTrustRegistry.lookup('https://unused.test'), isNull);
    expect(harness.connection.baseUrl, isEmpty);
    expect(harness.controller.authState.isAuthorized, isFalse);
    expect(harness.controller.hasSavedCredentials, isFalse);
    expect(await harness.controller.loadSavedCredentials(), isNull);
    expect(await ServerTrustStore.read('https://unused.test'), isNull);
    expect(connection.logoutRequests, 1);
  });

  test('disconnect cancels a password login before it changes the selected server', () async {
    _mockTrustVault();
    final connection = _DelayedLoginConnection();
    connection.portsResponse.complete(ServerPortsResponse(httpPort: 3000, quicPort: 3001, quicEnabled: true));
    final harness = _Harness(connection: connection);
    addTearDown(harness.controller.close);
    await harness.controller.initialize();

    final login = harness.controller.loginWithPassword(
      baseUrl: 'https://new-target.test:3000/api',
      username: 'test',
      password: 'secret',
      rememberMe: true,
    );
    final disconnect = harness.controller.logout();
    await Future.wait([login, disconnect]);

    expect(connection.portsRequested.isCompleted, isFalse);
    expect(connection.token, isNull);
    expect(connection.baseUrl, isEmpty);
    expect(harness.controller.authState.isAuthorized, isFalse);
    expect(harness.controller.hasSavedCredentials, isFalse);
    expect(ServerTrustRegistry.lookup('https://new-target.test:3000/api'), isNull);
  });

  test('key rotation disconnects remote playback and requires password sign-in', () async {
    final events = StreamController<MetadataUpdateEvent>();
    final connection = _Connection()..metadataEvents = events.stream;
    final harness = _Harness(authenticated: true, connection: connection);
    addTearDown(harness.controller.close);
    addTearDown(events.close);
    await harness.startRemote();
    events.add(MetadataUpdateEvent(revision: 1, kind: 'session_invalidated', id: 'server_keys_rotated', updatedAt: 0));
    await Future<void>.delayed(Duration.zero);
    expect(connection.token, isNull);
    expect(harness.controller.authState.requiresSignIn, isTrue);
    expect(harness.controller.authState.baseUrl, 'https://unused.test');
    expect(harness.controller.playbackState.isPlaying, isFalse);
    expect(harness.controller.playbackState.track, isNull);
    expect(harness.auth.clears, 1);
    expect(await harness.controller.loadSavedCredentials(), isNull);
    expect(connection.trust, testServerTrust);
    connection.pendingHealth = Future.value(25);
    await harness.controller.refreshServerAvailability();
    expect(harness.controller.authState.requiresSignIn, isTrue);
    expect(connection.token, isNull);
  });

  test('missed rotation notification is detected without replacing the saved pin', () async {
    final harness = _Harness(authenticated: true);
    addTearDown(harness.controller.close);
    await harness.startRemote();
    harness.connection.identityChanged = true;
    await harness.controller.refreshServerAvailability();
    expect(harness.connection.token, isNull);
    expect(harness.controller.authState.requiresSignIn, isTrue);
    expect(harness.controller.playbackState.track, isNull);
    expect(harness.connection.trust, testServerTrust);
    expect(harness.auth.clears, 1);
  });

  test('a delayed identity check cannot invalidate a newer session', () async {
    final harness = _Harness(authenticated: true);
    addTearDown(harness.controller.close);
    await harness.startRemote();
    final checked = Completer<bool>();
    harness.connection.pendingIdentityCheck = checked.future;
    final refresh = harness.controller.refreshServerAvailability();
    await Future<void>.delayed(Duration.zero);
    harness.controller.loginWithToken(baseUrl: 'https://unused.test', token: 'new-token');
    checked.complete(true);
    await refresh;
    expect(harness.connection.token, 'new-token');
    expect(harness.controller.authState.requiresSignIn, isFalse);
    expect(harness.auth.clears, 0);
  });

  test('saved session with a rotated key requires sign-in on startup', () async {
    final connection = _Connection()
      ..identityChanged = true
      ..playbackSettingsFailure = true;
    final harness = _Harness(authenticated: true, connection: connection);
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    await harness.controller.restoreSession();
    expect(connection.token, isNull);
    expect(harness.controller.authState.requiresSignIn, isTrue);
    expect(harness.auth.clears, 1);
  });

  test('startup cleanup retains a remembered connection when its server is unavailable', () async {
    _mockTrustVault();
    final directory = await Directory.systemTemp.createTemp('phonolite_startup_auth_');
    addTearDown(() => directory.delete(recursive: true));
    final storage = AuthStorage(files: SettingsFiles(directoryProvider: () async => directory));
    final connection = _Connection()..playbackSettingsFailure = true;
    final credentials = AuthCredentials(
      baseUrl: connection.baseUrl,
      token: 'saved-offline-token',
      username: 'listener',
      trust: testServerTrust,
    );
    const orphan = 'https://orphaned-startup.test:3000/api';
    await storage.write(credentials);
    await ServerTrustStore.write(credentials.baseUrl, credentials.trust);
    await ServerTrustStore.write(orphan, testServerTrust);

    await storage.removeOrphanedCredentials();
    final harness = _Harness(connection: connection, authStorage: storage);
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    await harness.controller.restoreSession();

    expect(harness.controller.authState.status, SessionStatus.serverUnavailable);
    expect(harness.controller.hasSavedCredentials, isTrue);
    expect(harness.controller.savedBaseUrl, credentials.baseUrl);
    expect(connection.token, credentials.token);
    expect(connection.trust?.toJson(), credentials.trust.toJson());
    expect((await storage.read())?.toJson(), credentials.toJson());
    expect((await ServerTrustStore.read(credentials.baseUrl))?.toJson(), credentials.trust.toJson());
    expect(await ServerTrustStore.read(orphan), isNull);
  });

  test('paused quality selection is applied when playback resumes', () async {
    final harness = _Harness(authenticated: true);
    addTearDown(harness.controller.close);
    await harness.startRemote();
    harness.onStats!(const Duration(seconds: 5), const Duration(seconds: 3), 160, null, false);
    await harness.controller.pause(true);
    harness.controller.updateStreamMode(StreamMode.low);
    await Future<void>.delayed(Duration.zero);
    expect(harness.controller.playbackState.isPlaying, isFalse);
    expect(harness.audio.starts.last.initialPaused, isTrue);
    expect(harness.audio.starts.last.offset, const Duration(seconds: 5));
    await harness.controller.pause(false);
    await Future<void>.delayed(Duration.zero);
    expect(harness.audio.settings.last.quality, 'low');
    expect(harness.audio.settings.last.mode, 'fixed');
  });

  test('quality selection bypasses duplicate-start suppression at the same position', () async {
    final harness = _Harness(authenticated: true);
    addTearDown(harness.controller.close);
    await harness.startRemote();
    // No clock/position advancement: selecting a different encoder setting
    // must not be discarded as a duplicate press of the same track.
    harness.controller.updateStreamMode(StreamMode.medium);
    await Future<void>.delayed(Duration.zero);
    expect(harness.audio.settings.last.quality, 'medium');
    expect(harness.audio.settings.last.frameMs, 20);
    harness.controller.updateStreamMode(StreamMode.low);
    await Future<void>.delayed(Duration.zero);
    expect(harness.audio.settings.last.quality, 'low');
  });

  test('selecting the current streaming quality does not restart output', () async {
    final harness = _Harness(authenticated: true);
    addTearDown(harness.controller.close);
    await harness.startRemote();
    expect(harness.controller.playbackState.streamMode, StreamMode.original);
    expect(harness.audio.settings.single.isOriginal, isTrue);
    harness.controller.updateStreamMode(StreamMode.original);
    await Future<void>.delayed(Duration.zero);
    expect(harness.audio.starts, hasLength(1));
  });

  test('Original selection restarts at the paused position without requesting Opus', () async {
    final harness = _Harness(authenticated: true);
    addTearDown(harness.controller.close);
    harness.controller.updateStreamMode(StreamMode.high);
    await harness.startRemote();
    harness.onStats!(const Duration(seconds: 7), const Duration(seconds: 2), 160, null, false);
    await harness.controller.pause(true);

    harness.controller.updateStreamMode(StreamMode.original);
    await Future<void>.delayed(Duration.zero);

    expect(harness.controller.playbackState.streamMode, StreamMode.original);
    expect(harness.controller.playbackState.isPlaying, isFalse);
    expect(harness.audio.starts.last.offset, const Duration(seconds: 7));
    expect(harness.audio.starts.last.initialPaused, isTrue);
    expect(harness.audio.settings.last.isOriginal, isTrue);
    expect(harness.audio.settings.last.quality, 'source');

    harness.controller.updateStreamMode(StreamMode.high);
    await Future<void>.delayed(Duration.zero);

    expect(harness.audio.settings.last.mode, 'fixed');
    expect(harness.audio.settings.last.quality, 'high');
    expect(harness.audio.settings.last.frameMs, 20);
    expect(harness.audio.starts.last.initialPaused, isTrue);
  });

  test('construction performs no startup work and can be closed without starting', () async {
    final harness = _Harness();
    expect(harness.audioCreations, 0);
    expect(harness.downloads.loads, 0);
    expect(harness.connection.pings, 0);
    expect(harness.preferences.reads, 0);
    expect(harness.shuffle.reads, 0);
    expect(harness.connectivity.checks, 0);
    expect(harness.controller.messages, isEmpty);
    expect(harness.connection.onTransportFailure, isNull);
    await harness.controller.close();
    await harness.controller.close();
    expect(harness.audio.disposals, 0);
    expect(harness.downloads.disposals, 1);
    expect(harness.nowPlaying.disposals, 0);
    await expectLater(harness.controller.initialize(), throwsStateError);
  });

  test('initialization and shutdown each happen once', () async {
    final harness = _Harness();
    final first = harness.controller.initialize();
    expect(harness.controller.initialize(), same(first));
    await first;
    expect(harness.controller.isInitialized, isTrue);
    await harness.controller.initialize();
    expect(harness.audioCreations, 1);
    expect(harness.downloads.loads, 1);
    expect(harness.shuffle.reads, 1);
    expect(harness.connectivity.checks, 1);
    expect(harness.connection.pings, 1);
    expect(harness.audio.volume, 0.4);
    expect(harness.controller.collectionListMode, isTrue);
    expect(harness.connection.onTransportFailure, isNotNull);
    final closing = harness.controller.close();
    expect(harness.controller.close(), same(closing));
    await closing;
    expect(harness.audio.disposals, 1);
    expect(harness.downloads.disposals, 1);
    expect(harness.nowPlaying.disposals, 1);
    expect(harness.vehicle.disposals, 1);
    expect(harness.permissions.disposals, 1);
    expect(harness.connection.onTransportFailure, isNull);
  });

  test('shutdown waits for an accepted device repeat preference write', () async {
    final harness = _Harness();
    final persisted = Completer<void>();
    harness.preferences.pendingRepeatWrite = persisted.future;
    addTearDown(() async {
      if (!persisted.isCompleted) persisted.complete();
      await harness.controller.close();
    });
    await harness.controller.initialize();
    harness.controller.toggleRepeatMode();
    await harness.preferences.repeatWriteStarted.future;

    var closed = false;
    final closing = harness.controller.close();
    unawaited(closing.then((_) => closed = true));
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    expect(harness.preferences.repeatWrites, isEmpty);
    expect(harness.controller.close(), same(closing));

    persisted.complete();
    await closing;
    expect(closed, isTrue);
    expect(harness.preferences.repeatMode, PlaybackRepeatMode.one);
    expect(harness.preferences.repeatWrites, [PlaybackRepeatMode.one]);
  });

  test('shutdown waits for metadata subscription cancellation before completing', () async {
    final cancellation = Completer<void>();
    final cancelling = Completer<void>();
    final events = StreamController<MetadataUpdateEvent>(
      onCancel: () {
        cancelling.complete();
        return cancellation.future;
      },
    );
    final connection = _Connection()..metadataEvents = events.stream;
    final harness = _Harness(authenticated: true, connection: connection);
    addTearDown(() async {
      if (!cancellation.isCompleted) cancellation.complete();
      await harness.controller.close();
      await events.close();
    });
    await harness.startRemote();

    var closed = false;
    final closing = harness.controller.close();
    unawaited(closing.then((_) => closed = true));
    await cancelling.future;
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    expect(harness.controller.close(), same(closing));

    cancellation.complete();
    await closing;
    expect(closed, isTrue);
  });

  test('system media commands keep controlling playback while the desktop window is hidden', () async {
    final connection = _Connection()
      ..trackResponse = [
        _metadataTrack().copyWith(id: 'first', albumId: 'album'),
        _metadataTrack().copyWith(id: 'second', albumId: 'album'),
      ];
    final harness = _Harness(authenticated: true, connection: connection, artworkLoader: _ArtworkLoader());
    harness.nowPlaying.supported = true;
    addTearDown(harness.controller.close);
    await harness.startRemote();
    harness.controller.handleAppLifecycleState(AppLifecycleState.hidden);
    final commands = harness.nowPlaying.commandHandler!;

    await commands(const NativeRemoteCommand(action: NativeRemoteAction.pause));
    expect(harness.controller.playbackState.isPlaying, isFalse);
    expect(harness.audio.pauses, greaterThan(0));
    expect(harness.nowPlaying.updates.last['isPlaying'], isFalse);

    await commands(const NativeRemoteCommand(action: NativeRemoteAction.play));
    expect(harness.controller.playbackState.isPlaying, isTrue);
    expect(harness.audio.resumes, greaterThan(0));

    await commands(const NativeRemoteCommand(action: NativeRemoteAction.seek, position: Duration(milliseconds: 12500)));
    expect(harness.controller.playbackState.position, const Duration(milliseconds: 12500));
    final firstTrack = harness.controller.playbackState.track!.id;
    final starts = harness.audio.starts.length;
    await commands(const NativeRemoteCommand(action: NativeRemoteAction.next));
    expect(harness.audio.starts.length, starts + 1);
    expect(harness.controller.playbackState.track!.id, isNot(firstTrack));
    await commands(const NativeRemoteCommand(action: NativeRemoteAction.previous));
    expect(harness.controller.playbackState.track!.id, firstTrack);

    final clears = harness.nowPlaying.clears;
    await harness.controller.close();
    expect(harness.nowPlaying.clears, greaterThan(clears));
    expect(harness.nowPlaying.commandHandler, isNull);
  });
  for (final nativeArtwork in [true, false]) {
    test('Now Playing loads artwork through ${nativeArtwork ? 'iOS' : 'Flutter'} only', () async {
      final loader = _ArtworkLoader();
      final harness = _Harness(authenticated: true, artworkLoader: loader);
      harness.nowPlaying
        ..supported = true
        ..nativeArtwork = nativeArtwork;
      addTearDown(harness.controller.close);
      await harness.startRemote();
      await harness.controller.pause(true);
      final updates = harness.nowPlaying.updates;
      expect(updates, isNotEmpty);
      expect(updates.last['artworkKey'], 'url:${updates.last['artworkUrl']}');
      expect(updates.last['token'], harness.connection.token);
      expect(updates.last['serverPin'], harness.connection.trust!.spki);
      if (nativeArtwork) {
        expect(loader.loads, 0);
        expect(updates.any((update) => update.containsKey('artworkBytes')), isFalse);
      } else {
        expect(loader.loads, 1);
        expect(updates.last['artworkBytes'], [1, 2, 3]);
      }
    });
  }

  test('local and server shuffle selections remain independent', () async {
    final harness = _Harness();
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    final controller = harness.controller;
    expect(controller.playbackState.localShuffleMode, ShuffleMode.off);
    expect(controller.playbackState.serverShuffleMode, ShuffleMode.off);

    controller.updateShuffleMode(ShuffleMode.liked, scope: ActionScope.local);
    controller.updateShuffleMode(ShuffleMode.all, scope: ActionScope.server);
    expect(controller.playbackState.shuffleMode, ShuffleMode.all);
    expect(controller.playbackState.localShuffleMode, ShuffleMode.liked);

    controller.updateShuffleMode(controller.playbackState.shuffleModeFor(ActionScope.local), scope: ActionScope.local);
    expect(controller.playbackState.shuffleMode, ShuffleMode.liked);
    expect(controller.playbackState.shuffleScope, ActionScope.local);
    expect(controller.playbackState.serverShuffleMode, ShuffleMode.all);

    controller.updateShuffleMode(ShuffleMode.off);
    controller.setVolume(0.6);
    expect(controller.playbackState.localShuffleMode, ShuffleMode.off);
    expect(controller.playbackState.serverShuffleMode, ShuffleMode.all);
    controller.updateShuffleMode(
      controller.playbackState.shuffleModeFor(ActionScope.server),
      scope: ActionScope.server,
    );
    expect(controller.playbackState.shuffleMode, ShuffleMode.all);
    expect(controller.playbackState.shuffleScope, ActionScope.server);
  });

  test('CarPlay server artists include authenticated pinned logo artwork', () async {
    final connection = _Connection()
      ..artistsPageResponse = [
        Artist(id: 'server artist/1', name: 'Artist with artwork', albumCount: 2, logoRef: 'logo version/2'),
        Artist(id: 'no-logo', name: 'No logo', albumCount: 1),
        Artist(id: 'empty-logo', name: 'Empty logo', albumCount: 1, logoRef: '  '),
      ];
    final harness = _Harness(authenticated: true, connection: connection);
    harness.vehicle.supported = true;
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    await harness.controller.restoreSession();

    final response = await harness.vehicle.handler!('getArtists', {'scope': 'server'}) as Map;
    final items = (response['items'] as List).cast<Map>();
    expect(items, hasLength(3));
    final artwork = Uri.parse(items.first['artworkUrl'] as String);
    expect(artwork.pathSegments, contains('server artist/1'));
    expect(artwork.queryParameters['kind'], 'logo');
    expect(artwork.queryParameters['v'], 'logo version/2');
    expect(items.first['token'], 'test-token');
    expect(items.first['serverPin'], testServerTrust.spki);
    expect(items[1].containsKey('artworkUrl'), isFalse);
    expect(items[2].containsKey('artworkUrl'), isFalse);
  });

  for (final initiallyAvailable in [true, false]) {
    test(
      'local and server likes stay independent through ${initiallyAvailable ? 'session restore' : 'reconnect'} and restart',
      () async {
        final root = await Directory.systemTemp.createTemp('local_like_scope_');
        addTearDown(() => root.delete(recursive: true));
        final connection = _LikeConnection()..available = initiallyAvailable;
        final storage = OfflineLibraryStorage(baseDirectory: root);
        final serverTrack = offlineTestTrack(id: 'server-track');
        final media = await offlineTestMediaFile(root, 'download.mp3');
        final download = await storage.prepareDownload(
          offlineTestDownload(
            serverBaseUrl: connection.baseUrl,
            track: serverTrack,
            filePath: media.path,
          ).copyWith(offlineMetadata: offlineTestOfflineMetadata(trackId: serverTrack.id)),
        );
        await storage.upsertDownload(download);
        final manager = OfflineDownloadManager(connection: connection, storage: storage);
        final harness = _Harness(
          authenticated: true,
          connection: connection,
          offlineDownloadManager: manager,
          offlineStorage: storage,
        );
        try {
          await harness.controller.initialize();
          await harness.controller.restoreSession();
          expect(harness.controller.canUseServer, initiallyAvailable);
          final localTrack = harness.controller.offlineTracks.single;
          expect(localTrack.serverTrackId, serverTrack.id);

          await harness.controller.toggleLike(localTrack);
          // Wait beyond the former background sync delay, with a server match
          // available, to detect delayed writes as well as immediate writes.
          await Future<void>.delayed(const Duration(milliseconds: 2100));
          expect(harness.controller.localLiked.single.liked, isTrue);
          expect(connection.likeUpdates, isEmpty);
          expect(connection.matches, 0);

          connection.available = true;
          connection.pendingHealth = Future.value(1);
          await harness.controller.refreshServerAvailability();
          await harness.controller.restoreSession();
          await Future<void>.delayed(const Duration(milliseconds: 50));
          expect(harness.controller.canUseServer, isTrue);
          expect(connection.likeUpdates, isEmpty);
          expect(connection.matches, 0);

          await harness.controller.toggleLike(serverTrack);
          expect(harness.controller.liked.single.title, serverTrack.title);
          await harness.controller.toggleLike(harness.controller.liked.single);
          await Future<void>.delayed(const Duration(milliseconds: 2100));
          expect(connection.likeUpdates, [
            {serverTrack.id: true},
            {serverTrack.id: false},
          ]);
          expect(harness.controller.liked, isEmpty);
          expect(harness.controller.localLiked.single.liked, isTrue);
          expect(connection.matches, 0);
        } finally {
          await harness.controller.close();
          await storage.close();
        }

        final restoredStorage = OfflineLibraryStorage(baseDirectory: root);
        final restoredManager = OfflineDownloadManager(connection: connection, storage: restoredStorage);
        final restoredHarness = _Harness(
          authenticated: true,
          connection: connection,
          offlineDownloadManager: restoredManager,
          offlineStorage: restoredStorage,
        );
        try {
          await restoredHarness.controller.initialize();
          await restoredHarness.controller.restoreSession();
          await Future<void>.delayed(const Duration(milliseconds: 50));
          expect(restoredHarness.controller.localLiked.single.liked, isTrue);
          expect(connection.serverLiked, isFalse);
          await restoredHarness.controller.toggleLike(restoredHarness.controller.localLiked.single);
          await Future<void>.delayed(const Duration(milliseconds: 2100));
          expect(restoredHarness.controller.localLiked, isEmpty);
          expect(await restoredStorage.readLocalLikedTracks(), isEmpty);
          expect(connection.likeUpdates, hasLength(2));
          expect(connection.matches, 0);
        } finally {
          await restoredHarness.controller.close();
          await restoredStorage.close();
        }
      },
    );
  }

  test('Connect only advances after the endpoint health check succeeds', () async {
    final pending = Completer<void>();
    final connection = _Connection()..pendingProbe = pending.future;
    final harness = _Harness(connection: connection);
    addTearDown(harness.controller.close);
    final original = connection.baseUrl;

    final result = harness.controller.probeServer('music.test:8443');
    await Future<void>.delayed(Duration.zero);
    expect(connection.verifiedServers, ['https://music.test:8443/api']);
    expect(harness.controller.authState.status, SessionStatus.checking);
    expect(connection.baseUrl, original);

    pending.complete();
    expect(await result, isTrue);
    expect(harness.controller.authState.status, SessionStatus.serverReachable);
    expect(connection.baseUrl, 'https://music.test:8443/api');
    expect(harness.controller.authState.isAuthorized, isFalse);
  });

  test('a late Connect health response cannot restore a disconnected server', () async {
    _mockTrustVault();
    final pending = Completer<void>();
    final connection = _Connection()..pendingProbe = pending.future;
    final harness = _Harness(connection: connection);
    addTearDown(harness.controller.close);
    await harness.controller.initialize();

    final connecting = harness.controller.probeServer('music.test:8443');
    await Future<void>.delayed(Duration.zero);
    expect(connection.verifiedServers, ['https://music.test:8443/api']);
    expect(harness.controller.authState.status, SessionStatus.checking);

    await harness.controller.logout();
    pending.complete();

    expect(await connecting, isFalse);
    expect(connection.baseUrl, isEmpty);
    expect(connection.token, isNull);
    expect(harness.controller.authState.status, SessionStatus.offline);
    expect(harness.controller.authState.baseUrl, isEmpty);
    expect(harness.controller.authState.error, isNull);
  });

  for (final initiallyAvailable in [false, true]) {
    test('saved login continues the full artist download (server available: $initiallyAvailable)', () async {
      final root = await Directory.systemTemp.createTemp('phonolite_startup_artist_');
      addTearDown(() => root.delete(recursive: true));
      final initialStorage = OfflineLibraryStorage(baseDirectory: root);
      final connection = _StartupDownloadConnection()..available = initiallyAvailable;
      final first = OfflineDownloadManager(connection: connection, storage: initialStorage);
      await first.load();
      final artist = Artist(id: 'artist', name: 'Artist', albumCount: 3);
      final albums = [
        for (var index = 1; index <= 3; index++)
          Album(id: 'album-$index', title: 'Album $index', artist: artist.name, artistId: artist.id, trackCount: 1),
      ];
      expect(await first.queueArtist(artist, albums), 3);
      final jobId = first.jobs.single.jobId;
      await first.dispose();
      final file = await initialStorage.trackFile(serverBaseUrl: connection.baseUrl, trackId: 'album-1-track');
      await file.writeAsBytes([1, 2, 3]);
      final done = await initialStorage.prepareDownload(
        offlineTestDownload(
          serverBaseUrl: connection.baseUrl,
          batchId: jobId,
          track: offlineTestTrack(id: 'album-1-track'),
          filePath: file.path,
        ),
      );
      await initialStorage.upsertDownload(done);
      final now = DateTime.now();
      await initialStorage.upsertDownloadJobItems([
        OfflineDownloadJobItem(
          jobId: jobId,
          position: 0,
          serverTrackId: 'album-1-track',
          materialized: true,
          status: OfflineDownloadStatus.downloaded,
          createdAt: now,
          updatedAt: now,
          track: done.track,
        ),
      ]);
      await initialStorage.upsertDownloadJobSources([
        (await initialStorage.readDownloadJobSources(
          jobId,
        )).first.copyWith(status: OfflineDownloadStatus.downloaded, updatedAt: now),
      ]);
      await initialStorage.close();

      final storage = OfflineLibraryStorage(baseDirectory: root);
      final manager = OfflineDownloadManager(connection: connection, storage: storage);
      final harness = _Harness(
        authenticated: true,
        connection: connection,
        offlineDownloadManager: manager,
        offlineStorage: storage,
      );
      try {
        await harness.controller.initialize();
        expect(connection.requestedAlbums, isEmpty);
        expect(manager.jobs.single.jobId, jobId);
        expect(manager.downloads.single.isDownloaded, isTrue);
        await harness.controller.restoreSession();
        if (!initiallyAvailable) {
          expect(harness.controller.authState.status, SessionStatus.serverUnavailable);
          expect(connection.requestedAlbums, isEmpty);
          expect(manager.jobs.single.jobId, jobId);
          connection.available = true;
          connection.pendingHealth = Future.value(1);
          await harness.controller.refreshServerAvailability();
        }
        await offlineTestWaitFor(() => manager.downloads.length == 3);
        expect(connection.requestedAlbums, ['album-2', 'album-3']);
        expect(connection.requestedBatches.single, ['album-2-track', 'album-3-track']);
        expect(manager.jobs.single.jobId, jobId);
        expect(manager.jobs.single.completedCount, 1);
        expect(manager.findForCurrentServer('album-1-track')!.filePath, file.path);
        expect(await file.readAsBytes(), [1, 2, 3]);
      } finally {
        await harness.controller.close();
        await storage.close();
      }
    });
  }

  test('failed endpoint verification stays offline and can be retried', () async {
    final pending = Completer<void>();
    final connection = _Connection()..pendingProbe = pending.future;
    final harness = _Harness(connection: connection);
    addTearDown(harness.controller.close);
    final original = connection.baseUrl;

    final result = harness.controller.probeServer('music.test:8443');
    await Future<void>.delayed(Duration.zero);
    pending.completeError(ServerConnectionCheckException('Unable to connect to server'));
    expect(await result, isFalse);
    expect(harness.controller.authState.status, SessionStatus.offline);
    expect(harness.controller.authState.error, 'Unable to connect to server');
    expect(connection.baseUrl, original);

    connection.pendingProbe = null;
    expect(await harness.controller.probeServer('music.test:8443'), isTrue);
    expect(harness.controller.authState.error, isNull);
  });

  test('password reset preserves the current session, saved auth and downloads', () async {
    final connection = _PasswordConnection();
    final harness = _Harness(authenticated: true, connection: connection);
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    await harness.controller.restoreSession();
    expect(harness.controller.hasSavedCredentials, isTrue);
    expect(harness.controller.canResetUserPassword, isTrue);

    await harness.controller.resetUserPassword(currentPassword: 'old password', newPassword: 'new secure password');

    expect(connection.passwordChanges, 1);
    expect(connection.logoutRequests, 0);
    expect(connection.token, 'test-token');
    expect(harness.controller.canUseServer, isTrue);
    expect(harness.controller.hasSavedCredentials, isTrue);
    expect(harness.auth.clears, 0);
    expect(harness.downloads.resets, 0);
    expect(harness.downloads.pausedServers, isEmpty);
  });

  test('password reset refuses an offline or mismatched authenticated session', () async {
    final connection = _PasswordConnection();
    final harness = _Harness(authenticated: true, connection: connection);
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    await expectLater(
      harness.controller.resetUserPassword(currentPassword: 'old password', newPassword: 'new secure password'),
      throwsA(isA<PasswordChangeException>()),
    );
    await harness.controller.restoreSession();
    connection.setBaseUrl('https://different.test/api');
    connection.setTrust(testServerTrust);
    connection.setToken('other-session');
    await expectLater(
      harness.controller.resetUserPassword(currentPassword: 'old password', newPassword: 'new secure password'),
      throwsA(isA<PasswordChangeException>()),
    );
    expect(connection.passwordChanges, 0);
    expect(connection.token, 'other-session');
    expect(harness.auth.clears, 0);
  });

  for (final requiresSignIn in [false, true]) {
    test('password reset failure requires sign in: $requiresSignIn', () async {
      final connection = _PasswordConnection()
        ..passwordFailure = PasswordChangeException('Safe password reset failure', requiresSignIn: requiresSignIn);
      final harness = _Harness(authenticated: true, connection: connection);
      addTearDown(harness.controller.close);
      await harness.controller.initialize();
      await harness.controller.restoreSession();
      await expectLater(
        harness.controller.resetUserPassword(currentPassword: 'old password', newPassword: 'new secure password'),
        throwsA(isA<PasswordChangeException>()),
      );
      expect(connection.token, requiresSignIn ? null : 'test-token');
      expect(harness.controller.canUseServer, !requiresSignIn);
      expect(harness.controller.hasSavedCredentials, !requiresSignIn);
      expect(harness.auth.clears, requiresSignIn ? 1 : 0);
      expect(connection.logoutRequests, 0);
    });
  }

  for (final ambiguousFailure in [false, true]) {
    test('late password reset cannot clear a new session, failed: $ambiguousFailure', () async {
      final completed = Completer<void>();
      final connection = _PasswordConnection()..passwordResponse = completed.future;
      final harness = _Harness(authenticated: true, connection: connection);
      addTearDown(harness.controller.close);
      await harness.controller.initialize();
      await harness.controller.restoreSession();
      final pending = harness.controller.resetUserPassword(
        currentPassword: 'old password',
        newPassword: 'new secure password',
      );
      connection.setToken('replacement-token');
      if (ambiguousFailure) {
        completed.completeError(PasswordChangeException('Unknown outcome', requiresSignIn: true));
      } else {
        completed.complete();
      }
      await expectLater(pending, throwsA(isA<PasswordChangeException>()));
      expect(connection.token, 'replacement-token');
      expect(harness.controller.canUseServer, isTrue);
      expect(harness.auth.clears, 0);
      expect(connection.logoutRequests, 0);
    });
  }

  test('closing during initialization ignores late settings and audio callbacks', () async {
    final harness = _Harness();
    final pendingSettings = Completer<CustomShuffleSettings>();
    final pendingPreferences = Completer<bool?>();
    final pendingHealth = Completer<int?>();
    harness.shuffle.pending = pendingSettings.future;
    harness.preferences.pending = pendingPreferences.future;
    harness.connection.pendingHealth = pendingHealth.future;
    final startup = harness.controller.initialize();
    await harness.controller.close();
    pendingSettings.complete(const CustomShuffleSettings(artistIds: ['late']));
    pendingPreferences.complete(false);
    pendingHealth.complete(50);
    await startup;
    harness.onStarted!();
    harness.onStats!(Duration.zero, Duration.zero, null, null, false);
    expect(harness.controller.isInitialized, isFalse);
    expect(harness.controller.customShuffleArtistIds, isEmpty);
    expect(harness.audio.volume, isNull);
    expect(harness.preferences.reads, 1);
  });

  test('startup failure releases partially created resources', () async {
    final harness = _Harness();
    harness.downloads.failLoad = true;
    await expectLater(harness.controller.initialize(), throwsStateError);
    expect(harness.controller.isInitialized, isFalse);
    expect(harness.audio.disposals, 1);
    expect(harness.downloads.disposals, 1);
    expect(harness.connection.onTransportFailure, isNull);
    await harness.controller.close();
    expect(harness.audio.disposals, 1);
  });

  test('audio factory failure releases subscriptions and the connection callback', () async {
    final harness = _Harness(failAudio: true);
    await expectLater(harness.controller.initialize(), throwsStateError);
    expect(harness.audio.disposals, 0);
    expect(harness.downloads.disposals, 1);
    expect(harness.connection.onTransportFailure, isNull);
  });

  test('getters and emitted lists cannot mutate controller collections', () async {
    final harness = _Harness();
    await harness.controller.initialize();
    addTearDown(harness.controller.close);
    final controller = harness.controller;
    for (final list in <List<Object?>>[
      controller.artists,
      controller.albums,
      controller.tracks,
      controller.playlists,
      controller.playlistTracks,
      controller.liked,
      controller.searchResults,
      controller.messages,
      controller.outputDevices,
      controller.customShuffleArtistIds,
      controller.customShuffleGenres,
      controller.localCustomShuffleArtistIds,
      controller.localCustomShuffleGenres,
      controller.customShuffleSettings.artistIds,
    ]) {
      expect(list.clear, throwsUnsupportedError);
    }
    controller.clearMessages();
    final message = controller.messageStream.first;
    AppLogger.info('snapshot one');
    final emitted = await message;
    expect(emitted.clear, throwsUnsupportedError);
    final snapshot = controller.messages;
    AppLogger.info('snapshot two');
    expect(snapshot, hasLength(1));
    expect(controller.messages, hasLength(2));
    final settings = controller.customShuffleSettingsStream.first;
    await controller.updateCustomShuffleSettings(artistIds: ['changed']);
    expect((await settings).artistIds.clear, throwsUnsupportedError);
    expect(controller.customShuffleArtistIds, ['changed']);
  });

  test('log bursts publish one bounded snapshot and clear cancels pending updates', () async {
    final harness = _Harness();
    await harness.controller.initialize();
    addTearDown(harness.controller.close);
    await harness.controller.clearMessages();
    final snapshots = <List<LogEntry>>[];
    final subscription = harness.controller.messageStream.listen(snapshots.add);
    addTearDown(subscription.cancel);
    for (var i = 0; i < 4000; i++) {
      AppLogger.info('burst-$i');
    }
    expect(harness.controller.messages, hasLength(3000));
    expect(harness.controller.messages.first.message, 'burst-1000');
    expect(snapshots, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(snapshots, hasLength(1));
    expect(snapshots.single.last.message, 'burst-3999');
    expect(snapshots.single.clear, throwsUnsupportedError);
    AppLogger.info('pending before clear');
    await harness.controller.clearMessages();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(snapshots, hasLength(2));
    expect(snapshots.last, isEmpty);
    expect(snapshots.first.last.message, 'burst-3999');
  });

  test('clearing unfinished downloads preserves local playback', () async {
    final root = await Directory.systemTemp.createTemp('keep_download_playback_');
    final storage = OfflineLibraryStorage(baseDirectory: root);
    final connection = _Connection();
    final file = await storage.trackFile(serverBaseUrl: connection.baseUrl, trackId: 'saved');
    await file.writeAsBytes([1, 2, 3]);
    final completed = await storage.prepareDownload(
      offlineTestDownload(
        serverBaseUrl: connection.baseUrl,
        track: offlineTestTrack(id: 'saved'),
        filePath: file.path,
      ),
    );
    await storage.upsertDownload(completed);
    final manager = OfflineDownloadManager(connection: connection, storage: storage);
    final harness = _Harness(connection: connection, offlineDownloadManager: manager, offlineStorage: storage);
    addTearDown(() async {
      await harness.controller.close();
      await storage.close();
      await root.delete(recursive: true);
    });
    await harness.controller.initialize();
    await harness.controller.playOfflineTrack(completed.localTrackId!);
    harness.onStarted!();
    expect(harness.controller.playbackState.isLocalPlayback, isTrue);
    expect(harness.audio.active, isTrue);
    final previousStops = harness.audio.stops;
    final playingTrack = harness.controller.playbackState.track!.id;

    await harness.controller.clearUnfinishedOfflineDownloads();

    expect(harness.audio.stops, previousStops);
    expect(harness.audio.active, isTrue);
    expect(harness.controller.playbackState.isPlaying, isTrue);
    expect(harness.controller.playbackState.track!.id, playingTrack);
    expect(await file.exists(), isTrue);
  });

  test('disconnect forgets the server while preserving downloaded local playback', () async {
    _mockTrustVault();
    final root = await Directory.systemTemp.createTemp('disconnect_local_playback_');
    final storage = OfflineLibraryStorage(baseDirectory: root);
    final connection = _PasswordConnection();
    final file = await storage.trackFile(serverBaseUrl: connection.baseUrl, trackId: 'saved');
    await file.writeAsBytes([1, 2, 3]);
    final completed = await storage.prepareDownload(
      offlineTestDownload(
        serverBaseUrl: connection.baseUrl,
        track: offlineTestTrack(id: 'saved'),
        filePath: file.path,
      ),
    );
    await storage.upsertDownload(completed);
    final manager = OfflineDownloadManager(connection: connection, storage: storage);
    final harness = _Harness(
      authenticated: true,
      connection: connection,
      offlineDownloadManager: manager,
      offlineStorage: storage,
    );
    addTearDown(() async {
      await harness.controller.close();
      await storage.close();
      await root.delete(recursive: true);
    });
    await harness.controller.initialize();
    await harness.controller.restoreSession();
    await ServerTrustStore.write(connection.baseUrl, testServerTrust);
    await harness.controller.playOfflineTrack(completed.localTrackId!);
    harness.onStarted!();
    final previousStops = harness.audio.stops;
    final playingTrack = harness.controller.playbackState.track!.id;

    await harness.controller.logout();

    expect(connection.baseUrl, isEmpty);
    expect(connection.token, isNull);
    expect(ServerTrustRegistry.lookup('https://unused.test'), isNull);
    expect(await ServerTrustStore.read('https://unused.test'), isNull);
    expect(await harness.controller.loadSavedCredentials(), isNull);
    expect(harness.audio.stops, previousStops);
    expect(harness.audio.active, isTrue);
    expect(harness.controller.playbackState.isLocalPlayback, isTrue);
    expect(harness.controller.playbackState.isPlaying, isTrue);
    expect(harness.controller.playbackState.track!.id, playingTrack);
    expect(manager.downloads, hasLength(1));
    expect(await file.exists(), isTrue);
    expect(connection.logoutRequests, 1);
  });

  for (final failStop in [false, true]) {
    test('full local reset waits for audio file release, stop fails: $failStop', () async {
      final root = await Directory.systemTemp.createTemp('local_reset_stop_');
      final storage = OfflineLibraryStorage(baseDirectory: root);
      final connection = _Connection();
      final file = await storage.trackFile(serverBaseUrl: connection.baseUrl, trackId: 'saved');
      await file.writeAsBytes([1, 2, 3]);
      final completed = await storage.prepareDownload(
        offlineTestDownload(
          serverBaseUrl: connection.baseUrl,
          track: offlineTestTrack(id: 'saved'),
          filePath: file.path,
        ),
      );
      await storage.upsertDownload(completed);
      final manager = OfflineDownloadManager(connection: connection, storage: storage);
      final harness = _Harness(connection: connection, offlineDownloadManager: manager, offlineStorage: storage);
      addTearDown(() async {
        harness.audio.stopGate = null;
        await harness.controller.close();
        await storage.close();
        await root.delete(recursive: true);
      });
      await harness.controller.initialize();
      await harness.controller.playOfflineTrack(completed.localTrackId!);
      harness.onStarted!();
      final stopGate = Completer<void>();
      harness.audio.stopGate = stopGate.future;
      final previousStops = harness.audio.stops;

      final resetting = harness.controller.resetOfflineData();
      await offlineTestWaitFor(() => harness.audio.stops > previousStops);
      expect(harness.audio.lastStopWaitForRelease, isTrue);
      expect(await file.exists(), isTrue);
      expect(manager.downloads, hasLength(1));
      if (failStop) {
        stopGate.completeError(StateError('stop failed'));
      } else {
        stopGate.complete();
      }
      await resetting;
      expect(await file.exists(), failStop);
      expect(manager.downloads, hasLength(failStop ? 1 : 0));
      if (failStop) {
        expect(harness.controller.messages.last.message, contains('Failed to reset local data:'));
      } else {
        expect(harness.audio.active, isFalse);
        expect(harness.controller.playbackState.track, isNull);
      }
    });
  }

  test('clearing all download jobs and cache keeps log history', () async {
    final harness = _Harness();
    await harness.controller.initialize();
    addTearDown(harness.controller.close);
    await harness.controller.clearMessages();
    AppLogger.warning('existing warning');

    await harness.controller.clearUnfinishedOfflineDownloads();

    expect(harness.downloads.resets, 1);
    expect(harness.controller.messages.first.message, 'existing warning');
    expect(harness.controller.messages.last.message, 'Cleared unfinished download jobs and partial cache.');
  });

  test('failed download cache clear reports the failure and keeps logs', () async {
    final harness = _Harness();
    await harness.controller.initialize();
    addTearDown(harness.controller.close);
    await harness.controller.clearMessages();
    AppLogger.warning('existing warning');
    harness.downloads.failReset = true;

    await harness.controller.clearUnfinishedOfflineDownloads();

    expect(harness.downloads.resets, 1);
    expect(harness.controller.messages.first.message, 'existing warning');
    expect(harness.controller.messages.last.message, contains('Failed to clear download jobs and cache:'));
  });

  test('reset local data clears log history in every category', () async {
    final harness = _Harness();
    await harness.controller.initialize();
    addTearDown(harness.controller.close);
    await harness.controller.clearMessages();
    for (final level in LogLevel.values) {
      AppLogger.instance.log(LogEntry(message: 'old-${level.name}', level: level));
    }
    expect(harness.controller.messages, hasLength(LogLevel.values.length));

    await harness.controller.resetOfflineData();

    expect(harness.downloads.resets, 1);
    expect(harness.controller.messages.single.message, 'Reset all local downloads, metadata, and logs.');
    final replayed = <LogEntry>[];
    AppLogger.instance.attach(replayed.add);
    AppLogger.instance.detach(replayed.add);
    expect(replayed.single.message, harness.controller.messages.single.message);
  });

  test('failed local data reset keeps logs for troubleshooting', () async {
    final harness = _Harness();
    await harness.controller.initialize();
    addTearDown(harness.controller.close);
    await harness.controller.clearMessages();
    AppLogger.warning('existing warning');
    harness.downloads.failReset = true;

    await harness.controller.resetOfflineData();

    expect(harness.downloads.resets, 1);
    expect(harness.controller.messages.first.message, 'existing warning');
    expect(harness.controller.messages.last.message, contains('Failed to reset local data:'));
  });

  for (final afterOutput in [false, true]) {
    test('server request rejection stops playback without reconnecting afterOutput=$afterOutput', () async {
      final harness = _Harness(authenticated: true);
      addTearDown(harness.controller.close);
      await harness.controller.initialize();
      await harness.controller.restoreSession();
      await harness.controller.queueAlbum('album');
      if (afterOutput) harness.onStarted!();
      harness.audio.sourceRejected = true;
      harness.failTransport();
      expect(harness.audio.starts, hasLength(1));
      expect(harness.controller.playbackState.track, isNotNull);
      expect(harness.controller.playbackState.isPlaying, isFalse);
      expect(harness.controller.playbackState.isLoading, isFalse);
      await harness.controller.refreshServerAvailability();
      expect(harness.audio.starts, hasLength(1));
      await harness.controller.pause(false); // Explicit user retry remains available.
      expect(harness.audio.starts, hasLength(2));
      expect(harness.controller.playbackState.isPlaying, isTrue);
    });
  }

  test('source rejection during a seek does not restart a failed request', () async {
    final harness = _Harness(authenticated: true);
    await harness.startRemote();
    addTearDown(harness.controller.close);
    final result = Completer<bool>();
    harness.audio.seekResults.add(result.future);
    final seek = harness.controller.seekTo(const Duration(seconds: 40));
    await Future<void>.delayed(Duration.zero);
    harness.audio.sourceRejected = true;
    harness.failTransport();
    result.complete(false);
    await seek;
    expect(harness.audio.starts, hasLength(1));
    expect(harness.controller.playbackState.isPlaying, isFalse);
    expect(harness.controller.playbackState.isLoading, isFalse);
  });

  test('transport failure during rapid seeks restarts at the latest target', () async {
    final harness = _Harness(authenticated: true);
    await harness.startRemote();
    addTearDown(harness.controller.close);
    await harness.controller.seekTo(const Duration(seconds: 80));
    await harness.controller.seekTo(const Duration(seconds: 20));

    harness.failTransport();

    expect(harness.audio.starts, hasLength(2));
    expect(harness.audio.starts.last.offset, const Duration(seconds: 20));
    expect(harness.audio.starts.last.quickStart, isFalse);
    expect(harness.controller.playbackState.isPlaying, isTrue);
    expect(harness.controller.playbackState.isLoading, isTrue);

    harness.onStats!(const Duration(seconds: 21), const Duration(seconds: 2), 96, 400, false);
    expect(harness.controller.playbackState.position, const Duration(seconds: 21));
  });

  test('repeated interruption preserves play intent and waits for healthy reconnect', () async {
    final harness = _Harness(authenticated: true);
    await harness.startRemote();
    addTearDown(harness.controller.close);
    await harness.controller.seekTo(const Duration(seconds: 25));
    harness.failTransport();

    harness.failTransport();

    expect(harness.audio.starts, hasLength(2));
    expect(harness.controller.playbackState.isPlaying, isTrue);
    expect(harness.controller.playbackState.isLoading, isFalse);
    expect(harness.controller.playbackState.streamConnected, isFalse);

    await harness.controller.refreshServerAvailability();
    harness.playbackTime = harness.playbackTime.add(const Duration(seconds: 9));
    harness.connection.pendingHealth = Future.value(25);
    await harness.controller.refreshServerAvailability();
    expect(harness.audio.starts, hasLength(3));
    expect(harness.audio.starts.last.offset, const Duration(seconds: 25));
    expect(harness.controller.playbackState.isPlaying, isTrue);
    expect(harness.controller.playbackState.isLoading, isTrue);
  });

  test('healthy resume keeps the paused session after a long pause', () async {
    final harness = _Harness(authenticated: true);
    await harness.startRemote();
    addTearDown(harness.controller.close);
    await harness.controller.pause(true);
    harness.playbackTime = harness.playbackTime.add(const Duration(minutes: 2));

    await harness.controller.pause(false);

    expect(harness.audio.starts, hasLength(1));
    expect(harness.audio.resumes, 1);
    expect(harness.audio.paused, isFalse);
    expect(harness.controller.playbackState.isPlaying, isTrue);
  });

  test('a user pause cancels playback recovery after reconnect', () async {
    final harness = _Harness(authenticated: true);
    await harness.startRemote();
    addTearDown(harness.controller.close);
    harness.failTransport();
    harness.failTransport();
    await harness.controller.pause(true);
    harness.playbackTime = harness.playbackTime.add(const Duration(seconds: 9));
    harness.connection.pendingHealth = Future.value(25);

    await harness.controller.refreshServerAvailability();

    expect(harness.audio.starts, hasLength(2));
    expect(harness.controller.playbackState.isPlaying, isFalse);
  });

  test('an old failed seek cannot restart after a newer seek is ready', () async {
    final harness = _Harness(authenticated: true);
    await harness.startRemote();
    addTearDown(harness.controller.close);
    final first = Completer<bool>();
    final second = Completer<bool>();
    harness.audio.seekResults.addAll([first.future, second.future]);
    final oldSeek = harness.controller.seekTo(const Duration(seconds: 80));
    final latestSeek = harness.controller.seekTo(const Duration(seconds: 20));

    second.complete(true);
    await latestSeek;
    first.complete(false);
    await oldSeek;

    expect(harness.audio.starts, hasLength(1));
    expect(harness.controller.playbackState.position, const Duration(seconds: 20));
  });

  test('seek fallback applies the latest pause intent when the session starts', () async {
    final harness = _Harness(authenticated: true);
    await harness.startRemote();
    addTearDown(harness.controller.close);
    final pending = Completer<bool>();
    harness.audio.seekResults.add(pending.future);
    harness.controller.previewSeek(const Duration(seconds: 40));
    final seek = harness.controller.seekTo(const Duration(seconds: 40));
    await harness.controller.pause(true);

    pending.complete(false);
    await seek;

    expect(harness.audio.starts, hasLength(2));
    expect(harness.audio.starts.last.initialPaused, isTrue);
    expect(harness.audio.paused, isTrue);
    await harness.controller.pause(false);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(harness.audio.paused, isFalse);
    expect(harness.audio.pauses, 1);
  });

  test('transport recovery supersedes the pending seek acknowledgement', () async {
    final harness = _Harness(authenticated: true);
    await harness.startRemote();
    addTearDown(harness.controller.close);
    final pending = Completer<bool>();
    harness.audio.seekResults.add(pending.future);
    final seek = harness.controller.seekTo(const Duration(seconds: 60));

    harness.failTransport();
    pending.complete(false);
    await seek;

    expect(harness.audio.starts, hasLength(2));
    expect(harness.audio.starts.last.offset, const Duration(seconds: 60));
  });

  test('changing output devices preserves a paused session', () async {
    final harness = _Harness(authenticated: true);
    await harness.startRemote();
    addTearDown(harness.controller.close);
    await harness.controller.pause(true);

    await harness.controller.selectOutputDevice(OutputDevice(id: 9, name: 'Test output'));

    expect(harness.audio.starts, hasLength(2));
    expect(harness.audio.starts.last.initialPaused, isTrue);
    expect(harness.audio.paused, isTrue);
    expect(harness.controller.playbackState.isPlaying, isFalse);
  });

  test('a failed seek at the initial offset still replaces the session', () async {
    final harness = _Harness(authenticated: true);
    await harness.startRemote();
    addTearDown(harness.controller.close);
    harness.audio.seekResults.add(Future.value(false));

    await harness.controller.seekTo(Duration.zero);

    expect(harness.audio.starts, hasLength(2));
    expect(harness.audio.starts.last.offset, Duration.zero);
  });

  test('paused seek failure stays paused and can resume from its target', () async {
    final harness = _Harness(authenticated: true);
    await harness.startRemote();
    addTearDown(harness.controller.close);
    await harness.controller.pause(true);
    await harness.controller.seekTo(const Duration(seconds: 40));

    harness.failTransport();

    expect(harness.audio.starts, hasLength(1));
    expect(harness.controller.playbackState.isPlaying, isFalse);
    expect(harness.controller.playbackState.isLoading, isFalse);
    expect(harness.controller.playbackState.streamConnected, isFalse);
    await harness.controller.pause(false);
    expect(harness.audio.starts, hasLength(2));
    expect(harness.audio.starts.last.offset, const Duration(seconds: 40));
  });

  test('transport failure during scrubbing waits for the user seek commit', () async {
    final harness = _Harness(authenticated: true);
    await harness.startRemote();
    addTearDown(harness.controller.close);
    harness.controller.previewSeek(const Duration(seconds: 50));

    harness.failTransport();

    expect(harness.audio.starts, hasLength(1));
    expect(harness.controller.playbackState.isLoading, isFalse);
    await harness.controller.seekTo(const Duration(seconds: 60));
    expect(harness.audio.starts, hasLength(2));
    expect(harness.audio.starts.last.offset, const Duration(seconds: 60));
  });

  test('ordinary interruption resumes from output position', () async {
    final harness = _Harness(authenticated: true);
    await harness.startRemote();
    addTearDown(harness.controller.close);
    harness.onStats!(const Duration(seconds: 12), const Duration(seconds: 2), 160, 100, false);

    harness.failTransport();

    expect(harness.audio.starts, hasLength(2));
    expect(harness.audio.starts.last.offset, const Duration(seconds: 12));
  });

  test('album queue normalization preserves artist and genre metadata', () async {
    final track = _metadataTrack();
    final connection = _Connection()..trackResponse = [track];
    final harness = _Harness(authenticated: true, connection: connection);
    await harness.startRemote();
    addTearDown(harness.controller.close);

    final playing = harness.controller.playbackState.track!;
    expect(playing.albumId, 'album');
    _expectTrackMetadata(playing, track);
  });

  test('playback search refuses uncertain album attribution', () async {
    final scenarios = <List<SearchResult>>[
      [SearchResult(kind: 'album', id: 'wrong', title: 'The Album')],
      [SearchResult(kind: 'album', id: 'wrong', title: 'The Album', subtitle: 'The Artist Orchestra')],
      [SearchResult(kind: 'album', id: 'wrong', title: 'The Album Deluxe', subtitle: 'The Artist')],
      [
        for (final id in ['first-release', 'second-release'])
          SearchResult(kind: 'album', id: id, title: 'The Album', subtitle: 'The Artist'),
      ],
    ];
    for (final results in scenarios) {
      final connection = _Connection()
        ..trackResponse = [_metadataTrack()]
        ..searchResponse = results;
      final harness = _Harness(authenticated: true, connection: connection);
      await harness.controller.initialize();
      await harness.controller.restoreSession();
      await harness.controller.queuePlaylist('playlist');
      await Future<void>.delayed(Duration.zero);

      expect(connection.searches, 1);
      expect(harness.controller.playbackState.track?.albumId, isNull);
      await harness.controller.close();
    }
  });

  test('exact Unicode album attribution preserves track metadata', () async {
    final track = _metadataTrack().copyWith(artist: '宇多田ヒカル', album: '初恋');
    final connection = _Connection()
      ..trackResponse = [track]
      ..searchResponse = [SearchResult(kind: 'album', id: 'correct', title: '初恋', subtitle: '宇多田ヒカル')];
    final harness = _Harness(authenticated: true, connection: connection);
    await harness.controller.initialize();
    await harness.controller.restoreSession();
    addTearDown(harness.controller.close);
    final hydrated = harness.controller.playbackStream.firstWhere((state) => state.track?.albumId == 'correct');
    await harness.controller.queuePlaylist('playlist');
    final playing = (await hydrated).track!;

    _expectTrackMetadata(playing, track);
  });

  test('album lookup cache does not survive a server switch', () async {
    final connection = _Connection()..trackResponse = [_metadataTrack()];
    final harness = _Harness(authenticated: true, connection: connection);
    await harness.controller.initialize();
    await harness.controller.restoreSession();
    addTearDown(harness.controller.close);
    await harness.controller.loadTracks('old-server-album');

    connection.setBaseUrl('https://other.test/api');
    connection.searchResponse = [
      SearchResult(kind: 'album', id: 'new-server-album', title: 'The Album', subtitle: 'The Artist'),
    ];
    final hydrated = harness.controller.playbackStream.firstWhere(
      (state) => state.track?.albumId == 'new-server-album',
    );
    await harness.controller.queuePlaylist('playlist');

    expect((await hydrated).track?.albumId, 'new-server-album');
    expect(connection.searches, 1);
  });

  test('cached album IDs preserve playlist track metadata', () async {
    final track = _metadataTrack();
    final connection = _Connection()..trackResponse = [track];
    final harness = _Harness(authenticated: true, connection: connection);
    await harness.controller.initialize();
    await harness.controller.restoreSession();
    addTearDown(harness.controller.close);
    await harness.controller.loadTracks('album');
    await harness.controller.queuePlaylist('playlist');

    final playing = harness.controller.playbackState.track!;
    expect(playing.albumId, 'album');
    _expectTrackMetadata(playing, track);
    expect(connection.searches, 0);
  });

  test('cached releases with the same title remain ambiguous', () async {
    final connection = _Connection()
      ..trackResponse = [_metadataTrack()]
      ..albumResponse = [
        for (final id in ['first-release', 'second-release'])
          Album(id: id, title: 'The Album', artist: 'The Artist', artistId: 'artist-id', trackCount: 1),
      ];
    final harness = _Harness(authenticated: true, connection: connection);
    await harness.controller.initialize();
    await harness.controller.restoreSession();
    addTearDown(harness.controller.close);
    await harness.controller.loadAlbums('artist-id');
    await harness.controller.queuePlaylist('playlist');
    await Future<void>.delayed(Duration.zero);

    expect(harness.controller.playbackState.track?.albumId, isNull);
    expect(connection.searches, 0);
  });

  test('album artist updates do not retain a previous artist name', () async {
    final events = StreamController<MetadataUpdateEvent>.broadcast();
    addTearDown(events.close);
    final connection = _Connection()
      ..metadataEvents = events.stream
      ..albumResponse = [
        Album(id: 'album', title: 'The Album', artist: 'Old Artist', artistId: 'old-artist', trackCount: 1),
      ]
      ..updatedAlbum = Album(id: 'album', title: 'The Album', artist: '', artistId: 'new-artist', trackCount: 1)
      ..updatedArtist = Artist(id: 'new-artist', name: 'Correct Artist', albumCount: 1);
    final harness = _Harness(authenticated: true, connection: connection);
    await harness.controller.initialize();
    await harness.controller.restoreSession();
    addTearDown(harness.controller.close);
    await harness.controller.loadAlbums('old-artist');
    final refreshed = harness.controller.watchAlbum('album').first;
    events.add(MetadataUpdateEvent(revision: 1, kind: 'album', id: 'album', updatedAt: 0));

    final album = await refreshed;
    expect(album.artistId, 'new-artist');
    expect(album.artist, 'Correct Artist');
  });

  test('album events refresh loaded performers without restarting audio', () async {
    final events = StreamController<MetadataUpdateEvent>.broadcast();
    addTearDown(events.close);
    final original = _metadataTrack().copyWith(albumId: 'album', liked: true, inPlaylists: true);
    final connection = _Connection()
      ..metadataEvents = events.stream
      ..trackResponse = [original]
      ..updatedAlbum = Album(
        id: 'album',
        title: 'Correct Album',
        artist: 'Album Primary Artist',
        artistId: 'album-primary-id',
        trackCount: 1,
      );
    final harness = _Harness(authenticated: true, connection: connection);
    await harness.controller.initialize();
    await harness.controller.restoreSession();
    addTearDown(harness.controller.close);
    await harness.controller.loadTracks('album');
    await harness.controller.loadPlaylistTracks('playlist');
    await harness.controller.loadLikedTracks();
    await harness.controller.queueAlbum('album');
    harness.onStarted!();
    harness.onStats!(const Duration(seconds: 12), Duration.zero, 160, 100, false);
    final requestsBefore = connection.trackListRequests;
    connection.trackResponse = [
      original.copyWith(
        artist: 'Correct Track Performer',
        artistId: 'correct-performer-id',
        album: 'Correct Album',
        genres: ['Chamber Music'],
        listeningGenres: ['Baroque'],
        liked: false,
        inPlaylists: false,
      ),
    ];
    final refreshed = harness.controller.playbackStream.firstWhere(
      (state) => state.track?.artist == 'Correct Track Performer',
    );
    events.add(MetadataUpdateEvent(revision: 1, kind: 'album', id: 'album', updatedAt: 0));

    final playback = await refreshed;
    expect(playback.position, const Duration(seconds: 12));
    expect(playback.isPlaying, isTrue);
    expect(playback.track?.liked, isTrue);
    expect(playback.track?.inPlaylists, isTrue);
    expect(playback.track?.artistId, 'correct-performer-id');
    expect(playback.track?.genres, ['Chamber Music']);
    expect(playback.track?.listeningGenres, ['Baroque']);
    expect(harness.audio.starts, hasLength(1));
    expect(connection.trackListRequests, requestsBefore + 1);
    expect(harness.controller.tracks.single.artist, 'Correct Track Performer');
    expect(harness.controller.playlistTracks.single.artist, 'Correct Track Performer');
    expect(harness.controller.liked.single.artist, 'Correct Track Performer');
    for (final track in [
      harness.controller.tracks.single,
      harness.controller.playlistTracks.single,
      harness.controller.liked.single,
    ]) {
      expect(track.listeningGenres, ['Baroque']);
    }
    expect(harness.downloads.refreshedAlbums, ['album']);
  });

  test('artist events refresh only tracks with the exact performer ID', () async {
    final events = StreamController<MetadataUpdateEvent>.broadcast();
    addTearDown(events.close);
    final original = _metadataTrack().copyWith(albumId: 'album');
    final collaborator = original.copyWith(id: 'other-track', artist: 'Another Performer', artistId: 'another-id');
    final connection = _Connection()
      ..metadataEvents = events.stream
      ..trackResponse = [original, collaborator]
      ..updatedArtist = Artist(id: original.artistId!, name: 'Correct Performer', albumCount: 1);
    final harness = _Harness(authenticated: true, connection: connection);
    harness.downloads.localTracks = [original];
    await harness.controller.initialize();
    await harness.controller.restoreSession();
    addTearDown(harness.controller.close);
    await harness.controller.loadTracks('album');
    await harness.controller.queueAlbum('album');
    final requestsBefore = connection.trackListRequests;
    final refreshed = harness.controller.playbackStream.firstWhere(
      (state) => state.track?.artist == 'Correct Performer',
    );
    events.add(MetadataUpdateEvent(revision: 1, kind: 'artist', id: original.artistId!, updatedAt: 0));

    expect((await refreshed).track?.artist, 'Correct Performer');
    expect(harness.controller.tracks.last.artist, 'Another Performer');
    expect(connection.trackListRequests, requestsBefore);
    expect(harness.audio.starts, hasLength(1));
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(harness.downloads.refreshedArtists, [original.artistId]);
  });

  test('old playback hydration cannot overwrite a metadata event', () async {
    final events = StreamController<MetadataUpdateEvent>.broadcast();
    addTearDown(events.close);
    final oldRead = Completer<Track>();
    final original = _metadataTrack().copyWith(albumId: 'album', album: '');
    final connection = _Connection()
      ..metadataEvents = events.stream
      ..trackResponse = [original]
      ..pendingTrackById = oldRead.future
      ..updatedAlbum = Album(
        id: 'album',
        title: 'Correct Album',
        artist: 'Correct Performer',
        artistId: 'artist-id',
        trackCount: 1,
      );
    final harness = _Harness(authenticated: true, connection: connection);
    await harness.controller.initialize();
    await harness.controller.restoreSession();
    addTearDown(harness.controller.close);
    await harness.controller.queuePlaylist('playlist');
    connection.trackResponse = [original.copyWith(album: 'Correct Album', artist: 'Correct Performer')];
    final refreshed = harness.controller.playbackStream.firstWhere(
      (state) => state.track?.artist == 'Correct Performer',
    );
    events.add(MetadataUpdateEvent(revision: 1, kind: 'album', id: 'album', updatedAt: 0));
    await refreshed;
    oldRead.complete(original.copyWith(artist: 'Old Wrong Performer'));
    await Future<void>.delayed(Duration.zero);

    expect(harness.controller.playbackState.track?.artist, 'Correct Performer');
    expect(harness.audio.starts, hasLength(1));
  });
  test('artist refresh resets pagination and requests billed artists only', () async {
    final connection = _Connection();
    final stale = Completer<List<Artist>>();
    connection.pendingArtistsPage = stale.future;
    connection.artistsPageResponse = [Artist(id: 'guest', name: 'Guest', albumCount: 0, appearanceCount: 1)];
    final harness = _Harness(authenticated: true, connection: connection);
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    await harness.controller.restoreSession();
    final first = harness.controller.loadArtists();
    await Future<void>.delayed(Duration.zero);
    final refresh = harness.controller.loadArtists(refresh: true);
    stale.complete([Artist(id: 'stale', name: 'Old page', albumCount: 1)]);
    await first;
    await refresh;
    expect(connection.artistPageFilters, [false, false]);
    expect(connection.artistPageOffsets, [0, 0]);
    expect(harness.controller.artists.map((artist) => artist.id), ['guest']);
  });

  test('loaded releases update compact roster counts without detail metadata requests', () async {
    final album = Album(id: 'one', title: 'One', artist: 'A', artistId: 'a', trackCount: 1);
    final credit = ArtistReleaseContribution(album: album, roles: const ['composer']);
    final connection = _Connection()
      ..artistsPageResponse = [
        Artist(
          id: 'composer',
          name: 'Composer',
          albumCount: 0,
          genres: const ['Jazz'],
          summary: 'Biography',
          logoRef: 'logo.png',
        ),
      ]
      ..releaseResponses = {
        'composer': Future.value(ArtistReleases(collabAlbums: [credit], otherCredits: [credit])),
      };
    final harness = _Harness(authenticated: true, connection: connection);
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    await harness.controller.restoreSession();
    await harness.controller.loadArtists();
    final rowUpdate = harness.controller.artistsStream.firstWhere((artists) => artists.single.otherCreditCount == 1);
    final profileUpdate = harness.controller.watchArtist('composer').first;
    await harness.controller.loadArtistReleases('composer');
    expect((await rowUpdate).single.releaseCount, 0);
    final updated = await profileUpdate;
    expect(updated.albumCount, 0);
    expect(updated.collabAlbumCount, 0);
    expect(updated.otherCreditCount, 1);
    expect(updated.releaseCount, 0);
    expect(updated.summary, isNull, reason: 'Biographies are retained only by the independent detail cache.');
    expect(updated.genres, ['Jazz']);
    expect(updated.logoRef, 'logo.png');
    expect(connection.artistLookups, isEmpty);
    expect(connection.artistPageOffsets, [0]);
  });

  test('late relationship reads cannot replace a different artist profile', () async {
    final connection = _Connection();
    final first = Completer<ArtistReleases>();
    final joint = Album(
      id: 'shared',
      title: 'Joint',
      artist: 'A & B',
      artistId: 'a',
      trackCount: 2,
      artistCredits: const [
        ArtistCredit(artistId: 'a', name: 'A'),
        ArtistCredit(artistId: 'b', name: 'B', role: 'joint'),
      ],
    );
    connection.releaseResponses = {
      'a': first.future,
      'b': Future.value(ArtistReleases(albums: [joint])),
    };
    connection.artistsPageResponse = [
      Artist(id: 'a', name: 'A', albumCount: 3),
      Artist(id: 'b', name: 'B', albumCount: 0),
    ];
    final harness = _Harness(authenticated: true, connection: connection);
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    await harness.controller.restoreSession();
    await harness.controller.loadArtists();
    final readA = harness.controller.loadArtistReleases('a');
    await harness.controller.loadArtistReleases('b');
    first.complete(const ArtistReleases());
    await readA;
    expect(harness.controller.artists.first.releaseCount, 3);
    expect(harness.controller.artists.last.releaseCount, 1);
    expect(harness.controller.artistReleases.albums, isEmpty);
    expect(harness.controller.artistReleases.collabAlbums.single.album.id, 'shared');
    expect(harness.controller.artistReleases.collabAlbums.single.album.credits, hasLength(2));
  });

  for (final scenario in [
    (artistId: 'guest', guestOnTrack: true, expected: ShuffleMode.custom),
    (artistId: 'joint', guestOnTrack: false, expected: ShuffleMode.custom),
    (artistId: 'composer', guestOnTrack: false, expected: ShuffleMode.off),
    (artistId: 'guest', guestOnTrack: false, expected: ShuffleMode.off),
    (artistId: 'album-composer', guestOnTrack: false, expected: ShuffleMode.off),
  ]) {
    test('remote custom shuffle keeps only credited artist selections: '
        '${scenario.artistId}, guest ${scenario.guestOnTrack}', () async {
      final track = _collaborationTrack(guest: scenario.guestOnTrack);
      final connection = _Connection()
        ..trackResponse = [track]
        ..updatedAlbum = _collaborationAlbum();
      final harness = _Harness(authenticated: true, connection: connection);
      addTearDown(harness.controller.close);
      await harness.controller.initialize();
      await harness.controller.restoreSession();
      await harness.controller.updateCustomShuffleSettings(artistIds: [scenario.artistId]);
      harness.controller.updateShuffleMode(ShuffleMode.custom, scope: ActionScope.server);

      await harness.controller.queuePlaylist('playlist', startTrackId: track.id);

      expect(harness.controller.playbackState.shuffleMode, scenario.expected);
      expect(harness.audio.starts.single.trackId, track.id);
    });
  }

  for (final cached in [false, true]) {
    test('remote custom shuffle matches guest genres, cached $cached', () async {
      final track = _collaborationTrack(guest: true);
      final guest = Artist(id: 'guest', name: 'Guest', albumCount: 0, genres: [' Jazz ']);
      final connection = _Connection()
        ..trackResponse = [track]
        ..updatedAlbum = _collaborationAlbum()
        ..artistsById = {'guest': guest}
        ..artistsPageResponse = [Artist(id: 'main', name: 'Main', albumCount: 0), guest];
      final harness = _Harness(authenticated: true, connection: connection);
      addTearDown(harness.controller.close);
      await harness.controller.initialize();
      await harness.controller.restoreSession();
      await harness.controller.updateCustomShuffleSettings(genres: ['jazz']);
      if (cached) await harness.controller.loadArtists();
      harness.controller.updateShuffleMode(ShuffleMode.custom, scope: ActionScope.server);

      await harness.controller.queuePlaylist('playlist', startTrackId: track.id);

      expect(harness.controller.playbackState.shuffleMode, ShuffleMode.custom);
      expect(connection.artistLookups, cached ? isEmpty : ['main', 'guest']);
    });
  }

  test('remote custom shuffle recognizes a credited track without an album ID', () async {
    final track = _collaborationTrack(guest: true).copyWith(albumId: null);
    final connection = _Connection()..trackResponse = [track];
    final harness = _Harness(authenticated: true, connection: connection);
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    await harness.controller.restoreSession();
    await harness.controller.updateCustomShuffleSettings(artistIds: ['guest']);
    harness.controller.updateShuffleMode(ShuffleMode.custom, scope: ActionScope.server);

    await harness.controller.queuePlaylist('playlist', startTrackId: track.id);

    expect(harness.controller.playbackState.shuffleMode, ShuffleMode.custom);
  });
  test('5000-artist browsing bounds its window without filling the selection roster', () async {
    final connection = _Connection()..generatedArtistCount = 5000;
    final harness = _Harness(authenticated: true, connection: connection);
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    await harness.controller.restoreSession();
    await harness.controller.loadArtists();
    expect(harness.controller.artists, hasLength(60));

    for (var index = 0; index < 5000; index += 60) {
      await harness.controller.loadArtistBrowsePage(index);
      expect(harness.controller.artistBrowseSnapshot.pages.length, lessThanOrEqualTo(12));
    }

    expect(harness.controller.artistBrowseSnapshot.total, 5000);
    expect(harness.controller.artists, hasLength(60));
    await harness.controller.loadAllArtists();
    expect(harness.controller.artists, hasLength(5000));
    expect(harness.controller.artists.every((artist) => artist.summary == null && artist.bannerRef == null), isTrue);
  });
}

Album _collaborationAlbum() => Album(
  id: 'shared',
  title: 'Shared',
  artist: 'Main & Joint',
  artistId: 'main',
  trackCount: 2,
  artistCredits: const [
    ArtistCredit(artistId: 'main', name: 'Main', role: 'album_artist'),
    ArtistCredit(artistId: 'joint', name: 'Joint', role: 'joint'),
    ArtistCredit(artistId: 'album-composer', name: 'Album Composer', role: 'composer'),
  ],
);

Track _collaborationTrack({required bool guest}) => Track(
  id: 'collab-track',
  title: 'Collab track',
  artist: guest ? 'Main feat. Guest' : 'Main',
  artistId: 'main',
  album: 'Shared',
  albumId: 'shared',
  durationMs: 180000,
  liked: false,
  inPlaylists: false,
  artistCredits: [
    const ArtistCredit(artistId: 'main', name: 'Main', role: 'track_artist'),
    if (guest) const ArtistCredit(artistId: 'guest', name: 'Guest', role: 'featured_artist'),
    const ArtistCredit(artistId: 'composer', name: 'Composer', role: 'composer'),
  ],
);

Track _metadataTrack() => Track(
  id: 'track',
  title: 'Track',
  artist: 'The Artist',
  artistId: 'artist-id',
  album: 'The Album',
  durationMs: 180000,
  genres: ['Classical'],
  listeningGenres: ['Orchestral'],
  albumArtPath: 'album-art.jpg',
  artistArtPath: 'artist-art.jpg',
  artistBannerPath: 'artist-banner.jpg',
  liked: false,
  inPlaylists: false,
);

void _expectTrackMetadata(Track actual, Track original) {
  expect(actual.artistId, original.artistId);
  expect(actual.genres, original.genres);
  expect(actual.listeningGenres, original.listeningGenres);
  expect(actual.albumArtPath, original.albumArtPath);
  expect(actual.artistArtPath, original.artistArtPath);
  expect(actual.artistBannerPath, original.artistBannerPath);
}

Future<OfflineLibraryStorage> _seedResumeLibrary(Directory directory, int count) async {
  final storage = OfflineLibraryStorage(baseDirectory: directory);
  for (var index = 0; index < count; index++) {
    final track = offlineTestTrack(id: 'server-$index', title: 'Unique song $index');
    final media = await offlineTestMediaFile(directory, 'resume-$index.mp3');
    final download = await storage.prepareDownload(
      offlineTestDownload(serverBaseUrl: 'https://unused.test', track: track, filePath: media.path),
    );
    await storage.upsertDownload(download);
  }
  return storage;
}

_Harness _resumeHarness(OfflineLibraryStorage storage, PlaybackResumeStorage resume) {
  final connection = _Connection();
  return _Harness(
    connection: connection,
    offlineStorage: storage,
    offlineDownloadManager: OfflineDownloadManager(connection: connection, storage: storage),
    playbackResumeStorage: resume,
  );
}

Future<void> _resumeUntil(FutureOr<bool> Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 4));

  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Playback resume did not settle');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _ResumeConnection extends _Connection {
  String userId = 'resume-user';
  final durableDecks = <String, List<Track>>{};
  final deckReads = <String>[];
  final missingPlaylists = <String>{};
  AccountPlaybackSnapshot snapshot = const AccountPlaybackSnapshot(revision: 0);
  Future<AccountPlaybackSnapshot>? pendingSnapshot;
  Future<AccountPlaybackSnapshot>? pendingSave;
  final saved = <PlaybackResumeCheckpoint>[];
  final intents = <String>[];
  int reads = 0;

  @override
  Future<ServerCapabilities> fetchCapabilities() async => ServerCapabilities(
    downloadJobsV2: false,
    eventReplayV2: false,
    metadataSnapshotsV2: false,
    trackFileContractV2: false,
    playbackResume: true,
  );

  @override
  Future<AccountState> fetchAccountState() async => AccountState(
    userId: userId,
    username: 'Listener',
    role: 'user',
    revisions: AccountRevisions(collections: 0, presets: 0, statistics: 0),
  );

  @override
  Future<AccountPlaybackSnapshot> fetchAccountPlayback() async {
    reads++;
    final pending = pendingSnapshot;
    pendingSnapshot = null;
    return pending ?? snapshot;
  }

  @override
  Future<ShuffleSessionPage> fetchAccountPlaybackDeck(String deckId, {int offset = 0, int limit = 10}) async {
    deckReads.add(deckId);
    final tracks = durableDecks[deckId] ?? trackResponse!;
    final end = min(offset + limit, tracks.length);
    return ShuffleSessionPage(
      sessionId: deckId,
      offset: offset,
      nextOffset: end,
      total: tracks.length,
      hasMore: end < tracks.length,
      items: tracks.sublist(offset, end),
      itemOffsets: [for (var index = offset; index < end; index++) index],
    );
  }

  @override
  Future<List<Track>> fetchPlaylistTracks(String playlistId) {
    if (missingPlaylists.contains(playlistId)) {
      throw ApiException(404, 'Playlist not found');
    }

    return super.fetchPlaylistTracks(playlistId);
  }

  @override
  Future<AccountPlaybackSnapshot> saveAccountPlayback({
    required int expectedRevision,
    required String sessionId,
    required int sequence,
    required String requestId,
    required String intent,
    required PlaybackResumeCheckpoint checkpoint,
    String? generation,
    String? clientId,
  }) async {
    saved.add(checkpoint);
    intents.add(intent);
    snapshot = AccountPlaybackSnapshot(
      revision: expectedRevision + 1,
      generation: 'accepted-generation',
      checkpoint: checkpoint,
    );
    return pendingSave ?? snapshot;
  }
}

class _Harness {
  _Harness({
    bool failAudio = false,
    bool authenticated = false,
    _Connection? connection,
    OfflineDownloadManager? offlineDownloadManager,
    OfflineLibraryStorage? offlineStorage,
    NowPlayingArtworkLoader? artworkLoader,
    ArtworkPreloader? shuffleArtworkPreloader,
    AuthStorage? authStorage,
    PlaybackResumeStorage? playbackResumeStorage,
  }) : connection = connection ?? _Connection(),
       auth = _MemoryAuth(authenticated) {
    controller = AppController(
      connection: this.connection,
      audioEngineFactory: ({onMessage, onStats, onComplete, onStarted, onState}) {
        audioCreations++;
        if (failAudio) throw StateError('audio unavailable');
        this.onStarted = onStarted;
        this.onComplete = onComplete;
        this.onStats = onStats;
        this.onState = onState;
        return audio;
      },
      offlineDownloadManager: offlineDownloadManager ?? downloads,
      offlineStorage: offlineStorage ?? _Storage(),
      authStorage: authStorage ?? auth,
      playbackPreferencesStorage: preferences,
      playbackResumeStorage: playbackResumeStorage,
      customShuffleStorage: shuffle,
      connectivitySignalSource: connectivity,
      nowPlayingPlatformService: nowPlaying,
      nowPlayingArtworkLoader: artworkLoader,
      shuffleArtworkPreloader: shuffleArtworkPreloader,
      vehicleSurfaceService: vehicle,
      localNetworkPermissionService: permissions,
      playbackClock: () => playbackTime,
    );
  }
  late final AppController controller;
  final _Connection connection;
  final _MemoryAuth auth;
  final audio = _Audio();
  final downloads = _Downloads();
  final preferences = _Preferences();
  final shuffle = _Shuffle();
  final connectivity = _Connectivity();
  final nowPlaying = _NowPlaying();
  final vehicle = _Vehicle();
  final permissions = _Permissions();
  int audioCreations = 0;
  DateTime playbackTime = DateTime.utc(2026, 10, 1);
  void Function()? onStarted;
  void Function()? onComplete;
  void Function(Duration, Duration, double?, int?, bool)? onStats;
  void Function(bool, bool)? onState;

  Future<void> startRemote() async {
    await controller.initialize();
    await controller.restoreSession();
    await controller.queueAlbum('album');
    expect(audio.starts, hasLength(1));
    onStarted!();
  }

  void failTransport() {
    audio.active = false;
    audio.paused = false;
    onState!(false, false);
  }
}

class _Audio implements AudioEngine {
  @override
  Future<void> initialize() async {}

  @override
  void Function(Map<String, dynamic>)? onListeningSegment;
  Map<String, dynamic>? listeningContext;

  @override
  void configureListening(Map<String, dynamic>? context, {bool updateActive = false, bool discardPending = true}) {
    listeningContext = context == null ? null : Map.of(context);
  }

  int disposals = 0;
  double? volume;
  bool active = false;
  bool paused = false;
  @override
  bool sourceRejected = false;
  int pauses = 0;
  int resumes = 0;
  int stops = 0;
  Future<void>? stopGate;
  bool lastStopWaitForRelease = false;
  final seekResults = <Future<bool>>[];
  final settings = <StreamSettings>[];
  final starts = <({String trackId, Duration offset, bool quickStart, bool initialPaused})>[];
  final queueIds = <List<String>>[];
  final localStarts = <({String trackId, Duration offset})>[];
  @override
  bool get hasActivePlayer => active;
  @override
  bool get isPaused => paused;

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
    this.settings.add(settings);
    queueIds.add(List.of(queueTrackIds));
    sourceRejected = false;
    active = true;
    paused = initialPaused;
    starts.add((trackId: track.id, offset: startOffset, quickStart: quickStart, initialPaused: initialPaused));
  }

  @override
  Future<bool> seekTo(Duration position) async => seekResults.isEmpty ? active : await seekResults.removeAt(0);

  @override
  Future<void> playLocalFile({
    required Track track,
    required String filePath,
    String? contentType,
    Duration startOffset = Duration.zero,
    bool initialPaused = false,
  }) async {
    localStarts.add((trackId: track.id, offset: startOffset));
    active = true;
    paused = initialPaused;
  }

  @override
  void pause() {
    pauses++;
    paused = true;
  }

  @override
  void resume() {
    resumes++;
    paused = false;
  }

  @override
  Future<void> stop({bool waitForRelease = false}) async {
    stops++;
    lastStopWaitForRelease = waitForRelease;
    final gate = stopGate;
    if (gate != null) await gate;
    active = false;
    paused = false;
  }

  @override
  void setVolume(double value) {
    volume = value;
  }

  @override
  void setOutputDevice(int deviceId) {}

  @override
  Future<void> dispose() async {
    disposals++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Downloads implements OfflineDownloadManager {
  int loads = 0;
  int disposals = 0;
  int resets = 0;
  bool failLoad = false;
  bool failReset = false;
  final refreshedAlbums = <String>[];
  final refreshedArtists = <String>[];
  final pausedServers = <String>[];
  @override
  Future<void> pauseDownloadsForServer(String serverBaseUrl) async {
    pausedServers.add(serverBaseUrl);
  }

  @override
  List<OfflineTrackDownload> get downloads => const [];
  @override
  List<Track> localDownloadedTracks() => localTracks;
  List<Track> localTracks = const [];
  @override
  OfflineLibrarySnapshot get librarySnapshot => OfflineLibrarySnapshot(
    tracks: localTracks,
    artistGroups: offline_views.offlineArtistGroups(localTracks),
    liked: const [],
    playlists: const [],
    playlistTracks: const [],
    revision: 0,
  );
  @override
  OfflineTrackDownload? findForCurrentServer(String trackId) => null;
  @override
  OfflineTrackDownload? findLocal(String trackId) => null;
  @override
  Future<void> resumePausedForCurrentServer() async {}
  @override
  Future<void> repairOfflineMetadataFragments() async {}
  @override
  Future<void> refreshOfflineMetadataForAlbum(String albumId) async {
    refreshedAlbums.add(albumId);
  }

  @override
  Future<void> refreshOfflineMetadataForArtist(String artistId) async {
    refreshedArtists.add(artistId);
  }

  @override
  Stream<OfflineLibrarySnapshot> get librarySnapshotStream => const Stream.empty();
  @override
  Stream<List<Track>> get localLikedStream => const Stream.empty();
  @override
  Stream<List<Playlist>> get localPlaylistsStream => const Stream.empty();
  @override
  Future<void> load() async {
    loads++;
    if (failLoad) throw StateError('load failed');
  }

  @override
  Future<void> resetLocalData() async {
    resets++;
    if (failReset) throw StateError('reset failed');
  }

  @override
  Future<void> clearUnfinishedDownloads() async {
    resets++;
    if (failReset) throw StateError('reset failed');
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Connection extends ServerConnection {
  _Connection() : super(baseUrl: 'https://unused.test') {
    setTrust(testServerTrust);
  }
  int pings = 0;
  bool identityChanged = false;
  Future<bool>? pendingIdentityCheck;
  bool playbackSettingsFailure = false;
  int _shuffleSessionSequence = 0;
  @override
  Future<ShuffleSessionPage> createShuffleSession({
    required String mode,
    required String clientId,
    required String requestId,
    String? artistId,
    String? albumId,
    List<String> artistIds = const [],
    List<String> genres = const [],
    String? playlistId,
    String? startTrackId,
  }) async {
    final tracks = mode == 'playlist'
        ? await fetchPlaylistTracks(playlistId!)
        : mode == 'liked'
        ? await fetchLikedTracks()
        : trackResponse ?? [offlineTestTrack(id: 'track')];
    final ordered = [
      ...tracks.where((track) => track.id == startTrackId),
      ...tracks.where((track) => track.id != startTrackId),
    ];
    return ShuffleSessionPage(
      sessionId: 'test-session-${++_shuffleSessionSequence}',
      offset: 0,
      nextOffset: ordered.length,
      total: ordered.length,
      hasMore: false,
      items: ordered,
      itemOffsets: List.generate(ordered.length, (i) => i),
    );
  }

  @override
  Future<void> releaseShuffleSession(String sessionId, {required String clientId}) async {}
  @override
  Future<void> updatePlaybackSettings({required String repeatMode}) async => repeatUpdates.add(repeatMode);

  final repeatUpdates = <String>[];
  @override
  Future<bool> hasServerIdentityChanged() async => pendingIdentityCheck ?? identityChanged;
  Future<void>? pendingProbe;
  final verifiedServers = <String>[];

  @override
  Future<void> verifyServerConnection(String input, {Duration timeout = const Duration(seconds: 10)}) async {
    verifiedServers.add(input);
    await pendingProbe;
  }

  int searches = 0;
  Future<List<Artist>>? pendingArtistsPage;
  List<Artist> artistsPageResponse = const [];
  int? generatedArtistCount;
  final artistPageFilters = <bool>[];
  final artistPageOffsets = <int>[];
  Map<String, Future<ArtistReleases>> releaseResponses = {};
  @override
  Future<List<Artist>> fetchArtistsPage({
    int limit = ServerConnection.artistsPageSize,
    int offset = 0,
    bool includeContributors = false,
  }) async {
    artistPageFilters.add(includeContributors);
    artistPageOffsets.add(offset);
    final pending = pendingArtistsPage;
    pendingArtistsPage = null;
    return pending ?? artistsPageResponse;
  }

  @override
  Future<ArtistSummaryPage> fetchArtistSummariesPage({int limit = 60, int offset = 0, String? revision}) async {
    final count = generatedArtistCount;

    if (count != null) {
      final end = (offset + limit).clamp(0, count);

      return ArtistSummaryPage(
        items: [for (var index = offset; index < end; index++) ArtistSummary(id: '$index', name: 'Artist $index')],
        total: count,
        nextOffset: end < count ? end : null,
        browseRevision: 'generated-catalogue',
      );
    }

    final artists = await fetchArtistsPage(limit: limit, offset: offset);

    return ArtistSummaryPage(
      items: artists.map(ArtistSummary.fromArtist).toList(),
      total: offset + artists.length + (artists.length == limit ? 1 : 0),
      nextOffset: artists.length == limit ? offset + artists.length : null,
      browseRevision: 'test-catalogue',
    );
  }

  @override
  Future<ArtistReleases> fetchArtistReleases(String artistId) async =>
      releaseResponses[artistId] ?? ArtistReleases(albums: albumResponse);

  int trackListRequests = 0;
  List<Track>? trackResponse;
  List<Album> albumResponse = const [];
  List<SearchResult> searchResponse = const [];
  Album? updatedAlbum;
  Artist? updatedArtist;
  Map<String, Artist> artistsById = {};
  final artistLookups = <String>[];
  Stream<MetadataUpdateEvent>? metadataEvents;
  Future<Track>? pendingTrackById;
  Future<int?>? pendingHealth;
  @override
  Future<ServerCapabilities> fetchCapabilities() async => ServerCapabilities(
    downloadJobsV2: true,
    metadataSnapshotsV2: true,
    eventReplayV2: true,
    trackFileContractV2: true,
  );
  @override
  Future<PlaybackSettingsResponse> fetchPlaybackSettings({
    Duration timeout = const Duration(seconds: 8),
    bool retryable = true,
  }) async {
    if (playbackSettingsFailure) throw StateError('TLS pin mismatch');
    return PlaybackSettingsResponse(repeatMode: 'off');
  }

  @override
  Future<ServerPortsResponse> fetchServerPorts({
    Duration timeout = const Duration(seconds: 8),
    bool retryable = true,
  }) async => ServerPortsResponse(httpPort: 8000, quicPort: 8001, quicEnabled: true);
  @override
  Stream<MetadataUpdateEvent> streamMetadataEvents() => metadataEvents ?? const Stream.empty();
  @override
  Future<List<Album>> fetchAlbums(String artistId) async => albumResponse;
  @override
  Future<Album> fetchAlbumById(String albumId) async => updatedAlbum!;
  @override
  Future<Artist> fetchArtistById(String artistId) async {
    artistLookups.add(artistId);
    return artistsById[artistId] ?? updatedArtist!;
  }

  @override
  Future<Track> fetchTrackById(String trackId) async => pendingTrackById ?? trackResponse!.first;
  @override
  Future<List<Track>> fetchPlaylistTracks(String playlistId) async => trackResponse!;
  @override
  Future<List<Track>> fetchLikedTracks() async => trackResponse!;
  @override
  Future<List<SearchResult>> search(String query, {String? filter}) async {
    searches++;
    return searchResponse;
  }

  @override
  Future<List<Track>> fetchTracks(String albumId) async {
    trackListRequests++;
    return trackResponse ??
        [
          Track(
            id: 'track',
            title: 'Track',
            artist: 'Artist',
            album: 'Album',
            albumId: albumId,
            durationMs: 180000,
            liked: false,
            inPlaylists: false,
          ),
        ];
  }

  @override
  Future<int?> pingHealthMs({Duration timeout = const Duration(seconds: 3)}) {
    pings++;
    return pendingHealth ?? Future.value(null);
  }
}

class _LikeConnection extends _Connection {
  bool available = true;
  bool serverLiked = false;
  int matches = 0;
  final likeUpdates = <Map<String, bool>>[];

  @override
  Future<PlaybackSettingsResponse> fetchPlaybackSettings({
    Duration timeout = const Duration(seconds: 8),
    bool retryable = true,
  }) async {
    if (!available) throw const SocketException('Server unavailable');
    return PlaybackSettingsResponse(repeatMode: 'off');
  }

  @override
  Future<List<ServerLikeState>> updateLikeStates(
    Map<String, bool> states, {
    Map<String, int> updatedAtByTrack = const {},
  }) async {
    likeUpdates.add(Map.of(states));
    serverLiked = states.values.single;
    return [
      for (final entry in states.entries)
        ServerLikeState(trackId: entry.key, liked: entry.value, updatedAt: DateTime.now().millisecondsSinceEpoch),
    ];
  }

  @override
  Future<List<Track>> fetchLikedTracks() async =>
      serverLiked ? [offlineTestTrack(id: 'server-track').copyWith(liked: true)] : [];

  @override
  Future<List<TrackMatchResult>> matchTracks(List<TrackMatchDescriptor> tracks) async {
    matches++;
    return [
      for (final track in tracks)
        TrackMatchResult(
          localTrackId: track.localTrackId,
          serverTrackId: 'server-track',
          confidence: 1,
          matchKind: 'exact_server_track_id',
          serverLiked: serverLiked,
          serverUpdatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
    ];
  }
}

class _StartupDownloadConnection extends _Connection {
  bool available = true;
  final requestedAlbums = <String>[];
  final requestedBatches = <List<String>>[];

  @override
  Future<List<TrackMatchResult>> matchTracks(List<TrackMatchDescriptor> tracks) async {
    return const [];
  }

  @override
  Future<PlaybackSettingsResponse> fetchPlaybackSettings({
    Duration timeout = const Duration(seconds: 8),
    bool retryable = true,
  }) async {
    if (!available) {
      throw const SocketException('Server temporarily unavailable');
    }
    return PlaybackSettingsResponse(repeatMode: 'off');
  }

  @override
  Future<ServerCapabilities> fetchCapabilities() async => ServerCapabilities(
    downloadJobsV2: false,
    metadataSnapshotsV2: false,
    eventReplayV2: false,
    trackFileContractV2: false,
  );

  @override
  Future<List<Track>> fetchTracks(String albumId) async {
    requestedAlbums.add(albumId);
    return [offlineTestTrack(id: '$albumId-track')];
  }

  @override
  Future<DownloadBatchManifest> createDownloadBatch(List<String> trackIds, {String? clientBatchId}) async {
    requestedBatches.add(List.of(trackIds));
    // Stop after metadata planning; no socket or media worker is started.
    setToken(null);
    return DownloadBatchManifest(
      schemaVersion: 1,
      batchId: clientBatchId!,
      createdAt: DateTime.now(),
      unavailable: const [],
      items: [for (final id in trackIds) offlineTestDownloadManifest(batchId: clientBatchId, trackId: id).items.single],
    );
  }

  @override
  Future<OfflineTrackMetadata> fetchOfflineMetadata(String trackId) async =>
      offlineTestOfflineMetadata(trackId: trackId);

  @override
  Future<ServerArtwork?> fetchAlbumCoverBytes(String albumId, {Duration? timeout}) async => null;

  @override
  Future<ServerArtwork?> fetchArtistCoverBytes(String artistId, {String kind = 'logo', Duration? timeout}) async =>
      null;
}

class _DelayedLoginConnection extends _PasswordConnection {
  final portsRequested = Completer<void>();
  final portsResponse = Completer<ServerPortsResponse>();

  @override
  Future<String> login({required String username, required String password}) async {
    setTrust(testServerTrust);
    setToken('password-token');
    return 'password-token';
  }

  @override
  Future<ServerPortsResponse> fetchServerPorts({Duration timeout = const Duration(seconds: 8), bool retryable = true}) {
    if (!portsRequested.isCompleted) portsRequested.complete();
    return portsResponse.future;
  }
}

class _PasswordConnection extends _Connection {
  int passwordChanges = 0;
  int logoutRequests = 0;
  Future<void>? passwordResponse;
  PasswordChangeException? passwordFailure;
  @override
  bool get canChangeOwnPassword => token?.isNotEmpty == true;
  @override
  Future<void> changeOwnPassword({
    required String currentPassword,
    required String newPassword,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    passwordChanges++;
    if (passwordFailure != null) throw passwordFailure!;
    await passwordResponse;
  }

  @override
  Future<void> logout({Duration timeout = const Duration(seconds: 8)}) async {
    logoutRequests++;
  }
}

class _MemoryAuth extends AuthStorage {
  _MemoryAuth(this.authenticated);
  final bool authenticated;
  int clears = 0;
  Completer<void>? clearingServer;
  Future<void>? clearServerResponse;

  @override
  Future<AuthCredentials?> read() async => authenticated
      ? const AuthCredentials(
          baseUrl: 'https://unused.test',
          token: 'test-token',
          username: 'test',
          trust: testServerTrust,
        )
      : null;
  @override
  Future<void> clear() async {
    clears++;
  }

  @override
  Future<void> clearForServer(String url) async {
    clearingServer?.complete();
    await clearServerResponse;
    final credentials = await read();
    if (credentials != null &&
        ServerTrust.origin(Uri.parse(credentials.baseUrl)) == ServerTrust.origin(Uri.parse(url))) {
      await clear();
    }
  }
}

void _mockTrustVault() {
  const vault = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final values = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(vault, (call) async {
    final args = Map<String, dynamic>.from(call.arguments as Map);
    if (call.method == 'readAll') return Map<String, String>.from(values);
    final key = args['key'] as String;
    if (call.method == 'read') return values[key];
    if (call.method == 'write') values[key] = args['value'] as String;
    if (call.method == 'delete') values.remove(key);
    return null;
  });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(vault, null),
  );
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
  int reads = 0;
  Future<bool?>? pending;
  PlaybackRepeatMode? repeatMode;
  Future<PlaybackRepeatMode?>? pendingRepeat;
  Future<void>? pendingRepeatWrite;
  final repeatWriteStarted = Completer<void>();
  final repeatWrites = <PlaybackRepeatMode>[];

  @override
  Future<PlaybackRepeatMode?> readRepeatMode() => pendingRepeat ?? Future.value(repeatMode);

  @override
  Future<void> writeRepeatMode(PlaybackRepeatMode mode) async {
    if (!repeatWriteStarted.isCompleted) repeatWriteStarted.complete();

    final pending = pendingRepeatWrite;

    if (pending != null) {
      await pending;
    }

    repeatMode = mode;
    repeatWrites.add(mode);
  }

  @override
  Future<bool?> readCollectionListMode() {
    reads++;
    return pending ?? Future.value(true);
  }

  @override
  Future<double?> readVolume() async {
    reads++;
    return 0.4;
  }
}

class _Shuffle extends CustomShuffleSettingsStorage {
  int reads = 0;
  Future<CustomShuffleSettings>? pending;
  @override
  Future<CustomShuffleSettings> read() {
    reads++;
    return pending ?? Future.value(const CustomShuffleSettings(artistIds: ['artist']));
  }

  @override
  Future<void> write(CustomShuffleSettings settings) async {}

  @override
  Future<void> writeLocal(CustomShuffleSettings settings) async {}

  @override
  Future<CustomShuffleSettings> readForAccount(String scope) async => const CustomShuffleSettings();

  @override
  Future<void> writeForAccount(String scope, CustomShuffleSettings settings) async {}
}

class _Connectivity extends ConnectivitySignalSource {
  int checks = 0;
  @override
  Stream<bool> get availabilityStream => const Stream.empty();
  @override
  Future<bool> hasConnectivity() async {
    checks++;
    return true;
  }
}

class _NowPlaying extends NowPlayingPlatformService {
  int disposals = 0;
  int clears = 0;
  Future<void> Function(NativeRemoteCommand)? commandHandler;
  bool supported = false;
  bool nativeArtwork = false;
  final updates = <Map<String, dynamic>>[];
  @override
  bool get isSupported => supported;
  @override
  bool get loadsArtworkNatively => nativeArtwork;
  @override
  void setRemoteCommandHandler(Future<void> Function(NativeRemoteCommand) handler) {
    commandHandler = handler;
  }

  @override
  Future<void> setNowPlaying(Map<String, dynamic> payload) async => updates.add(payload);
  @override
  Future<void> clearNowPlaying() async {
    clears++;
  }

  @override
  void dispose() {
    disposals++;
    commandHandler = null;
  }
}

class _RecordingArtworkPreloader implements ArtworkPreloader {
  final updates = <List<ArtworkRequest>>[];
  List<ArtworkRequest> current = const [];
  int clears = 0;

  @override
  void update(Iterable<ArtworkRequest> requests) {
    current = requests.toList();
    updates.add(current);
  }

  @override
  void clear() {
    clears++;
    current = const [];
  }
}

class _ArtworkLoader extends NowPlayingArtworkLoader {
  int loads = 0;
  @override
  Future<Uint8List?> loadRemote(String url, {required String token}) async {
    loads++;
    return Uint8List.fromList([1, 2, 3]);
  }
}

class _Vehicle extends VehicleSurfaceService {
  int disposals = 0;
  bool supported = false;
  Future<dynamic> Function(String method, Map<String, dynamic> arguments)? handler;
  @override
  bool get isSupported => supported;
  @override
  void setMethodHandler(Future<dynamic> Function(String method, Map<String, dynamic> arguments) handler) {
    this.handler = handler;
  }

  @override
  Future<void> notifyState(Map<String, dynamic> payload) async {}
  @override
  Future<void> notifyAuthorization(bool authorized) async {}
  @override
  void dispose() {
    disposals++;
    handler = null;
  }
}

class _Permissions extends LocalNetworkPermissionService {
  int disposals = 0;
  @override
  bool get isSupported => false;
  @override
  void dispose() {
    disposals++;
  }
}

class _IsolationConnection extends _Connection {
  Future<List<Track>>? pendingLiked;
  Future<List<Playlist>>? pendingPlaylists;
  Future<List<Track>>? pendingCollectionTracks;
  Future<ServerLikeState?>? pendingLikeWrite;
  Future<Playlist>? pendingCreate;
  List<Playlist> playlistResponse = [];
  final settingsByToken = <String, Future<PlaybackSettingsResponse>>{};
  final settingsRequested = <String?>[];
  final _settingsStarted = <String?, Completer<void>>{};
  int coverDeletes = 0;

  Future<void> waitForSettings(String token) => _settingsStarted.putIfAbsent(token, Completer<void>.new).future;

  @override
  Future<List<Track>> fetchLikedTracks() async => pendingLiked ?? trackResponse ?? [];
  @override
  Future<List<Playlist>> fetchPlaylists() async => pendingPlaylists ?? playlistResponse;
  @override
  Future<List<Track>> fetchPlaylistTracks(String playlistId) async => pendingCollectionTracks ?? trackResponse ?? [];
  @override
  Future<List<Track>> fetchTracks(String albumId) async => pendingCollectionTracks ?? trackResponse ?? [];
  @override
  Future<ServerLikeState?> setLikeState(String trackId, bool liked) async => pendingLikeWrite;
  @override
  Future<Playlist> createPlaylist(String name, {String? description}) async => pendingCreate!;
  @override
  Future<Playlist> deletePlaylistCover(String playlistId) async {
    coverDeletes++;
    return Playlist(id: playlistId, name: 'Old list', trackIds: []);
  }

  @override
  Future<PlaybackSettingsResponse> fetchPlaybackSettings({
    Duration timeout = const Duration(seconds: 8),
    bool retryable = true,
  }) async {
    settingsRequested.add(token);
    final started = _settingsStarted.putIfAbsent(token, Completer<void>.new);
    if (!started.isCompleted) started.complete();
    return settingsByToken[token] ?? PlaybackSettingsResponse(repeatMode: 'off');
  }
}

class _WindowShuffleConnection extends _Connection {
  bool distinctAlbumIds = false;
  int creates = 0;
  final modes = <String>[];
  final requestIds = <String>[];
  final clientIds = <String>[];
  final pageOffsets = <int>[];
  final released = <String>[];
  Future<ShuffleSessionPage>? pendingPage;
  Future<ShuffleSessionPage>? pendingCreate;
  bool initialPageEmpty = false;
  final createStarted = Completer<void>();
  ApiException? pageFailure;

  ShuffleSessionPage page(String sessionId, int offset) {
    const total = 35;
    final next = (offset + 10).clamp(0, total);
    return ShuffleSessionPage(
      sessionId: sessionId,
      offset: offset,
      nextOffset: next,
      total: total,
      hasMore: next < total,
      items: List.generate(
        next - offset,
        (i) => offlineTestTrack(
          id: 'deck-track-${offset + i}',
          albumId: distinctAlbumIds ? 'album-${offset + i}' : 'album-1',
        ),
      ),
      itemOffsets: List.generate(next - offset, (i) => offset + i),
    );
  }

  @override
  Future<ShuffleSessionPage> createShuffleSession({
    required String mode,
    required String clientId,
    required String requestId,
    String? artistId,
    String? albumId,
    List<String> artistIds = const [],
    List<String> genres = const [],
    String? playlistId,
    String? startTrackId,
  }) async {
    modes.add(mode);
    requestIds.add(requestId);
    clientIds.add(clientId);
    final id = 'window-${++creates}';
    if (!createStarted.isCompleted) createStarted.complete();
    if (pendingCreate != null) return pendingCreate!;
    if (initialPageEmpty) {
      return ShuffleSessionPage(
        sessionId: id,
        offset: 0,
        nextOffset: 10,
        total: 35,
        hasMore: true,
        items: [],
        itemOffsets: [],
      );
    }
    return page(id, 0);
  }

  @override
  Future<ShuffleSessionPage> fetchShuffleSessionPage(
    String sessionId, {
    required String clientId,
    required int offset,
  }) async {
    pageOffsets.add(offset);
    if (pageFailure != null) throw pageFailure!;
    return pendingPage ?? page(sessionId, offset);
  }

  @override
  Future<void> releaseShuffleSession(String sessionId, {required String clientId}) async => released.add(sessionId);

  @override
  Future<ServerLikeState?> setLikeState(String trackId, bool liked) async =>
      ServerLikeState(trackId: trackId, liked: liked, updatedAt: 1);
}
