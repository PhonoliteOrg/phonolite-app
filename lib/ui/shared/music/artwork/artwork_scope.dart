import 'package:flutter/widgets.dart';

import 'package:phonolite_app/data/models/artwork/artwork_request.dart';

/// Provides a borrowed application-owned image capability to presentation.
class ArtworkScope extends InheritedWidget {
  final ArtworkLoader loader;

  const ArtworkScope({super.key, required this.loader, required super.child});

  static ArtworkLoader? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ArtworkScope>()?.loader;

  @override
  bool updateShouldNotify(ArtworkScope oldWidget) => loader != oldWidget.loader;
}
