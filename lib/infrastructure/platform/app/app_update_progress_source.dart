import 'package:flutter/foundation.dart';

import 'package:phonolite_app/data/models/updates/app_update_progress.dart';

abstract interface class AppUpdateProgressSource {
  ValueListenable<AppUpdateProgress> get progress;
  void cancelDownload();
}
