import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:phonolite_app/data/models/artwork/artwork_request.dart';
import 'package:phonolite_app/data/rules/artwork/encoded_artwork.dart';
import 'package:phonolite_app/data/storage/artwork/artwork_disk_cache.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';

/// Shared trusted artwork execution. At most four loads run and 32 wait;
/// simultaneous same-key consumers share bytes without adding queue entries.
/// The creator closes this owner before closing its borrowed server transport.
class ManagedArtworkLoader implements ArtworkLoader {
  static const int maximumActive = 4;
  static const int maximumQueued = 32;
  static const Duration _bodyTimeout = Duration(seconds: 12);

  final ServerConnection connection;
  final String? Function()? accountScope;
  final ArtworkDiskCache disk;
  final DateTime Function() now;
  final Queue<_ArtworkLoad> _queue = Queue<_ArtworkLoad>();
  final Map<String, _ArtworkLoad> _pending = {};
  final Set<Future<void>> _running = {};
  final Queue<_ArtworkDecode> _decodeQueue = Queue<_ArtworkDecode>();
  final Set<Future<void>> _decodes = {};
  final Expando<_DeliveredArtwork> _delivered = Expando<_DeliveredArtwork>();
  int _active = 0;
  int _activeDecodes = 0;
  bool _closed = false;

  ManagedArtworkLoader({required this.connection, this.accountScope, ArtworkDiskCache? disk, DateTime Function()? now})
    : disk = disk ?? ArtworkDiskCache(),
      now = now ?? DateTime.now;

