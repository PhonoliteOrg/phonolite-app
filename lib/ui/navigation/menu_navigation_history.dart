import 'dart:async';

import 'package:flutter/material.dart';

/// Remembers popped menu pages so Forward can reopen them in the same tab.
class MenuNavigationHistory extends NavigatorObserver {
  final List<MaterialPageRoute<void> Function()> _forwardPages = [];
  Route<dynamic>? _topRoute;
  Route<dynamic>? _restoringRoute;

  void goBack() {
    final state = navigator;

    if (state != null && state.canPop()) {
      unawaited(state.maybePop());
    }
  }

  void goForward() {
    final state = navigator;
    final top = _topRoute;

    if (state == null || top is! PageRoute<dynamic> || top.willHandlePopInternally || _forwardPages.isEmpty) {
      return;
    }

    final route = _forwardPages.removeLast()();

    _restoringRoute = route;

    unawaited(state.push<void>(route));
  }

  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    _topRoute = topRoute;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (identical(route, _restoringRoute)) {
      _restoringRoute = null;
    } else if (route is PageRoute<dynamic>) {
      _forwardPages.clear();
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null || route is! MaterialPageRoute<dynamic>) {
      return;
    }

    // A popped route is disposed after its transition. Keep a factory for a
    // fresh route, including its settings, rather than reusing that route.
    final builder = route.builder;
    final settings = route.settings;
    final maintainState = route.maintainState;
    final fullscreenDialog = route.fullscreenDialog;
    final allowSnapshotting = route.allowSnapshotting;
    final barrierDismissible = route.barrierDismissible;
    final requestFocus = route.requestFocus;
    final traversalEdgeBehavior = route.traversalEdgeBehavior;
    final directionalTraversalEdgeBehavior = route.directionalTraversalEdgeBehavior;

    _forwardPages.add(
      () => MaterialPageRoute<void>(
        builder: builder,
        settings: settings,
        maintainState: maintainState,
        fullscreenDialog: fullscreenDialog,
        allowSnapshotting: allowSnapshotting,
        barrierDismissible: barrierDismissible,
        requestFocus: requestFocus,
        traversalEdgeBehavior: traversalEdgeBehavior,
        directionalTraversalEdgeBehavior: directionalTraversalEdgeBehavior,
      ),
    );
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _forwardPages.clear();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute<dynamic>) {
      _forwardPages.clear();
    }
  }
}
