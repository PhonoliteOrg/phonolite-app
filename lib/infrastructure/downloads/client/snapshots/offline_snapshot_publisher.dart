part of 'package:phonolite_app/infrastructure/downloads/client/offline_download_client.dart';

class _OfflineSnapshotPublisher {
  final OfflineDownloadClient _host;
  final StreamController<List<OfflineTrackDownload>> _controller =
      StreamController<List<OfflineTrackDownload>>.broadcast();
  final StreamController<List<OfflineDownloadBatch>> _batchController =
      StreamController<List<OfflineDownloadBatch>>.broadcast();
  final StreamController<List<OfflineDownloadJob>> _jobController =
      StreamController<List<OfflineDownloadJob>>.broadcast();
  final StreamController<List<Track>> _localLikedController = StreamController<List<Track>>.broadcast();
  final StreamController<List<Playlist>> _localPlaylistsController = StreamController<List<Playlist>>.broadcast();
  final StreamController<List<Track>> _localPlaylistTracksController = StreamController<List<Track>>.broadcast();
  final StreamController<OfflineDownloadSnapshot> _downloadSnapshotController =
      StreamController<OfflineDownloadSnapshot>.broadcast();
  final StreamController<OfflineLibrarySnapshot> _librarySnapshotController =
      StreamController<OfflineLibrarySnapshot>.broadcast();
  List<OfflineTrackDownload> _downloads = const <OfflineTrackDownload>[];
  List<OfflineDownloadBatch> _batches = const <OfflineDownloadBatch>[];
  List<OfflineDownloadJob> _jobs = const <OfflineDownloadJob>[];
  List<Track> _localLiked = const <Track>[];
  List<Playlist> _localPlaylists = const <Playlist>[];
  List<Track> _localPlaylistTracks = const <Track>[];
  OfflineDownloadSnapshot _downloadSnapshot = const OfflineDownloadSnapshot(
    downloads: <OfflineTrackDownload>[],
    batches: <OfflineDownloadBatch>[],
    jobs: <OfflineDownloadJob>[],
    revision: 0,
  );
  OfflineLibrarySnapshot _librarySnapshot = const OfflineLibrarySnapshot(
    tracks: <Track>[],
    artistGroups: <offline_views.OfflineArtistGroup>[],
    liked: <Track>[],
    playlists: <Playlist>[],
    playlistTracks: <Track>[],
    revision: 0,
  );
  OfflineDownloadIndex _downloadIndex = OfflineDownloadIndex(const [], trimServerKeys: true);
  bool _disposed = false;
  final List<StreamSubscription<dynamic>> _inlineSubscriptions = <StreamSubscription<dynamic>>[];
  Timer? _inlineDownloadTimer;
  Timer? _inlineLibraryTimer;
  int _inlineRevision = 0;

  _OfflineSnapshotPublisher(this._host);

  void _listenToInlineCore() {
    final core = _host._inlineCore;
    if (core == null) {
      return;
    }

    void scheduleChangedSnapshots(List<OfflineTrackDownload> _) {
      _scheduleInlineDownloadSnapshot();
      _scheduleInlineLibrarySnapshot();
    }

    _inlineSubscriptions.addAll([
      core.stream.listen(scheduleChangedSnapshots),
      core.batchStream.listen((_) => _scheduleInlineDownloadSnapshot()),
      core.jobStream.listen((_) => _scheduleInlineDownloadSnapshot()),
      core.localLikedStream.listen((_) => _scheduleInlineLibrarySnapshot()),
      core.localPlaylistsStream.listen((_) => _scheduleInlineLibrarySnapshot()),
      core.localPlaylistTracksStream.listen((_) => _scheduleInlineLibrarySnapshot()),
    ]);
  }

  void _scheduleInlineDownloadSnapshot() {
    if (_disposed || _inlineDownloadTimer != null) {
      return;
    }

    void publishDownloadSnapshot() {
      _inlineDownloadTimer = null;

      if (_disposed) {
        return;
      }

      _applyDownloadState(
        OfflineActorDownloadState(
          downloads: _host._inlineCore!.downloads,
          batches: _host._inlineCore.batches,
          jobs: _host._inlineCore.jobs,
          revision: ++_inlineRevision,
        ),
      );
    }

    _inlineDownloadTimer = Timer(_OfflineDownloadActorCore._stateEmitCoalesceDelay, publishDownloadSnapshot);
  }

