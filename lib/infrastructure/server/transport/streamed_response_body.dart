import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Releases a streamed response whose body will not be read.
Future<void> discardResponseBody(http.StreamedResponse response) => response.stream.listen((_) {}).cancel();

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
