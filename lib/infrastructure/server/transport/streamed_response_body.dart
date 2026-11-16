import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:phonolite_app/infrastructure/server/transport/api_response_decoder.dart';

/// Releases a streamed response whose body will not be read.
Future<void> discardResponseBody(http.StreamedResponse response) => response.stream.listen((_) {}).cancel();

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

/// Reads a whole body within one [deadline] across all chunks.
///
/// Throws the error from [tooLarge], given the length the body would have
/// reached, as soon as the body passes [maximumBytes].
/// An empty body returns empty bytes; the caller decides what that means.
Future<Uint8List> readBoundedBody(
  Stream<List<int>> chunks, {
  required Duration deadline,
  required int maximumBytes,
  required Object Function(int length) tooLarge,
}) async {
  final bytes = BytesBuilder(copy: false);
  final elapsed = Stopwatch()..start();
  final iterator = StreamIterator(chunks);

  try {
    while (true) {
      final remaining = deadline - elapsed.elapsed;

      if (remaining <= Duration.zero) {
        throw TimeoutException('Response body deadline exceeded');
      }

      if (!await iterator.moveNext().timeout(remaining)) {
        break;
      }

      final length = bytes.length + iterator.current.length;

      if (length > maximumBytes) {
        throw tooLarge(length);
      }

      bytes.add(iterator.current);
    }
  } finally {
    await iterator.cancel();
  }

  return bytes.takeBytes();
}
