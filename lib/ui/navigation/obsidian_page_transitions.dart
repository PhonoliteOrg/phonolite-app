import 'package:flutter/material.dart';

/// Fades outgoing content early so transparent pages do not linger underneath.
class ObsidianPageTransitionsBuilder extends FadeForwardsPageTransitionsBuilder {
  const ObsidianPageTransitionsBuilder() : super(backgroundColor: Colors.transparent);

  @override
  Duration get transitionDuration => const Duration(milliseconds: 180);

  @override
  Widget buildTransitions<T>(
    PageRoute<T>? route,
    BuildContext? context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => super.buildTransitions(
    route,
    context,
    animation,
    secondaryAnimation,
    // Keep portal content inside the same fade and offstage scope as its anchor.
    Overlay.wrap(child: child),
  );
}
