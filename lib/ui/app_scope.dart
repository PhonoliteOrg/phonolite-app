import 'package:flutter/widgets.dart';

import 'package:phonolite_app/application/app/app_controller.dart';

class AppScope extends InheritedWidget {
  final AppController controller;

  const AppScope({super.key, required this.controller, required super.child});

  static AppController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    if (scope == null) {
      throw StateError('AppScope not found in widget tree');
    }

    return scope.controller;
  }

  /// The nearest controller, or null when this context has no [AppScope].
  static AppController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()?.controller;

  @override
  bool updateShouldNotify(AppScope oldWidget) => controller != oldWidget.controller;
}
