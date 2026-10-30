import 'dart:async';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/feature_controller.dart';
import 'package:phonolite_app/application/controllers/shared/controller_selection.dart';
import 'package:phonolite_app/application/downloads/downloaded_track_selection.dart';
import 'package:phonolite_app/application/library/artist_artwork_diagnostics.dart';
import 'package:phonolite_app/application/library/visible_artist_loader.dart';
import 'package:phonolite_app/application/workflows/debounced_action.dart';
import 'package:phonolite_app/data/models/downloads/offline_deletion.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/library/search_result.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/projections/library/offline_library_views.dart';
import 'package:phonolite_app/data/queries/library/local_library_search.dart';
import 'package:phonolite_app/data/rules/library/track_identity.dart' as identity;
import 'package:phonolite_app/data/storage/logs/app_log.dart';

class LibraryController extends FeatureController {
  final AppController app;
  String _query = '';
  final _searchDebounce = DebouncedAction();
  bool _requestedServerLoad = false;
  late final _selection = ControllerSelection<String>(update);
  bool _refreshingLibrary = false;
  final _artworkDiagnostics = ArtistArtworkDiagnostics();
  List<Track>? _localSearchTracks;
  List<OfflineArtistGroup>? _localSearchArtists;
  int? _localSearchRevision;
  String? _localSearchQuery;
  List<SearchResult>? _localSearchResults;
  late final _visibleArtists = VisibleArtistLoader(
    fetch: (id) => app.fetchArtistMetadata(id),
    watch: (id) => app.watchArtist(id),
    onChanged: () => update(() {}),
    onError: (id, error) => AppLogger.debug('Visible artist refresh failed for $id (${error.runtimeType})'),
  );
  int? _artistSessionRevision;

  LibraryController(this.app) {
    listenTo(app.authStream, (_) {
      _syncArtistSession();
      loadIfNeeded();
    });
  }

  String get query => _query;

  bool get refreshingLibrary => _refreshingLibrary;

  bool get artistSelectionMode => _selection.active;

  set artistSelectionMode(bool value) => _selection.setActive(value);

  Set<String> get selectedArtistIds => _selection.keys();

  @override
  void dispose() {
    _searchDebounce.cancel();
    _clearLocalSearchCache();
    _visibleArtists.dispose();
    super.dispose();
  }

  void _syncArtistSession() {
    final revision = app.connection.sessionRevision;
    if (_artistSessionRevision != revision || !app.authState.isAuthorized) {
      _artistSessionRevision = revision;
      _clearLocalSearchCache();
      _visibleArtists.clear();
    }
  }

  Artist visibleArtist(Artist artist) => _visibleArtists.resolve(artist);

  void artistVisibilityChanged(Artist artist, bool visible) {
    if (isDisposed) {
      return;
    }
    _syncArtistSession();
    _visibleArtists.setVisible(artist, visible && app.authState.isAuthorized);
  }

  void setQuery(String value) {
    if (_query == value) {
      return;
    }

    update(() => _query = value);
  }

  void loadIfNeeded() {
    if (!app.authState.isAuthorized) {
      _requestedServerLoad = false;

      return;
    }

    if (!_requestedServerLoad && app.artists.isEmpty) {
      _requestedServerLoad = true;
      unawaited(app.loadArtists());
    }
  }

  void loadMoreArtists(double extentAfter) {
    if (_query.trim().isNotEmpty ||
        !app.authState.isAuthorized ||
        app.artistsLoading ||
        !app.hasMoreArtists ||
        extentAfter > 720) {
      return;
    }

    if (app.artistBrowseSnapshot.total > 0) {
      // The windowed viewport requests missing indices directly. Its total
      // already represents the complete catalogue, unlike the compact roster.
      return;
    }

    unawaited(app.loadMoreArtists());
  }

  void clearSearch() {
    _searchDebounce.cancel();
    setQuery('');
    app.search('', filter: 'all');
  }

  /// Published offline snapshots contain immutable lists. Supplying their
  /// revision allows repeated widget builds to reuse one bounded result page.
  /// Callers with mutable lists can omit it and always receive a fresh search.
  List<SearchResult> localResults(List<Track> tracks, List<OfflineArtistGroup> artists, {int? revision}) {
    final query = normalizeLibrarySearch(_query);
    final cached = _localSearchResults;

    if (revision != null &&
        revision == _localSearchRevision &&
        query == _localSearchQuery &&
        identical(tracks, _localSearchTracks) &&
        identical(artists, _localSearchArtists) &&
        cached != null) {
      // Preserve the caller-owned, fixed-length result-list contract without
      // allowing a caller to modify the cached page.
      return List<SearchResult>.of(cached, growable: false);
    }

    final results = searchLocalLibrary(query: _query.trim(), tracks: tracks, artists: artists);

    _clearLocalSearchCache();
    if (revision != null && query.isNotEmpty && !isDisposed) {
      _localSearchTracks = tracks;
      _localSearchArtists = artists;
      _localSearchRevision = revision;
      _localSearchQuery = query;
      _localSearchResults = List<SearchResult>.of(results, growable: false);
    }

    return results;
  }

