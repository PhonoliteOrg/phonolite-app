import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:phonolite_app/data/storage/logs/app_log.dart';

bool _installed = false;

/// Routes framework and uncaught asynchronous errors to the app log, as Flutter's error-handling
/// guidance expects (see [FlutterError.onError] and [PlatformDispatcher.onError]). Without this,
/// release builds only print them to stderr, which desktop GUI builds never show.
///
/// Install before handlers that filter specific errors, so those filters run first and only
/// unfiltered errors are reported here.
void installAppErrorReporting() {
  if (_installed) {
    return;
  }

  _installed = true;

  final previous = FlutterError.onError;

  FlutterError.onError = (details) {
    AppLogger.error('Unexpected interface error: ${details.exceptionAsString()}');
    AppLogger.debug(details.toString());

    (previous ?? FlutterError.presentError)(details);
  };

  PlatformDispatcher.instance.onError = (error, stackTrace) {
    AppLogger.error('Unexpected error: $error');
    AppLogger.debug('$stackTrace');

    return true;
  };

  if (kReleaseMode) {
    // The default release ErrorWidget is a blank grey box; say what happened instead.
    ErrorWidget.builder = (_) => const _ReleaseErrorWidget();
  }
}

class _ReleaseErrorWidget extends StatelessWidget {
  const _ReleaseErrorWidget();

  @override
  Widget build(BuildContext context) {
    // The failing subtree may have no Directionality or theme above it.
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: Color(0xFF050505),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Something went wrong here. Details are in the app log.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF8A8A9A), fontSize: 13),
            ),
          ),
        ),
      ),
    );
  }
}
