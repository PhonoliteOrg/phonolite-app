import 'package:flutter/material.dart';

/// Fades outgoing content early so transparent pages do not linger underneath.
class ObsidianPageTransitionsBuilder
    extends FadeForwardsPageTransitionsBuilder {
  const ObsidianPageTransitionsBuilder()
    : super(backgroundColor: Colors.transparent);

  @override
  Duration get transitionDuration => const Duration(milliseconds: 180);
}
