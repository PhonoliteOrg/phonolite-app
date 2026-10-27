import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/infrastructure/audio/engine/audio_engine.dart';
import 'package:phonolite_app/data/models/auth/auth_credentials.dart';
import 'package:phonolite_app/data/storage/auth/auth_storage.dart';
import 'package:phonolite_app/infrastructure/platform/connectivity/connectivity_signal_source.dart';
import 'package:phonolite_app/data/models/playback/custom_shuffle_settings.dart';
import 'package:phonolite_app/data/storage/preferences/custom_shuffle_settings_storage.dart';
import 'package:phonolite_app/data/rules/listening_stats/listening_recorder.dart';
import 'package:phonolite_app/data/models/listening_stats/listening_event.dart';
import 'package:phonolite_app/data/repositories/listening_stats_service.dart';
import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/data/models/library/metadata_update_event.dart';
import 'package:phonolite_app/data/models/listening_stats/listening_report.dart';
import 'package:phonolite_app/application/downloads/offline_download_manager.dart';
import 'package:phonolite_app/data/storage/offline/library/offline_library.dart';
import 'package:phonolite_app/data/models/preferences/offline_storage_locations.dart';
import 'package:phonolite_app/data/storage/preferences/playback_preferences.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';
import 'package:phonolite_app/infrastructure/platform/permissions/local_network_permission_service.dart';
import 'package:phonolite_app/infrastructure/platform/media/now_playing_platform_service.dart';
import 'package:phonolite_app/infrastructure/platform/media/vehicle_surface_service.dart';

import '../support/streaming_test_helpers.dart' show waitUntil;
import '../support/auth_test_helpers.dart';
import 'listening_counter_fixtures.dart';

Future<List<dynamic>> pendingGenres(ListeningStatsService history) async =>
    ((await pendingCounterBatch(history))['metadata'] as Map).values.map((value) => value['genres']).toList();

