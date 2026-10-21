import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:phonolite_app/application/controllers/feature_controller.dart';

/// Connects controller notifications to rendering and owns their disposal.
/// Controllers themselves have no dependency on widget lifecycle or context.
mixin ControllerBinding<T extends StatefulWidget> on State<T> {
  final List<FeatureController> _boundControllers = [];

  @override
  void dispose() {
    for (final controller in _boundControllers.reversed) {
      controller.removeListener(_renderControllerState);
      controller.dispose();
    }

    super.dispose();
  }

  C bindController<C extends FeatureController>(C controller) {
    unawaited(controller.initialize().catchError(controller.reportInitializationFailure));

    _boundControllers.add(controller);
    controller.addListener(_renderControllerState);

    return controller;
  }

  void _renderControllerState() {
    if (mounted) {
      setState(() {});
    }
  }
}
