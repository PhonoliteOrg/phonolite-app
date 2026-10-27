import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Desktop playback dimensions in logical pixels before a single uniform scale.
class DesktopPlaybackLayout {
  static const double panelHeight = 147;
  static const double rowGap = 12;
  static const double commandWidth = 312;
  static const double _minimumSideWidth = 260;
  static const double _maximumSideWidth = 350;
  static const EdgeInsets margin = EdgeInsets.fromLTRB(16, 6, 16, 16);
  static const EdgeInsets panelPadding = EdgeInsets.symmetric(horizontal: 20, vertical: 6);
  static const double canvasHeight = panelHeight + 22;
  static const double _minimumWidth = _minimumSideWidth * 2 + commandWidth + rowGap * 2 + 72;

  final double width;
  final double scale;
  final double canvasWidth;
  final double sideWidth;

  const DesktopPlaybackLayout._({
    required this.width,
    required this.scale,
    required this.canvasWidth,
    required this.sideWidth,
  });

  factory DesktopPlaybackLayout.resolve({required Size availableSize}) {
    assert(availableSize.width.isFinite && availableSize.width >= 0);
    assert(availableSize.height.isFinite && availableSize.height >= 0);

    final widthScale = (availableSize.width / _minimumWidth).clamp(0.0, 1.0);
    // Leave at least two thirds of a short desktop window for page content.
    final heightScale = (availableSize.height / (canvasHeight * 3)).clamp(0.0, 1.0);
    final scale = math.min(widthScale, heightScale);
    final canvasWidth = scale > 0 ? availableSize.width / scale : _minimumWidth;
    final contentWidth = canvasWidth - margin.horizontal - panelPadding.horizontal;
    final sideWidth = ((contentWidth - commandWidth - rowGap * 2) / 2).clamp(_minimumSideWidth, _maximumSideWidth);

    return DesktopPlaybackLayout._(
      width: availableSize.width,
      scale: scale,
      canvasWidth: canvasWidth,
      sideWidth: sideWidth,
    );
  }

  double get height => canvasHeight * scale;

  static bool supports(TargetPlatform platform) => switch (platform) {
    TargetPlatform.windows || TargetPlatform.macOS || TargetPlatform.linux => true,
    TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.fuchsia => false,
  };
}
