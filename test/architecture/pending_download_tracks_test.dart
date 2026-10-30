import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/data/models/downloads/download_job.dart';
import 'package:phonolite_app/data/models/downloads/download_status.dart';
import 'package:phonolite_app/data/models/downloads/offline_track_download.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/projections/downloads/download_manager_view_state.dart';

const _server = 'https://downloads.test/api';
final _now = DateTime.utc(2026);

void main() {
  test('known queued tracks remain visible beyond the transfer window', () {
    final job = _job('album');
    final items = [for (var position = 0; position < 25; position++) _item(job.jobId, 'song-$position', position)];
    final state = DownloadManagerViewState([], [job], jobItems: items);
    final pending = state.pendingGroups[DownloadSection.queue]!;

    expect(pending.map((value) => value.item.serverTrackId), items.map((value) => value.serverTrackId));
    expect(state.isEmpty, isFalse);
    expect(state.hasPausable, isTrue);
    expect(() => pending.clear(), throwsUnsupportedError);
  });

  test('a transfer replaces its pending row and completion cannot revive a stale queued item', () {
    final job = _job('album');
    final item = _item(job.jobId, 'song', 0);
    final transfer = _download(item.track!);

    final transferring = DownloadManagerViewState([transfer], [job], jobItems: [item]);
    expect(transferring.pendingGroups.values.expand((items) => items), isEmpty);
    expect(transferring.groups[DownloadSection.queue], [transfer]);

    final complete = DownloadManagerViewState(
      [transfer.copyWith(status: OfflineDownloadStatus.downloaded)],
      [job],
      jobItems: [item],
    );
    expect(complete.pendingGroups.values.expand((items) => items), isEmpty);
    expect(complete.groups.values.expand((items) => items), isEmpty);
  });

  for (final status in [OfflineDownloadStatus.failed, OfflineDownloadStatus.corrupt, OfflineDownloadStatus.canceled]) {
    test('a new queued retry replaces an obsolete ${status.name} transfer row', () {
      final job = _job('new-job');
      final item = _item(job.jobId, 'song', 0);
      final obsolete = _download(
        item.track!,
        batchId: 'old-job',
        status: status,
        createdAt: _now.subtract(const Duration(days: 1)),
      );
      final state = DownloadManagerViewState([obsolete], [job], jobItems: [item]);

      expect(state.pendingGroups[DownloadSection.queue]!.single.item, same(item));
      expect(state.groups.values.expand((items) => items), isEmpty);
    });

    test('a stale pending item cannot replace its own ${status.name} transfer row', () {
      final job = _job('same-job');
      final item = _item(job.jobId, 'song', 0);
      final transfer = _download(item.track!, batchId: job.jobId, status: status);
      final state = DownloadManagerViewState([transfer], [job], jobItems: [item]);

      expect(state.pendingGroups.values.expand((items) => items), isEmpty);
      expect(state.groups[DownloadSection.needsAttention], [transfer]);
    });
  }

  test('an existing active, paused, or removing transfer still owns its source row', () {
    final job = _job('new-job');
    final item = _item(job.jobId, 'song', 0);

    for (final status in [
      OfflineDownloadStatus.queued,
      OfflineDownloadStatus.preparing,
      OfflineDownloadStatus.downloading,
      OfflineDownloadStatus.validating,
      OfflineDownloadStatus.paused,
      OfflineDownloadStatus.removing,
    ]) {
      final transfer = _download(item.track!, batchId: 'other-job', status: status);
      final state = DownloadManagerViewState([transfer], [job], jobItems: [item]);

      expect(state.pendingGroups.values.expand((items) => items), isEmpty, reason: status.name);
      expect(state.groups.values.expand((items) => items), [transfer], reason: status.name);
    }
  });

  test('overlapping jobs share one source row while different servers retain their own tracks', () {
    final first = _job('first');
    final duplicate = _job('duplicate');
    final otherServer = _job('other', server: 'https://other.test/api');
    final state = DownloadManagerViewState(
      [],
      [first, duplicate, otherServer],
      jobItems: [_item(first.jobId, 'song', 0), _item(duplicate.jobId, 'song', 0), _item(otherServer.jobId, 'song', 0)],
    );
    final pending = state.pendingGroups[DownloadSection.queue]!;

    expect(pending, hasLength(2));
    expect(pending.map((value) => value.job.serverBaseUrl).toSet(), {_server, 'https://other.test/api'});
  });

  test('waiting tracks inherit paused and failed jobs without losing item errors', () {
    final paused = _job('paused', status: OfflineDownloadStatus.paused);
    final failed = _job('failed', status: OfflineDownloadStatus.failed, error: 'Preparation failed');
    final state = DownloadManagerViewState(
      [],
      [paused, failed],
      jobItems: [
        _item(paused.jobId, 'paused-song', 0),
        _item(failed.jobId, 'failed-song', 0).copyWith(error: 'Source could not be encoded'),
      ],
    );

    expect(state.pendingGroups[DownloadSection.paused]!.single.status, OfflineDownloadStatus.paused);
    final failure = state.pendingGroups[DownloadSection.needsAttention]!.single;
    expect(failure.status, OfflineDownloadStatus.failed);
    expect(failure.error, 'Source could not be encoded');
    expect(state.hasPaused, isTrue);
  });

  test('completed and canceled jobs never leave phantom pending tracks', () {
    final complete = _job('complete', status: OfflineDownloadStatus.downloaded);
    final canceled = _job('canceled', status: OfflineDownloadStatus.canceled);
    final state = DownloadManagerViewState(
      [],
      [complete, canceled],
      jobItems: [_item(complete.jobId, 'one', 0), _item(canceled.jobId, 'two', 0)],
    );

    expect(state.pendingGroups.values.expand((items) => items), isEmpty);
    expect(state.isEmpty, isTrue);
  });
}

OfflineDownloadJob _job(
  String id, {
  String server = _server,
  OfflineDownloadStatus status = OfflineDownloadStatus.queued,
  String? error,
}) => OfflineDownloadJob(
  jobId: id,
  kind: 'album',
  profile: 'opus_128',
  serverBaseUrl: server,
  status: status,
  createdAt: _now,
  updatedAt: _now,
  error: error,
);

OfflineDownloadJobItem _item(String jobId, String trackId, int position) => OfflineDownloadJobItem(
  jobId: jobId,
  position: position,
  serverTrackId: trackId,
  status: OfflineDownloadStatus.queued,
  materialized: false,
  createdAt: _now,
  updatedAt: _now,
  track: Track(
    id: trackId,
    title: trackId,
    artist: 'Artist',
    album: 'Album',
    durationMs: 60000,
    liked: false,
    inPlaylists: false,
  ),
);

OfflineTrackDownload _download(
  Track track, {
  String? batchId,
  OfflineDownloadStatus status = OfflineDownloadStatus.downloading,
  DateTime? createdAt,
}) => OfflineTrackDownload(
  serverBaseUrl: _server,
  track: track,
  batchId: batchId,
  status: status,
  createdAt: createdAt ?? _now,
  updatedAt: createdAt ?? _now,
);
