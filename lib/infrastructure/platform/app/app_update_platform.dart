import 'package:flutter/foundation.dart';

import 'package:phonolite_app/data/models/updates/app_update_configuration.dart';
import 'package:phonolite_app/data/models/updates/app_update_progress.dart';

abstract interface class AppUpdatePlatform {
  Future<AppUpdateConfiguration> initialize({required Future<void> Function() onInstall});
  Future<void> showUpdate();
  Future<void> dispose();
}

abstract interface class AppUpdateProgressSource {
  ValueListenable<AppUpdateProgress> get progress;
  void cancelDownload();
}

abstract interface class AppUpdatePreparationPlatform {
  void setPreparationCallback(Future<void> Function() prepare);
}
