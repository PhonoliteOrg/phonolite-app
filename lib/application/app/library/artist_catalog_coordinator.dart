part of '../app_controller.dart';

/// Owns the compact selection roster independently of the bounded browse window.
class _ArtistCatalogCoordinator {
  final _LibraryCoordinator _library;
  final AppController _host;
  List<Artist> artists = [];
  int offset = 0;
  bool hasMore = true;
  final requests = RequestGeneration();
  Completer<void>? _pageCompleter;
  final _rosterIndices = <String, int>{};
  String? _rosterRevision;
  late final details = ArtistMetadataRepository(
    fetch: _host.connection.fetchArtistById,
    sessionRevision: () => _host.connection.sessionRevision,
  );
  late final browse = ArtistBrowseRepository(
    fetch: _host.connection.fetchArtistSummariesPage,
    sessionRevision: () => _host.connection.sessionRevision,
    onPage: _refreshKnownSummaries,
  );
  StreamSubscription<ArtistBrowseSnapshot>? _browseSubscription;
  late final offlineRepairs = OfflineArtistMetadataRepairQueue(
    repair: _host._offlineDownloadManager.refreshOfflineMetadataForArtist,
    isDownloaded: (id) => _host.offlineLibrarySnapshot.artistGroups.any((artist) => artist.id == id),
    downloadedArtistAt: (index) {
      final groups = _host.offlineLibrarySnapshot.artistGroups;

      return index < groups.length ? groups[index].id : null;
    },
    onError: (error) => AppLogger.debug('Offline artist metadata repair failed (${error.runtimeType})'),
  );

  _ArtistCatalogCoordinator(this._library, this._host);

  Future<void> close() async {
    await Future.wait([
      if (_browseSubscription != null) _browseSubscription!.cancel(),
      offlineRepairs.close(),
      browse.close(),
      details.close(),
    ]);
  }

  void reset() {
    requests.advance();
    browse.reset();
    details.reset();
    offlineRepairs.reset();
    artists = [];
    _rosterIndices.clear();
    _rosterRevision = null;
    offset = 0;
    hasMore = true;
  }

  Future<void> load({bool refresh = false}) async {
    if (!_host._requireServer('loading artists')) {
      return;
    }

    _listen();

    if (refresh) {
      await _pageCompleter?.future;
      reset();
      _publishRoster();
    }

    if (artists.isEmpty && hasMore) {
      await loadMore();
    }
  }

  Future<void> loadIndex(int index) async {
    if (!_host._requireServer('loading artists')) {
      return;
    }

    _listen();

    try {
      await browse.loadIndex(index);
    } on ApiException catch (error) {
      _host._handleApiError(error, context: 'artists');
    } catch (error) {
      if (!_host._disposed) {
        AppLogger.debug('Artist browse page unavailable (${error.runtimeType})');
      }
    }
  }

  Future<void> loadMore() async {
    if (!_host._requireServer('loading artists') || !hasMore) {
      return;
    }

    final existing = _pageCompleter;

    if (existing != null) {
      await existing.future;

      return;
    }

    _listen();
    final completer = Completer<void>();
    final generation = requests.current;
    final session = _host.connection.sessionRevision;
    _pageCompleter = completer;
    _library._setArtistsLoading(true);

    try {
      // Full-roster consumers still page sequentially, retaining only compact values.
      var requestedOffset = offset;
      ArtistSummaryPage page;

      try {
        page = await _host.connection.fetchArtistSummariesPage(
          limit: ServerConnection.artistsPageSize,
          offset: requestedOffset,
          revision: _rosterRevision,
        );
      } on ApiException catch (error) {
        if (error.statusCode != 409) {
          rethrow;
        }

        requestedOffset = 0;
        page = await _host.connection.fetchArtistSummariesPage(limit: ServerConnection.artistsPageSize);
      }

      if (_host._disposed || session != _host.connection.sessionRevision || !requests.isCurrent(generation)) {
        return;
      }

      _acceptPage(page);
      browse.retainPage(requestedOffset, page);
      offset = page.nextOffset ?? page.total;
      hasMore = page.nextOffset != null;
    } on ApiException catch (error) {
      if (!_host._disposed && requests.isCurrent(generation)) {
        _host._handleApiError(error, context: 'artists');
      }
    } catch (error) {
      if (!_host._disposed && requests.isCurrent(generation)) {
        _host._pushMessage('Failed to load artists: $error', level: LogLevel.warning);
      }
    } finally {
      if (identical(_pageCompleter, completer)) {
        _pageCompleter = null;
      }

      completer.complete();
      _library._setArtistsLoading(false);
    }
  }

  Future<void> loadAll() async {
    await load();

    while (hasMore && !_host._disposed && _host._authState.isAuthorized) {
      final before = offset;
      await loadMore();

      if (offset == before) {
        break;
      }
    }
  }

  void updateArtist(Artist artist) {
    details.retain(artist);
    final index = _rosterIndices[artist.id];

    if (index != null && index < artists.length) {
      final next = [...artists];
      next[index] = ArtistSummary.fromArtist(artist).toArtist();
      artists = next;
      _publishRoster();
    }
  }

  void _listen() {
    _browseSubscription ??= browse.changes.listen((_) {
      // Existing artist-list observers also rebuild when a materialized page changes.
      _publishRoster();
    });
  }

  void _acceptPage(ArtistSummaryPage page) {
    if (_rosterRevision != null && _rosterRevision != page.browseRevision) {
      artists = [];
      _rosterIndices.clear();
      offset = 0;
      hasMore = true;
    }

    _rosterRevision = page.browseRevision;
    final next = [...artists];

    for (final summary in page.items) {
      final index = _rosterIndices[summary.id];
      final compact = summary.toArtist();

      if (index == null) {
        _rosterIndices[summary.id] = next.length;
        next.add(compact);
      } else if (index < next.length) {
        next[index] = compact;
      }
    }

    artists = next;
    artists.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _rosterIndices.clear();

    for (var index = 0; index < artists.length; index++) {
      _rosterIndices[artists[index].id] = index;
    }

    _publishRoster();
  }

  void _refreshKnownSummaries(ArtistSummaryPage page) {
    if (_rosterRevision != null && _rosterRevision != page.browseRevision) {
      artists = [];
      _rosterIndices.clear();
      offset = 0;
      hasMore = true;
    }

    _rosterRevision = page.browseRevision;
    final known = page.items.where((summary) => _rosterIndices.containsKey(summary.id)).toList();

    if (known.isNotEmpty) {
      _acceptPage(
        ArtistSummaryPage(
          items: known,
          total: page.total,
          nextOffset: page.nextOffset,
          browseRevision: page.browseRevision,
        ),
      );
    }
  }

  void _publishRoster() {
    if (!_host._disposed && !_library._artistsController.isClosed) {
      _library._artistsController.add(List.unmodifiable(artists));
    }
  }
}