  void _scheduleInlineLibrarySnapshot() {
    if (_disposed || _inlineLibraryTimer != null) {
      return;
    }

    void publishLibrarySnapshot() {
      _inlineLibraryTimer = null;

      if (_disposed) {
        return;
      }

      final core = _host._inlineCore!;
      final tracks = core.localDownloadedTracks();

      // Progress-only changes must not rebuild the artist/album groups.
      if (sameOfflineTrackSnapshots(_librarySnapshot.tracks, tracks) &&
          sameOfflineTrackSnapshots(_localLiked, core.localLiked) &&
          sameOfflinePlaylistSnapshots(_localPlaylists, core.localPlaylists) &&
          sameOfflineTrackSnapshots(_localPlaylistTracks, core.localPlaylistTracks)) {
        return;
      }

      _applyLibraryState(
        OfflineActorLibraryState(
          localLiked: core.localLiked,
          localPlaylists: core.localPlaylists,
          localPlaylistTracks: core.localPlaylistTracks,
          localDownloadedTracks: tracks,
          offlineArtistGroups: offline_views.offlineArtistGroups(tracks),
          revision: ++_inlineRevision,
        ),
      );
    }

    _inlineLibraryTimer = Timer(_OfflineDownloadActorCore._stateEmitCoalesceDelay, publishLibrarySnapshot);
  }

  void _applyDownloadState(OfflineActorDownloadState state) {
    developer.Timeline.startSync('offline.actor.downloadState');

    try {
      final nextDownloads = List<OfflineTrackDownload>.unmodifiable(state.downloads);
      final nextBatches = List<OfflineDownloadBatch>.unmodifiable(state.batches);
      final nextJobs = List<OfflineDownloadJob>.unmodifiable(state.jobs);
      final downloadsChanged = !_sameDownloadSnapshots(_downloads, nextDownloads);
      final batchesChanged = !_sameBatchSnapshots(_batches, nextBatches);
      final jobsChanged = !_sameJobSnapshots(_jobs, nextJobs);

      if (!downloadsChanged && !batchesChanged && !jobsChanged) {
        return;
      }

      _downloads = nextDownloads;
      _batches = nextBatches;
      _jobs = nextJobs;

      _downloadSnapshot = OfflineDownloadSnapshot(
        downloads: _downloads,
        batches: _batches,
        jobs: _jobs,
        revision: state.revision,
      );

      if (downloadsChanged) {
        _rebuildLookups();

        if (!_controller.isClosed) {
          _controller.add(_downloads);
        }
      }

      if (batchesChanged && !_batchController.isClosed) {
        _batchController.add(_batches);
      }

      if (jobsChanged && !_jobController.isClosed) {
        _jobController.add(_jobs);
      }

      if (!_downloadSnapshotController.isClosed) {
        _downloadSnapshotController.add(_downloadSnapshot);
      }
    } finally {
      developer.Timeline.finishSync();
    }
  }

  void _applyLibraryState(OfflineActorLibraryState state) {
    developer.Timeline.startSync('offline.actor.libraryState');

    try {
      final nextLiked = List<Track>.unmodifiable(state.localLiked);
      final nextPlaylists = List<Playlist>.unmodifiable(state.localPlaylists);
      final nextPlaylistTracks = List<Track>.unmodifiable(state.localPlaylistTracks);
      final nextDownloadedTracks = List<Track>.unmodifiable(state.localDownloadedTracks);
      final likedChanged = !sameOfflineTrackSnapshots(_localLiked, nextLiked);
      final playlistsChanged = !sameOfflinePlaylistSnapshots(_localPlaylists, nextPlaylists);
      final playlistTracksChanged = !sameOfflineTrackSnapshots(_localPlaylistTracks, nextPlaylistTracks);
      final tracksChanged = !sameOfflineTrackSnapshots(_librarySnapshot.tracks, nextDownloadedTracks);

      if (!likedChanged && !playlistsChanged && !playlistTracksChanged && !tracksChanged) {
        return;
      }

      _localLiked = nextLiked;
      _localPlaylists = nextPlaylists;
      _localPlaylistTracks = nextPlaylistTracks;

      _librarySnapshot = OfflineLibrarySnapshot(
        tracks: nextDownloadedTracks,
        artistGroups: List<offline_views.OfflineArtistGroup>.unmodifiable(state.offlineArtistGroups),
        liked: _localLiked,
        playlists: _localPlaylists,
        playlistTracks: _localPlaylistTracks,
        revision: state.revision,
      );

      if (likedChanged && !_localLikedController.isClosed) {
        _localLikedController.add(_localLiked);
      }

      if (playlistsChanged && !_localPlaylistsController.isClosed) {
        _localPlaylistsController.add(_localPlaylists);
      }

      if (playlistTracksChanged && !_localPlaylistTracksController.isClosed) {
        _localPlaylistTracksController.add(_localPlaylistTracks);
      }

      if (!_librarySnapshotController.isClosed) {
        _librarySnapshotController.add(_librarySnapshot);
      }
    } finally {
      developer.Timeline.finishSync();
    }
  }