final _time = DateTime.utc(2026, 10, 8);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('offline reset refreshes statistics and rejects delayed old segments', () async {
    final harness = _Harness();
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    final old = harness.interval('before-reset');
    harness.audio.onListeningSegment!(old);
    await harness.controller.loadStats(year: 2026);
    await expectLater(harness.controller.resetAccountListeningHistory(), throwsStateError);
    await harness.controller.resetListeningStatistics();
    expect(harness.controller.stats!.totalListeningMs, 0);
    expect(harness.controller.statsCollectionEnabled, isTrue);
    harness.audio.onListeningSegment!({...old, 'event_id': 'late'});
    await harness.controller.loadStats(year: 2026);
    expect(harness.controller.stats!.totalListeningMs, 0);
    harness.audio.onListeningSegment!(harness.interval('fresh'));
    await harness.controller.loadStats(year: 2026);
    expect(harness.controller.stats!.totalListeningMs, 60000);
  });

  test('account reset suspends recording and starts a fresh active session', () async {
    final harness = _Harness();
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    harness.controller.loginWithToken(baseUrl: harness.connection.baseUrl, token: 'test-token');
    await waitUntil(() => harness.history.accountScope != 'local');
    harness.connection.tracks = [
      _metadataTrack('track', ['Ambient']),
    ];
    await harness.controller.queueAlbum('album');
    final old = harness.audio.contextChanges.last!;
    final contextsBeforeLocalReset = harness.audio.contextChanges.length;
    await harness.controller.resetLocalListeningHistory();
    expect(harness.audio.contextChanges.length, contextsBeforeLocalReset);
    expect(harness.audio.contextChanges.last, same(old));
    void checkpoint(Map<String, dynamic> context, String id) {
      harness.audio.onListeningSegment!({
        ...context,
        'event_id': id,
        'ended_at_ms': _time.millisecondsSinceEpoch + 60000,
        'listened_ms': 60000,
      });
    }

    checkpoint(old, 'before-reset');
    await harness.controller.loadStats(year: 2026);
    final gate = Completer<void>();
    final started = Completer<void>();
    harness.connection.resetGate = gate;
    harness.connection.resetStarted = started;
    final resetting = harness.controller.resetListeningStatistics();
    await started.future;
    expect(harness.audio.contextChanges.last, isNull);
    final received = harness.history.received.length;
    checkpoint(old, 'during-reset');
    expect(harness.history.received, hasLength(received));
    gate.complete();
    await resetting;
    expect(harness.controller.stats!.totalListeningMs, 0);
    expect(harness.controller.statsCollectionEnabled, isTrue);
    final fresh = harness.audio.contextChanges.last!;
    expect(fresh['history_generation'], 2);
    expect(fresh['session_id'], isNot(old['session_id']));
    checkpoint(old, 'late');
    await harness.controller.loadStats(year: 2026);
    expect(harness.controller.stats!.totalListeningMs, 0);
    checkpoint(fresh, 'fresh');
    await harness.controller.loadStats(year: 2026);
    expect(harness.controller.stats!.totalListeningMs, 60000);
  });

  test('default-on rendered segments populate offline controller statistics', () async {
    final harness = _Harness();
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    expect(harness.controller.statsCollectionEnabled, isTrue);
    expect(harness.controller.authState.hasSession, isFalse);
    expect(harness.audio.onListeningSegment, isNotNull);

    harness.audio.onListeningSegment!(harness.interval('first'));
    await harness.controller.loadStats(year: 2026);
    final stats = harness.controller.stats!;
    expect(stats.totalListeningMs, 60000);
    expect(stats.totalMinutes, 1);
    expect(stats.totalPlays, 1);
    expect(stats.uniqueTracks, 1);
    expect(stats.uniqueArtists, 1);
    expect(stats.topTracks.single.title, 'Offline song');
    expect(stats.topArtists.single.name, 'The artist');
    expect(stats.topGenres.single.name, 'Ambient');
    expect(harness.controller.pendingStatsCount, 0);
    expect(harness.connection.statsRequests, 0);
  });

  test('active playback publishes shared genre times after each checkpoint without refresh', () async {
    final harness = _Harness();
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    final updates = <StatsResponse>[];
    final subscription = harness.controller.statsStream.listen((stats) {
      if (stats != null) updates.add(stats);
    });
    addTearDown(subscription.cancel);
    var now = _time;
    final recorder = ListeningRecorder(
      emit: harness.audio.onListeningSegment!,
      playbackId: 1,
      clock: () => now,
      context: {
        ...harness.interval('active-song'),
        'genres': ['Acid Jazz', 'Electronic', 'Funk'],
      },
    );

    now = now.add(const Duration(seconds: 15));
    recorder.addSamples(48000 * 15, sampleRate: 48000, channels: 1);
    await waitUntil(() => updates.any((stats) => stats.totalListeningMs == 15000));
    final first = updates.lastWhere((stats) => stats.totalListeningMs == 15000);
    expect(first.topGenres.map((genre) => genre.name), ['Acid Jazz', 'Electronic', 'Funk']);
    expect(first.topGenres.map((genre) => genre.listeningMs), [5000, 5000, 5000]);

    now = now.add(const Duration(seconds: 15));
    recorder.addSamples(48000 * 15, sampleRate: 48000, channels: 1);
    await waitUntil(() => updates.any((stats) => stats.totalListeningMs == 30000));
    final second = updates.lastWhere((stats) => stats.totalListeningMs == 30000);
    expect(second.topGenres.map((genre) => genre.listeningMs), [10000, 10000, 10000]);
    expect(harness.history.received, hasLength(2));
    expect(recorder.enabled, isTrue);
    expect(harness.connection.statsRequests, 0);
  });

  test('playback captures cached album genres for older server track payloads', () async {
    final harness = _Harness();
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    harness.controller.loginWithToken(baseUrl: harness.connection.baseUrl, token: 'test-token');
    await waitUntil(() => harness.history.accountScope != 'local');
    harness.connection.albums = [
      Album(
        id: 'album',
        title: 'Release',
        artist: 'Performer',
        artistId: 'artist',
        trackCount: 1,
        genres: ['Electronic', 'Downtempo'],
      ),
    ];
    harness.connection.tracks = [
      Track(
        id: 'song',
        title: 'Song',
        artist: 'Performer',
        artistId: 'artist',
        album: 'Release',
        albumId: 'album',
        genres: ['Rock', 'Pop'],
        durationMs: 180000,
        liked: false,
        inPlaylists: false,
      ),
    ];
    await harness.controller.loadAlbums('artist');
    await harness.controller.queueAlbum('album');
    final context = harness.audio.contextChanges.last!;
    expect(context['genres'], ['Electronic', 'Downtempo']);
    harness.audio.onListeningSegment!({
      ...context,
      'event_id': 'captured-genres',
      'ended_at_ms': _time.millisecondsSinceEpoch + 60000,
      'listened_ms': 60000,
    });
    await harness.controller.loadStats(year: 2026);
    expect(harness.controller.stats!.topGenres.map((genre) => genre.name), containsAll(['Electronic', 'Downtempo']));
    expect(harness.connection.statsRequests, 0);
  });

  test('refresh repairs historical genre labels without rewriting uploads', () async {
    final harness = _Harness();
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    harness.controller.loginWithToken(baseUrl: harness.connection.baseUrl, token: 'test-token');
    await waitUntil(() => harness.history.accountScope != 'local');
    harness.connection.metadataTracks = [
      _metadataTrack('track', ['Acid Jazz', 'Funk']),
    ];
    harness.audio.onListeningSegment!({
      ...harness.interval('historical-genres'),
      'genres': ['Rock', 'Pop'],
    });
    await harness.controller.loadStats(year: 2026);
    await waitUntil(() => harness.controller.stats!.topGenres.any((genre) => genre.name == 'Acid Jazz'));
    final stats = harness.controller.stats!;
    expect(stats.totalListeningMs, 60000);
    expect(stats.topGenres.map((genre) => genre.listeningMs), [30000, 30000]);
    expect((await pendingGenres(harness.history)).single, ['Rock', 'Pop']);
    await harness.controller.loadStats(year: 2026);
    expect(harness.connection.metadataReads, 1);
    expect(harness.connection.uploads, 0);
  });

  test('removed tracks repair only from their exact saved album identity', () async {
    final harness = _Harness();
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    harness.controller.loginWithToken(baseUrl: harness.connection.baseUrl, token: 'test-token');
    await waitUntil(() => harness.history.accountScope != 'local');
    harness.connection.albums = [
      Album(
        id: 'unrelated-album',
        title: 'The album',
        artist: 'The artist',
        artistId: 'artist',
        trackCount: 1,
        genres: ['Classical'],
      ),
      Album(
        id: 'recorded-album',
        title: 'The album',
        artist: 'The artist',
        artistId: 'artist',
        trackCount: 1,
        genres: ['Melodic Death Metal'],
      ),
    ];
    for (final saved in [
      (track: 'a-removed-with-album', album: 'recorded-album'),
      (track: 'b-removed-without-album', album: 'missing-album'),
    ]) {
      harness.audio.onListeningSegment!({
        ...harness.interval(saved.track),
        'track_id': saved.track,
        'album_id': saved.album,
        'genres': ['Rock', 'Pop'],
      });
    }
    await harness.controller.loadStats(year: 2026);
    await waitUntil(() => harness.controller.stats!.topGenres.any((genre) => genre.name == 'Melodic Death Metal'));
    final stats = harness.controller.stats!;
    expect(stats.totalListeningMs, 120000);
    expect(
      {for (final genre in stats.topGenres) genre.name: genre.listeningMs},
      {'Melodic Death Metal': 60000, 'Pop': 30000, 'Rock': 30000},
    );
    expect(harness.connection.metadataAlbumReads, ['recorded-album', 'missing-album']);
    expect(await harness.history.genreMetadataCandidates(), ['b-removed-without-album']);
    expect(await pendingGenres(harness.history), everyElement(['Rock', 'Pop']));
    expect(harness.connection.statsRequests, 0);
    expect(harness.connection.uploads, 0);
  });

  test('delayed genre metadata reply cannot cross an account switch', () async {
    final harness = _Harness();
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    harness.connection.userId = 'original-user';
    harness.controller.loginWithToken(baseUrl: harness.connection.baseUrl, token: 'original-token');
    await waitUntil(() => harness.history.accountScope.contains('original-user'));
    final delayed = Completer<Track>();
    harness.connection.pendingMetadataTracks['track'] = delayed.future;
    addTearDown(() {
      if (!delayed.isCompleted) {
        delayed.complete(_metadataTrack('track', ['Acid Jazz']));
      }
    });
    harness.audio.onListeningSegment!({
      ...harness.interval('original-genre-history'),
      'genres': ['Rock', 'Pop'],
    });
    await harness.controller.loadStats(year: 2026);
    await waitUntil(() => harness.connection.metadataReads == 1);

    harness.connection.userId = 'different-user';
    harness.connection.metadataTracks = [
      _metadataTrack('track', ['Funk']),
    ];
    harness.controller.loginWithToken(baseUrl: harness.connection.baseUrl, token: 'different-token');
    await waitUntil(() => harness.history.accountScope.contains('different-user'));
    harness.audio.onListeningSegment!({
      ...harness.interval('different-genre-history'),
      'genres': ['Jazz'],
    });
    expect((await harness.history.stats(year: 2026)).topGenres.single.name, 'Jazz');
    delayed.complete(_metadataTrack('track', ['Acid Jazz']));
    await Future<void>.delayed(Duration.zero);
    expect((await harness.history.stats(year: 2026)).topGenres.single.name, 'Jazz');
    expect(await harness.history.genreMetadataCandidates(), ['track']);

    await harness.history.setAccount(serverId: 'server', userId: 'original-user');
    final original = await harness.history.stats(year: 2026);
    expect(original.totalListeningMs, 60000);
    expect(original.topGenres.map((genre) => genre.name), ['Pop', 'Rock']);
    expect((await pendingGenres(harness.history)).single, ['Rock', 'Pop']);
    expect(await harness.history.genreMetadataCandidates(), ['track']);

    await harness.history.setAccount(serverId: 'server', userId: 'different-user');
    await harness.controller.loadStats(year: 2026);
    await waitUntil(() => harness.controller.stats!.topGenres.single.name == 'Funk');
    expect(harness.controller.stats!.totalListeningMs, 60000);
    expect((await pendingGenres(harness.history)).single, ['Jazz']);
    expect(harness.connection.metadataReads, 2);
    expect(harness.connection.statsRequests, 0);
    expect(harness.connection.uploads, 0);
  });

  test('missing and failed genre metadata do not prevent other history repair', () async {
    final harness = _Harness();
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    harness.controller.loginWithToken(baseUrl: harness.connection.baseUrl, token: 'test-token');
    await waitUntil(() => harness.history.accountScope != 'local');
    harness.connection.failedMetadataIds.add('b-failed');
    harness.connection.metadataTracks = [
      _metadataTrack('c-known', ['Funk']),
    ];
    for (final id in ['a-missing', 'b-failed', 'c-known']) {
      harness.audio.onListeningSegment!({
        ...harness.interval(id),
        'track_id': id,
        'genres': ['Rock', 'Pop'],
      });
    }
    await harness.controller.loadStats(year: 2026);
    await waitUntil(() => harness.controller.stats!.topGenres.any((genre) => genre.name == 'Funk'));
    final stats = harness.controller.stats!;
    expect(stats.totalListeningMs, 180000);
    expect(stats.topGenres.map((genre) => genre.listeningMs), [60000, 60000, 60000]);
    expect(await harness.history.genreMetadataCandidates(), ['a-missing', 'b-failed']);
    expect(await pendingGenres(harness.history), everyElement(['Rock', 'Pop']));
  });

  test('genre repair advances beyond fifty missing historical recordings', () async {
    final harness = _Harness();
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    harness.controller.loginWithToken(baseUrl: harness.connection.baseUrl, token: 'test-token');
    await waitUntil(() => harness.history.accountScope != 'local');
    harness.connection.metadataTracks = [
      _metadataTrack('z-known', ['Funk']),
    ];
    for (var index = 0; index < 50; index++) {
      harness.audio.onListeningSegment!({
        ...harness.interval('missing-$index'),
        'track_id': 'missing-${index.toString().padLeft(2, '0')}',
      });
    }
    harness.audio.onListeningSegment!({...harness.interval('z-known'), 'track_id': 'z-known'});
    await harness.controller.loadStats(year: 2026);
    await waitUntil(() => harness.connection.metadataReads == 50);
    // Wait for the first bounded repair to release its single-flight guard.
    await Future<void>.delayed(Duration.zero);
    await harness.controller.loadStats(year: 2026);
    await waitUntil(() => harness.controller.stats!.topGenres.any((genre) => genre.name == 'Funk'));
    expect(harness.connection.metadataReads, 51);
    expect(harness.controller.stats!.totalListeningMs, 51 * 60000);
  });

  test('opt-out rejects late segments and keeps existing listening history', () async {
    final harness = _Harness();
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    final callback = harness.audio.onListeningSegment!;
    final originalRevision = harness.interval('delayed-before-opt-out');
    callback(harness.interval('before-off'));
    await harness.controller.loadStats(year: 2026);
    expect(harness.controller.stats!.totalListeningMs, 60000);

    final enabledChange = harness.controller.statsCollectionEnabledStream.firstWhere((value) => !value);
    await harness.controller.setStatsCollectionEnabled(false);
    expect(await enabledChange, isFalse);
    expect(harness.audio.contextChanges, [null]);
    callback(harness.interval('late-output'));
    await harness.controller.loadStats(year: 2026);
    expect(harness.history.received, hasLength(1));
    expect(harness.controller.stats!.totalListeningMs, 60000);
    expect(harness.controller.stats!.totalPlays, 1);
    expect(await harness.history.pendingEvents(), isEmpty);

    await harness.controller.setStatsCollectionEnabled(true);
    callback(originalRevision);
    callback(harness.interval('after-on'));
    await harness.controller.loadStats(year: 2026);
    expect(harness.controller.stats!.totalListeningMs, 120000);
    expect(harness.controller.stats!.totalPlays, 2);
    expect(harness.history.received, hasLength(2));
    expect(harness.connection.statsRequests, 0);
  });

  test('token account switch clears visible history before new identity discovery', () async {
    final harness = _Harness();
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    await harness.history.setAccount(serverId: 'server', userId: 'original-user');
    harness.audio.onListeningSegment!(harness.interval('original-account-play'));
    await harness.controller.loadStats(year: 2026);
    expect(harness.controller.stats!.totalListeningMs, 60000);

    final discovery = Completer<Map<String, dynamic>>();
    harness.connection.pendingListeningIdentity = discovery.future;
    addTearDown(() {
      if (!discovery.isCompleted) {
        discovery.complete(harness.connection.identity());
      }
    });
    harness.controller.loginWithToken(baseUrl: harness.connection.baseUrl, token: 'different-user-token');
    await waitUntil(() => harness.history.accountScope == 'local');
    await waitUntil(() => harness.controller.stats!.totalListeningMs == 0);
    expect(harness.audio.contextChanges.last, isNull);
    expect(discovery.isCompleted, isFalse);

    harness.audio.onListeningSegment!(harness.interval('identity-not-known'));
    expect((await harness.history.stats(year: 2026)).totalListeningMs, 60000);
    discovery.complete(harness.connection.identity());
    await waitUntil(() => harness.history.accountScope.contains('different-user'));
    await harness.controller.loadStats(year: 2026);
    expect(harness.controller.stats!.totalListeningMs, 0);
    expect(harness.controller.canImportLocalStats, isTrue);
    expect(harness.connection.uploads, 0);

    await harness.history.setAccount(serverId: 'server', userId: 'original-user');
    expect((await harness.history.stats(year: 2026)).totalListeningMs, 60000);
  });

  test('expired saved login detaches statistics and preserves its previous account history', () async {
    final harness = _Harness(
      credentials: const AuthCredentials(
        baseUrl: 'https://unused.test',
        token: 'expired-token',
        username: 'original-user',
        serverId: 'server',
        userId: 'original-user',
        trust: testServerTrust,
      ),
    );
    addTearDown(harness.controller.close);
    await harness.controller.initialize();
    await harness.history.setAccount(serverId: 'server', userId: 'original-user');
    harness.audio.onListeningSegment!(harness.interval('saved-account-listening'));
    await harness.controller.loadStats(year: 2026);
    expect(harness.controller.stats!.totalListeningMs, 60000);
    harness.connection.rejectSavedPlaybackSettings = true;

    await harness.controller.restoreSession();
    expect(harness.connection.token, isNull);
    expect(harness.controller.authState.hasSession, isFalse);
    expect(harness.controller.authState.error, 'Saved login expired. Sign in again.');
    expect(harness.auth.clears, 1);
    expect(harness.auth.saved, isNull);
    expect(await harness.controller.loadSavedCredentials(), isNull);
    expect(harness.history.accountScope, 'local');
    expect(harness.audio.contextChanges.last, isNull);
    expect(harness.controller.stats!.totalListeningMs, 0);

    harness.audio.onListeningSegment!(harness.interval('subsequent-local-listening'));
    await harness.controller.loadStats(year: 2026);
    expect(harness.controller.stats!.totalListeningMs, 60000);
    expect(harness.connection.uploads, 0);
    await harness.history.setAccount(serverId: 'server', userId: 'original-user');
    expect((await harness.history.stats(year: 2026)).totalListeningMs, 60000);
    expect(harness.history.pendingCount, 1);
  });

  test('shutdown persists the final output interval and rejects later callbacks', () async {
    final harness = _Harness();
    await harness.controller.initialize();
    final callback = harness.audio.onListeningSegment!;
    callback(harness.interval('checkpoint'));
    await harness.controller.loadStats(year: 2026);
    harness.audio.onDispose = () => callback(harness.interval('final-flush'));

    await harness.controller.close();
    expect(harness.history.finalStats!.totalListeningMs, 120000);
    expect(harness.history.finalStats!.totalPlays, 2);
    expect(harness.audio.onListeningSegment, isNull);
    callback(harness.interval('after-close'));
    expect(harness.history.received, hasLength(2));
    await harness.controller.close();
  });
}

