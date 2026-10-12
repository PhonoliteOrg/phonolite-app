import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/entities/app_controller.dart';
import 'package:phonolite_app/entities/app_log.dart';
import 'package:phonolite_app/entities/audio_engine.dart';
import 'package:phonolite_app/entities/auth_storage.dart';
import 'package:phonolite_app/entities/connectivity_signal_source.dart';
import 'package:phonolite_app/entities/custom_shuffle_settings.dart';
import 'package:phonolite_app/entities/models.dart';
import 'package:phonolite_app/entities/offline_download_manager.dart';
import 'package:phonolite_app/entities/offline_library.dart';
import 'package:phonolite_app/entities/offline_storage_settings.dart';
import 'package:phonolite_app/entities/playback_preferences.dart';
import 'package:phonolite_app/entities/server_connection.dart';
import 'package:phonolite_app/platform/local_network_permission_service.dart';
import 'package:phonolite_app/platform/now_playing_platform_service.dart';
import 'package:phonolite_app/platform/vehicle_surface_service.dart';
import '../support/auth_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'construction performs no startup work and can be closed without starting',
    () async {
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
    },
  );

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

  test(
    'closing during initialization ignores late settings and audio callbacks',
    () async {
      final harness = _Harness();
      final pendingSettings = Completer<CustomShuffleSettings>();
      final pendingPreferences = Completer<bool?>();
      final pendingHealth = Completer<int?>();
      harness.shuffle.pending = pendingSettings.future;
      harness.preferences.pending = pendingPreferences.future;
      harness.connection.pendingHealth = pendingHealth.future;
      final startup = harness.controller.initialize();
      await harness.controller.close();
      pendingSettings.complete(
        const CustomShuffleSettings(artistIds: ['late']),
      );
      pendingPreferences.complete(false);
      pendingHealth.complete(50);
      await startup;
      harness.onStarted!();
      harness.onStats!(Duration.zero, Duration.zero, null, null, false);
      expect(harness.controller.isInitialized, isFalse);
      expect(harness.controller.customShuffleArtistIds, isEmpty);
      expect(harness.audio.volume, isNull);
      expect(harness.preferences.reads, 1);
    },
  );

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

  test(
    'audio factory failure releases subscriptions and the connection callback',
    () async {
      final harness = _Harness(failAudio: true);
      await expectLater(harness.controller.initialize(), throwsStateError);
      expect(harness.audio.disposals, 0);
      expect(harness.downloads.disposals, 1);
      expect(harness.connection.onTransportFailure, isNull);
    },
  );

  test(
    'getters and emitted lists cannot mutate controller collections',
    () async {
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
    },
  );

  test(
    'log bursts publish one bounded snapshot and clear cancels pending updates',
    () async {
      final harness = _Harness();
      await harness.controller.initialize();
      addTearDown(harness.controller.close);
      await harness.controller.clearMessages();
      final snapshots = <List<LogEntry>>[];
      final subscription = harness.controller.messageStream.listen(
        snapshots.add,
      );
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
    },
  );

  test(
    'transport failure during rapid seeks restarts at the latest target',
    () async {
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

      harness.onStats!(
        const Duration(seconds: 21),
        const Duration(seconds: 2),
        96,
        400,
        false,
      );
      expect(
        harness.controller.playbackState.position,
        const Duration(seconds: 21),
      );
    },
  );

  test(
    'repeated interruption preserves play intent and waits for healthy reconnect',
    () async {
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
      harness.playbackTime = harness.playbackTime.add(
        const Duration(seconds: 9),
      );
      harness.connection.pendingHealth = Future.value(25);
      await harness.controller.refreshServerAvailability();
      expect(harness.audio.starts, hasLength(3));
      expect(harness.audio.starts.last.offset, const Duration(seconds: 25));
      expect(harness.controller.playbackState.isPlaying, isTrue);
      expect(harness.controller.playbackState.isLoading, isTrue);
    },
  );

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

  test(
    'an old failed seek cannot restart after a newer seek is ready',
    () async {
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
      expect(
        harness.controller.playbackState.position,
        const Duration(seconds: 20),
      );
    },
  );

  test(
    'seek fallback applies the latest pause intent when the session starts',
    () async {
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
    },
  );

  test(
    'transport recovery supersedes the pending seek acknowledgement',
    () async {
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
    },
  );

  test('changing output devices preserves a paused session', () async {
    final harness = _Harness(authenticated: true);
    await harness.startRemote();
    addTearDown(harness.controller.close);
    await harness.controller.pause(true);

    await harness.controller.selectOutputDevice(
      OutputDevice(id: 9, name: 'Test output'),
    );

    expect(harness.audio.starts, hasLength(2));
    expect(harness.audio.starts.last.initialPaused, isTrue);
    expect(harness.audio.paused, isTrue);
    expect(harness.controller.playbackState.isPlaying, isFalse);
  });

  test(
    'a failed seek at the initial offset still replaces the session',
    () async {
      final harness = _Harness(authenticated: true);
      await harness.startRemote();
      addTearDown(harness.controller.close);
      harness.audio.seekResults.add(Future.value(false));

      await harness.controller.seekTo(Duration.zero);

      expect(harness.audio.starts, hasLength(2));
      expect(harness.audio.starts.last.offset, Duration.zero);
    },
  );

  test(
    'paused seek failure stays paused and can resume from its target',
    () async {
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
    },
  );

  test(
    'transport failure during scrubbing waits for the user seek commit',
    () async {
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
    },
  );

  test('ordinary interruption resumes from output position', () async {
    final harness = _Harness(authenticated: true);
    await harness.startRemote();
    addTearDown(harness.controller.close);
    harness.onStats!(
      const Duration(seconds: 12),
      const Duration(seconds: 2),
      160,
      100,
      false,
    );

    harness.failTransport();

    expect(harness.audio.starts, hasLength(2));
    expect(harness.audio.starts.last.offset, const Duration(seconds: 12));
  });

  test(
    'album queue normalization preserves artist and genre metadata',
    () async {
      final track = _metadataTrack();
      final connection = _Connection()..trackResponse = [track];
      final harness = _Harness(authenticated: true, connection: connection);
      await harness.startRemote();
      addTearDown(harness.controller.close);

      final playing = harness.controller.playbackState.track!;
      expect(playing.albumId, 'album');
      _expectTrackMetadata(playing, track);
    },
  );

  test('playback search refuses uncertain album attribution', () async {
    final scenarios = <List<SearchResult>>[
      [SearchResult(kind: 'album', id: 'wrong', title: 'The Album')],
      [
        SearchResult(
          kind: 'album',
          id: 'wrong',
          title: 'The Album',
          subtitle: 'The Artist Orchestra',
        ),
      ],
      [
        SearchResult(
          kind: 'album',
          id: 'wrong',
          title: 'The Album Deluxe',
          subtitle: 'The Artist',
        ),
      ],
      [
        for (final id in ['first-release', 'second-release'])
          SearchResult(
            kind: 'album',
            id: id,
            title: 'The Album',
            subtitle: 'The Artist',
          ),
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
      ..searchResponse = [
        SearchResult(
          kind: 'album',
          id: 'correct',
          title: '初恋',
          subtitle: '宇多田ヒカル',
        ),
      ];
    final harness = _Harness(authenticated: true, connection: connection);
    await harness.controller.initialize();
    await harness.controller.restoreSession();
    addTearDown(harness.controller.close);
    final hydrated = harness.controller.playbackStream.firstWhere(
      (state) => state.track?.albumId == 'correct',
    );
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

    connection.setBaseUrl('https://other.test/api/v1');
    connection.searchResponse = [
      SearchResult(
        kind: 'album',
        id: 'new-server-album',
        title: 'The Album',
        subtitle: 'The Artist',
      ),
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
          Album(
            id: id,
            title: 'The Album',
            artist: 'The Artist',
            artistId: 'artist-id',
            trackCount: 1,
          ),
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
        Album(
          id: 'album',
          title: 'The Album',
          artist: 'Old Artist',
          artistId: 'old-artist',
          trackCount: 1,
        ),
      ]
      ..updatedAlbum = Album(
        id: 'album',
        title: 'The Album',
        artist: '',
        artistId: 'new-artist',
        trackCount: 1,
      )
      ..updatedArtist = Artist(
        id: 'new-artist',
        name: 'Correct Artist',
        albumCount: 1,
      );
    final harness = _Harness(authenticated: true, connection: connection);
    await harness.controller.initialize();
    await harness.controller.restoreSession();
    addTearDown(harness.controller.close);
    await harness.controller.loadAlbums('old-artist');
    final refreshed = harness.controller.watchAlbum('album').first;
    events.add(
      MetadataUpdateEvent(
        revision: 1,
        kind: 'album',
        id: 'album',
        updatedAt: 0,
      ),
    );

    final album = await refreshed;
    expect(album.artistId, 'new-artist');
    expect(album.artist, 'Correct Artist');
  });

  test(
    'album events refresh loaded performers without restarting audio',
    () async {
      final events = StreamController<MetadataUpdateEvent>.broadcast();
      addTearDown(events.close);
      final original = _metadataTrack().copyWith(
        albumId: 'album',
        liked: true,
        inPlaylists: true,
      );
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
      harness.onStats!(
        const Duration(seconds: 12),
        Duration.zero,
        160,
        100,
        false,
      );
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
      events.add(
        MetadataUpdateEvent(
          revision: 1,
          kind: 'album',
          id: 'album',
          updatedAt: 0,
        ),
      );

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
      expect(
        harness.controller.tracks.single.artist,
        'Correct Track Performer',
      );
      expect(
        harness.controller.playlistTracks.single.artist,
        'Correct Track Performer',
      );
      expect(harness.controller.liked.single.artist, 'Correct Track Performer');
      for (final track in [
        harness.controller.tracks.single,
        harness.controller.playlistTracks.single,
        harness.controller.liked.single,
      ]) {
        expect(track.listeningGenres, ['Baroque']);
      }
      expect(harness.downloads.refreshedAlbums, ['album']);
    },
  );

  test(
    'artist events refresh only tracks with the exact performer ID',
    () async {
      final events = StreamController<MetadataUpdateEvent>.broadcast();
      addTearDown(events.close);
      final original = _metadataTrack().copyWith(albumId: 'album');
      final collaborator = original.copyWith(
        id: 'other-track',
        artist: 'Another Performer',
        artistId: 'another-id',
      );
      final connection = _Connection()
        ..metadataEvents = events.stream
        ..trackResponse = [original, collaborator]
        ..updatedArtist = Artist(
          id: original.artistId!,
          name: 'Correct Performer',
          albumCount: 1,
        );
      final harness = _Harness(authenticated: true, connection: connection);
      await harness.controller.initialize();
      await harness.controller.restoreSession();
      addTearDown(harness.controller.close);
      await harness.controller.loadTracks('album');
      await harness.controller.queueAlbum('album');
      final requestsBefore = connection.trackListRequests;
      final refreshed = harness.controller.playbackStream.firstWhere(
        (state) => state.track?.artist == 'Correct Performer',
      );
      events.add(
        MetadataUpdateEvent(
          revision: 1,
          kind: 'artist',
          id: original.artistId!,
          updatedAt: 0,
        ),
      );

      expect((await refreshed).track?.artist, 'Correct Performer');
      expect(harness.controller.tracks.last.artist, 'Another Performer');
      expect(connection.trackListRequests, requestsBefore);
      expect(harness.audio.starts, hasLength(1));
      await Future<void>.delayed(Duration.zero);
      expect(harness.downloads.refreshedArtists, [original.artistId]);
    },
  );

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
    connection.trackResponse = [
      original.copyWith(album: 'Correct Album', artist: 'Correct Performer'),
    ];
    final refreshed = harness.controller.playbackStream.firstWhere(
      (state) => state.track?.artist == 'Correct Performer',
    );
    events.add(
      MetadataUpdateEvent(
        revision: 1,
        kind: 'album',
        id: 'album',
        updatedAt: 0,
      ),
    );
    await refreshed;
    oldRead.complete(original.copyWith(artist: 'Old Wrong Performer'));
    await Future<void>.delayed(Duration.zero);

    expect(harness.controller.playbackState.track?.artist, 'Correct Performer');
    expect(harness.audio.starts, hasLength(1));
  });
  test(
    'artist refresh resets pagination and requests billed artists only',
    () async {
      final connection = _Connection();
      final stale = Completer<List<Artist>>();
      connection.pendingArtistsPage = stale.future;
      connection.artistsPageResponse = [
        Artist(id: 'guest', name: 'Guest', albumCount: 0, appearanceCount: 1),
      ];
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
    },
  );

  test(
    'loaded releases immediately update artist counts without metadata requests',
    () async {
      final album = Album(
        id: 'one',
        title: 'One',
        artist: 'A',
        artistId: 'a',
        trackCount: 1,
      );
      final credit = ArtistReleaseContribution(
        album: album,
        roles: const ['composer'],
      );
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
          'composer': Future.value(
            ArtistReleases(collabAlbums: [credit], otherCredits: [credit]),
          ),
        };
      final harness = _Harness(authenticated: true, connection: connection);
      addTearDown(harness.controller.close);
      await harness.controller.initialize();
      await harness.controller.restoreSession();
      await harness.controller.loadArtists();
      final rowUpdate = harness.controller.artistsStream.firstWhere(
        (artists) => artists.single.otherCreditCount == 1,
      );
      final profileUpdate = harness.controller.watchArtist('composer').first;
      await harness.controller.loadArtistReleases('composer');
      expect((await rowUpdate).single.releaseCount, 0);
      final updated = await profileUpdate;
      expect(updated.albumCount, 0);
      expect(updated.collabAlbumCount, 0);
      expect(updated.otherCreditCount, 1);
      expect(updated.releaseCount, 0);
      expect(updated.summary, 'Biography');
      expect(updated.genres, ['Jazz']);
      expect(updated.logoRef, 'logo.png');
      expect(connection.artistLookups, isEmpty);
      expect(connection.artistPageOffsets, [0]);
    },
  );

  test(
    'late relationship reads cannot replace a different artist profile',
    () async {
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
      expect(
        harness.controller.artistReleases.collabAlbums.single.album.id,
        'shared',
      );
      expect(
        harness.controller.artistReleases.collabAlbums.single.album.credits,
        hasLength(2),
      );
    },
  );

  for (final scenario in [
    (artistId: 'guest', guestOnTrack: true, expected: ShuffleMode.custom),
    (artistId: 'joint', guestOnTrack: false, expected: ShuffleMode.custom),
    (artistId: 'composer', guestOnTrack: false, expected: ShuffleMode.off),
    (artistId: 'guest', guestOnTrack: false, expected: ShuffleMode.off),
    (
      artistId: 'album-composer',
      guestOnTrack: false,
      expected: ShuffleMode.off,
    ),
  ]) {
    test('remote custom shuffle keeps only credited artist selections: '
        '${scenario.artistId}, guest ${scenario.guestOnTrack}', () async {
      final track = _collaborationTrack(guest: scenario.guestOnTrack);
      final connection = _Connection()
        ..trackResponse = [track]
        ..updatedAlbum = _collaborationAlbum();
      final harness = _Harness(authenticated: true, connection: connection);
      harness.shuffle.pending = Future.value(
        CustomShuffleSettings(artistIds: [scenario.artistId]),
      );
      addTearDown(harness.controller.close);
      await harness.controller.initialize();
      await harness.controller.restoreSession();
      harness.controller.updateShuffleMode(
        ShuffleMode.custom,
        scope: ActionScope.server,
      );

      await harness.controller.queuePlaylist(
        'playlist',
        startTrackId: track.id,
      );

      expect(harness.controller.playbackState.shuffleMode, scenario.expected);
      expect(harness.audio.starts.single.trackId, track.id);
    });
  }

  for (final cached in [false, true]) {
    test(
      'remote custom shuffle matches guest genres, cached $cached',
      () async {
        final track = _collaborationTrack(guest: true);
        final guest = Artist(
          id: 'guest',
          name: 'Guest',
          albumCount: 0,
          genres: [' Jazz '],
        );
        final connection = _Connection()
          ..trackResponse = [track]
          ..updatedAlbum = _collaborationAlbum()
          ..artistsById = {'guest': guest}
          ..artistsPageResponse = [
            Artist(id: 'main', name: 'Main', albumCount: 0),
            guest,
          ];
        final harness = _Harness(authenticated: true, connection: connection);
        harness.shuffle.pending = Future.value(
          const CustomShuffleSettings(genres: ['jazz']),
        );
        addTearDown(harness.controller.close);
        await harness.controller.initialize();
        await harness.controller.restoreSession();
        if (cached) await harness.controller.loadArtists();
        harness.controller.updateShuffleMode(
          ShuffleMode.custom,
          scope: ActionScope.server,
        );

        await harness.controller.queuePlaylist(
          'playlist',
          startTrackId: track.id,
        );

        expect(
          harness.controller.playbackState.shuffleMode,
          ShuffleMode.custom,
        );
        expect(connection.artistLookups, cached ? isEmpty : ['main', 'guest']);
      },
    );
  }

  test(
    'remote custom shuffle recognizes a credited track without an album ID',
    () async {
      final track = _collaborationTrack(guest: true).copyWith(albumId: null);
      final connection = _Connection()..trackResponse = [track];
      final harness = _Harness(authenticated: true, connection: connection);
      harness.shuffle.pending = Future.value(
        const CustomShuffleSettings(artistIds: ['guest']),
      );
      addTearDown(harness.controller.close);
      await harness.controller.initialize();
      await harness.controller.restoreSession();
      harness.controller.updateShuffleMode(
        ShuffleMode.custom,
        scope: ActionScope.server,
      );

      await harness.controller.queuePlaylist(
        'playlist',
        startTrackId: track.id,
      );

      expect(harness.controller.playbackState.shuffleMode, ShuffleMode.custom);
    },
  );
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
    ArtistCredit(
      artistId: 'album-composer',
      name: 'Album Composer',
      role: 'composer',
    ),
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
    if (guest)
      const ArtistCredit(
        artistId: 'guest',
        name: 'Guest',
        role: 'featured_artist',
      ),
    const ArtistCredit(
      artistId: 'composer',
      name: 'Composer',
      role: 'composer',
    ),
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

