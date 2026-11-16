import 'package:phonolite_app/application/controllers/settings/app_updates_controller.dart';
import 'package:phonolite_app/application/controllers/settings/desktop_settings_controller.dart';
import 'package:phonolite_app/application/controllers/settings/display_settings_controller.dart';
import 'package:phonolite_app/application/controllers/settings/download_settings_controller.dart';

/// The device-preference controllers one running app uses. The application
/// owner initializes and shuts them down; pages borrow them from
/// `SettingsScope`.
class AppSettingsControllers {
  /// The process-wide controllers the installed application uses.
  static final shared = AppSettingsControllers(
    display: DisplaySettingsController.instance,
    download: DownloadSettingsController.instance,
    desktop: DesktopSettingsController.instance,
    updates: AppUpdatesController.instance,
  );

  final DisplaySettingsController display;
  final DownloadSettingsController download;
  final DesktopSettingsController desktop;
  final AppUpdatesController updates;

  const AppSettingsControllers({
    required this.display,
    required this.download,
    required this.desktop,
    required this.updates,
  });
}
