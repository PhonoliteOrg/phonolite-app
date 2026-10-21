import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/ui/shared/music/artwork/artwork_errors.dart';

Map<String, String> authHeaders(AppController controller) => controller.artworkHeaders;

Future<void> precacheImages(
  BuildContext context,
  Iterable<String> urls, {
  Map<String, String> headers = const {},
}) async {
  if (!shouldPrecacheImages()) {
    return;
  }

  for (final url in urls) {
    try {
      await precacheImage(
        NetworkImage(url, headers: headers),
        context,
        onError: (error, _) => ArtworkErrors.instance.report(url, error),
      );
    } catch (error) {
      ArtworkErrors.instance.report(url, error);
    }
  }
}

bool shouldPrecacheImages() {
  if (kIsWeb) {
    return false;
  }

  return defaultTargetPlatform != TargetPlatform.windows;
}
