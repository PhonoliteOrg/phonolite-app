import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/music/artwork/artwork_errors.dart';
import 'package:phonolite_app/ui/shared/music/artwork/artwork_scope.dart';
import 'package:phonolite_app/ui/shared/music/artwork/authenticated_network_image.dart';

Future<void> precacheImages(BuildContext context, Iterable<String> urls) async {
  if (!shouldPrecacheImages()) {
    return;
  }
  final loader = ArtworkScope.maybeOf(context);
  if (loader == null) {
    return;
  }

  for (final url in urls) {
    try {
      await precacheImage(
        AuthenticatedNetworkImage(url, loader: loader),
        context,
        onError: (error, _) => ArtworkErrors.instance.report(url, error),
      );
    } on Object catch (error) {
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
