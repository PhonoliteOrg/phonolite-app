import 'package:phonolite_app/data/models/updates/app_update_configuration.dart';

abstract interface class AppUpdatePlatform {
  Future<AppUpdateConfiguration> initialize({required Future<void> Function() onInstall});
  Future<void> showUpdate();
  Future<void> dispose();
}
