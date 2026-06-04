import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

bool enableBackdropBlur() {
  return !kIsWeb && defaultTargetPlatform != TargetPlatform.windows;
}

Widget maybeBlur({required double sigma, required Widget child}) {
  if (sigma <= 0 || !enableBackdropBlur()) {
    return child;
  }
  return BackdropFilter(
    filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
    child: child,
  );
}