Track _metadataTrack(String id, List<String> genres) => Track(
  id: id,
  title: 'Song',
  artist: 'Performer',
  artistId: 'artist',
  album: 'Release',
  genres: genres,
  listeningGenres: genres,
  durationMs: 180000,
  liked: false,
  inPlaylists: false,
);

class _Harness {
  _Harness({AuthCredentials? credentials}) : auth = _Auth()..saved = credentials {
    controller = AppController(
      connection: connection,
      listeningStatsService: history,
      audioEngineFactory: ({onMessage, onStats, onComplete, onStarted, onState}) => audio,
      offlineDownloadManager: _Downloads(),
      offlineStorage: _Storage(),
      authStorage: auth,
      customShuffleStorage: _Shuffle(),
      playbackPreferencesStorage: _Preferences(),
      connectivitySignalSource: _Connectivity(),
      nowPlayingPlatformService: _NowPlaying(),
      vehicleSurfaceService: _Vehicle(),
      localNetworkPermissionService: _Permissions(),
      playbackClock: () => _time,
    );
  }

  late final AppController controller;
  final connection = _Connection();
  final history = _History();
  final audio = _Audio();
  final _Auth auth;

  Map<String, dynamic> interval(String id) => {
    ...ListeningEvent(
      eventId: id,
      sessionId: 'session-$id',
      deviceId: history.deviceId,
      trackId: 'track',
      title: 'Offline song',
      artistId: 'artist',
      artistName: 'The artist',
      albumTitle: 'The album',
      genres: const ['Ambient'],
      trackDurationMs: 180000,
      sessionStartedAtMs: _time.millisecondsSinceEpoch,
      startedAtMs: _time.millisecondsSinceEpoch,
      endedAtMs: _time.millisecondsSinceEpoch + 60000,
      listenedMs: 60000,
    ).toJson(),
    'account_scope': history.accountScope,
    'history_generation': history.historyGeneration,
    'collection_revision': history.preferenceRevision,
  };
}

