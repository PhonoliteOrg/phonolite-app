import 'package:phonolite_app/data/models/downloads/download_job.dart';
import 'package:phonolite_app/data/models/downloads/download_status.dart';
import 'package:phonolite_app/data/models/downloads/offline_track_download.dart';
import 'package:phonolite_app/data/rules/downloads/download_queue_rules.dart';

enum DownloadSection { queue, removing, paused, needsAttention }

class DownloadManagerViewState {
  late final bool hasPausable;
  late final bool hasPaused;
  late final bool isEmpty;
  late final bool hasActiveWork;
  late final List<OfflineDownloadJob> jobs;
  late final Map<DownloadSection, List<OfflineTrackDownload>> groups;

  DownloadManagerViewState(List<OfflineTrackDownload> downloads, List<OfflineDownloadJob> jobs) {
    final visibleDownloads = downloads
        .where((download) => download.status != OfflineDownloadStatus.downloaded)
        .toList(growable: false);
    final visibleJobs = jobs
        .where((job) => job.status != OfflineDownloadStatus.downloaded && job.status != OfflineDownloadStatus.canceled)
        .toList(growable: false);
    final groups = _groups(visibleDownloads);
    final pausedDownloads = groups[DownloadSection.paused]!;

    hasPausable =
        visibleDownloads.any((download) => DownloadQueueRules.canPauseDownloadStatus(download.status)) ||
        visibleJobs.any((job) => DownloadQueueRules.canPauseDownloadStatus(job.status));
    hasPaused = pausedDownloads.isNotEmpty || visibleJobs.any((job) => job.status == OfflineDownloadStatus.paused);
    isEmpty = visibleDownloads.isEmpty && visibleJobs.isEmpty;
    hasActiveWork =
        visibleDownloads.any((download) => DownloadQueueRules.hasActiveWork(download.status)) ||
        visibleJobs.any((job) => DownloadQueueRules.hasActiveWork(job.status));
    this.jobs = List<OfflineDownloadJob>.unmodifiable(visibleJobs);
    this.groups = Map<DownloadSection, List<OfflineTrackDownload>>.unmodifiable({
      for (final entry in groups.entries) entry.key: List<OfflineTrackDownload>.unmodifiable(entry.value),
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
      switch (download.status) {
        case OfflineDownloadStatus.queued:
        case OfflineDownloadStatus.preparing:
        case OfflineDownloadStatus.downloading:
        case OfflineDownloadStatus.validating:
          groups[DownloadSection.queue]!.add(download);
          break;
        case OfflineDownloadStatus.removing:
          groups[DownloadSection.removing]!.add(download);
          break;
        case OfflineDownloadStatus.paused:
          groups[DownloadSection.paused]!.add(download);
          break;
        case OfflineDownloadStatus.failed:
        case OfflineDownloadStatus.corrupt:
        case OfflineDownloadStatus.canceled:
          groups[DownloadSection.needsAttention]!.add(download);
          break;
        case OfflineDownloadStatus.downloaded:
          break;
      }
    }

    groups[DownloadSection.queue]!.sort(DownloadQueueRules.compareQueueDownloads);
    groups[DownloadSection.removing]!.sort(DownloadQueueRules.compareUpdatedNewestFirst);
    groups[DownloadSection.paused]!.sort(DownloadQueueRules.compareUpdatedNewestFirst);
    groups[DownloadSection.needsAttention]!.sort(DownloadQueueRules.compareUpdatedNewestFirst);

    return groups;
  }
}
