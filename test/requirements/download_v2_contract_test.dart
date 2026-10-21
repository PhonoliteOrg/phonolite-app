import 'package:flutter_test/flutter_test.dart';

import '../support/source_test_helpers.dart';

void main() {
  test('app exposes v2 download job client contract', () {
    final models = readProjectFiles([
      'lib/data/models/library/artist_credit.dart',
      'lib/data/models/library/artist_releases.dart',
      'lib/data/models/library/artist.dart',
      'lib/data/models/library/album.dart',
      'lib/data/models/library/track.dart',
      'lib/data/models/collections/playlist.dart',
      'lib/data/models/library/metadata_update_event.dart',
      'lib/data/models/listening_stats/listening_report.dart',
      'lib/data/models/library/search_result.dart',
      'lib/data/models/downloads/offline_track_metadata.dart',
      'lib/data/models/server/download_batch_manifest.dart',
      'lib/data/models/server/server_capabilities.dart',
      'lib/data/models/server/download_job_v2.dart',
      'lib/data/models/library/track_match.dart',
      'lib/data/models/collections/like_state.dart',
      'lib/data/models/playback/output_device.dart',
    ]);
    final connection = readProjectModule(
      'lib/infrastructure/server/server_connection.dart',
    );
    final manager = readProjectModule(
      'lib/application/downloads/offline_download_manager.dart',
    );

    expectContainsAll(models, [
      'class ServerCapabilities',
      'class DownloadJobScopeV2',
      'class DownloadJobV2',
      'class DownloadJobItemV2',
      "status == 'ready_to_download'",
    ]);
    expectContainsAll(connection, [
      "Future<ServerCapabilities> fetchCapabilities()",
      "Future<DownloadJobV2> createDownloadJob",
      "Future<void> applyDownloadJobAction",
      "'/download/jobs'",
      r"'/download/jobs/$encoded/actions'",
      "String buildDownloadUrl(String trackId, {String? downloadUrl})",
    ]);
    expectContainsAll(manager, [
      'Future<int?> _tryQueueV2DownloadJob',
      '_queueAttemptRequestId(clientRequestId)',
      '_clearObsoleteStopMarkersForQueue',
      '_retireServerDownloadJobIfUnused',
      '_downloadBelongsToV2Job',
      'connection.createDownloadJob',
      'connection.applyDownloadJobAction',
      'DownloadJobScopeV2(kind: \'artist\', id: artist.id)',
      'downloadUrl: download.downloadUrl',
    ]);
  });

  test('offline schema retains v10 tables and playlist download plans', () {
    final source = readProjectModule(
      'lib/data/storage/offline/library/offline_library.dart',
    );

    expectContainsAll(source, [
      'static const int _schemaVersion = 11',
      'CREATE TABLE IF NOT EXISTS pending_playlist_tracks',
      'CREATE TABLE IF NOT EXISTS client_identity',
      'CREATE TABLE IF NOT EXISTS metadata_snapshots',
      'CREATE TABLE IF NOT EXISTS file_artifacts',
      'CREATE TABLE IF NOT EXISTS artwork_artifacts',
      'CREATE TABLE IF NOT EXISTS sync_cursors',
      'CREATE TABLE IF NOT EXISTS repair_queue',
      'Future<String> readOrCreateClientId()',
    ]);
  });

  test('artist detail download state observes jobs as well as tracks', () {
    final source = readProjectFiles([
      'lib/pages/library/artist_detail_screen.dart',
      'lib/application/controllers/library/artist_detail_controller.dart',
    ]);

    expectContainsAll(source, [
      'StreamBuilder<OfflineDownloadSnapshot>',
      'controller.offlineDownloadSnapshotStream',
      'for (final job in controller.offlineDownloadJobs)',
      "job.kind == 'artist'",
      'OfflineDownloadStatus.paused',
    ]);
  });

  test('download manager observes a single combined download snapshot', () {
    final source = readProjectFiles([
      'lib/ui/features/downloads/widgets/download_manager_panel.dart',
      'lib/application/controllers/downloads/download_manager_controller.dart',
    ]);

    expectContainsAll(source, [
      'StreamBuilder<OfflineDownloadSnapshot>',
      'controller!.offlineDownloadSnapshotStream',
      'DownloadManagerViewState(state.downloads, state.jobs)',
      'ListView.builder',
    ]);
    expect(source, isNot(contains('controller!.offlineDownloadsStream')));
    expect(source, isNot(contains('controller!.offlineDownloadJobsStream')));
  });

  test('offline actor splits download and library state updates', () {
    final source = readProjectModule(
      'lib/application/downloads/offline_download_manager.dart',
    );

    expectContainsAll(source, [
      'class OfflineActorDownloadState',
      'class OfflineActorLibraryState',
      'scheduleDownloadState();',
      'scheduleLibraryState();',
      'core.localLikedStream.listen((_) => scheduleLibraryState())',
      '_applyDownloadState',
      '_applyLibraryState',
      'sameOfflineTrackSnapshots',
    ]);
    expect(source, isNot(contains('class _OfflineActorSnapshot')));
  });

  test('v2 download jobs only materialize the rolling window initially', () {
    final source = readProjectModule(
      'lib/application/downloads/offline_download_manager.dart',
    );

    expectContainsAll(source, [
      'static const int _rollingWindowSize = 20',
      'for (final item in serverJob.items)',
      "if (downloads.length >= _OfflineDownloadActorCore._rollingWindowSize)",
      "await _host._persistMaterializedDownloads(jobId, downloads)",
      'await _topUpRollingJob(job)',
    ]);
  });
}