class _History extends ListeningStatsService {
  _History() : super(inMemory: true, clock: () => _time);
  final received = <ListeningEvent>[];
  StatsResponse? finalStats;

  @override
  Future<void> recordSegment(ListeningEvent event, {String? scope, int? generation}) {
    received.add(event);
    return super.recordSegment(event, scope: scope, generation: generation);
  }

  @override
  Future<void> close() async {
    finalStats = await stats(year: 2026);
    await super.close();
  }
}

class _Audio extends Fake implements AudioEngine {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> stop({bool waitForRelease = false}) async {}

  @override
  bool get hasActivePlayer => false;
  @override
  bool get isPaused => false;
  @override
  void Function(Map<String, dynamic>)? onListeningSegment;
  final contextChanges = <Map<String, dynamic>?>[];
  void Function()? onDispose;

  @override
  void configureListening(Map<String, dynamic>? context, {bool updateActive = false, bool discardPending = true}) {
    contextChanges.add(context);
  }

  @override
  void setVolume(double value) {}
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
  }) async {}
  @override
  Future<void> dispose() async => onDispose?.call();
}

class _Connection extends ServerConnection {
  _Connection() : super(baseUrl: 'https://unused.test') {
    setTrust(testServerTrust);
  }
  int statsRequests = 0;
  int uploads = 0;
  int historyGeneration = 1;
  Completer<void>? resetGate;
  Completer<void>? resetStarted;
  bool rejectSavedPlaybackSettings = false;
  Future<Map<String, dynamic>>? pendingListeningIdentity;
  List<Album> albums = const [];
  List<Track> tracks = const [];
  List<Track> metadataTracks = const [];
  String userId = 'different-user';
  final pendingMetadataTracks = <String, Future<Track>>{};
  final metadataAlbumReads = <String>[];
  final failedMetadataIds = <String>{};
  int metadataReads = 0;

