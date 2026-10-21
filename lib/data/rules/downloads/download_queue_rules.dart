import 'package:phonolite_app/data/models/downloads/download_status.dart';
import 'package:phonolite_app/data/models/downloads/offline_track_download.dart';

/// Status eligibility and ordering shared by download execution and observation.
abstract final class DownloadQueueRules {
  static bool canPauseDownloadStatus(OfflineDownloadStatus status) {
    return switch (status) {
      OfflineDownloadStatus.queued ||
      OfflineDownloadStatus.preparing ||
      OfflineDownloadStatus.downloading ||
      OfflineDownloadStatus.validating => true,
      OfflineDownloadStatus.paused ||
      OfflineDownloadStatus.downloaded ||
      OfflineDownloadStatus.removing ||
      OfflineDownloadStatus.failed ||
      OfflineDownloadStatus.corrupt ||
      OfflineDownloadStatus.canceled => false,
    };
  }

  static int compareQueueDownloads(OfflineTrackDownload left, OfflineTrackDownload right) {
    final status = _queueStatusRank(left.status).compareTo(_queueStatusRank(right.status));

    if (status != 0) {
      return status;
    }

    final priority = right.priority.compareTo(left.priority);

    if (priority != 0) {
      return priority;
    }

    return left.createdAt.compareTo(right.createdAt);
  }

  static int _queueStatusRank(OfflineDownloadStatus status) {
    return switch (status) {
      OfflineDownloadStatus.downloading => 0,
      OfflineDownloadStatus.preparing => 1,
      OfflineDownloadStatus.validating => 2,
      OfflineDownloadStatus.queued => 3,
      OfflineDownloadStatus.paused ||
      OfflineDownloadStatus.downloaded ||
      OfflineDownloadStatus.removing ||
      OfflineDownloadStatus.failed ||
      OfflineDownloadStatus.corrupt ||
      OfflineDownloadStatus.canceled => 4,
    };
  }

  static int compareUpdatedNewestFirst(OfflineTrackDownload left, OfflineTrackDownload right) {
    return right.updatedAt.compareTo(left.updatedAt);
  }
}
