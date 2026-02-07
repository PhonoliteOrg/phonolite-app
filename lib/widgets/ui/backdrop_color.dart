import 'package:flutter/material.dart';

import '../../core/constants.dart';

final Map<String, Color> _artistBackdropCache = <String, Color>{};
final Map<String, Color> _albumBackdropCache = <String, Color>{};

Future<Color> resolveLogoBackdropColor(
  ImageProvider provider,
  String cacheKey,
) async {
  final cached = _artistBackdropCache[cacheKey];
  if (cached != null) {
    return cached;
  }
  final resolved = _fastArtistBackdropColor(cacheKey);
  _artistBackdropCache[cacheKey] = resolved;
  return resolved;
}

Color _tuneBackdropColor(Color? color) {
  if (color == null || color.alpha < 16) {
    return artistLogoBackdrop;
  }
  final opaque = color.withAlpha(255);
  final luminance = opaque.computeLuminance();
  final Color blended;
  if (luminance < artistBackdropMinLuminance) {
    blended = Color.lerp(opaque, Colors.white, artistBackdropLightenFactor) ??
        artistLogoBackdrop;
  } else {
    blended = Color.lerp(opaque, Colors.black, artistBackdropDarkenFactor) ??
        artistLogoBackdrop;
  }
  return _ensureMinLightness(blended, artistBackdropMinLightness);
}

Color _ensureMinLightness(Color color, double minLightness) {
  final hsl = HSLColor.fromColor(color);
  if (hsl.lightness >= minLightness) {
    return color;
  }
  return artistBackdropForcedLight;
}

Future<Color> resolveAlbumBackdropColor(
  ImageProvider provider,
  String cacheKey,
) async {
  final cached = _albumBackdropCache[cacheKey];
  if (cached != null) {
    return cached;
  }
  final resolved = _fastAlbumBackdropColor(cacheKey);
  _albumBackdropCache[cacheKey] = resolved;
  return resolved;
}

Color _tuneAlbumBackdropColor(Color? color) {
  if (color == null) {
    return bgDark;
  }
  final opaque = color.withAlpha(255);
  final luminance = opaque.computeLuminance();
  final blend = luminance < 0.4 ? 0.25 : 0.4;
  return Color.lerp(opaque, bgDark, blend) ?? bgDark;
}

Color _fastAlbumBackdropColor(String key) {
  var hash = 0;
  for (final unit in key.codeUnits) {
    hash = 0x1fffffff & (hash + unit);
    hash = 0x1fffffff & (hash + ((hash & 0x0007ffff) << 10));
    hash ^= (hash >> 6);
  }
  hash = 0x1fffffff & (hash + ((hash & 0x03ffffff) << 3));
  hash ^= (hash >> 11);
  hash = 0x1fffffff & (hash + ((hash & 0x00003fff) << 15));
  final hue = (hash % 360).toDouble();
  final color = HSLColor.fromAHSL(1, hue, 0.35, 0.25).toColor();
  return Color.lerp(color, bgDark, 0.35) ?? bgDark;
}

Color _fastArtistBackdropColor(String key) {
  var hash = 0;
  for (final unit in key.codeUnits) {
    hash = 0x1fffffff & (hash + unit);
    hash = 0x1fffffff & (hash + ((hash & 0x0007ffff) << 10));
    hash ^= (hash >> 6);
  }
  hash = 0x1fffffff & (hash + ((hash & 0x03ffffff) << 3));
  hash ^= (hash >> 11);
  hash = 0x1fffffff & (hash + ((hash & 0x00003fff) << 15));
  final hue = (hash % 360).toDouble();
  final color = HSLColor.fromAHSL(1, hue, 0.45, 0.38).toColor();
  return _tuneBackdropColor(color);
}
