import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/data/models/playback/playback_state.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/downloads/download_status.dart';
import 'package:phonolite_app/data/models/downloads/offline_track_download.dart';

void main() {
  final track = Track.fromJson({
    'id': 'track',
    'title': 'Song',
    'artist': 'Artist',
    'album': 'Album',
    'duration_ms': 1234,
  });

  test('playback copy distinguishes omitted and explicitly cleared values', () {
    final state = PlaybackState(
      track: track,
      isPlaying: true,
      isLoading: false,
      position: const Duration(milliseconds: 50),
      duration: const Duration(milliseconds: 1234),
      bufferRatio: 0.5,
      volume: 0.7,
      shuffleMode: ShuffleMode.album,
      shuffleScope: ActionScope.local,
      repeatMode: RepeatMode.one,
      streamMode: StreamMode.high,
      bitrateKbps: 128,
      streamConnected: true,
      streamRttMs: 20,
      queueSource: PlaybackQueueSource.playlist,
      queueSourcePlaylistId: 'playlist',
      localPlaybackSource: LocalPlaybackSource.none,
      isLocalPlayback: false,
    );
    final copy = state.copyWith(isPlaying: false);
    expect(copy.track, same(track));
    expect(copy.queueSourcePlaylistId, 'playlist');
    expect(copy.volume, 0.7);
    expect(copy.shuffleMode, ShuffleMode.album);
    expect(copy.localShuffleMode, ShuffleMode.album);
    expect(copy.serverShuffleMode, ShuffleMode.off);
    final server = copy.copyWith(shuffleScope: ActionScope.server);
    expect(server.shuffleMode, ShuffleMode.off);
    final configured = server.copyWith(shuffleMode: ShuffleMode.liked);
    final local = configured.copyWith(shuffleScope: ActionScope.local);
    expect(local.shuffleMode, ShuffleMode.album);
    expect(local.serverShuffleMode, ShuffleMode.liked);
    expect(
      local.copyWith(shuffleScope: ActionScope.server).shuffleMode,
      ShuffleMode.liked,
    );
    expect(copy.position, state.position);
    expect(state.isPlaying, isTrue);
    final cleared = state.copyWith(track: null, queueSourcePlaylistId: null);
    expect(cleared.track, isNull);
    expect(cleared.queueSourcePlaylistId, isNull);
    expect(copy.bitrateKbps, 128);
    expect(copy.streamRttMs, 20);
    expect(state.copyWith(bitrateKbps: null).bitrateKbps, isNull);
    expect(state.copyWith(streamRttMs: null).streamRttMs, isNull);
  });

  test('offline values retain serialization, copy and progress contracts', () {
    final download = OfflineTrackDownload(
      serverBaseUrl: 'https://server.test/api',
      track: track,
      status: OfflineDownloadStatus.downloaded,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(2),
      filePath: 'song.opus',
      bytesDownloaded: 150,
      bytesTotal: 100,
      etag: 'version',
      error: 'previous failure',
    );
    expect(download.progress, 1);
    expect(download.copyWith(bytesTotal: null).progress, isNull);
    expect(download.copyWith().filePath, 'song.opus');
    expect(download.copyWith(filePath: null, error: null).filePath, isNull);
    expect(download.copyWith(error: null).error, isNull);
    final restored = OfflineTrackDownload.fromJson(download.toJson())!;
    expect(restored.toJson(), download.toJson());
    expect(restored.isDownloaded, isTrue);
    final legacy = OfflineTrackDownload.fromJson({
      ...download.toJson(),
      'status': 'future-status',
      'bytesTotal': 0,
    })!;
    expect(legacy.status, OfflineDownloadStatus.queued);
    expect(legacy.progress, isNull);
    expect(OfflineTrackDownload.fromJson({'serverBaseUrl': ''}), isNull);
  });
}
