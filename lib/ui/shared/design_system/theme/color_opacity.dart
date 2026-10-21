import 'package:flutter/painting.dart';

/// Retains the palette's established eight-bit opacity and RGB conversion.
extension ByteColorOpacity on Color {
  /// Reconstructs the color with byte-rounded alpha, matching existing paints.
  /// Use floating-point color updates when a new design needs that precision.
  Color withByteOpacity(double opacity) {
    assert(opacity >= 0.0 && opacity <= 1.0);

    return withAlpha((255.0 * opacity).round());
  }
}