class _Harness {
  _Harness({
    bool failAudio = false,
    bool authenticated = false,
    _Connection? connection,
  }) : connection = connection ?? _Connection() {
    controller = AppController(
      connection: this.connection,
      audioEngineFactory:
          ({onMessage, onStats, onComplete, onStarted, onState}) {
            audioCreations++;
            if (failAudio) throw StateError('audio unavailable');
            this.onStarted = onStarted;
            this.onStats = onStats;
            this.onState = onState;
            return audio;
          },
      offlineDownloadManager: downloads,
      offlineStorage: _Storage(),
      authStorage: _MemoryAuth(authenticated),
      playbackPreferencesStorage: preferences,
      customShuffleStorage: shuffle,
      connectivitySignalSource: connectivity,
      nowPlayingPlatformService: nowPlaying,
      vehicleSurfaceService: vehicle,
      localNetworkPermissionService: permissions,
      playbackClock: () => playbackTime,
    );
  }
  late final AppController controller;
  final _Connection connection;
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
  void Function(Map<String, dynamic>)? onListeningSegment;
  Map<String, dynamic>? listeningContext;

  @override
  void configureListening(
    Map<String, dynamic>? context, {
    bool updateActive = false,
    bool discardPending = true,
  }) {
    listeningContext = context == null ? null : Map.of(context);
  }

