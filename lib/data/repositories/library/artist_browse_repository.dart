import 'dart:async';
import 'dart:collection';

import 'package:phonolite_app/data/models/library/artist_browse_snapshot.dart';
import 'package:phonolite_app/data/models/library/artist_summary.dart';
import 'package:phonolite_app/data/models/server/server_errors.dart';
import 'package:phonolite_app/data/structures/library/byte_lru_cache.dart';

typedef ArtistSummaryPageFetcher =
    Future<ArtistSummaryPage> Function({required int limit, required int offset, String? revision});

/// One logical catalogue with a byte/count-bounded materialized window.
/// Index identity and total survive page eviction. Snapshots do not replay.
class ArtistBrowseRepository {
  final ArtistSummaryPageFetcher fetch;
  final int Function() sessionRevision;
  final void Function(ArtistSummaryPage)? onPage;
  final int pageSize;
  final int concurrency;
  final int maxQueued;
  final ByteLruCache<int, ArtistSummaryPage> _pages;
  final _changes = StreamController<ArtistBrowseSnapshot>.broadcast();
  final _pending = <int, Completer<void>>{};
  final _queue = Queue<({int page, Completer<void> result, int generation})>();
  final _active = <Future<void>>{};
  final _metadataMutations = ByteLruCache<String, int>(
    maxBytes: 128 * 1024,
    maxEntries: 512,
    sizeOf: (id, _) => 96 + id.length * 2,
  );
  int _metadataEpoch = 0;
  int _mutationFloor = 0;
  int? _session;
  int _generation = 0;
  int _total = 0;
  String? _revision;
  bool _closed = false;

  ArtistBrowseRepository({
    required this.fetch,
    required this.sessionRevision,
    this.onPage,
    this.pageSize = 60,
    this.concurrency = 2,
    this.maxQueued = 16,
    int maxPages = 12,
    int maxBytes = 4 * 1024 * 1024,
  }) : assert(pageSize > 0),
       assert(concurrency > 0),
       assert(maxQueued >= 0),
       _pages = ByteLruCache(maxBytes: maxBytes, maxEntries: maxPages, sizeOf: (_, page) => page.retainedBytes + 64);

  Stream<ArtistBrowseSnapshot> get changes => _changes.stream;

  ArtistBrowseSnapshot get current => ArtistBrowseSnapshot(
    total: _total,
    pageSize: pageSize,
    revision: _revision,
    pages: Map.unmodifiable({for (final key in _pages.keys) key: _pages.get(key)!}),
    loadingPages: Set.unmodifiable(_pending.keys),
    retainedBytes: _pages.bytes,
  );

  Future<void> close() async {
    _closed = true;
    reset();
    await Future.wait(_active.toList());
    await _changes.close();
  }

  Future<void> loadIndex(int index, {bool refresh = false}) {
    _syncSession();

    if (_closed || index < 0 || (_total > 0 && index >= _total)) {
      return Future.value();
    }

    final page = index ~/ pageSize;

    if (!refresh && _pages.get(page) != null) {
      return Future.value();
    }

    final existing = _pending[page];

    if (existing != null) {
      return existing.future;
    }

    if (_active.length >= concurrency && _queue.length >= maxQueued) {
      if (_queue.isEmpty) {
        return Future.error(StateError('Artist browse capacity reached'));
      }

      // A newly visible page takes precedence over an older queued viewport.
      // Active requests retain their bounded shared transport ownership.
      final obsolete = _queue.removeLast();
      _pending.remove(obsolete.page);
      obsolete.result.complete();
    }

    final result = Completer<void>();
    _pending[page] = result;
    _queue.addFirst((page: page, result: result, generation: _generation));
    _publish();
    _drain();

    return result.future;
  }

  void retainPage(int offset, ArtistSummaryPage page) {
    _syncSession();

    if (_revision != null && _revision != page.browseRevision) {
      _pages.clear();
    }

    _revision = page.browseRevision;
    _total = page.total;
    _pages.put(offset ~/ pageSize, page);
    _publish();
  }

  void invalidateArtist(String id) {
    _metadataEpoch++;

    if (_metadataMutations.length >= 512) {
      _mutationFloor = _metadataEpoch;
      _metadataMutations.clear();
    }

    _metadataMutations.put(id, _metadataEpoch);
    final affected = <int>[];

    for (final page in _pages.keys) {
      if (_pages.get(page)!.items.any((artist) => artist.id == id)) {
        affected.add(page);
      }
    }

    for (final page in affected) {
      _pages.remove(page);
    }

    _publish();
  }

  /// Retains logical positions but releases materialized pages. Visible
  /// placeholders request only the window the user is currently observing.
  void reconcile() {
    _generation++;
    _pages.clear();

    for (final work in _queue) {
      work.result.complete();
    }

    _queue.clear();
    _pending.clear();
    _publish();
  }

  void reset() {
    _generation++;
    _pages.clear();
    _revision = null;
    _total = 0;
    _metadataMutations.clear();
    _metadataEpoch = 0;
    _mutationFloor = 0;

    for (final work in _queue) {
      work.result.complete();
    }

    _queue.clear();
    _pending.clear();
    _publish();
  }

  void _syncSession() {
    final revision = sessionRevision();

    if (_session != revision) {
      _session = revision;
      reset();
    }
  }

  void _publish() {
    if (!_closed) {
      _changes.add(current);
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

  Future<void> _read(({int page, Completer<void> result, int generation}) work) async {
    var generation = work.generation;

    try {
      ArtistSummaryPage? page;
      var metadataEpoch = _metadataEpoch;
      var revision = _revision;

      for (var attempt = 0; attempt < 4; attempt++) {
        ArtistSummaryPage response;

        try {
          response = await fetch(limit: pageSize, offset: work.page * pageSize, revision: revision);
        } on ApiException catch (error) {
          if (error.statusCode != 409 || generation != _generation) {
            rethrow;
          }

          // Ordering changed. Fence every old ordering fill before allowing a
          // new version to publish; ordinary metadata events do not enter here.
          generation = ++_generation;
          _pages.clear();
          _revision = null;

          for (final queued in _queue) {
            queued.result.complete();
          }

          _queue.clear();
          _pending.clear();
          _pending[work.page] = work.result;
          revision = null;
          continue;
        }

        _syncSession();

        if (_closed || generation != _generation) {
          break;
        }

        if (_revision != null && _revision != response.browseRevision) {
          // Two initial requests can have begun without a revision. Ask the
          // server to validate the currently published version before accepting
          // a different one; an opaque version cannot be ordered locally.
          revision = _revision;
          continue;
        }

        if (_changedSince(response, metadataEpoch)) {
          metadataEpoch = _metadataEpoch;
          revision = response.browseRevision;
          continue;
        }

        page = response;
        break;
      }

      if (page != null && !_closed && generation == _generation) {
        _revision = page.browseRevision;
        _total = page.total;
        _pages.put(work.page, page);
        onPage?.call(page);
      }

      work.result.complete();
    } catch (error, stack) {
      work.result.completeError(error, stack);
    } finally {
      if (identical(_pending[work.page], work.result)) {
        _pending.remove(work.page);
      }

      _publish();
    }
  }

  bool _changedSince(ArtistSummaryPage page, int epoch) =>
      epoch < _mutationFloor || page.items.any((artist) => (_metadataMutations.get(artist.id) ?? 0) > epoch);
}
