import 'package:flutter/material.dart';

class ObsidianScale extends InheritedWidget {
  const ObsidianScale({
    super.key,
    required this.scale,
    required super.child,
  });

  final double scale;

  static double of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ObsidianScale>();
    return scope?.scale ?? 1.0;
  }

  static double compute(double width) {
    const baseWidth = 900.0;
    final raw = width / baseWidth;
    if (raw >= 1.0) {
      return 1.0;
    }
    if (raw <= 0.7) {
      return 0.7;
    }
    return raw;
  }

  @override
  bool updateShouldNotify(covariant ObsidianScale oldWidget) {
    return oldWidget.scale != scale;
  }
}

extension ObsidianScaleExt on BuildContext {
  double s(double value) => value * ObsidianScale.of(this);
}