  int disposals = 0;
  double? volume;
  bool active = false;
  bool paused = false;
  int pauses = 0;
  int resumes = 0;
  final seekResults = <Future<bool>>[];
  final starts =
      <
        ({String trackId, Duration offset, bool quickStart, bool initialPaused})
      >[];
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
    active = true;
    paused = initialPaused;
    starts.add((
      trackId: track.id,
      offset: startOffset,
      quickStart: quickStart,
      initialPaused: initialPaused,
    ));
  }

  @override
  Future<bool> seekTo(Duration position) async =>
      seekResults.isEmpty ? active : await seekResults.removeAt(0);

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
  bool failLoad = false;
  final refreshedAlbums = <String>[];
  final refreshedArtists = <String>[];
  @override
  List<OfflineTrackDownload> get downloads => const [];
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
  Stream<OfflineLibrarySnapshot> get librarySnapshotStream =>
      const Stream.empty();
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
  int searches = 0;
  Future<List<Artist>>? pendingArtistsPage;
  List<Artist> artistsPageResponse = const [];
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
  }) async => PlaybackSettingsResponse(repeatMode: 'off');
  @override
  Future<ServerPortsResponse> fetchServerPorts({
    Duration timeout = const Duration(seconds: 8),
    bool retryable = true,
  }) async =>
      ServerPortsResponse(httpPort: 8000, quicPort: 8001, quicEnabled: true);
  @override
  Stream<MetadataUpdateEvent> streamMetadataEvents() =>
      metadataEvents ?? const Stream.empty();
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
  Future<Track> fetchTrackById(String trackId) async =>
      pendingTrackById ?? trackResponse!.first;
  @override
  Future<List<Track>> fetchPlaylistTracks(String playlistId) async =>
      trackResponse!;
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

class _MemoryAuth extends AuthStorage {
  const _MemoryAuth(this.authenticated);
  final bool authenticated;

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
  Future<void> clear() async {}
}

class _Storage extends OfflineLibraryStorage {
  @override
  Future<OfflineStorageLocations> resolveStorageLocations() async =>
      const OfflineStorageLocations(
        metadataDirectory: 'metadata',
        downloadsDirectory: 'downloads',
        metadataDirectoryIsDefault: true,
        downloadsDirectoryIsDefault: true,
      );
}

class _Preferences extends PlaybackPreferencesStorage {
  int reads = 0;
  Future<bool?>? pending;
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
    return pending ??
        Future.value(const CustomShuffleSettings(artistIds: ['artist']));
  }

  @override
  Future<void> write(CustomShuffleSettings settings) async {}
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
  @override
  bool get isSupported => false;
  @override
  void dispose() {
    disposals++;
  }
}

class _Vehicle extends VehicleSurfaceService {
  int disposals = 0;
  @override
  bool get isSupported => false;
  @override
  void dispose() {
    disposals++;
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
