import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/navigation/menu_navigation_history.dart';

class TabRouteObserver extends MenuNavigationHistory {
  final ValueChanged<String?> onRouteChanged;
  String? currentRouteName;

  TabRouteObserver({required this.onRouteChanged});

  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    super.didChangeTop(topRoute, previousTopRoute);

    currentRouteName = topRoute.settings.name;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);

    _notifyAfterTransition(route, route.settings.name, AnimationStatus.completed);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);

    _notifyAfterTransition(route, previousRoute?.settings.name, AnimationStatus.dismissed);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);

    _notifyAfterTransition(newRoute, newRoute?.settings.name, AnimationStatus.completed);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);

    _notify(previousRoute?.settings.name);
  }

  void _notify(String? routeName) {
    onRouteChanged(routeName);
  }

  void _notifyAfterTransition(Route<dynamic>? transitionRoute, String? routeName, AnimationStatus targetStatus) {
    final animation = transitionRoute is TransitionRoute<dynamic> ? transitionRoute.animation : null;

    if (animation == null || animation.status == targetStatus) {
      _notify(routeName);

      return;
    }

    late AnimationStatusListener listener;

    listener = (status) {
      if (status != targetStatus) {
        return;
      }

      animation.removeStatusListener(listener);
      _notify(routeName);
    };
    animation.addStatusListener(listener);
  }
}
