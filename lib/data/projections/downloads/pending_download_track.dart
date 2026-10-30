import 'package:phonolite_app/data/models/downloads/download_job.dart';
import 'package:phonolite_app/data/models/downloads/download_status.dart';

/// A durable job track whose file has not entered the transfer window yet.
class PendingDownloadTrack {
  final OfflineDownloadJob job;
  final OfflineDownloadJobItem item;

  const PendingDownloadTrack({required this.job, required this.item});

  OfflineDownloadStatus get status {
    if (item.status == OfflineDownloadStatus.failed || item.status == OfflineDownloadStatus.corrupt) {
      return item.status;
    }

    return switch (job.status) {
      OfflineDownloadStatus.paused ||
      OfflineDownloadStatus.failed ||
      OfflineDownloadStatus.corrupt ||
      OfflineDownloadStatus.removing => job.status,
      OfflineDownloadStatus.preparing => OfflineDownloadStatus.preparing,
      OfflineDownloadStatus.queued ||
      OfflineDownloadStatus.downloading ||
      OfflineDownloadStatus.validating ||
      OfflineDownloadStatus.downloaded ||
      OfflineDownloadStatus.canceled => item.status,
    };
  }

  String? get error => item.error ?? job.error;
}
