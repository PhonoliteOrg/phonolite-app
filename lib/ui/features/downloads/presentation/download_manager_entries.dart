import 'package:phonolite_app/data/models/downloads/download_job.dart';
import 'package:phonolite_app/data/models/downloads/offline_track_download.dart';
import 'package:phonolite_app/data/projections/downloads/download_manager_view_state.dart';

enum DownloadManagerEntryKind { jobHeader, job, sectionHeader, download, spacer }

/// Assembles the panel's visual rows, captions and inter-section spacing.
abstract final class DownloadManagerEntries {
  static List<DownloadManagerEntry> build(DownloadManagerViewState state) {
    final jobs = state.jobs;
    final groups = state.groups;
    final entries = <DownloadManagerEntry>[];

    if (jobs.isNotEmpty) {
      entries.add(const DownloadManagerEntry.jobHeader());

      for (final job in jobs) {
        entries.add(DownloadManagerEntry.job(job));
      }

      entries.add(const DownloadManagerEntry.spacer('jobs-bottom', 12));
    }

    void addSection(DownloadSection section, String title) {
      final downloads = groups[section]!;

      if (downloads.isEmpty) {
        return;
      }

      entries.add(DownloadManagerEntry.sectionHeader(section.name, title, downloads.length));

      for (final download in downloads) {
        entries.add(DownloadManagerEntry.download(download));
      }

      entries.add(DownloadManagerEntry.spacer('${section.name}-bottom', 12));
    }

    addSection(DownloadSection.queue, 'Queue');
    addSection(DownloadSection.removing, 'Removing');
    addSection(DownloadSection.paused, 'Paused');
    addSection(DownloadSection.needsAttention, 'Needs Attention');

    return List<DownloadManagerEntry>.unmodifiable(entries);
  }
}

class DownloadManagerEntry {
  final DownloadManagerEntryKind kind;
  final String key;
  final OfflineDownloadJob? job;
  final OfflineTrackDownload? download;
  final String? title;
  final int count;
  final double height;

  const DownloadManagerEntry._({
    required this.key,
    required this.kind,
    this.job,
    this.download,
    this.title,
    this.count = 0,
    this.height = 0,
  });

  const DownloadManagerEntry.jobHeader() : this._(kind: DownloadManagerEntryKind.jobHeader, key: 'job-header');

  DownloadManagerEntry.job(OfflineDownloadJob job)
    : this._(kind: DownloadManagerEntryKind.job, key: 'job:${job.jobId}', job: job);

  DownloadManagerEntry.sectionHeader(String sectionKey, String title, int count)
    : this._(kind: DownloadManagerEntryKind.sectionHeader, key: 'section:$sectionKey', title: title, count: count);

  DownloadManagerEntry.download(OfflineTrackDownload download)
    : this._(
        kind: DownloadManagerEntryKind.download,
        key: 'download:${download.serverBaseUrl}:${download.track.serverTrackId ?? download.track.id}',
        download: download,
      );

  const DownloadManagerEntry.spacer(String key, double height)
    : this._(kind: DownloadManagerEntryKind.spacer, key: 'spacer:$key', height: height);
}
