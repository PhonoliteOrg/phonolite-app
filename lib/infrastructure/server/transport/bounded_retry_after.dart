import 'package:http/http.dart' as http;

import 'package:phonolite_app/infrastructure/server/transport/api_response_decoder.dart';

/// The server's requested cooldown, bounded to between one second and one minute.
///
/// Artwork consumers schedule their own retry from it, so a missing or
/// malformed value stays null and they keep their usual delay.
Duration? boundedRetryAfter(http.BaseResponse response) {
  final delay = const ApiResponseDecoder().retryAfter(response);

  if (delay == null) {
    return null;
  }

  if (delay < const Duration(seconds: 1)) {
    return const Duration(seconds: 1);
  }

  if (delay > const Duration(minutes: 1)) {
    return const Duration(minutes: 1);
  }

  return delay;
}