  @override
  Future<Track> fetchTrackById(String trackId) async {
    metadataReads++;
    final delayed = pendingMetadataTracks.remove(trackId);
    if (delayed != null) return delayed;
    if (failedMetadataIds.contains(trackId)) {
      throw ApiException(503, 'Temporarily unavailable');
    }
    for (final track in metadataTracks) {
      if (track.id == trackId) return track;
    }
    throw ApiException(404, 'Recording no longer in catalog');
  }

  @override
  Future<Album> fetchAlbumById(String albumId) async {
    metadataAlbumReads.add(albumId);
    for (final album in albums) {
      if (album.id == albumId) return album;
    }
    throw ApiException(404, 'Release no longer in catalog');
  }

  @override
  Future<List<Album>> fetchAlbums(String artistId) async => albums;
  @override
  Future<List<Track>> fetchTracks(String albumId) async => tracks;

  Map<String, dynamic> identity() => {
    'server_id': 'server',
    'user_id': userId,
    'history_generation': historyGeneration,
    'collection_enabled': false,
    'device_enabled': true,
    'preference_revision': 0,
    'events': [],
    'next_cursor': 0,
    'has_more': false,
    'checkpoint': {'last_sequence': 0, 'upgraded': true},
    'months': [],
  };

  @override
  Future<Map<String, dynamic>> fetchListeningCounterState({required String deviceId}) {
    final pending = pendingListeningIdentity;
    pendingListeningIdentity = null;
    return pending ?? Future.value(identity());
  }

