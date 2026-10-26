import 'dart:async';
import 'dart:collection';

import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/server/server_errors.dart';
import 'package:phonolite_app/data/structures/library/byte_lru_cache.dart';

/// Session-owned detail reads with bounded retained metadata and pending work.
/// Cached missing logos survive viewport changes; invalidation fences old fills.
class ArtistMetadataRepository {
  final Future<Artist> Function(String) fetch;
  final int Function() sessionRevision;
  final DateTime Function() now;
  final Duration detailTtl;
  final Duration missingArtworkTtl;
  final int concurrency;
  final int maxQueued;
  final ByteLruCache<String, ({Artist? artist, int? status, DateTime expires})> _cache;
  final _requests = <String, Completer<Artist>>{};
  final _queue = Queue<({String id, Completer<Artist> result, int generation})>();
  final _active = <Future<void>>{};
  int? _session;
  int _generation = 0;
  bool _closed = false;

  ArtistMetadataRepository({
    required this.fetch,
    required this.sessionRevision,
    DateTime Function()? now,
    this.detailTtl = const Duration(minutes: 5),
    this.missingArtworkTtl = const Duration(seconds: 30),
    this.concurrency = 3,
    this.maxQueued = 32,
    int maxBytes = 2 * 1024 * 1024,
    int maxEntries = 128,
  }) : assert(concurrency > 0),
       assert(maxQueued >= 0),
       now = now ?? DateTime.now,
       _cache = ByteLruCache(maxBytes: maxBytes, maxEntries: maxEntries, sizeOf: _sizeOf);

  int get retainedBytes => _cache.bytes;

  int get retainedEntries => _cache.length;

  int get activeReads => _active.length;

  int get queuedReads => _queue.length;

  bool contains(String id) {
    _syncSession();

    return _cache.get(id) != null || _requests.containsKey(id);
  }

  Future<void> close() async {
    _closed = true;
    reset();
    await Future.wait(_active.toList());
  }

  Future<Artist> load(String id, {bool refresh = false}) {
    _syncSession();

    if (_closed) {
      return Future.error(StateError('Artist metadata repository is closed'));
    }

    final cached = _cache.get(id);

    if (!refresh && cached != null && now().isBefore(cached.expires)) {
      final artist = cached.artist;

      return artist != null
          ? Future.value(artist)
          : Future.error(
              ApiException(
                cached.status ?? 503,
                'Artist metadata temporarily unavailable',
                retryAfter: cached.expires.difference(now()),
              ),
            );
    }

    final pending = _requests[id];

    if (pending != null) {
      return pending.future;
    }

    if (_active.length >= concurrency && _queue.length >= maxQueued) {
      return Future.error(StateError('Artist metadata capacity reached'));
    }

    final result = Completer<Artist>();
    _requests[id] = result;
    _queue.add((id: id, result: result, generation: _generation));
    _drain();

    return result.future;
  }

  void invalidate(String id) {
    _syncSession();
    _cache.remove(id);
    _requests.remove(id);
    final queued = _queue.where((work) => work.id == id).toList();

    for (final work in queued) {
      _queue.remove(work);
      work.result.completeError(StateError('Artist metadata read superseded'));
    }
  }

  void retain(Artist artist) {
    _syncSession();
    final ttl = artist.logoRef?.trim().isNotEmpty == true ? detailTtl : missingArtworkTtl;
    _cache.put(artist.id, (artist: artist, status: null, expires: now().add(ttl)));
  }

  void reset() {
    _generation++;
    _cache.clear();

    for (final work in _queue) {
      _requests.remove(work.id);
      work.result.completeError(StateError('Artist metadata session changed'));
    }

    _queue.clear();
    _requests.clear();
  }

  void _syncSession() {
    final revision = sessionRevision();

    if (_session != revision) {
      _session = revision;
      reset();
    }
  }

  void _drain() {
    while (!_closed && _active.length < concurrency && _queue.isNotEmpty) {
      final work = _queue.removeFirst();
      late final Future<void> operation;
      operation = _read(work).whenComplete(() {
        _active.remove(operation);
        _drain();
      });
      _active.add(operation);
    }
  }

  Future<void> _read(({String id, Completer<Artist> result, int generation}) work) async {
    try {
      final artist = await fetch(work.id);
      _syncSession();

      if (_closed || work.generation != _generation || !identical(_requests[work.id], work.result)) {
        throw StateError('Artist metadata read superseded');
      }

      retain(artist);
      work.result.complete(artist);
    } catch (error, stack) {
      if (!_closed &&
          work.generation == _generation &&
          identical(_requests[work.id], work.result) &&
          error is ApiException &&
          const [404, 410, 429, 503].contains(error.statusCode)) {
        _cache.put(work.id, (
          artist: null,
          status: error.statusCode,
          expires: now().add(error.retryAfter ?? missingArtworkTtl),
        ));
      }

      work.result.completeError(error, stack);
    } finally {
      if (identical(_requests[work.id], work.result)) {
        _requests.remove(work.id);
      }
    }
  }

  static int _sizeOf(String id, ({Artist? artist, int? status, DateTime expires}) entry) {
    final artist = entry.artist;

    if (artist == null) {
      return 256 + id.length * 2;
    }

    return 512 +
        2 *
            (id.length +
                artist.id.length +
                artist.name.length +
                (artist.summary?.length ?? 0) +
                (artist.logoRef?.length ?? 0) +
                (artist.bannerRef?.length ?? 0)) +
        artist.genres.fold(0, (bytes, genre) => bytes + 48 + 2 * genre.length);
  }
}