  void _clearLocalSearchCache() {
    _localSearchTracks = null;
    _localSearchArtists = null;
    _localSearchRevision = null;
    _localSearchQuery = null;
    _localSearchResults = null;
  }

  List<Track> tracksForArtists(List<OfflineArtistGroup> groups) {
    final ids = groups.map(artistSelectionKey).toSet();

    return <String, Track>{
      for (final group in app.offlineLibrarySnapshot.artistGroups)
        if (ids.contains(artistSelectionKey(group)))
          for (final track in group.tracksForArtist) (track.localId ?? track.id): track,
    }.values.toList();
  }

  Future<void> removeArtistDownloads(List<OfflineArtistGroup> groups, String label) async {
    final tracks = tracksForArtists(groups);

    clearArtistSelection();

    try {
      await app.removeDownloadedTracks(
        tracks,
        label: label,
        scope: OfflineDeletionScope.artist(
          id: groups.length == 1 ? groups.single.id : null,
          ids: groups.map((group) => group.id).toList(growable: false),
          label: label,
        ),
      );
    } catch (error) {
      AppLogger.warning('Failed to remove $label: $error');
    }
  }

  Future<void> refreshLibrary(AppController controller) async {
    if (_refreshingLibrary) {
      return;
    }

    update(() => _refreshingLibrary = true);

    try {
      await controller.refreshLibrary();

      if (isDisposed) {
        return;
      }

      final query = _query.trim();

      if (controller.authState.isAuthorized && query.length >= 2) {
        runSearch(controller);
      } else {
        update(() {});
      }
    } finally {
      if (!isDisposed) {
        update(() => _refreshingLibrary = false);
      }
    }
  }

  void runSearch(AppController controller) {
    controller.search(_query.trim(), filter: 'all');
  }

  void queueSearch(AppController controller) {
    final query = _query.trim();

    _searchDebounce.cancel();

    if (query.length < 2) {
      controller.search('', filter: 'all');

      return;
    }

    _searchDebounce.schedule(const Duration(milliseconds: 450), () {
      controller.search(query, filter: 'all');
    });
  }

  List<OfflineArtistGroup> selectedOfflineArtists(List<OfflineArtistGroup> groups) {
    final selected = selectedArtistIds;

    if (selected.isEmpty) {
      return const [];
    }

    return groups
        .where((group) => selected.contains(artistSelectionKey(group)) && group.tracksForArtist.isNotEmpty)
        .toList(growable: false);
  }

  void toggleArtistSelection(OfflineArtistGroup group) {
    final key = artistSelectionKey(group);

    _selection.toggle(key);
  }

  void selectAllArtists(Iterable<String> artistIds) {
    _selection.replace(artistIds);
  }

  void deselectAllArtists() {
    _selection.clear(activate: true);
  }

  void startArtistSelection() {
    _selection.clear(activate: true);
  }

  void clearArtistSelection() {
    _selection.clear();
  }

  String artistSelectionKey(OfflineArtistGroup group) => group.id;

  Set<String> removingTrackIds(AppController controller) {
    return DownloadedTrackSelection(controller).removingIdentities;
  }

  bool groupHasRemovingTracks(OfflineArtistGroup group, Set<String> removingTrackIds) {
    if (removingTrackIds.isEmpty) {
      return false;
    }

    for (final album in group.albums) {
      for (final track in album.tracks) {
        if (trackMatchesAnyIdentity(track, removingTrackIds)) {
          return true;
        }
      }
    }

    return false;
  }

  bool trackMatchesAnyIdentity(Track track, Set<String> ids) {
    return identity.trackMatchesAnyIdentity(track, ids);
  }

  String? artistCoverUrl(AppController controller, Artist artist) {
    _artworkDiagnostics.tile(artist, sessionRevision: controller.connection.sessionRevision);
    if (artist.logoRef == null || artist.logoRef!.isEmpty) {
      return null;
    }

    return controller.connection.buildArtistCoverUrl(artist.id, kind: 'logo', ref: artist.logoRef);
  }
}
