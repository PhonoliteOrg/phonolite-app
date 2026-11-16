import 'package:flutter/widgets.dart';

import 'package:phonolite_app/application/controllers/settings/app_settings_controllers.dart';

/// Supplies the running app's settings controllers to pages and dialogs.
///
/// Controllers are fixed for the app's lifetime, so lookups do not register a
/// rebuild dependency and are valid from `initState`. Widgets built outside a
/// scope, such as isolated widget tests, use [AppSettingsControllers.shared].
class SettingsScope extends InheritedWidget {
  final AppSettingsControllers settings;

  const SettingsScope({super.key, required this.settings, required super.child});

  static AppSettingsControllers of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SettingsScope>()?.settings ?? AppSettingsControllers.shared;

  @override
  bool updateShouldNotify(SettingsScope oldWidget) => !identical(settings, oldWidget.settings);
}
