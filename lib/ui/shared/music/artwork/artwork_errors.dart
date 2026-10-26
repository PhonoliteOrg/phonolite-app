import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'package:phonolite_app/application/controllers/library/artwork_error_controller.dart';
import 'package:phonolite_app/data/models/artwork/artwork_request.dart';

class ArtworkErrors extends ArtworkErrorController {
  static final ArtworkErrors instance = ArtworkErrors();

  ArtworkErrors({super.logger, super.now});

  @override
  void report(String source, Object error, {int? status}) => super.report(
    source,
    error,
    status:
        status ??
        (error is NetworkImageLoadException
            ? error.statusCode
            : error is ArtworkLoadException
            ? error.statusCode
            : null),
  );

  /// Handle only network-image resource failures; other framework exceptions
  /// must still reach Flutter's normal error handler.
  bool handleFlutterError(FlutterErrorDetails details) {
    final error = details.exception;

    if (details.library != 'image resource service' || error is! NetworkImageLoadException) {
      return false;
    }

    report(error.uri.toString(), error);

    return true;
  }
}

void installArtworkErrorHandler() {
  final previous = FlutterError.onError;

  FlutterError.onError = (details) {
    if (ArtworkErrors.instance.handleFlutterError(details)) {
      return;
    }

    (previous ?? FlutterError.presentError)(details);
  };
}
