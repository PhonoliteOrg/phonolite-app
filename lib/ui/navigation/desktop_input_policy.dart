import 'package:flutter/foundation.dart';

/// Enables app-level desktop input bindings for native desktop platforms.
bool get desktopInputEnabled =>
    !kIsWeb &&
    switch (defaultTargetPlatform) {
      TargetPlatform.windows || TargetPlatform.macOS || TargetPlatform.linux => true,
      TargetPlatform.android || TargetPlatform.fuchsia || TargetPlatform.iOS => false,
    };
