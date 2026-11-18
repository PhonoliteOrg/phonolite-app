import 'package:phonolite_app/data/models/updates/app_update_configuration.dart';
import 'package:phonolite_app/data/models/updates/app_update_release.dart';

abstract interface class AppUpdateFeed {
  Future<AppUpdateRelease?> latest(AppUpdateConfiguration configuration);
  void close();
}
