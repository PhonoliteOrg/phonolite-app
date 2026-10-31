import 'package:flutter/foundation.dart';

import 'package:phonolite_app/infrastructure/platform/app/app_update_platform.dart';
import 'package:phonolite_app/infrastructure/platform/app/linux_app_update_platform.dart';
import 'package:phonolite_app/infrastructure/updates/app_update_feed.dart';

class AppUpdateBackend {
  final AppUpdatePlatform platform;
  final AppUpdateFeed feed;

  const AppUpdateBackend(this.platform, this.feed);

  factory AppUpdateBackend.current() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
      final linux = LinuxAppUpdatePlatform();
      return AppUpdateBackend(linux, linux);
    }
    return AppUpdateBackend(WindowsAppUpdatePlatform(), HttpAppUpdateFeed());
  }
}
