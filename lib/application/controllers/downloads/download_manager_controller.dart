import 'package:phonolite_app/data/models/downloads/download_status.dart';
import 'package:phonolite_app/data/rules/downloads/download_queue_rules.dart';

export 'package:phonolite_app/data/projections/downloads/download_manager_view_state.dart';

class DownloadManagerController {
  static bool canPauseDownloadStatus(OfflineDownloadStatus status) => DownloadQueueRules.canPauseDownloadStatus(status);
}
