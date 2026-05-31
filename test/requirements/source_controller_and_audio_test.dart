import 'package:flutter_test/flutter_test.dart';

import '../support/source_test_helpers.dart';

void main() {
  group('controller source contracts', () {
    test('controller preserves key enums channels and timing constants', () {
      final source = readProjectFile('lib/entities/app_controller.dart');

      expectContainsAll(source, const [
        'enum ShuffleMode { off, all, artist, album, custom, liked, currentPlaylist }',
        'enum RepeatMode { off, one }',
        'enum StreamMode { auto, high, medium, low }',
        'enum LocalNetworkPermissionState { unknown, granted, denied }',
        'enum PlaybackQueueSource { none, liked, playlist, offline }',
        "final MethodChannel _nowPlayingChannel = const MethodChannel(",
        "'phonolite/now_playing'",
        "'phonolite/carplay'",
        "'phonolite/permissions'",
        'static const Duration storedSessionRestoreTimeout = Duration(seconds: 10);',
        'static const Duration _storedSessionRequestTimeout = Duration(seconds: 4);',
        'static const Duration _seekDebounceDelay = Duration(milliseconds: 180);',
        'static const Duration _seekCompletionGuard = Duration(seconds: 8);',
        'static const Duration _resumeStreamRestartThreshold = Duration(seconds: 45);',
        'static const Duration _offlineRefreshTimeout = Duration(seconds: 5);',
        'const Duration(seconds: 12)',
        'static const Duration _displayPositionHeartbeat = Duration(seconds: 1);',
        "'playback.position.tick'",
      ]);
    });

    test('controller preserves login restore and custom shuffle update hooks', () {
      final source = readProjectFile('lib/entities/app_controller.dart');

      expectContainsAll(source, const [
        'Future<void> loginWithPassword({',
        'bool rememberMe = false,',
        'if (rememberMe) {',
        'Future<bool> probeServer(String input) async {',
        'SessionStatus.checking',
        "'Saved server unavailable'",
        'err.statusCode == 401',
        "error: 'Saved login expired'",
        'Future<void> startFreshLoginFlow() async {',
        'bool get canUseServer => _authState.isAuthorized;',
        'bool _requireServer(String action)',
        'Stream<OfflineStorageLocations> get offlineStorageLocationsStream',
        'Future<void> updateOfflineMetadataDirectory(String? path) async',
        'Future<void> updateOfflineDownloadsDirectory(String? path) async',
        'Future<void> downloadAlbum(Album album, List<Track> tracks) async',
        'Future<void> downloadArtist(Artist artist, List<Album> albums) async',
        'Future<void> _downloadTrackCollection(',
        '_offlineDownloadManager.downloadTrack(track)',
        '_offlineDownloadManager.queueTracks(',
        'Future<void> removeDownloadedTrack(Track track) async',
        'Future<void> removeDownloadedTracks(',
        'Future<void> removeOfflineDownload(OfflineTrackDownload download) async',
        'Future<void> removeOfflineDownloads(',
        '_offlineDownloadManager.removeDownloads(',
        'scope: scope,',
        'await stop();',
        '_pruneRemovedDownloadsFromOfflineQueue',
        'Future<void> pauseOfflineDownload(OfflineTrackDownload download) async',
        'Future<void> resumeOfflineDownload(OfflineTrackDownload download) async',
        'Future<void> pauseOfflineDownloadJob(OfflineDownloadJob job) async',
        'Future<void> resumeOfflineDownloadJob(OfflineDownloadJob job) async',
        'Future<void> clearFailedOfflineDownloads() async',
        'Future<void> resetOfflineData() async',
        'pauseDownloadsForServer(connection.baseUrl)',
        'resumePausedForCurrentServer()',
        'repairOfflineMetadataFragments()',
        'Future<void> playOfflineTrack(',
        'Future<void> playLocalLikedTrack(String trackId) async {',
        'Future<void> queueLocalPlaylist(',
        'Future<void> toggleLocalLike(Track track) async {',
        'Future<void> addTrackToLocalPlaylist(Playlist playlist, Track track) async {',
        'bool _shouldUseLocalUserData(Track track)',
        '_playbackState.queueSource == PlaybackQueueSource.offline',
        'await _startLocalPlayback(',
        'contentType: download.contentType,',
        'Future<void> updateCustomShuffleSettings({',
        '_refreshCustomShuffleQueueIfNeeded()',
        'Future<List<OutputDevice>> listOutputDevices({bool refresh = false}) async {',
        'Future<void> selectOutputDevice(OutputDevice device) async {',
        '_lastStartPlaybackAt = null;',
        '_startPlayback(track, startOffset: _playbackState.position);',
        'Future<void> seekTo(Duration position) async {',
      ]);
    });

    test('controller bounds offline refresh before server refresh', () {
      final source = readProjectFile('lib/entities/app_controller.dart');

      expectContainsAll(source, const [
        'Future<void> refreshLibrary() async',
        'await _offlineDownloadManager.load().timeout(_offlineRefreshTimeout)',
        'await loadOfflineStorageLocations().timeout(_offlineRefreshTimeout)',
        'Offline library refresh timed out; continuing with server refresh.',
        'await loadArtists(refresh: true)',
        'Server library refreshed; offline refresh did not complete.',
      ]);
    });

    test('controller listens for live metadata updates', () {
      final source = readProjectFile('lib/entities/app_controller.dart');

      expectContainsAll(source, const [
        'StreamSubscription<MetadataUpdateEvent>? _metadataEventsSubscription',
        'Stream<Artist> watchArtist(String artistId)',
        'Stream<Album> watchAlbum(String albumId)',
        'connection.streamMetadataEvents().listen(',
        '_queueMetadataEvent(event)',
        "case 'artist':",
        "case 'album':",
        "case 'album_artists':",
        'await _refreshMetadataArtist(event.artistId ?? event.id)',
        'await _refreshMetadataAlbum(event.albumId ?? event.id)',
        '_albumWithListFallbacks(',
        'album.copyWith(trackCount: existing.trackCount)',
        '_albums = _sortAlbumsByReleaseYear(',
        'await connection.fetchAlbums(artistId),',
        '_sortAlbumsByReleaseYear(next)',
        '_artistUpdatesController.add(effective)',
        '_albumUpdatesController.add(updated)',
        'refreshOfflineMetadataForArtist(artistId)',
        'refreshOfflineMetadataForAlbum(albumId)',
        '_stopMetadataEventListener();',
      ]);
    });

    test('controller keeps local queue playback routes wired', () {
      final source = readProjectFile('lib/entities/app_controller.dart');

      expectContainsAll(source, const [
        'Future<void> playOfflineTrack(',
        'Future<void> playLocalLikedTrack(String trackId) async {',
        'Future<void> queueLocalPlaylist(',
        'queueSource: PlaybackQueueSource.offline',
        'enum _OfflineQueueSource { none, tracks, localLiked, localPlaylist }',
        'localLikedQueue: true',
        'void _pruneTrackFromLocalLikedQueue(String localTrackId)',
        '_offlineQueueSource != _OfflineQueueSource.localLiked',
        'await _playCurrent();',
        'Future<void> nextTrack({bool fromAutoAdvance = false}) async {',
        'Future<void> prevTrack({bool fromAutoAdvance = false}) async {',
        'if (_playbackState.repeatMode == RepeatMode.one) {',
        'await _audioEngine.playLocalFile(',
        'startOffset: startOffset,',
        'contentType: download.contentType,',
      ]);
    });

    test('controller hydrates synced server likes with known metadata', () {
      final source = readProjectFile('lib/entities/app_controller.dart');

      expectContainsAll(source, const [
        'void _updateLike(String trackId, bool liked, {Track? knownTrack})',
        'Track _serverTrackFromMatchedDownload(',
        'knownTrack: decision.knownTrack?.copyWith(liked: serverState.liked)',
        'Track? _knownLikedTrack(String trackId, {Track? knownTrack})',
      ]);
      expect(source, isNot(contains("title: 'Unknown track'")));
    });
  });

  group('audio engine source contracts', () {
    test(
      'audio engine preserves platform players transport tags and defaults',
      () {
        final source = readProjectFile('lib/entities/audio_engine.dart');

        expectContainsAll(source, const [
          "const MethodChannel _androidAudioOutputChannel = MethodChannel(",
          "'phonolite/audio_output'",
          'class _AndroidChannelPlayer implements _NativeAudioPlayer {',
          'class _WaveOutPlayer implements _NativeAudioPlayer {',
          'class _CoreAudioPlayer implements _NativeAudioPlayer {',
          'const int kDefaultOutputDeviceId = -1;',
          "OutputDevice(id: kDefaultOutputDeviceId, name: 'System Default')",
          'static const double _seekStartSeconds = 0.05;',
          'static const double _seekCatchupMinSeconds = 0.2;',
          'static const double _seekCatchupTargetSeconds = 0.4;',
          'static const int _pumpChunkMs = 200;',
          'static const int _playbackReportIntervalMs = 1000;',
          'static const int _quicStatsLogIntervalMs = 2000;',
          'const List<int> _rawHeaderMagic = [79, 80, 85, 83, 82, 48, 49, 0];',
          'const List<int> _rawSeekMarkerBytes = [255, 255];',
          "import 'package:phonolite_local_audio/phonolite_local_audio.dart';",
          'Future<void> playLocalFile({',
          'String? contentType,',
          "'cmd': 'play_local'",
          'case \'play_local\':',
          '_PlaybackSession.local(',
          'LocalAudioDecoder? _localDecoder;',
          'LocalAudioDecoder.open(filePath, startOffset: startOffset)',
          'Future<void> _runLocalFilePlayback(String filePath) async',
          'Future<void> _applyLocalSeek(',
          'void _createLocalPcmOutput()',
          "'local': _isLocalFile",
          '_createPlayer(',
        ]);
        expect(source, isNot(contains('package:just_audio/just_audio.dart')));
        expect(source, isNot(contains('ja.AudioPlayer')));
        expect(source, isNot(contains('StreamAudioSource')));
      },
    );
  });
}