  @override
  Future<Map<String, dynamic>> activateListeningCounters({
    required String deviceId,
    required int historyGeneration,
  }) async => {'last_sequence': 0, 'upgraded': true};

  @override
  Future<Map<String, dynamic>> resetListeningHistory({required int historyGeneration}) async {
    if (historyGeneration == this.historyGeneration) this.historyGeneration++;
    resetStarted?.complete();
    resetStarted = null;
    final gate = resetGate;
    resetGate = null;
    if (gate != null) await gate.future;
    return identity();
  }

  @override
  Future<Map<String, dynamic>> uploadListeningEvents({
    required String deviceId,
    required int historyGeneration,
    required List<Map<String, dynamic>> events,
  }) async {
    uploads++;
    return {'accepted': events.map((event) => event['event_id']).toList(), 'rejected': []};
  }

  @override
  Stream<MetadataUpdateEvent> streamMetadataEvents() => const Stream.empty();
  @override
  Future<ServerPortsResponse> fetchServerPorts({
    Duration timeout = const Duration(seconds: 8),
    bool retryable = true,
  }) async => ServerPortsResponse(httpPort: 8000, quicPort: null, quicEnabled: false);
  @override
  Future<PlaybackSettingsResponse> fetchPlaybackSettings({
    Duration timeout = const Duration(seconds: 8),
    bool retryable = true,
  }) async {
    if (rejectSavedPlaybackSettings) throw ApiException(401, 'Expired login');
    return PlaybackSettingsResponse(repeatMode: 'off');
  }

