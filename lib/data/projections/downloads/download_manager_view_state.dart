import 'package:phonolite_app/data/models/downloads/download_job.dart';
import 'package:phonolite_app/data/models/downloads/download_status.dart';
import 'package:phonolite_app/data/models/downloads/offline_track_download.dart';
import 'package:phonolite_app/data/projections/downloads/pending_download_track.dart';
import 'package:phonolite_app/data/rules/downloads/download_queue_rules.dart';

enum DownloadSection { queue, removing, paused, needsAttention }

class DownloadManagerViewState {
  late final bool hasPausable;
  late final bool hasPaused;
  late final bool isEmpty;
  late final bool hasActiveWork;
  late final List<OfflineDownloadJob> jobs;
  late final Map<DownloadSection, List<OfflineTrackDownload>> groups;
  late final Map<DownloadSection, List<PendingDownloadTrack>> pendingGroups;

  DownloadManagerViewState(
    List<OfflineTrackDownload> downloads,
    List<OfflineDownloadJob> jobs, {
    List<OfflineDownloadJobItem> jobItems = const [],
  }) {
    final visibleJobs = jobs
        .where((job) => job.status != OfflineDownloadStatus.downloaded && job.status != OfflineDownloadStatus.canceled)
        .toList(growable: false);
    final pendingGroups = _pendingGroups(downloads, visibleJobs, jobItems);
    final pending = pendingGroups.values.expand((tracks) => tracks).toList(growable: false);
    final pendingKeys = {for (final track in pending) (track.job.serverBaseUrl, track.item.serverTrackId)};
    final visibleDownloads = downloads
        .where(
          (download) =>
              download.status != OfflineDownloadStatus.downloaded &&
              !pendingKeys.contains((download.serverBaseUrl, download.track.serverTrackId ?? download.track.id)),
        )
        .toList(growable: false);
    final groups = _groups(visibleDownloads);
    final pausedDownloads = groups[DownloadSection.paused]!;

    hasPausable =
        visibleDownloads.any((download) => DownloadQueueRules.canPauseDownloadStatus(download.status)) ||
        visibleJobs.any((job) => DownloadQueueRules.canPauseDownloadStatus(job.status)) ||
        pending.any((track) => DownloadQueueRules.canPauseDownloadStatus(track.status));
    hasPaused =
        pausedDownloads.isNotEmpty ||
        visibleJobs.any((job) => job.status == OfflineDownloadStatus.paused) ||
        pendingGroups[DownloadSection.paused]!.isNotEmpty;
    isEmpty = visibleDownloads.isEmpty && visibleJobs.isEmpty;
    hasActiveWork =
        visibleDownloads.any((download) => DownloadQueueRules.hasActiveWork(download.status)) ||
        visibleJobs.any((job) => DownloadQueueRules.hasActiveWork(job.status)) ||
        pending.any((track) => DownloadQueueRules.hasActiveWork(track.status));
    this.jobs = List<OfflineDownloadJob>.unmodifiable(visibleJobs);
    this.groups = Map<DownloadSection, List<OfflineTrackDownload>>.unmodifiable({
      for (final entry in groups.entries) entry.key: List<OfflineTrackDownload>.unmodifiable(entry.value),
    });
    this.pendingGroups = pendingGroups;
  }

  static DownloadSection? _section(OfflineDownloadStatus status) => switch (status) {
    OfflineDownloadStatus.queued ||
    OfflineDownloadStatus.preparing ||
    OfflineDownloadStatus.downloading ||
    OfflineDownloadStatus.validating => DownloadSection.queue,
    OfflineDownloadStatus.removing => DownloadSection.removing,
    OfflineDownloadStatus.paused => DownloadSection.paused,
    OfflineDownloadStatus.failed ||
    OfflineDownloadStatus.corrupt ||
    OfflineDownloadStatus.canceled => DownloadSection.needsAttention,
    OfflineDownloadStatus.downloaded => null,
  };

  static bool _failedTransfer(OfflineDownloadStatus status) =>
      status == OfflineDownloadStatus.failed ||
      status == OfflineDownloadStatus.corrupt ||
      status == OfflineDownloadStatus.canceled;

  static Map<DownloadSection, List<PendingDownloadTrack>> _pendingGroups(
    List<OfflineTrackDownload> downloads,
    List<OfflineDownloadJob> jobs,
    List<OfflineDownloadJobItem> jobItems,
  ) {
    final jobsById = {for (final job in jobs) job.jobId: job};
    final transfers = {
      for (final download in downloads)
        (download.serverBaseUrl, download.track.serverTrackId ?? download.track.id): download,
    };
    final represented = <(String, String)>{};
    final groups = {for (final section in DownloadSection.values) section: <PendingDownloadTrack>[]};

    for (final item in jobItems) {
      final job = jobsById[item.jobId];

      if (job == null ||
          item.materialized ||
          item.status == OfflineDownloadStatus.downloaded ||
          item.status == OfflineDownloadStatus.canceled) {
        continue;
      }

      final key = (job.serverBaseUrl, item.serverTrackId);
      final transfer = transfers[key];

      if (transfer != null && (transfer.batchId == item.jobId || !_failedTransfer(transfer.status))) {
        continue;
      }

      if (!represented.add(key)) {
        continue;
      }

      final pending = PendingDownloadTrack(job: job, item: item);
      final section = _section(pending.status);

      if (section != null) {
        groups[section]!.add(pending);
      }
    }

    for (final tracks in groups.values) {
      tracks.sort((left, right) {
        final jobOrder = right.job.createdAt.compareTo(left.job.createdAt);

        if (jobOrder != 0) {
          return jobOrder;
        }

        final jobId = left.job.jobId.compareTo(right.job.jobId);

        return jobId != 0 ? jobId : left.item.position.compareTo(right.item.position);
      });
    }

    return Map<DownloadSection, List<PendingDownloadTrack>>.unmodifiable({
      for (final entry in groups.entries) entry.key: List<PendingDownloadTrack>.unmodifiable(entry.value),
    });
  }

  static Map<DownloadSection, List<OfflineTrackDownload>> _groups(List<OfflineTrackDownload> downloads) {
    final groups = {
      DownloadSection.queue: <OfflineTrackDownload>[],
      DownloadSection.removing: <OfflineTrackDownload>[],
      DownloadSection.paused: <OfflineTrackDownload>[],
      DownloadSection.needsAttention: <OfflineTrackDownload>[],
    };

    for (final download in downloads) {
      final section = _section(download.status);

      if (section != null) {
        groups[section]!.add(download);
      }
    }

    groups[DownloadSection.queue]!.sort(DownloadQueueRules.compareQueueDownloads);
    groups[DownloadSection.removing]!.sort(DownloadQueueRules.compareUpdatedNewestFirst);
    groups[DownloadSection.paused]!.sort(DownloadQueueRules.compareUpdatedNewestFirst);
    groups[DownloadSection.needsAttention]!.sort(DownloadQueueRules.compareUpdatedNewestFirst);

    return groups;
  }
}
