import 'package:flutter_test/flutter_test.dart';

import '../support/source_test_helpers.dart';

void main() {
  test('app exposes v2 download job client contract', () {
    final models = readProjectFile('lib/entities/models.dart');
    final connection = readProjectFile('lib/entities/server_connection.dart');
    final manager = readProjectFile(
      'lib/entities/offline_download_manager.dart',
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
      "'/download/v2/jobs'",
      r"'/download/v2/jobs/$encoded/actions'",
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

  test('offline schema has v10 migration tables', () {
    final source = readProjectFile('lib/entities/offline_library.dart');

    expectContainsAll(source, [
      'static const int _schemaVersion = 10',
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
    final source = readProjectFile('lib/pages/artist_detail_screen.dart');

    expectContainsAll(source, [
      'StreamBuilder<OfflineDownloadSnapshot>',
      'controller.offlineDownloadSnapshotStream',
      'for (final job in controller.offlineDownloadJobs)',
      "job.kind == 'artist'",
      'OfflineDownloadStatus.paused',
    ]);
  });

  test('download manager observes a single combined download snapshot', () {
    final source = readProjectFile(
      'lib/widgets/modals/download_manager_panel.dart',
    );

    expectContainsAll(source, [
      'StreamBuilder<OfflineDownloadSnapshot>',
      'controller!.offlineDownloadSnapshotStream',
      '_DownloadManagerViewState(state.downloads, state.jobs)',
      'ListView.builder',
    ]);
    expect(source, isNot(contains('controller!.offlineDownloadsStream')));
    expect(source, isNot(contains('controller!.offlineDownloadJobsStream')));
  });

  test('offline actor splits download and library state updates', () {
    final source = readProjectFile(
      'lib/entities/offline_download_manager.dart',
    );

    expectContainsAll(source, [
      'class _OfflineActorDownloadState',
      'class _OfflineActorLibraryState',
      'scheduleDownloadState();',
      'scheduleLibraryState();',
      'core.localLikedStream.listen((_) => scheduleLibraryState())',
      '_applyDownloadState',
      '_applyLibraryState',
      '_actorSameTrackSnapshots',
    ]);
    expect(source, isNot(contains('class _OfflineActorSnapshot')));
  });

  test('v2 download jobs only materialize the rolling window initially', () {
    final source = readProjectFile(
      'lib/entities/offline_download_manager.dart',
    );

    expectContainsAll(source, [
      'static const int _rollingWindowSize = 20',
      'for (final item in serverJob.items)',
      'if (downloads.length >= _rollingWindowSize)',
      'await _persistMaterializedDownloads(jobId, downloads)',
      'await _topUpRollingJob(job)',
    ]);
  });
}
