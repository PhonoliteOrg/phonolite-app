import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/theme/backdrop_blur_resize_suspension.dart';

bool enableBackdropBlur() {
  return !kIsWeb && defaultTargetPlatform != TargetPlatform.windows;
}

Widget maybeBlur({required double sigma, required Widget child}) {
  if (sigma <= 0 || !enableBackdropBlur()) {
    return child;
  }

  return Builder(
    builder: (context) => BackdropFilter(
      filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      enabled: !BackdropBlurResizeSuspension.isSuspended(context),
      child: child,
    ),
  );
}
