import 'package:flutter/foundation.dart';

import 'package:phonolite_app/ui/shared/music/artwork/artwork_errors.dart';

void installArtworkErrorHandler() {
  final previous = FlutterError.onError;

  FlutterError.onError = (details) {
    if (ArtworkErrors.instance.handleFlutterError(details)) {
      return;
    }

    (previous ?? FlutterError.presentError)(details);
  };
}
