import 'package:phonolite_app/data/models/downloads/download_batch.dart';
import 'package:phonolite_app/data/models/downloads/download_job.dart';
import 'package:phonolite_app/data/models/downloads/offline_track_download.dart';

class OfflineDownloadSnapshot {
  final List<OfflineTrackDownload> downloads;
  final List<OfflineDownloadBatch> batches;
  final List<OfflineDownloadJob> jobs;
  final int revision;

  const OfflineDownloadSnapshot({
    required this.downloads,
    required this.batches,
    required this.jobs,
    required this.revision,
  });
}