  @override
  String get cacheScope => _digest([
    connection.baseUrl,
    connection.trust?.opaqueKey ?? '',
    connection.trust?.spki ?? '',
    accountScope?.call() ?? _digest([connection.token ?? 'anonymous']),
  ]);

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }

    _closed = true;

    for (final load in _queue) {
      load.result.completeError(const ArtworkLoadException());
      _pending.remove(load.key);
    }

    _queue.clear();

    for (final decode in _decodeQueue) {
      decode.reject();
    }

    _decodeQueue.clear();
    await Future.wait(_running.toList());
    await Future.wait(_decodes.toList());
    await disk.close();
  }

  @override
  Future<Uint8List> load(ArtworkRequest request) {
    if (_closed) {
      return Future.error(const ArtworkLoadException());
    }

    final source = _rendition(request.source, request.decodeSize);
    final scope = cacheScope;
    final key = _digest([scope, source]);
    final existing = _pending[key];

    if (existing != null) {
      if (existing.consumers >= 32) {
        return Future.error(const ArtworkLoadException(statusCode: 503, retryAfter: Duration(seconds: 2)));
      }

      existing.consumers++;
      return _forConsumer(existing, request);
    }

    if (_active >= maximumActive && _queue.length >= maximumQueued) {
      return Future.error(const ArtworkLoadException(statusCode: 503, retryAfter: Duration(seconds: 2)));
    }

    final load = _ArtworkLoad(
      key: key,
      source: source,
      scope: scope,
      session: connection.sessionRevision,
      request: request,
    );
    _pending[key] = load;
    _queue.add(load);
    _drain();

    return _forConsumer(load, request);
  }

  Future<Uint8List> _forConsumer(_ArtworkLoad load, ArtworkRequest request) async {
    final bytes = await load.result.future;
    final digest = load.contentDigest ??= sha256.convert(bytes).toString();
    _delivered[request] = _DeliveredArtwork(scope: load.scope, key: load.key, digest: digest);
    return bytes;
  }

  @override
  Future<void> invalidate(ArtworkRequest request) async {
    final delivered = _delivered[request];
    if (delivered == null || delivered.scope != cacheScope) {
      return;
    }
    await disk.remove(delivered.key, expectedDigest: delivered.digest);
  }

  @override
  Future<T> decode<T>(String scope, Future<T> Function() operation) {
    if (_closed || scope != cacheScope) {
      return Future.error(const ArtworkLoadException());
    }

    if (_activeDecodes >= 2 && _decodeQueue.length >= maximumQueued) {
      return Future.error(const ArtworkLoadException(statusCode: 503, retryAfter: Duration(seconds: 2)));
    }

    final result = Completer<T>();
    _decodeQueue.add(
      _ArtworkDecode(
        scope: scope,
        run: () async {
          try {
            result.complete(await operation());
          } catch (error, stack) {
            result.completeError(error, stack);
          }
        },
        reject: () => result.completeError(const ArtworkLoadException()),
      ),
    );
    _drainDecodes();

    return result.future;
  }

  void _drainDecodes() {
    while (!_closed && _activeDecodes < 2 && _decodeQueue.isNotEmpty) {
      final decode = _decodeQueue.removeFirst();

      if (decode.scope != cacheScope) {
        decode.reject();

        continue;
      }

      _activeDecodes++;
      late final Future<void> operation;
      operation = decode.run().whenComplete(() {
        _activeDecodes--;
        _decodes.remove(operation);
        _drainDecodes();
      });
      _decodes.add(operation);
    }
  }

  void _drain() {
    while (!_closed && _active < maximumActive && _queue.isNotEmpty) {
      final load = _queue.removeFirst();
      _active++;
      late final Future<void> operation;
      operation = _read(load).whenComplete(() => _running.remove(operation));
      _running.add(operation);
    }
  }

  bool _isCurrent(_ArtworkLoad load) =>
      !_closed && load.session == connection.sessionRevision && load.scope == cacheScope;

  Future<void> _read(_ArtworkLoad load) async {
    try {
      if (!_isCurrent(load)) {
        throw const ArtworkLoadException();
      }

      final uri = Uri.tryParse(load.source);
      final remote = uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
      final bytes = remote ? await _remote(load) : await _file(load.source);

      if (!_isCurrent(load)) {
        throw const ArtworkLoadException();
      }

      load.result.complete(bytes);
    } catch (error, stack) {
      load.result.completeError(error, stack);
    } finally {
      _pending.remove(load.key);
      _active--;
      _drain();
    }
  }

  Future<Uint8List> _remote(_ArtworkLoad load) async {
    final authorization = load.request.headers['Authorization'];

    if (authorization != null && authorization != 'Bearer ${connection.token}') {
      throw const ArtworkLoadException(statusCode: 401);
    }

    StoredArtwork? stored;

    try {
      stored = await disk.read(load.key);
    } on FileSystemException {
      // The network remains usable when the disposable cache is unavailable.
    }

    if (!_isCurrent(load)) {
      throw const ArtworkLoadException();
    }

    if (stored != null && stored.expiresAt.isAfter(now())) {
      return stored.bytes;
    }

    final response = await connection.openArtwork(
      load.source,
      headers: {if (stored?.etag != null) HttpHeaders.ifNoneMatchHeader: stored!.etag!},
    );

    if (response.statusCode == 304 && stored != null) {
      await response.stream.listen((_) {}).cancel();

      return stored.bytes;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.stream.listen((_) {}).cancel();
      final seconds = int.tryParse(response.headers[HttpHeaders.retryAfterHeader] ?? '');

      throw ArtworkLoadException(
        statusCode: response.statusCode,
        retryAfter: seconds == null ? null : Duration(seconds: seconds.clamp(1, 60)),
      );
    }

    if ((response.contentLength ?? 0) > ArtworkDiskCache.maximumImageBytes) {
      await response.stream.listen((_) {}).cancel();

      throw const ArtworkLoadException(statusCode: 413);
    }

    // IOClient may expose decompressed bytes while retaining the encoded
    // Content-Length. Compare lengths only for an identity representation.
    final encoding = response.headers[HttpHeaders.contentEncodingHeader]?.trim().toLowerCase();
    final expectedLength = encoding == null || encoding.isEmpty || encoding == 'identity'
        ? response.contentLength
        : null;
    final bytes = await _collect(response.stream, expectedLength: expectedLength);

    if (!hasCompleteArtworkBytes(bytes)) {
      throw const ArtworkLoadException();
    }

    if (!_isCurrent(load)) {
      throw const ArtworkLoadException();
    }

    final policy = response.headers[HttpHeaders.cacheControlHeader] ?? '';

    if (!policy.contains('no-store')) {
      try {
        await disk.write(
          load.key,
          StoredArtwork(
            bytes: bytes,
            expiresAt: now().add(_freshness(policy)),
            etag: response.headers[HttpHeaders.etagHeader],
          ),
        );
      } on FileSystemException {
        // Persistence is optional; successful downloaded bytes are still usable.
      }
    }

    return bytes;
  }

  static Future<Uint8List> _file(String source) async => _collect(File(source).openRead());

  static Future<Uint8List> _collect(Stream<List<int>> chunks, {int? expectedLength}) async {
    final result = BytesBuilder(copy: false);
    final elapsed = Stopwatch()..start();
    final iterator = StreamIterator(chunks);

    try {
      while (true) {
        final remaining = _bodyTimeout - elapsed.elapsed;

        if (remaining <= Duration.zero) {
          throw TimeoutException('Artwork body deadline exceeded');
        }

        if (!await iterator.moveNext().timeout(remaining)) {
          break;
        }

        final chunk = iterator.current;

        if (result.length + chunk.length > ArtworkDiskCache.maximumImageBytes) {
          throw const ArtworkLoadException(statusCode: 413);
        }

        result.add(chunk);
        if (expectedLength != null && result.length > expectedLength) {
          throw const ArtworkLoadException();
        }
      }
    } finally {
      await iterator.cancel();
    }

    if (result.isEmpty || (expectedLength != null && result.length != expectedLength)) {
      throw const ArtworkLoadException();
    }

    return result.takeBytes();
  }

  static String _rendition(String source, int? size) {
    final uri = Uri.tryParse(source);

    if (size == null || uri == null || !uri.path.contains('/library/artists/') || !uri.path.endsWith('/cover')) {
      return source;
    }

    final bucket = size <= 128
        ? 128
        : size <= 256
        ? 256
        : 512;

    return uri.replace(queryParameters: {...uri.queryParameters, 'size': '$bucket', 'rendition': '1'}).toString();
  }

  static Duration _freshness(String cacheControl) {
    if (cacheControl.contains('no-cache')) {
      return Duration.zero;
    }

    final seconds = int.tryParse(RegExp(r'max-age=(\d+)').firstMatch(cacheControl)?.group(1) ?? '');

    if (seconds != null) {
      return Duration(seconds: seconds.clamp(0, 365 * 24 * 60 * 60));
    }

    return const Duration(minutes: 5);
  }

  static String _digest(List<String> parts) => sha256.convert(utf8.encode(jsonEncode(parts))).toString();
}

class _ArtworkLoad {
  final String key;
  final String source;
  final String scope;
  final int session;
  final ArtworkRequest request;
  String? contentDigest;
  final Completer<Uint8List> result = Completer<Uint8List>();
  int consumers = 1;

  _ArtworkLoad({
    required this.key,
    required this.source,
    required this.scope,
    required this.session,
    required this.request,
  });
}

class _DeliveredArtwork {
  final String scope;
  final String key;
  final String digest;

  const _DeliveredArtwork({required this.scope, required this.key, required this.digest});
}

class _ArtworkDecode {
  final String scope;
  final Future<void> Function() run;
  final void Function() reject;

  const _ArtworkDecode({required this.scope, required this.run, required this.reject});
}