  @override
  Future<int?> pingHealthMs({Duration timeout = const Duration(seconds: 3)}) async => null;
  @override
  Future<StatsResponse> fetchStats({int? year, int? month}) {
    statsRequests++;
    throw StateError('Offline statistics must not request server aggregates');
  }
}

class _Downloads extends Fake implements OfflineDownloadManager {
  @override
  OfflineLibrarySnapshot get librarySnapshot => const OfflineLibrarySnapshot(
    tracks: [],
    artistGroups: [],
    liked: [],
    playlists: [],
    playlistTracks: [],
    revision: 0,
  );
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
  Stream<OfflineLibrarySnapshot> get librarySnapshotStream => const Stream.empty();
  @override
  Stream<List<Track>> get localLikedStream => const Stream.empty();
  @override
  Stream<List<Playlist>> get localPlaylistsStream => const Stream.empty();
  @override
  Future<void> load() async {}
  @override
  Future<void> dispose() async {}
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

class _Auth extends AuthStorage {
  AuthCredentials? saved;
  int clears = 0;
  final writes = <AuthCredentials>[];
  @override
  Future<AuthCredentials?> read() async => saved;
  @override
  Future<void> write(AuthCredentials credentials) async {
    writes.add(credentials);
    saved = credentials;
  }

  @override
  Future<void> clear() async {
    clears++;
    saved = null;
  }
}

class _Shuffle extends CustomShuffleSettingsStorage {
  @override
  Future<CustomShuffleSettings> read() async => const CustomShuffleSettings();

  @override
  Future<CustomShuffleSettings> readForAccount(String scope) async => const CustomShuffleSettings();

  @override
  Future<void> writeLocal(CustomShuffleSettings settings) async {}

  @override
  Future<void> writeForAccount(String scope, CustomShuffleSettings settings) async {}
}

class _Preferences extends PlaybackPreferencesStorage {
  @override
  Future<PlaybackRepeatMode?> readRepeatMode() async => null;

  @override
  Future<void> writeRepeatMode(PlaybackRepeatMode mode) async {}

  @override
  Future<double?> readVolume() async => null;
  @override
  Future<bool?> readCollectionListMode() async => null;
}

class _Connectivity extends ConnectivitySignalSource {
  @override
  Stream<bool> get availabilityStream => const Stream.empty();
  @override
  Future<bool> hasConnectivity() async => false;
}

class _NowPlaying extends NowPlayingPlatformService {
  @override
  bool get isSupported => false;
}

class _Vehicle extends VehicleSurfaceService {
  @override
  bool get isSupported => false;
}

class _Permissions extends LocalNetworkPermissionService {
  @override
  bool get isSupported => false;
}
