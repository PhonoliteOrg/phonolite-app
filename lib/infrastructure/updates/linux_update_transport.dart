import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

class LinuxUpdateTransport {
  final http.Client Function() _createClient;
  http.Client? _client;
  int _generation = 0;
  void Function()? _interrupt;

  LinuxUpdateTransport({http.Client Function()? createClient})
    : _createClient = createClient ?? (() => IOClient(_PublicUpdateHttpOverrides().createHttpClient(null)));

  void cancel() {
    ++_generation;
    _interrupt?.call();
    _client?.close();
    _client = null;
  }

  Future<List<int>> metadata(Uri url, {int maximum = 1024 * 1024}) async {
    final bytes = <int>[];
    await _read(url, maximum: maximum, deadline: const Duration(seconds: 30), onChunk: bytes.addAll);
    return bytes;
  }

  Future<void> download(
    Uri url,
    File destination, {
    required int length,
    required String digest,
    required void Function(double) onProgress,
  }) async {
    final output = destination.openWrite();
    final hash = _DigestReceiver();
    final hashing = sha256.startChunkedConversion(hash);
    var received = 0;
    try {
      await _read(
        url,
        maximum: length,
        deadline: const Duration(minutes: 15),
        onChunk: (bytes) async {
          received += bytes.length;
          output.add(bytes);
          hashing.add(bytes);
          await output.flush();
          onProgress(received / length);
        },
      );
      hashing.close();
      await output.flush();
      await output.close();
      if (received != length || hash.value?.toString() != digest) {
        throw const FormatException('The package does not match its signed length and digest.');
      }
    } catch (_) {
      await output.close();
      if (await destination.exists()) {
        await destination.delete();
      }
      rethrow;
    }
  }

  Future<void> _read(
    Uri url, {
    required int maximum,
    required Duration deadline,
    required FutureOr<void> Function(List<int>) onChunk,
  }) async {
    final client = _createClient();
    final generation = _generation;
    _client = client;
    final interruption = Completer<void>();
    var interrupted = false;
    void stop(Object error) {
      interrupted = true;
      if (!interruption.isCompleted) interruption.completeError(error);
      client.close();
    }

    _interrupt = () => stop(const UpdateDownloadCancelled());
    final timer = Timer(deadline, () => stop(TimeoutException('The update download exceeded its deadline.')));
    Future<void> readResponse() async {
      var uri = url;
      for (var redirect = 0; redirect <= 5; ++redirect) {
        if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty || uri.hasFragment) {
          throw const FormatException('Update requests and redirects must use HTTPS without credentials or fragments.');
        }
        final response = await client
            .send(http.Request('GET', uri)..followRedirects = false)
            .timeout(const Duration(seconds: 15));
        if ({301, 302, 303, 307, 308}.contains(response.statusCode)) {
          await response.stream.listen((_) {}).cancel();
          final location = response.headers['location'];
          if (location == null) {
            throw const FormatException('An update redirect has no destination.');
          }
          uri = uri.resolve(location);
          continue;
        }
        if (response.statusCode != 200) {
          throw http.ClientException('Update request returned HTTP ${response.statusCode}.');
        }
        if ((response.contentLength ?? 0) > maximum) {
          throw const FormatException('Update response exceeds its size limit.');
        }
        var count = 0;
        await for (final chunk in response.stream.timeout(const Duration(seconds: 30))) {
          if (interrupted || generation != _generation) throw const UpdateDownloadCancelled();
          count += chunk.length;
          if (count > maximum) throw const FormatException('Update response exceeds its size limit.');
          await onChunk(chunk);
        }
        if (interrupted || generation != _generation) throw const UpdateDownloadCancelled();
        return;
      }
      throw const FormatException('Too many update redirects.');
    }

    try {
      await Future.any([readResponse(), interruption.future]);
    } catch (_) {
      if (generation != _generation) throw const UpdateDownloadCancelled();
      rethrow;
    } finally {
      interrupted = true;
      timer.cancel();
      _interrupt = null;
      client.close();
      if (identical(_client, client)) _client = null;
    }
  }
}

class UpdateDownloadCancelled implements Exception {
  const UpdateDownloadCancelled();
  @override
  String toString() => 'Update download cancelled.';
}

class _DigestReceiver implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

// Bypass the music-server HttpOverrides while retaining normal system CA checks.
class _PublicUpdateHttpOverrides extends HttpOverrides {}
