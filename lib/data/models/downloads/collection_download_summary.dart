import 'package:phonolite_app/data/models/downloads/download_status.dart';

class CollectionDownloadSummary {
  final int total;
  final int downloaded;
  final int active;
  final int failed;
  final OfflineDownloadStatus? requestStatus;

  const CollectionDownloadSummary({
    required this.total,
    required this.downloaded,
    required this.active,
    required this.failed,
    this.requestStatus,
  });

  bool get isComplete => total > 0 && downloaded >= total;

  bool get canStart => total > 0 && active == 0 && !isComplete && !_hasPendingRequest;

  bool get _hasPendingRequest => switch (requestStatus) {
    OfflineDownloadStatus.queued ||
    OfflineDownloadStatus.preparing ||
    OfflineDownloadStatus.downloading ||
    OfflineDownloadStatus.validating ||
    OfflineDownloadStatus.paused ||
    OfflineDownloadStatus.removing => true,
    OfflineDownloadStatus.downloaded ||
    OfflineDownloadStatus.failed ||
    OfflineDownloadStatus.corrupt ||
    OfflineDownloadStatus.canceled ||
    null => false,
  };

  String get label {
    if (isComplete) {
      return 'Downloaded';
    }

    final requestLabel = switch (requestStatus) {
      OfflineDownloadStatus.queued => 'Queued',
      OfflineDownloadStatus.preparing => 'Preparing',
      OfflineDownloadStatus.downloading => 'Downloading',
      OfflineDownloadStatus.validating => 'Validating',
      OfflineDownloadStatus.paused => 'Paused',
      OfflineDownloadStatus.removing => 'Removing',
      OfflineDownloadStatus.failed || OfflineDownloadStatus.corrupt => 'Retry Downloads',
      OfflineDownloadStatus.downloaded || OfflineDownloadStatus.canceled || null => null,
    };

    if (requestLabel != null) {
      return requestLabel;
    }

    if (active > 0) {
      return 'Downloading';
    }

    if (failed > 0) {
      return 'Retry Downloads';
    }

    if (downloaded > 0) {
      return 'Download Missing';
    }

    return 'Download Album';
  }
}
