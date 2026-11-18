import 'dart:async';

import 'package:flutter/foundation.dart';

bool get desktopLifecycleSupported =>
    !kIsWeb &&
    switch (defaultTargetPlatform) {
      TargetPlatform.windows || TargetPlatform.macOS || TargetPlatform.linux => true,
      _ => false,
    };

abstract interface class DesktopLifecyclePlatform {
  Future<void> initialize({required Future<void> Function() onClose, required Future<void> Function() onQuit});
  Future<void> setLaunchAtStartup(bool enabled);
  Future<void> setBackgroundEnabled(bool enabled);
  Future<void> hide();
  Future<void> show();
  Future<void> quit();
  Future<void> dispose();
}
