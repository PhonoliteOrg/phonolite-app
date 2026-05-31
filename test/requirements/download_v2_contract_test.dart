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

  test('offline schema has v8 migration tables', () {
    final source = readProjectFile('lib/entities/offline_library.dart');

    expectContainsAll(source, [
      'static const int _schemaVersion = 8',
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
}
