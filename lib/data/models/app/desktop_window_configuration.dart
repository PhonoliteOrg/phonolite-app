import 'dart:ui';

/// Minimum usable content area, measured in logical pixels without window chrome.
abstract final class DesktopWindowConfiguration {
  static const double minimumWidth = 600;
  static const double minimumHeight = 360;
  static const Size minimumSize = Size(minimumWidth, minimumHeight);
}