  bool _sameDownloadSnapshots(List<OfflineTrackDownload> left, List<OfflineTrackDownload> right) {
    if (left.length != right.length) {
      return false;
    }

    for (var i = 0; i < left.length; i += 1) {
      final a = left[i];
      final b = right[i];

      if (a.serverBaseUrl != b.serverBaseUrl ||
          a.localTrackId != b.localTrackId ||
          a.status != b.status ||
          a.createdAt != b.createdAt ||
          a.updatedAt != b.updatedAt ||
          a.filePath != b.filePath ||
          a.partialPath != b.partialPath ||
          a.bytesDownloaded != b.bytesDownloaded ||
          a.bytesTotal != b.bytesTotal ||
          a.error != b.error ||
          a.priority != b.priority ||
          a.batchId != b.batchId ||
          a.downloadUrl != b.downloadUrl ||
          a.etag != b.etag ||
          a.expectedSha256 != b.expectedSha256 ||
          a.contentType != b.contentType ||
          !sameOfflineTrackSnapshot(a.track, b.track)) {
        return false;
      }
    }

    return true;
  }

  bool _sameBatchSnapshots(List<OfflineDownloadBatch> left, List<OfflineDownloadBatch> right) {
    if (left.length != right.length) {
      return false;
    }

    for (var i = 0; i < left.length; i += 1) {
      final a = left[i];
      final b = right[i];

      if (a.batchId != b.batchId ||
          a.serverBaseUrl != b.serverBaseUrl ||
          a.status != b.status ||
          a.createdAt != b.createdAt ||
          a.updatedAt != b.updatedAt ||
          a.totalCount != b.totalCount ||
          a.completedCount != b.completedCount ||
          a.failedCount != b.failedCount ||
          a.label != b.label) {
        return false;
      }
    }

    return true;
  }

  bool _sameJobSnapshots(List<OfflineDownloadJob> left, List<OfflineDownloadJob> right) {
    if (left.length != right.length) {
      return false;
    }

    for (var i = 0; i < left.length; i += 1) {
      final a = left[i];
      final b = right[i];

      if (a.jobId != b.jobId ||
          a.kind != b.kind ||
          a.serverBaseUrl != b.serverBaseUrl ||
          a.status != b.status ||
          a.createdAt != b.createdAt ||
          a.updatedAt != b.updatedAt ||
          a.totalCount != b.totalCount ||
          a.discoveredCount != b.discoveredCount ||
          a.completedCount != b.completedCount ||
          a.failedCount != b.failedCount ||
          a.materializedCount != b.materializedCount ||
          a.sourceCursor != b.sourceCursor ||
          a.label != b.label ||
          a.sourceId != b.sourceId ||
          a.error != b.error) {
        return false;
      }
    }

    return true;
  }

  void _rebuildLookups() {
    _downloadIndex = OfflineDownloadIndex(_downloads, trimServerKeys: true);
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _OfflineSnapshotPublisherFacade {
  _OfflineSnapshotPublisher get _ownerSnapshots;

  StreamController<List<OfflineTrackDownload>> get _controller => _ownerSnapshots._controller;

  StreamController<List<OfflineDownloadBatch>> get _batchController => _ownerSnapshots._batchController;

  StreamController<List<OfflineDownloadJob>> get _jobController => _ownerSnapshots._jobController;

  StreamController<List<Track>> get _localLikedController => _ownerSnapshots._localLikedController;

  StreamController<List<Playlist>> get _localPlaylistsController => _ownerSnapshots._localPlaylistsController;

  StreamController<List<Track>> get _localPlaylistTracksController => _ownerSnapshots._localPlaylistTracksController;

  StreamController<OfflineDownloadSnapshot> get _downloadSnapshotController =>
      _ownerSnapshots._downloadSnapshotController;

  StreamController<OfflineLibrarySnapshot> get _librarySnapshotController => _ownerSnapshots._librarySnapshotController;

  List<OfflineTrackDownload> get _downloads => _ownerSnapshots._downloads;

  List<OfflineDownloadBatch> get _batches => _ownerSnapshots._batches;

  List<OfflineDownloadJob> get _jobs => _ownerSnapshots._jobs;

  List<Track> get _localLiked => _ownerSnapshots._localLiked;

  List<Playlist> get _localPlaylists => _ownerSnapshots._localPlaylists;

  List<Track> get _localPlaylistTracks => _ownerSnapshots._localPlaylistTracks;

  OfflineDownloadSnapshot get _downloadSnapshot => _ownerSnapshots._downloadSnapshot;

  OfflineLibrarySnapshot get _librarySnapshot => _ownerSnapshots._librarySnapshot;

  OfflineDownloadIndex get _downloadIndex => _ownerSnapshots._downloadIndex;

  bool get _disposed => _ownerSnapshots._disposed;

  set _disposed(bool value) => _ownerSnapshots._disposed = value;

  List<StreamSubscription<dynamic>> get _inlineSubscriptions => _ownerSnapshots._inlineSubscriptions;

  Timer? get _inlineDownloadTimer => _ownerSnapshots._inlineDownloadTimer;

  Timer? get _inlineLibraryTimer => _ownerSnapshots._inlineLibraryTimer;

  void _listenToInlineCore() => _ownerSnapshots._listenToInlineCore();

  void _applyDownloadState(OfflineActorDownloadState state) => _ownerSnapshots._applyDownloadState(state);

  void _applyLibraryState(OfflineActorLibraryState state) => _ownerSnapshots._applyLibraryState(state);
}
