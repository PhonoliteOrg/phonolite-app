import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' show RootIsolateToken;
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import 'app_log.dart';
import 'models.dart';
import 'offline_library.dart';
import 'offline_library_views.dart' as offline_views;
import 'offline_storage_settings.dart';
import 'server_connection.dart';

class OfflineDownloadManager {
  OfflineDownloadManager({
    required this.connection,
    OfflineLibraryStorage storage = const OfflineLibraryStorage(),
  }) : _storageConfig = _OfflineStorageConfig.fromStorage(storage),
       _inlineCore = _canUseActor(storage)
           ? null
           : _OfflineDownloadActorCore(
               connection: connection,
               storage: storage,
             );

  static const int maxParallelDownloadsPerServer = 1;

  final ServerConnection connection;
  final _OfflineStorageConfig _storageConfig;
  final _OfflineDownloadActorCore? _inlineCore;

  final StreamController<List<OfflineTrackDownload>> _controller =
      StreamController<List<OfflineTrackDownload>>.broadcast();
  final StreamController<List<OfflineDownloadBatch>> _batchController =
      StreamController<List<OfflineDownloadBatch>>.broadcast();
  final StreamController<List<OfflineDownloadJob>> _jobController =
      StreamController<List<OfflineDownloadJob>>.broadcast();
  final StreamController<List<Track>> _localLikedController =
      StreamController<List<Track>>.broadcast();
  final StreamController<List<Playlist>> _localPlaylistsController =
      StreamController<List<Playlist>>.broadcast();
  final StreamController<List<Track>> _localPlaylistTracksController =
      StreamController<List<Track>>.broadcast();
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
  Map<String, OfflineTrackDownload> _downloadLookup =
      <String, OfflineTrackDownload>{};
  Map<String, OfflineTrackDownload> _localDownloadLookup =
      <String, OfflineTrackDownload>{};
  ReceivePort? _receivePort;
  Isolate? _isolate;
  SendPort? _actorPort;
  Future<void>? _actorStartFuture;
  final RootIsolateToken? _rootIsolateToken = RootIsolateToken.instance;
  final Map<int, Completer<Object?>> _pending = <int, Completer<Object?>>{};
  int _nextCommandId = 1;
  bool _disposed = false;

  static bool _canUseActor(OfflineLibraryStorage storage) {
    return storage.runtimeType == OfflineLibraryStorage &&
        storage.settingsStorage.runtimeType == OfflineStorageSettingsStorage &&
        storage.baseDirectory == null &&
        storage.metadataDirectory == null &&
        storage.downloadsDirectory == null;
  }

  Stream<List<OfflineTrackDownload>> get stream =>
      _inlineCore?.stream ?? _controller.stream;
  Stream<List<OfflineDownloadBatch>> get batchStream =>
      _inlineCore?.batchStream ?? _batchController.stream;
  Stream<List<OfflineDownloadJob>> get jobStream =>
      _inlineCore?.jobStream ?? _jobController.stream;
  Stream<OfflineDownloadSnapshot> get downloadSnapshotStream =>
      _downloadSnapshotController.stream;
  Stream<OfflineLibrarySnapshot> get librarySnapshotStream =>
      _librarySnapshotController.stream;
  Stream<List<Track>> get localLikedStream =>
      _inlineCore?.localLikedStream ?? _localLikedController.stream;
  Stream<List<Playlist>> get localPlaylistsStream =>
      _inlineCore?.localPlaylistsStream ?? _localPlaylistsController.stream;
  Stream<List<Track>> get localPlaylistTracksStream =>
      _inlineCore?.localPlaylistTracksStream ??
      _localPlaylistTracksController.stream;
  List<OfflineTrackDownload> get downloads =>
      _inlineCore?.downloads ?? List.unmodifiable(_downloads);
  List<OfflineDownloadBatch> get batches =>
      _inlineCore?.batches ?? List.unmodifiable(_batches);
  List<OfflineDownloadJob> get jobs =>
      _inlineCore?.jobs ?? List.unmodifiable(_jobs);
  OfflineDownloadSnapshot get downloadSnapshot => _inlineCore == null
      ? _downloadSnapshot
      : OfflineDownloadSnapshot(
          downloads: _inlineCore.downloads,
          batches: _inlineCore.batches,
          jobs: _inlineCore.jobs,
          revision: _downloadSnapshot.revision,
        );
  OfflineLibrarySnapshot get librarySnapshot => _inlineCore == null
      ? _librarySnapshot
      : OfflineLibrarySnapshot(
          tracks: _inlineCore.localDownloadedTracks(),
          artistGroups: offline_views.offlineArtistGroups(
            _inlineCore.localDownloadedTracks(),
          ),
          liked: _inlineCore.localLiked,
          playlists: _inlineCore.localPlaylists,
          playlistTracks: _inlineCore.localPlaylistTracks,
          revision: _librarySnapshot.revision,
        );
  List<Track> get localLiked =>
      _inlineCore?.localLiked ?? List.unmodifiable(_localLiked);
  List<Playlist> get localPlaylists =>
      _inlineCore?.localPlaylists ?? List.unmodifiable(_localPlaylists);
  List<Track> get localPlaylistTracks =>
      _inlineCore?.localPlaylistTracks ??
      List.unmodifiable(_localPlaylistTracks);

  Future<void> load() {
    final core = _inlineCore;
    if (core != null) {
      return core.load();
    }
    return _send<void>('load');
  }

  OfflineTrackDownload? findForCurrentServer(String trackId) {
    return find(connection.baseUrl, trackId);
  }

  OfflineTrackDownload? find(String serverBaseUrl, String trackId) {
    final core = _inlineCore;
    if (core != null) {
      return core.find(serverBaseUrl, trackId);
    }
    return _downloadLookup[_lookupKey(serverBaseUrl, trackId)];
  }

  OfflineTrackDownload? findLocal(String localTrackId) {
    final core = _inlineCore;
    if (core != null) {
      return core.findLocal(localTrackId);
    }
    return _localDownloadLookup[localTrackId];
  }

  List<Track> localDownloadedTracks() {
    final core = _inlineCore;
    if (core != null) {
      return core.localDownloadedTracks();
    }
    return List.unmodifiable(_librarySnapshot.tracks);
  }

  Future<int> downloadTrack(Track track) {
    final core = _inlineCore;
    if (core != null) {
      return core.downloadTrack(track);
    }
    return _send<int>('downloadTrack', track);
  }

  Future<int> queueTracks(
    Iterable<Track> tracks, {
    String? label,
    String kind = 'tracks',
    String? sourceId,
  }) {
    final core = _inlineCore;
    if (core != null) {
      return core.queueTracks(
        tracks,
        label: label,
        kind: kind,
        sourceId: sourceId,
      );
    }
    return _send<int>(
      'queueTracks',
      _QueueTracksRequest(
        tracks.toList(growable: false),
        label,
        kind,
        sourceId,
      ),
    );
  }

  Future<int> queueBatch(DownloadBatchManifest manifest, {String? label}) {
    final core = _inlineCore;
    if (core != null) {
      return core.queueBatch(manifest, label: label);
    }
    return _send<int>('queueBatch', _QueueBatchRequest(manifest, label));
  }

  Future<int> queueArtist(Artist artist, List<Album> albums) {
    final core = _inlineCore;
    if (core != null) {
      return core.queueArtist(artist, albums);
    }
    return _send<int>('queueArtist', _QueueArtistRequest(artist, albums));
  }

  Future<void> pauseDownload(OfflineTrackDownload download) => _commandOrInline(
    'pauseDownload',
    download,
    (core) => core.pauseDownload(download),
  );

  Future<void> resumeDownload(OfflineTrackDownload download) =>
      _commandOrInline(
        'resumeDownload',
        download,
        (core) => core.resumeDownload(download),
      );

  Future<void> retryDownload(OfflineTrackDownload download) => _commandOrInline(
    'retryDownload',
    download,
    (core) => core.retryDownload(download),
  );

  Future<void> cancelDownload(OfflineTrackDownload download) =>
      _commandOrInline(
        'cancelDownload',
        download,
        (core) => core.cancelDownload(download),
      );

  Future<void> pauseDownloadsForServer(String serverBaseUrl) =>
      _commandOrInline(
        'pauseDownloadsForServer',
        serverBaseUrl,
        (core) => core.pauseDownloadsForServer(serverBaseUrl),
      );

  Future<void> resumePausedForCurrentServer() => _commandOrInline(
    'resumePausedForCurrentServer',
    null,
    (core) => core.resumePausedForCurrentServer(),
  );

  Future<void> repairOfflineMetadataFragments() => _commandOrInline(
    'repairOfflineMetadataFragments',
    null,
    (core) => core.repairOfflineMetadataFragments(),
  );

  Future<void> refreshOfflineMetadataForAlbum(String albumId) =>
      _commandOrInline(
        'refreshOfflineMetadataForAlbum',
        albumId,
        (core) => core.refreshOfflineMetadataForAlbum(albumId),
      );

  Future<void> refreshOfflineMetadataForArtist(String artistId) =>
      _commandOrInline(
        'refreshOfflineMetadataForArtist',
        artistId,
        (core) => core.refreshOfflineMetadataForArtist(artistId),
      );

  Future<void> pauseDownloadJob(OfflineDownloadJob job) => _commandOrInline(
    'pauseDownloadJob',
    job,
    (core) => core.pauseDownloadJob(job),
  );

  Future<void> resumeDownloadJob(OfflineDownloadJob job) => _commandOrInline(
    'resumeDownloadJob',
    job,
    (core) => core.resumeDownloadJob(job),
  );

  Future<void> cancelDownloadJob(OfflineDownloadJob job) => _commandOrInline(
    'cancelDownloadJob',
    job,
    (core) => core.cancelDownloadJob(job),
  );

  Future<void> removeTrack(String trackId) => _commandOrInline(
    'removeTrack',
    trackId,
    (core) => core.removeTrack(trackId),
  );

  Future<void> removeDownload(OfflineTrackDownload download) =>
      removeDownloads(<OfflineTrackDownload>[download]);

  Future<void> removeDownloads(
    Iterable<OfflineTrackDownload> downloads, {
    OfflineDeletionScope scope = const OfflineDeletionScope.track(),
  }) {
    final list = downloads.toList(growable: false);
    final request = OfflineDeletionRequest(scope: scope, downloads: list);
    final core = _inlineCore;
    if (core != null) {
      return core.removeDownloads(list, scope: scope);
    }
    return _send<void>('removeDownloads', request);
  }

  Future<void> clearFailedAndCorrupt() => _commandOrInline(
    'clearFailedAndCorrupt',
    null,
    (core) => core.clearFailedAndCorrupt(),
  );

  Future<void> resetLocalData() =>
      _commandOrInline('resetLocalData', null, (core) => core.resetLocalData());

  Future<void> loadLocalPlaylists() => _commandOrInline(
    'loadLocalPlaylists',
    null,
    (core) => core.loadLocalPlaylists(),
  );

  Future<void> loadLocalPlaylistTracks(String playlistId) => _commandOrInline(
    'loadLocalPlaylistTracks',
    playlistId,
    (core) => core.loadLocalPlaylistTracks(playlistId),
  );

  Future<void> loadLocalLikedTracks() => _commandOrInline(
    'loadLocalLikedTracks',
    null,
    (core) => core.loadLocalLikedTracks(),
  );

  Future<void> setLocalLike(Track track, bool liked) {
    final core = _inlineCore;
    if (core != null) {
      return core.setLocalLike(track, liked);
    }
    return _send<void>('setLocalLike', _TrackBoolRequest(track, liked));
  }

  Future<List<LocalLikeState>> readLocalLikeStates() {
    final core = _inlineCore;
    if (core != null) {
      return core.readLocalLikeStates();
    }
    return _send<List<LocalLikeState>>('readLocalLikeStates');
  }

  Future<List<ServerLikeSync>> readServerLikeSyncs(String serverBaseUrl) {
    final core = _inlineCore;
    if (core != null) {
      return core.readServerLikeSyncs(serverBaseUrl);
    }
    return _send<List<ServerLikeSync>>('readServerLikeSyncs', serverBaseUrl);
  }

  Future<void> upsertServerLikeSyncs(List<ServerLikeSync> syncs) {
    final core = _inlineCore;
    if (core != null) {
      return core.upsertServerLikeSyncs(syncs);
    }
    return _send<void>('upsertServerLikeSyncs', syncs);
  }

  Future<void> applySyncedLocalLikeState(
    String localTrackId,
    bool liked,
    int updatedAt,
  ) {
    final core = _inlineCore;
    if (core != null) {
      return core.applySyncedLocalLikeState(localTrackId, liked, updatedAt);
    }
    return _send<void>(
      'applySyncedLocalLikeState',
      _SyncedLocalLikeRequest(localTrackId, liked, updatedAt),
    );
  }

  Future<Playlist> createLocalPlaylist(String name, {String? description}) {
    final core = _inlineCore;
    if (core != null) {
      return core.createLocalPlaylist(name, description: description);
    }
    return _send<Playlist>(
      'createLocalPlaylist',
      _PlaylistDetailsRequest('', name, description),
    );
  }

  Future<Playlist?> renameLocalPlaylist(
    String playlistId,
    String name, {
    String? description,
  }) {
    final core = _inlineCore;
    if (core != null) {
      return core.renameLocalPlaylist(
        playlistId,
        name,
        description: description,
      );
    }
    return _send<Playlist?>(
      'renameLocalPlaylist',
      _PlaylistDetailsRequest(playlistId, name, description),
    );
  }

  Future<Playlist?> updateLocalPlaylistImage(
    String playlistId,
    PlaylistImageEdit imageEdit,
  ) {
    final core = _inlineCore;
    if (core != null) {
      return core.updateLocalPlaylistImage(playlistId, imageEdit);
    }
    return _send<Playlist?>(
      'updateLocalPlaylistImage',
      _PlaylistImageRequest(playlistId, imageEdit),
    );
  }

  Future<void> deleteLocalPlaylist(String playlistId) => _commandOrInline(
    'deleteLocalPlaylist',
    playlistId,
    (core) => core.deleteLocalPlaylist(playlistId),
  );

  Future<Playlist?> addLocalTrackToPlaylist(Playlist playlist, Track track) {
    final core = _inlineCore;
    if (core != null) {
      return core.addLocalTrackToPlaylist(playlist, track);
    }
    return _send<Playlist?>(
      'addLocalTrackToPlaylist',
      _PlaylistTrackRequest(playlist, track),
    );
  }

  Future<Playlist?> removeLocalTrackFromPlaylist(
    Playlist playlist,
    Track track,
  ) {
    final core = _inlineCore;
    if (core != null) {
      return core.removeLocalTrackFromPlaylist(playlist, track);
    }
    return _send<Playlist?>(
      'removeLocalTrackFromPlaylist',
      _PlaylistTrackRequest(playlist, track),
    );
  }

  Future<void> dispose() async {
    _disposed = true;
    final core = _inlineCore;
    if (core != null) {
      await core.dispose();
    } else if (_actorPort != null) {
      try {
        await _send<void>('dispose');
      } catch (_) {}
    }
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Offline download actor disposed'));
      }
    }
    _pending.clear();
    _receivePort?.close();
    _isolate?.kill(priority: Isolate.immediate);
    await _controller.close();
    await _batchController.close();
    await _jobController.close();
    await _localLikedController.close();
    await _localPlaylistsController.close();
    await _localPlaylistTracksController.close();
    await _downloadSnapshotController.close();
    await _librarySnapshotController.close();
  }

  Future<void> _commandOrInline(
    String name,
    Object? payload,
    Future<void> Function(_OfflineDownloadActorCore core) inline,
  ) {
    final core = _inlineCore;
    if (core != null) {
      return inline(core);
    }
    return _send<void>(name, payload);
  }

  Future<T> _send<T>(String name, [Object? payload]) async {
    if (_disposed && name != 'dispose') {
      throw StateError('Offline download manager disposed');
    }
    await _ensureActor();
    final port = _actorPort;
    if (port == null) {
      throw StateError('Offline download actor unavailable');
    }
    final id = _nextCommandId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    port.send(
      _OfflineActorCommand(
        id: id,
        name: name,
        payload: payload,
        baseUrl: connection.baseUrl,
        token: connection.token,
      ),
    );
    final result = await completer.future;
    return result as T;
  }

  Future<void> _ensureActor() {
    if (_actorPort != null) {
      return Future<void>.value();
    }
    final existing = _actorStartFuture;
    if (existing != null) {
      return existing;
    }
    final ready = Completer<void>();
    _receivePort = ReceivePort();
    _receivePort!.listen(_handleActorMessage);
    _actorStartFuture = ready.future.whenComplete(() {
      _actorStartFuture = null;
    });
    Isolate.spawn(
          _offlineDownloadActorMain,
          _OfflineActorInit(
            replyPort: _receivePort!.sendPort,
            baseUrl: connection.baseUrl,
            token: connection.token,
            storageConfig: _storageConfig,
            rootIsolateToken: _rootIsolateToken,
          ),
          debugName: 'OfflineDownloadActor',
        )
        .then((isolate) {
          _isolate = isolate;
        })
        .catchError((Object err, StackTrace stack) {
          if (!ready.isCompleted) {
            ready.completeError(err, stack);
          }
        });
    _pending[0] = Completer<Object?>()
      ..future
          .then((_) {
            if (!ready.isCompleted) {
              ready.complete();
            }
          })
          .catchError((Object err, StackTrace stack) {
            if (!ready.isCompleted) {
              ready.completeError(err, stack);
            }
          });
    return _actorStartFuture!;
  }

  void _handleActorMessage(Object? message) {
    if (message is _OfflineActorReady) {
      _actorPort = message.commandPort;
      final ready = _pending.remove(0);
      if (ready != null && !ready.isCompleted) {
        ready.complete(null);
      }
      return;
    }
    if (message is _OfflineActorDownloadState) {
      _applyDownloadState(message);
      return;
    }
    if (message is _OfflineActorLibraryState) {
      _applyLibraryState(message);
      return;
    }
    if (message is _OfflineActorResult) {
      final completer = _pending.remove(message.id);
      if (completer == null || completer.isCompleted) {
        return;
      }
      if (message.error != null) {
        completer.completeError(StateError(message.error!));
      } else {
        completer.complete(message.result);
      }
    }
  }

  void _applyDownloadState(_OfflineActorDownloadState state) {
    developer.Timeline.startSync('offline.actor.downloadState');
    try {
      final nextDownloads = List<OfflineTrackDownload>.unmodifiable(
        state.downloads,
      );
      final nextBatches = List<OfflineDownloadBatch>.unmodifiable(
        state.batches,
      );
      final nextJobs = List<OfflineDownloadJob>.unmodifiable(state.jobs);
      final downloadsChanged = !_sameDownloadSnapshots(
        _downloads,
        nextDownloads,
      );
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

  void _applyLibraryState(_OfflineActorLibraryState state) {
    developer.Timeline.startSync('offline.actor.libraryState');
    try {
      final nextLiked = List<Track>.unmodifiable(state.localLiked);
      final nextPlaylists = List<Playlist>.unmodifiable(state.localPlaylists);
      final nextPlaylistTracks = List<Track>.unmodifiable(
        state.localPlaylistTracks,
      );
      final nextDownloadedTracks = List<Track>.unmodifiable(
        state.localDownloadedTracks,
      );
      final likedChanged = !_sameTrackSnapshots(_localLiked, nextLiked);
      final playlistsChanged = !_samePlaylistSnapshots(
        _localPlaylists,
        nextPlaylists,
      );
      final playlistTracksChanged = !_sameTrackSnapshots(
        _localPlaylistTracks,
        nextPlaylistTracks,
      );
      final tracksChanged = !_sameTrackSnapshots(
        _librarySnapshot.tracks,
        nextDownloadedTracks,
      );
      if (!likedChanged &&
          !playlistsChanged &&
          !playlistTracksChanged &&
          !tracksChanged) {
        return;
      }

      _localLiked = nextLiked;
      _localPlaylists = nextPlaylists;
      _localPlaylistTracks = nextPlaylistTracks;
      _librarySnapshot = OfflineLibrarySnapshot(
        tracks: nextDownloadedTracks,
        artistGroups: List<offline_views.OfflineArtistGroup>.unmodifiable(
          state.offlineArtistGroups,
        ),
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

  bool _sameDownloadSnapshots(
    List<OfflineTrackDownload> left,
    List<OfflineTrackDownload> right,
  ) {
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
          !_sameTrackSnapshot(a.track, b.track)) {
        return false;
      }
    }
    return true;
  }

  bool _sameBatchSnapshots(
    List<OfflineDownloadBatch> left,
    List<OfflineDownloadBatch> right,
  ) {
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

  bool _sameJobSnapshots(
    List<OfflineDownloadJob> left,
    List<OfflineDownloadJob> right,
  ) {
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

  bool _sameTrackSnapshots(List<Track> left, List<Track> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var i = 0; i < left.length; i += 1) {
      if (!_sameTrackSnapshot(left[i], right[i])) {
        return false;
      }
    }
    return true;
  }

  bool _sameTrackSnapshot(Track a, Track b) {
    return a.id == b.id &&
        a.localId == b.localId &&
        a.serverBaseUrl == b.serverBaseUrl &&
        a.serverTrackId == b.serverTrackId &&
        a.title == b.title &&
        a.artist == b.artist &&
        a.artistId == b.artistId &&
        a.album == b.album &&
        a.albumId == b.albumId &&
        a.durationMs == b.durationMs &&
        a.liked == b.liked &&
        a.inPlaylists == b.inPlaylists &&
        a.albumArtPath == b.albumArtPath &&
        a.artistArtPath == b.artistArtPath &&
        a.artistBannerPath == b.artistBannerPath;
  }

  bool _samePlaylistSnapshots(List<Playlist> left, List<Playlist> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var i = 0; i < left.length; i += 1) {
      final a = left[i];
      final b = right[i];
      if (a.id != b.id ||
          a.name != b.name ||
          a.description != b.description ||
          a.imageRef != b.imageRef ||
          a.imagePath != b.imagePath ||
          a.trackIds.length != b.trackIds.length) {
        return false;
      }
      for (var j = 0; j < a.trackIds.length; j += 1) {
        if (a.trackIds[j] != b.trackIds[j]) {
          return false;
        }
      }
    }
    return true;
  }

  void _rebuildLookups() {
    final lookup = <String, OfflineTrackDownload>{};
    final localLookup = <String, OfflineTrackDownload>{};
    for (final download in _downloads) {
      void addServer(String? id) {
        final value = id?.trim();
        if (value == null || value.isEmpty) {
          return;
        }
        lookup.putIfAbsent(
          _lookupKey(download.serverBaseUrl, value),
          () => download,
        );
      }

      void addLocal(String? id) {
        final value = id?.trim();
        if (value == null || value.isEmpty) {
          return;
        }
        localLookup.putIfAbsent(value, () => download);
      }

      addServer(download.track.id);
      addServer(download.track.serverTrackId);
      addServer(download.localTrackId);
      addServer(download.track.localId);
      addLocal(download.localTrackId);
      addLocal(download.track.localId);
      addLocal(download.track.id);
      addLocal(download.track.serverTrackId);
    }
    _downloadLookup = lookup;
    _localDownloadLookup = localLookup;
  }

  String _lookupKey(String serverBaseUrl, String trackId) {
    return '${serverBaseUrl.trim()}\n${trackId.trim()}';
  }
}

class OfflineDownloadSnapshot {
  const OfflineDownloadSnapshot({
    required this.downloads,
    required this.batches,
    required this.jobs,
    required this.revision,
  });

  final List<OfflineTrackDownload> downloads;
  final List<OfflineDownloadBatch> batches;
  final List<OfflineDownloadJob> jobs;
  final int revision;
}

class OfflineLibrarySnapshot {
  const OfflineLibrarySnapshot({
    required this.tracks,
    required this.artistGroups,
    required this.liked,
    required this.playlists,
    required this.playlistTracks,
    required this.revision,
  });

  final List<Track> tracks;
  final List<offline_views.OfflineArtistGroup> artistGroups;
  final List<Track> liked;
  final List<Playlist> playlists;
  final List<Track> playlistTracks;
  final int revision;
}

class _OfflineStorageConfig {
  const _OfflineStorageConfig({
    this.baseDirectory,
    this.metadataDirectory,
    this.downloadsDirectory,
  });

  factory _OfflineStorageConfig.fromStorage(OfflineLibraryStorage storage) {
    return _OfflineStorageConfig(
      baseDirectory: storage.baseDirectory?.absolute.path,
      metadataDirectory: storage.metadataDirectory?.absolute.path,
      downloadsDirectory: storage.downloadsDirectory?.absolute.path,
    );
  }

  final String? baseDirectory;
  final String? metadataDirectory;
  final String? downloadsDirectory;

  OfflineLibraryStorage createStorage() {
    return OfflineLibraryStorage(
      baseDirectory: baseDirectory == null ? null : Directory(baseDirectory!),
      metadataDirectory: metadataDirectory == null
          ? null
          : Directory(metadataDirectory!),
      downloadsDirectory: downloadsDirectory == null
          ? null
          : Directory(downloadsDirectory!),
    );
  }
}

class _OfflineActorInit {
  const _OfflineActorInit({
    required this.replyPort,
    required this.baseUrl,
    required this.token,
    required this.storageConfig,
    required this.rootIsolateToken,
  });

  final SendPort replyPort;
  final String baseUrl;
  final String? token;
  final _OfflineStorageConfig storageConfig;
  final RootIsolateToken? rootIsolateToken;
}

class _OfflineActorReady {
  const _OfflineActorReady(this.commandPort);

  final SendPort commandPort;
}

class _OfflineActorCommand {
  const _OfflineActorCommand({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.token,
    this.payload,
  });

  final int id;
  final String name;
  final String baseUrl;
  final String? token;
  final Object? payload;
}

class _OfflineActorResult {
  const _OfflineActorResult({required this.id, this.result, this.error});

  final int id;
  final Object? result;
  final String? error;
}

class _OfflineActorDownloadState {
  _OfflineActorDownloadState.fromCore(
    _OfflineDownloadActorCore core,
    this.revision,
  ) : downloads = core.downloads,
      batches = core.batches,
      jobs = core.jobs;

  final List<OfflineTrackDownload> downloads;
  final List<OfflineDownloadBatch> batches;
  final List<OfflineDownloadJob> jobs;
  final int revision;
}

class _OfflineActorLibraryState {
  const _OfflineActorLibraryState({
    required this.localLiked,
    required this.localPlaylists,
    required this.localPlaylistTracks,
    required this.localDownloadedTracks,
    required this.offlineArtistGroups,
    required this.revision,
  });

  final List<Track> localLiked;
  final List<Playlist> localPlaylists;
  final List<Track> localPlaylistTracks;
  final List<Track> localDownloadedTracks;
  final List<offline_views.OfflineArtistGroup> offlineArtistGroups;
  final int revision;
}

class _QueueTracksRequest {
  const _QueueTracksRequest(this.tracks, this.label, this.kind, this.sourceId);

  final List<Track> tracks;
  final String? label;
  final String kind;
  final String? sourceId;
}

class _QueueBatchRequest {
  const _QueueBatchRequest(this.manifest, this.label);

  final DownloadBatchManifest manifest;
  final String? label;
}

class _QueueArtistRequest {
  const _QueueArtistRequest(this.artist, this.albums);

  final Artist artist;
  final List<Album> albums;
}

class _TrackBoolRequest {
  const _TrackBoolRequest(this.track, this.value);

  final Track track;
  final bool value;
}

class _SyncedLocalLikeRequest {
  const _SyncedLocalLikeRequest(this.localTrackId, this.liked, this.updatedAt);

  final String localTrackId;
  final bool liked;
  final int updatedAt;
}

class _PlaylistDetailsRequest {
  const _PlaylistDetailsRequest(this.playlistId, this.name, this.description);

  final String playlistId;
  final String name;
  final String? description;
}

class _PlaylistImageRequest {
  const _PlaylistImageRequest(this.playlistId, this.imageEdit);

  final String playlistId;
  final PlaylistImageEdit imageEdit;
}

class _PlaylistTrackRequest {
  const _PlaylistTrackRequest(this.playlist, this.track);

  final Playlist playlist;
  final Track track;
}

void _offlineDownloadActorMain(_OfflineActorInit init) {
  final token = init.rootIsolateToken;
  if (token != null) {
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  }
  final commandPort = ReceivePort();
  final connection = ServerConnection(baseUrl: init.baseUrl)
    ..setToken(init.token);
  final core = _OfflineDownloadActorCore(
    connection: connection,
    storage: init.storageConfig.createStorage(),
  );
  var revision = 0;
  Timer? downloadStateTimer;
  Timer? libraryStateTimer;
  List<Track> lastLocalLiked = const <Track>[];
  List<Playlist> lastLocalPlaylists = const <Playlist>[];
  List<Track> lastLocalPlaylistTracks = const <Track>[];
  List<Track> lastLocalDownloadedTracks = const <Track>[];
  final subscriptions = <StreamSubscription<dynamic>>[];

  void sendDownloadState() {
    developer.Timeline.startSync('offline.actor.downloadState');
    try {
      init.replyPort.send(
        _OfflineActorDownloadState.fromCore(core, ++revision),
      );
    } finally {
      developer.Timeline.finishSync();
    }
  }

  void sendLibraryState() {
    developer.Timeline.startSync('offline.actor.libraryState');
    try {
      final localLiked = List<Track>.unmodifiable(core.localLiked);
      final localPlaylists = List<Playlist>.unmodifiable(core.localPlaylists);
      final localPlaylistTracks = List<Track>.unmodifiable(
        core.localPlaylistTracks,
      );
      final localDownloadedTracks = List<Track>.unmodifiable(
        core.localDownloadedTracks(),
      );
      if (_actorSameTrackSnapshots(lastLocalLiked, localLiked) &&
          _actorSamePlaylistSnapshots(lastLocalPlaylists, localPlaylists) &&
          _actorSameTrackSnapshots(
            lastLocalPlaylistTracks,
            localPlaylistTracks,
          ) &&
          _actorSameTrackSnapshots(
            lastLocalDownloadedTracks,
            localDownloadedTracks,
          )) {
        return;
      }
      lastLocalLiked = localLiked;
      lastLocalPlaylists = localPlaylists;
      lastLocalPlaylistTracks = localPlaylistTracks;
      lastLocalDownloadedTracks = localDownloadedTracks;
      init.replyPort.send(
        _OfflineActorLibraryState(
          localLiked: localLiked,
          localPlaylists: localPlaylists,
          localPlaylistTracks: localPlaylistTracks,
          localDownloadedTracks: localDownloadedTracks,
          offlineArtistGroups: offline_views.offlineArtistGroups(
            localDownloadedTracks,
          ),
          revision: ++revision,
        ),
      );
    } finally {
      developer.Timeline.finishSync();
    }
  }

  void scheduleDownloadState() {
    if (downloadStateTimer != null) {
      return;
    }
    downloadStateTimer = Timer(
      _OfflineDownloadActorCore._stateEmitCoalesceDelay,
      () {
        downloadStateTimer = null;
        sendDownloadState();
      },
    );
  }

  void scheduleLibraryState() {
    if (libraryStateTimer != null) {
      return;
    }
    libraryStateTimer = Timer(
      _OfflineDownloadActorCore._stateEmitCoalesceDelay,
      () {
        libraryStateTimer = null;
        sendLibraryState();
      },
    );
  }

  void sendDownloadStateNow() {
    downloadStateTimer?.cancel();
    downloadStateTimer = null;
    sendDownloadState();
  }

  void sendLibraryStateNow() {
    libraryStateTimer?.cancel();
    libraryStateTimer = null;
    sendLibraryState();
  }

  subscriptions.add(
    core.stream.listen((_) {
      scheduleDownloadState();
      scheduleLibraryState();
    }),
  );
  subscriptions.add(core.batchStream.listen((_) => scheduleDownloadState()));
  subscriptions.add(core.jobStream.listen((_) => scheduleDownloadState()));
  subscriptions.add(
    core.localLikedStream.listen((_) => scheduleLibraryState()),
  );
  subscriptions.add(
    core.localPlaylistsStream.listen((_) => scheduleLibraryState()),
  );
  subscriptions.add(
    core.localPlaylistTracksStream.listen((_) => scheduleLibraryState()),
  );

  init.replyPort.send(_OfflineActorReady(commandPort.sendPort));
  Future<void> commandChain = Future<void>.value();

  Future<void> handleCommand(_OfflineActorCommand message) async {
    final task = developer.TimelineTask()..start('offline.actor.command');
    try {
      connection.setBaseUrl(message.baseUrl);
      connection.setToken(message.token);
      final result = await _handleOfflineActorCommand(core, message);
      if (_offlineActorCommandNeedsDownloadState(message.name)) {
        sendDownloadStateNow();
      }
      if (_offlineActorCommandMayChangeLibraryState(message.name)) {
        sendLibraryStateNow();
      }
      init.replyPort.send(_OfflineActorResult(id: message.id, result: result));
      if (message.name == 'dispose') {
        downloadStateTimer?.cancel();
        libraryStateTimer?.cancel();
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
        commandPort.close();
      }
    } catch (err, stack) {
      init.replyPort.send(
        _OfflineActorResult(id: message.id, error: '$err\n$stack'),
      );
    } finally {
      task.finish();
    }
  }

  commandPort.listen((message) {
    if (message is! _OfflineActorCommand) {
      return;
    }
    commandChain = commandChain.then((_) => handleCommand(message));
    unawaited(commandChain);
  });
}

bool _offlineActorCommandNeedsDownloadState(String name) {
  return switch (name) {
    'readLocalLikeStates' ||
    'readServerLikeSyncs' ||
    'upsertServerLikeSyncs' ||
    'loadLocalPlaylists' ||
    'loadLocalPlaylistTracks' ||
    'loadLocalLikedTracks' ||
    'setLocalLike' ||
    'applySyncedLocalLikeState' ||
    'createLocalPlaylist' ||
    'renameLocalPlaylist' ||
    'updateLocalPlaylistImage' ||
    'deleteLocalPlaylist' ||
    'addLocalTrackToPlaylist' ||
    'removeLocalTrackFromPlaylist' ||
    'dispose' => false,
    _ => true,
  };
}

bool _offlineActorCommandMayChangeLibraryState(String name) {
  return switch (name) {
    'load' ||
    'repairOfflineMetadataFragments' ||
    'refreshOfflineMetadataForAlbum' ||
    'refreshOfflineMetadataForArtist' ||
    'removeTrack' ||
    'removeDownloads' ||
    'clearFailedAndCorrupt' ||
    'resetLocalData' ||
    'loadLocalPlaylists' ||
    'loadLocalPlaylistTracks' ||
    'loadLocalLikedTracks' ||
    'setLocalLike' ||
    'applySyncedLocalLikeState' ||
    'createLocalPlaylist' ||
    'renameLocalPlaylist' ||
    'updateLocalPlaylistImage' ||
    'deleteLocalPlaylist' ||
    'addLocalTrackToPlaylist' ||
    'removeLocalTrackFromPlaylist' => true,
    _ => false,
  };
}

bool _actorSameTrackSnapshots(List<Track> left, List<Track> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var i = 0; i < left.length; i += 1) {
    if (!_actorSameTrackSnapshot(left[i], right[i])) {
      return false;
    }
  }
  return true;
}

bool _actorSameTrackSnapshot(Track a, Track b) {
  return a.id == b.id &&
      a.localId == b.localId &&
      a.serverBaseUrl == b.serverBaseUrl &&
      a.serverTrackId == b.serverTrackId &&
      a.title == b.title &&
      a.artist == b.artist &&
      a.artistId == b.artistId &&
      a.album == b.album &&
      a.albumId == b.albumId &&
      a.durationMs == b.durationMs &&
      a.liked == b.liked &&
      a.inPlaylists == b.inPlaylists &&
      a.albumArtPath == b.albumArtPath &&
      a.artistArtPath == b.artistArtPath &&
      a.artistBannerPath == b.artistBannerPath;
}

bool _actorSamePlaylistSnapshots(List<Playlist> left, List<Playlist> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var i = 0; i < left.length; i += 1) {
    final a = left[i];
    final b = right[i];
    if (a.id != b.id ||
        a.name != b.name ||
        a.description != b.description ||
        a.imageRef != b.imageRef ||
        a.imagePath != b.imagePath ||
        a.trackIds.length != b.trackIds.length) {
      return false;
    }
    for (var j = 0; j < a.trackIds.length; j += 1) {
      if (a.trackIds[j] != b.trackIds[j]) {
        return false;
      }
    }
  }
  return true;
}

Future<Object?> _handleOfflineActorCommand(
  _OfflineDownloadActorCore core,
  _OfflineActorCommand command,
) async {
  switch (command.name) {
    case 'load':
      await core.load();
      return null;
    case 'downloadTrack':
      return core.downloadTrack(command.payload! as Track);
    case 'queueTracks':
      final request = command.payload! as _QueueTracksRequest;
      return core.queueTracks(
        request.tracks,
        label: request.label,
        kind: request.kind,
        sourceId: request.sourceId,
      );
    case 'queueBatch':
      final request = command.payload! as _QueueBatchRequest;
      return core.queueBatch(request.manifest, label: request.label);
    case 'queueArtist':
      final request = command.payload! as _QueueArtistRequest;
      return core.queueArtist(request.artist, request.albums);
    case 'pauseDownload':
      await core.pauseDownload(command.payload! as OfflineTrackDownload);
      return null;
    case 'resumeDownload':
      await core.resumeDownload(command.payload! as OfflineTrackDownload);
      return null;
    case 'retryDownload':
      await core.retryDownload(command.payload! as OfflineTrackDownload);
      return null;
    case 'cancelDownload':
      await core.cancelDownload(command.payload! as OfflineTrackDownload);
      return null;
    case 'pauseDownloadsForServer':
      await core.pauseDownloadsForServer(command.payload! as String);
      return null;
    case 'resumePausedForCurrentServer':
      await core.resumePausedForCurrentServer();
      return null;
    case 'repairOfflineMetadataFragments':
      await core.repairOfflineMetadataFragments();
      return null;
    case 'refreshOfflineMetadataForAlbum':
      await core.refreshOfflineMetadataForAlbum(command.payload! as String);
      return null;
    case 'refreshOfflineMetadataForArtist':
      await core.refreshOfflineMetadataForArtist(command.payload! as String);
      return null;
    case 'pauseDownloadJob':
      await core.pauseDownloadJob(command.payload! as OfflineDownloadJob);
      return null;
    case 'resumeDownloadJob':
      await core.resumeDownloadJob(command.payload! as OfflineDownloadJob);
      return null;
    case 'cancelDownloadJob':
      await core.cancelDownloadJob(command.payload! as OfflineDownloadJob);
      return null;
    case 'removeTrack':
      await core.removeTrack(command.payload! as String);
      return null;
    case 'removeDownloads':
      final payload = command.payload!;
      if (payload is OfflineDeletionRequest) {
        await core.removeDownloads(payload.downloads, scope: payload.scope);
      } else {
        await core.removeDownloads(
          (payload as List).cast<OfflineTrackDownload>(),
        );
      }
      return null;
    case 'clearFailedAndCorrupt':
      await core.clearFailedAndCorrupt();
      return null;
    case 'resetLocalData':
      await core.resetLocalData();
      return null;
    case 'loadLocalPlaylists':
      await core.loadLocalPlaylists();
      return null;
    case 'loadLocalPlaylistTracks':
      await core.loadLocalPlaylistTracks(command.payload! as String);
      return null;
    case 'loadLocalLikedTracks':
      await core.loadLocalLikedTracks();
      return null;
    case 'setLocalLike':
      final request = command.payload! as _TrackBoolRequest;
      await core.setLocalLike(request.track, request.value);
      return null;
    case 'readLocalLikeStates':
      return core.readLocalLikeStates();
    case 'readServerLikeSyncs':
      return core.readServerLikeSyncs(command.payload! as String);
    case 'upsertServerLikeSyncs':
      await core.upsertServerLikeSyncs(
        (command.payload! as List).cast<ServerLikeSync>(),
      );
      return null;
    case 'applySyncedLocalLikeState':
      final request = command.payload! as _SyncedLocalLikeRequest;
      await core.applySyncedLocalLikeState(
        request.localTrackId,
        request.liked,
        request.updatedAt,
      );
      return null;
    case 'createLocalPlaylist':
      final request = command.payload! as _PlaylistDetailsRequest;
      return core.createLocalPlaylist(
        request.name,
        description: request.description,
      );
    case 'renameLocalPlaylist':
      final request = command.payload! as _PlaylistDetailsRequest;
      return core.renameLocalPlaylist(
        request.playlistId,
        request.name,
        description: request.description,
      );
    case 'updateLocalPlaylistImage':
      final request = command.payload! as _PlaylistImageRequest;
      return core.updateLocalPlaylistImage(
        request.playlistId,
        request.imageEdit,
      );
    case 'deleteLocalPlaylist':
      await core.deleteLocalPlaylist(command.payload! as String);
      return null;
    case 'addLocalTrackToPlaylist':
      final request = command.payload! as _PlaylistTrackRequest;
      return core.addLocalTrackToPlaylist(request.playlist, request.track);
    case 'removeLocalTrackFromPlaylist':
      final request = command.payload! as _PlaylistTrackRequest;
      return core.removeLocalTrackFromPlaylist(request.playlist, request.track);
    case 'dispose':
      await core.dispose();
      return null;
    default:
      throw StateError('Unknown offline actor command ${command.name}');
  }
}

class _OfflineDownloadActorCore {
  _OfflineDownloadActorCore({
    required this.connection,
    OfflineLibraryStorage storage = const OfflineLibraryStorage(),
  }) : _storage = storage;

  static const int maxParallelDownloadsPerServer = 1;
  static const Duration _progressEmitInterval = Duration(seconds: 3);
  static const Duration _artworkHydrationDelay = Duration(milliseconds: 500);
  static const Duration _localUserDataReloadDelay = Duration(milliseconds: 800);
  static const Duration _stateEmitCoalesceDelay = Duration(milliseconds: 80);
  static const int _progressEmitMinBytes = 4 * 1024 * 1024;
  static const int _diskFlushBytes = 8 * 1024 * 1024;
  static const int _queuePersistChunkSize = 20;
  static const int _rollingWindowSize = 20;
  static const Duration _queuePersistYieldDelay = Duration(milliseconds: 8);
  static const int _maxParallelFileDeletes = 4;
  static const int _metadataRepairBatchSize = 32;
  static const int _metadataRepairMaxPerRun = 256;
  static const int _maxParallelMetadataRepairs = 4;

  final ServerConnection connection;
  final OfflineLibraryStorage _storage;
  final StreamController<List<OfflineTrackDownload>> _controller =
      StreamController<List<OfflineTrackDownload>>.broadcast();
  final StreamController<List<OfflineDownloadBatch>> _batchController =
      StreamController<List<OfflineDownloadBatch>>.broadcast();
  final StreamController<List<OfflineDownloadJob>> _jobController =
      StreamController<List<OfflineDownloadJob>>.broadcast();
  final StreamController<List<Track>> _localLikedController =
      StreamController<List<Track>>.broadcast();
  final StreamController<List<Playlist>> _localPlaylistsController =
      StreamController<List<Playlist>>.broadcast();
  final StreamController<List<Track>> _localPlaylistTracksController =
      StreamController<List<Track>>.broadcast();

  List<OfflineTrackDownload> _downloads = <OfflineTrackDownload>[];
  List<OfflineDownloadBatch> _batches = <OfflineDownloadBatch>[];
  List<OfflineDownloadJob> _jobs = <OfflineDownloadJob>[];
  final Map<String, List<OfflineDownloadJobItem>> _jobItemsByJobId =
      <String, List<OfflineDownloadJobItem>>{};
  final Map<String, List<OfflineDownloadJobSource>> _jobSourcesByJobId =
      <String, List<OfflineDownloadJobSource>>{};
  List<Track> _localLiked = <Track>[];
  List<Playlist> _localPlaylists = <Playlist>[];
  List<Track> _localPlaylistTracks = <Track>[];
  String? _localPlaylistTracksId;
  Map<String, OfflineTrackDownload> _downloadLookup =
      <String, OfflineTrackDownload>{};
  Map<String, OfflineTrackDownload> _localDownloadLookup =
      <String, OfflineTrackDownload>{};
  List<Track> _localDownloadedTracksCache = const <Track>[];
  Future<void>? _topUpFuture;
  bool _topUpRunning = false;
  final Map<String, Future<void>> _active = <String, Future<void>>{};
  final Map<String, SendPort> _activeCancelPorts = <String, SendPort>{};
  String? _lastScheduledQueueGroup;
  final Set<String> _cancelRequested = <String>{};
  final Set<String> _removedDownloadKeys = <String>{};
  final Set<String> _pausedServerUrls = <String>{};
  final Set<String> _artHydrationKeys = <String>{};
  final Map<String, OfflineTrackDownload> _pendingArtworkHydration =
      <String, OfflineTrackDownload>{};
  final Map<String, String?> _albumArtPathById = <String, String?>{};
  final Map<String, String?> _artistArtPathByKey = <String, String?>{};
  Future<void>? _loadFuture;
  Future<void>? _metadataRepairFuture;
  Future<void>? _pendingFileCleanupFuture;
  Timer? _localUserDataReloadTimer;
  Timer? _downloadsEmitTimer;
  Timer? _batchesEmitTimer;
  Timer? _jobsEmitTimer;
  Future<void> _localUserDataReloadChain = Future<void>.value();
  bool _artHydrationRunning = false;
  bool _pendingFileCleanupRequested = false;
  bool _disposed = false;
  bool _loaded = false;
  bool _resettingLocalData = false;
  int _queueAttemptSequence = 0;

  Stream<List<OfflineTrackDownload>> get stream => _controller.stream;
  Stream<List<OfflineDownloadBatch>> get batchStream => _batchController.stream;
  Stream<List<OfflineDownloadJob>> get jobStream => _jobController.stream;
  Stream<List<Track>> get localLikedStream => _localLikedController.stream;
  Stream<List<Playlist>> get localPlaylistsStream =>
      _localPlaylistsController.stream;
  Stream<List<Track>> get localPlaylistTracksStream =>
      _localPlaylistTracksController.stream;
  List<OfflineTrackDownload> get downloads => List.unmodifiable(_downloads);
  List<OfflineDownloadBatch> get batches => List.unmodifiable(_batches);
  List<OfflineDownloadJob> get jobs => List.unmodifiable(_jobs);
  List<Track> get localLiked => List.unmodifiable(_localLiked);
  List<Playlist> get localPlaylists => List.unmodifiable(_localPlaylists);
  List<Track> get localPlaylistTracks =>
      List.unmodifiable(_localPlaylistTracks);

  Future<void> load() {
    final existing = _loadFuture;
    if (existing != null) {
      return existing;
    }
    final future = _load();
    _loadFuture = future.whenComplete(() {
      _loadFuture = null;
    });
    return _loadFuture!;
  }

  Future<void> _load() async {
    await _storage.migrateManagedStoragePathsIfNeeded();
    _downloads = await _storage.readDownloads();
    _batches = await _storage.readDownloadBatches();
    _jobs = await _storage.readDownloadJobs();
    _jobItemsByJobId
      ..clear()
      ..addEntries(
        await Future.wait(
          _jobs.map((job) async {
            return MapEntry(
              job.jobId,
              await _storage.readDownloadJobItemsLean(job.jobId),
            );
          }),
        ),
      );
    _jobSourcesByJobId
      ..clear()
      ..addEntries(
        await Future.wait(
          _jobs.map((job) async {
            return MapEntry(
              job.jobId,
              await _storage.readDownloadJobSources(job.jobId),
            );
          }),
        ),
      );
    final recovered = await _recoverInterruptedDownloads(_downloads);
    if (!_sameDownloadList(_downloads, recovered)) {
      _downloads = recovered;
      await _storage.writeDownloads(_downloads);
    }
    final recoveredJobs = _recoverInterruptedJobs(_jobs);
    if (!_sameJobList(_jobs, recoveredJobs)) {
      _jobs = recoveredJobs;
      await _storage.upsertDownloadJobs(_jobs);
    }
    _rebuildDownloadIndexes();
    _loaded = true;
    await _reconcileLoadedRollingJobs();
    await _pruneDuplicateRollingJobs();
    await _loadLocalUserData();
    _emit();
    _emitBatches();
    _emitJobs();
    _schedule();
    unawaited(_cleanupPendingFileDeletes());
    unawaited(_repairOfflineMetadataFragments());
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) {
      return;
    }
    await load();
  }

  OfflineTrackDownload? findForCurrentServer(String trackId) {
    return find(connection.baseUrl, trackId);
  }

  OfflineTrackDownload? find(String serverBaseUrl, String trackId) {
    return _downloadLookup[_lookupKey(serverBaseUrl, trackId)];
  }

  OfflineTrackDownload? findLocal(String localTrackId) {
    return _localDownloadLookup[localTrackId];
  }

  List<Track> localDownloadedTracks() =>
      List.unmodifiable(_localDownloadedTracksCache);

  Future<int> downloadTrack(Track track) async {
    await _ensureLoaded();
    final baseUrl = connection.baseUrl;
    final serverTrackId = (track.serverTrackId ?? track.id).trim();
    if (serverTrackId.isEmpty) {
      return 0;
    }
    final existing = find(baseUrl, serverTrackId);
    if (_downloadQueuedOrAvailable(existing)) {
      return 0;
    }

    if (connection.token != null && connection.token!.isNotEmpty) {
      Object? batchError;
      var batchResponded = false;
      try {
        final manifest = await connection.createDownloadBatch(<String>[
          serverTrackId,
        ]);
        batchResponded = true;
        if (manifest.items.isEmpty) {
          String? reason;
          for (final item in manifest.unavailable) {
            if (item.trackId == serverTrackId) {
              reason = item.reason;
              break;
            }
          }
          throw Exception(reason ?? 'track unavailable for download');
        }
        return queueBatch(manifest, label: track.title);
      } catch (err) {
        if (batchResponded) {
          rethrow;
        }
        batchError = err;
        AppLogger.warning(
          'Download batch metadata failed for ${track.title}: $err',
        );
      }

      try {
        final metadata = await connection.fetchOfflineMetadata(serverTrackId);
        final now = DateTime.now();
        final hydratedTrack = metadata.track.copyWith(
          id: serverTrackId,
          serverBaseUrl: baseUrl,
          serverTrackId: serverTrackId,
        );
        final initial =
            existing?.copyWith(
              status: OfflineDownloadStatus.queued,
              updatedAt: now,
              filePath: null,
              error: null,
              retryCount: existing.retryCount + 1,
              track: hydratedTrack,
              offlineMetadata: metadata.copyWith(track: hydratedTrack),
            ) ??
            OfflineTrackDownload(
              serverBaseUrl: baseUrl,
              track: hydratedTrack,
              offlineMetadata: metadata.copyWith(track: hydratedTrack),
              status: OfflineDownloadStatus.queued,
              createdAt: now,
              updatedAt: now,
            );
        final queued = await _storage.prepareDownload(initial);
        _clearObsoleteStopMarkersForQueue(queued);
        await _replace(queued, persist: true);
        _schedule();
        return 1;
      } catch (err) {
        throw Exception(
          'offline metadata unavailable for ${track.title}: $err; batch error: $batchError',
        );
      }
    }

    throw Exception(
      'server session required to fetch offline metadata for ${track.title}',
    );
  }

  Future<int> queueTracks(
    Iterable<Track> tracks, {
    String? label,
    String kind = 'tracks',
    String? sourceId,
  }) async {
    await _ensureLoaded();
    final baseUrl = connection.baseUrl;
    final now = DateTime.now();
    final seen = <String>{};
    final trackList = tracks
        .map((track) {
          final id = track.id.trim();
          if (id.isEmpty || !seen.add(id)) {
            return null;
          }
          return track.copyWith(
            id: id,
            serverBaseUrl: baseUrl,
            serverTrackId: id,
          );
        })
        .whereType<Track>()
        .toList(growable: false);
    if (trackList.isEmpty) {
      return 0;
    }

    final pending = <Track>[];
    for (var index = 0; index < trackList.length; index += 1) {
      final track = trackList[index];
      final existing = find(baseUrl, track.id);
      if (_downloadQueuedOrAvailable(existing)) {
        continue;
      }
      pending.add(track);
    }
    if (pending.isEmpty) {
      return 0;
    }

    final jobId = _stableJobId(
      kind,
      _rollingJobSignature(
        label: label,
        trackIds: pending.map((track) => track.id),
      ),
    );
    final v2Queued = await _tryQueueV2DownloadJob(
      scope: DownloadJobScopeV2(
        kind: pending.length == 1 ? 'track' : 'track_set',
        id: pending.length == 1 ? pending.first.id : null,
        trackIds: pending.length == 1
            ? const <String>[]
            : pending.map((track) => track.id).toList(growable: false),
      ),
      clientRequestId: jobId,
      kind: kind,
      label: label,
      sourceId: sourceId,
    );
    if (v2Queued != null) {
      return v2Queued;
    }
    final existingJob = await _reuseOrClearRollingJob(
      jobId: jobId,
      kind: kind,
      serverBaseUrl: baseUrl,
      label: label,
      trackIds: pending.map((track) => track.id),
    );
    if (existingJob != null) {
      _scheduleTopUp();
      return 0;
    }
    final job = OfflineDownloadJob(
      jobId: jobId,
      kind: kind,
      serverBaseUrl: baseUrl,
      status: OfflineDownloadStatus.queued,
      createdAt: now,
      updatedAt: now,
      totalCount: pending.length,
      discoveredCount: pending.length,
      label: label,
      sourceId: sourceId,
    );
    final items = <OfflineDownloadJobItem>[
      for (var index = 0; index < pending.length; index += 1)
        OfflineDownloadJobItem(
          jobId: jobId,
          position: index,
          serverTrackId: pending[index].id,
          status: OfflineDownloadStatus.queued,
          materialized: false,
          createdAt: now,
          updatedAt: now,
          track: pending[index],
        ),
    ];
    await _insertRollingJob(job, items: items);
    await _topUpRollingJob(job);
    _scheduleQueuedDownloads();
    return pending.length;
  }

  Future<int> queueBatch(
    DownloadBatchManifest manifest, {
    String? label,
  }) async {
    await _ensureLoaded();
    if (manifest.items.isEmpty) {
      return 0;
    }
    if (manifest.items.length > _rollingWindowSize) {
      return _queueRollingBatch(manifest, label: label);
    }
    final baseUrl = connection.baseUrl;
    final now = DateTime.now();
    final batch = OfflineDownloadBatch(
      batchId: manifest.batchId,
      serverBaseUrl: baseUrl,
      status: OfflineDownloadStatus.queued,
      createdAt: manifest.createdAt,
      updatedAt: now,
      totalCount: manifest.items.length,
      label: label,
    );
    await _upsertBatch(batch);

    final pending = <OfflineTrackDownload>[];
    for (var index = 0; index < manifest.items.length; index += 1) {
      final item = manifest.items[index];
      final track = item.offlineMetadata.track.copyWith(
        id: item.trackId,
        serverBaseUrl: baseUrl,
        serverTrackId: item.trackId,
      );
      final offlineMetadata = item.offlineMetadata.copyWith(track: track);
      final existing = find(baseUrl, item.trackId);
      if (_downloadQueuedOrAvailable(existing)) {
        continue;
      }
      final download =
          existing?.copyWith(
            batchId: manifest.batchId,
            downloadUrl: item.downloadUrl,
            status: OfflineDownloadStatus.queued,
            updatedAt: now,
            filePath: null,
            bytesTotal: item.byteLength > 0 ? item.byteLength : null,
            etag: item.etag.isEmpty ? null : item.etag,
            expectedSha256: item.sha256.isEmpty ? null : item.sha256,
            contentType: item.contentType,
            error: null,
            retryCount: existing.retryCount + 1,
            priority: manifest.items.length - index,
            track: track,
            offlineMetadata: offlineMetadata,
          ) ??
          OfflineTrackDownload(
            serverBaseUrl: baseUrl,
            batchId: manifest.batchId,
            downloadUrl: item.downloadUrl,
            track: track,
            offlineMetadata: offlineMetadata,
            status: OfflineDownloadStatus.queued,
            createdAt: now,
            updatedAt: now,
            bytesTotal: item.byteLength > 0 ? item.byteLength : null,
            etag: item.etag.isEmpty ? null : item.etag,
            expectedSha256: item.sha256.isEmpty ? null : item.sha256,
            contentType: item.contentType,
            priority: manifest.items.length - index,
          );
      pending.add(download);
    }
    var queuedCount = 0;
    if (pending.isNotEmpty) {
      for (final chunk in _chunks(pending, _queuePersistChunkSize)) {
        final prepared = await _storage.prepareDownloads(chunk);
        _replaceManyInMemory(prepared);
        await _storage.upsertDownloads(prepared);
        queuedCount += prepared.length;
        await Future<void>.delayed(_queuePersistYieldDelay);
      }
      await _refreshBatchCounts(manifest.batchId);
      _schedule();
    } else {
      await _refreshBatchCounts(manifest.batchId);
    }
    return queuedCount;
  }

  Future<int?> _tryQueueV2DownloadJob({
    required DownloadJobScopeV2 scope,
    required String clientRequestId,
    required String kind,
    String? label,
    String? sourceId,
  }) async {
    try {
      final capabilities = await connection.fetchCapabilities();
      if (!capabilities.downloadJobsV2) {
        return null;
      }
      final clientId = await _storage.readOrCreateClientId();
      final serverJob = await connection.createDownloadJob(
        clientId: clientId,
        clientRequestId: _queueAttemptRequestId(clientRequestId),
        scope: scope,
      );
      return _ingestV2DownloadJob(
        serverJob,
        kind: kind,
        label: label,
        sourceId: sourceId,
      );
    } catch (err, stackTrace) {
      AppLogger.warning(
        'Falling back to legacy offline queue after v2 job failure: $err',
      );
      developer.log(
        'v2 download job queue failed',
        name: 'OfflineDownloadManager',
        error: err,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<int> _ingestV2DownloadJob(
    DownloadJobV2 serverJob, {
    required String kind,
    String? label,
    String? sourceId,
  }) async {
    final jobId = serverJob.jobId.trim();
    if (jobId.isEmpty) {
      return 0;
    }
    final existingJob = _jobById(jobId);
    if (existingJob != null && _jobBlocksNewQueue(existingJob)) {
      return 0;
    }
    if (existingJob != null) {
      await _deleteRollingJob(jobId, removePendingDownloads: true);
    }
    final baseUrl = connection.baseUrl;
    final now = DateTime.now();
    final job = OfflineDownloadJob(
      jobId: jobId,
      kind: kind,
      serverBaseUrl: baseUrl,
      status: _statusFromV2Job(serverJob.status, freshQueue: true),
      createdAt: serverJob.createdAt,
      updatedAt: now,
      totalCount: serverJob.totalCount,
      discoveredCount: serverJob.items.length,
      failedCount: serverJob.failedCount,
      label: label,
      sourceId: sourceId ?? _v2ScopeSourceId(serverJob.scope, kind),
    );
    final jobItems = <OfflineDownloadJobItem>[
      for (final item in serverJob.items)
        OfflineDownloadJobItem(
          jobId: jobId,
          position: item.position,
          serverTrackId: item.trackId,
          status: _statusFromV2JobItem(item, freshQueue: true),
          materialized: false,
          createdAt: serverJob.createdAt,
          updatedAt: now,
          track: item.offlineMetadata?.track.copyWith(
            id: item.trackId,
            serverBaseUrl: baseUrl,
            serverTrackId: item.trackId,
          ),
          offlineMetadata: item.offlineMetadata,
          error: item.error,
        ),
    ];
    await _insertRollingJob(job, items: jobItems);

    final downloads = <OfflineTrackDownload>[];
    for (final item in serverJob.items) {
      if (downloads.length >= _rollingWindowSize) {
        break;
      }
      final freshPausedItem =
          item.status == 'paused' && item.offlineMetadata != null;
      if (!item.readyToDownload && !freshPausedItem) {
        continue;
      }
      final metadata = item.offlineMetadata!;
      final track = metadata.track.copyWith(
        id: item.trackId,
        serverBaseUrl: baseUrl,
        serverTrackId: item.trackId,
      );
      final hydratedMetadata = metadata.copyWith(track: track);
      final existing = find(baseUrl, item.trackId);
      if (_downloadQueuedOrAvailable(existing)) {
        continue;
      }
      downloads.add(
        existing?.copyWith(
              batchId: jobId,
              downloadUrl: item.downloadUrl,
              status: OfflineDownloadStatus.queued,
              updatedAt: now,
              filePath: null,
              bytesTotal: item.byteLength,
              etag: item.etag,
              expectedSha256: item.sha256,
              contentType: item.contentType,
              error: null,
              retryCount: existing.retryCount + 1,
              priority: serverJob.items.length - item.position,
              track: track,
              offlineMetadata: hydratedMetadata,
            ) ??
            OfflineTrackDownload(
              serverBaseUrl: baseUrl,
              batchId: jobId,
              downloadUrl: item.downloadUrl,
              track: track,
              offlineMetadata: hydratedMetadata,
              status: OfflineDownloadStatus.queued,
              createdAt: now,
              updatedAt: now,
              bytesTotal: item.byteLength,
              etag: item.etag,
              expectedSha256: item.sha256,
              contentType: item.contentType,
              priority: serverJob.items.length - item.position,
            ),
      );
    }
    if (downloads.isNotEmpty) {
      await _persistMaterializedDownloads(jobId, downloads);
      _scheduleQueuedDownloads();
    } else {
      await _refreshJobCounts(jobId);
    }
    return serverJob.totalCount > 0 ? serverJob.totalCount : downloads.length;
  }

  OfflineDownloadStatus _statusFromV2Job(
    String status, {
    bool freshQueue = false,
  }) {
    switch (status) {
      case 'downloading':
        return OfflineDownloadStatus.downloading;
      case 'paused':
        return freshQueue
            ? OfflineDownloadStatus.queued
            : OfflineDownloadStatus.paused;
      case 'complete':
        return OfflineDownloadStatus.downloaded;
      case 'failed':
      case 'metadata_failed':
        return OfflineDownloadStatus.failed;
      case 'canceled':
        return OfflineDownloadStatus.canceled;
      case 'removing':
        return OfflineDownloadStatus.removing;
      case 'resolving_metadata':
      case 'ready_to_download':
      case 'queued':
      default:
        return OfflineDownloadStatus.queued;
    }
  }

  String? _v2ScopeSourceId(DownloadJobScopeV2 scope, String kind) {
    if (kind != 'artist' && kind != 'album') {
      return null;
    }
    final id = scope.id?.trim();
    return id == null || id.isEmpty ? null : id;
  }

  OfflineDownloadStatus _statusFromV2JobItem(
    DownloadJobItemV2 item, {
    bool freshQueue = false,
  }) {
    switch (item.status) {
      case 'downloading':
        return OfflineDownloadStatus.downloading;
      case 'paused':
        return freshQueue
            ? OfflineDownloadStatus.queued
            : OfflineDownloadStatus.paused;
      case 'complete':
        return OfflineDownloadStatus.downloaded;
      case 'failed':
      case 'metadata_failed':
        return OfflineDownloadStatus.failed;
      case 'canceled':
        return OfflineDownloadStatus.canceled;
      case 'removing':
        return OfflineDownloadStatus.removing;
      case 'verifying':
        return OfflineDownloadStatus.validating;
      case 'ready_to_download':
        return item.readyToDownload
            ? OfflineDownloadStatus.queued
            : OfflineDownloadStatus.failed;
      case 'resolving_metadata':
      case 'queued':
      default:
        return OfflineDownloadStatus.queued;
    }
  }

  Future<int> queueArtist(Artist artist, List<Album> albums) async {
    await _ensureLoaded();
    final sources = albums
        .where((album) => album.id.trim().isNotEmpty)
        .toList(growable: false);
    if (sources.isEmpty) {
      return 0;
    }
    final now = DateTime.now();
    final baseUrl = connection.baseUrl;
    final jobId = _stableJobId(
      'artist',
      _rollingJobSignature(
        label: artist.name,
        sourceIds: sources.map((album) => album.id),
      ),
    );
    final v2Queued = await _tryQueueV2DownloadJob(
      scope: DownloadJobScopeV2(kind: 'artist', id: artist.id),
      clientRequestId: jobId,
      kind: 'artist',
      label: artist.name,
      sourceId: artist.id,
    );
    if (v2Queued != null) {
      return v2Queued;
    }
    final existingJob = await _reuseOrClearRollingJob(
      jobId: jobId,
      kind: 'artist',
      serverBaseUrl: baseUrl,
      label: artist.name,
      sourceIds: sources.map((album) => album.id),
    );
    if (existingJob != null) {
      _scheduleTopUp();
      return 0;
    }
    final job = OfflineDownloadJob(
      jobId: jobId,
      kind: 'artist',
      serverBaseUrl: baseUrl,
      status: OfflineDownloadStatus.queued,
      createdAt: now,
      updatedAt: now,
      totalCount: sources.fold<int>(0, (sum, album) => sum + album.trackCount),
      label: artist.name,
      sourceId: artist.id,
    );
    final jobSources = <OfflineDownloadJobSource>[
      for (var index = 0; index < sources.length; index += 1)
        OfflineDownloadJobSource(
          jobId: job.jobId,
          position: index,
          sourceId: sources[index].id,
          status: OfflineDownloadStatus.queued,
          createdAt: now,
          updatedAt: now,
          label: sources[index].title,
        ),
    ];
    await _insertRollingJob(job, sources: jobSources);
    _scheduleTopUp();
    return job.totalCount > 0 ? job.totalCount : sources.length;
  }

  Future<void> pauseDownload(OfflineTrackDownload download) async {
    final current = find(download.serverBaseUrl, _serverTrackId(download));
    if (current == null || !_canPause(current.status)) {
      return;
    }
    final key = _downloadKey(current);
    _cancelRequested.add(key);
    _activeCancelPorts[key]?.send(null);
    await _replace(
      current.copyWith(
        status: OfflineDownloadStatus.paused,
        updatedAt: DateTime.now(),
        error: null,
      ),
      persist: true,
    );
  }

  Future<void> resumeDownload(OfflineTrackDownload download) async {
    final current = find(download.serverBaseUrl, _serverTrackId(download));
    if (current == null) {
      return;
    }
    final parentJob = _pausedParentJob(current);
    if (parentJob != null &&
        (current.status == OfflineDownloadStatus.paused ||
            current.status == OfflineDownloadStatus.queued)) {
      await resumeDownloadJob(parentJob);
      return;
    }
    if (!_canResume(current.status)) {
      return;
    }
    _pausedServerUrls.remove(current.serverBaseUrl);
    if (current.status == OfflineDownloadStatus.corrupt) {
      await _deleteIfExists(current.partialPath);
    }
    await _replace(
      current.copyWith(
        status: OfflineDownloadStatus.queued,
        updatedAt: DateTime.now(),
        partialPath: current.status == OfflineDownloadStatus.corrupt
            ? null
            : current.partialPath,
        bytesDownloaded: current.status == OfflineDownloadStatus.corrupt
            ? 0
            : current.bytesDownloaded,
        error: null,
        retryCount: current.retryCount + 1,
      ),
      persist: true,
    );
    _schedule();
  }

  Future<void> retryDownload(OfflineTrackDownload download) async {
    await resumeDownload(download);
  }

  Future<void> cancelDownload(OfflineTrackDownload download) async {
    final current = find(download.serverBaseUrl, _serverTrackId(download));
    if (current == null || current.status == OfflineDownloadStatus.downloaded) {
      return;
    }
    final key = _downloadKey(current);
    _cancelRequested.add(key);
    _activeCancelPorts[key]?.send(null);
    if (!_active.containsKey(key)) {
      await _deleteIfExists(current.partialPath);
    }
    await _replace(
      current.copyWith(
        status: OfflineDownloadStatus.canceled,
        updatedAt: DateTime.now(),
        partialPath: null,
        bytesDownloaded: 0,
        error: null,
      ),
      persist: true,
    );
  }

  Future<void> pauseDownloadsForServer(String serverBaseUrl) async {
    final normalized = serverBaseUrl.trim();
    if (normalized.isEmpty) {
      return;
    }
    _pausedServerUrls.add(normalized);
    final now = DateTime.now();
    var changed = false;
    final pausedJobs = <OfflineDownloadJob>[];
    _jobs = _jobs
        .map((job) {
          if (job.serverBaseUrl != normalized || !_canPause(job.status)) {
            return job;
          }
          final updated = job.copyWith(
            status: OfflineDownloadStatus.paused,
            updatedAt: now,
          );
          pausedJobs.add(updated);
          return updated;
        })
        .toList(growable: false);
    if (pausedJobs.isNotEmpty) {
      await _storage.upsertDownloadJobs(pausedJobs);
      _emitJobs();
      changed = true;
    }
    for (final download in _downloads) {
      if (download.serverBaseUrl != normalized || !_canPause(download.status)) {
        continue;
      }
      final key = _downloadKey(download);
      _cancelRequested.add(key);
      _activeCancelPorts[key]?.send(null);
      await _replace(
        download.copyWith(
          status: OfflineDownloadStatus.paused,
          updatedAt: now,
          error: null,
        ),
        persist: true,
      );
      changed = true;
    }
    if (changed) {
      AppLogger.status('Paused downloads for $normalized');
    }
  }

  Future<void> resumePausedForCurrentServer() async {
    if (connection.token == null || connection.token!.isEmpty) {
      return;
    }
    final baseUrl = connection.baseUrl;
    _pausedServerUrls.remove(baseUrl);
    final now = DateTime.now();
    var changed = false;
    for (final download in _downloads) {
      if (download.serverBaseUrl != baseUrl ||
          download.status != OfflineDownloadStatus.paused) {
        continue;
      }
      await _replace(
        download.copyWith(
          status: OfflineDownloadStatus.queued,
          updatedAt: now,
          error: null,
        ),
        persist: true,
      );
      changed = true;
    }
    final resumedJobs = <OfflineDownloadJob>[];
    _jobs = _jobs
        .map((job) {
          if (job.serverBaseUrl != baseUrl ||
              job.status != OfflineDownloadStatus.paused) {
            return job;
          }
          final updated = job.copyWith(
            status: OfflineDownloadStatus.queued,
            updatedAt: now,
          );
          resumedJobs.add(updated);
          return updated;
        })
        .toList(growable: false);
    if (resumedJobs.isNotEmpty) {
      await _storage.upsertDownloadJobs(resumedJobs);
      _emitJobs();
      changed = true;
    }
    if (changed) {
      AppLogger.status('Resuming paused downloads for $baseUrl');
      _schedule();
    }
  }

  Future<void> repairOfflineMetadataFragments() async {
    await _ensureLoaded();
    await _repairOfflineMetadataFragments();
  }

  Future<void> refreshOfflineMetadataForAlbum(String albumId) async {
    await _ensureLoaded();
    final id = albumId.trim();
    if (id.isEmpty) {
      return;
    }
    await _refreshOfflineMetadataWhere(
      (download) =>
          _nonEmpty(download.track.albumId) == id ||
          _nonEmpty(download.offlineMetadata?.album.id) == id,
    );
  }

  Future<void> refreshOfflineMetadataForArtist(String artistId) async {
    await _ensureLoaded();
    final id = artistId.trim();
    if (id.isEmpty) {
      return;
    }
    await _refreshOfflineMetadataWhere(
      (download) =>
          _nonEmpty(download.track.artistId) == id ||
          _nonEmpty(download.offlineMetadata?.artist.id) == id,
    );
  }

  Future<void> pauseDownloadJob(OfflineDownloadJob job) async {
    final current = _jobById(job.jobId);
    if (current == null || current.status == OfflineDownloadStatus.paused) {
      return;
    }
    final updated = current.copyWith(
      status: OfflineDownloadStatus.paused,
      updatedAt: DateTime.now(),
    );
    _jobs = _jobs
        .map((item) => item.jobId == updated.jobId ? updated : item)
        .toList(growable: false);
    await _storage.upsertDownloadJob(updated);
    _emitJobs();
    final activeDownloads = _downloads
        .where(
          (download) =>
              download.batchId == updated.jobId &&
              (_active.containsKey(_downloadKey(download)) ||
                  _activeDownloadStatus(download.status)),
        )
        .toList(growable: false);
    for (final download in activeDownloads) {
      await pauseDownload(download);
    }
  }

  Future<void> resumeDownloadJob(OfflineDownloadJob job) async {
    final current = _jobById(job.jobId);
    if (current == null || current.status != OfflineDownloadStatus.paused) {
      return;
    }
    _pausedServerUrls.remove(current.serverBaseUrl);
    final now = DateTime.now();
    final pausedDownloads = _downloads
        .where(
          (download) =>
              download.batchId == current.jobId &&
              download.status == OfflineDownloadStatus.paused,
        )
        .toList(growable: false);
    final requeuedDownloads = <OfflineTrackDownload>[
      for (final download in pausedDownloads)
        download.copyWith(
          status: OfflineDownloadStatus.queued,
          updatedAt: now,
          error: null,
        ),
    ];
    if (requeuedDownloads.isNotEmpty) {
      _replaceManyInMemory(requeuedDownloads);
      await _storage.upsertDownloads(requeuedDownloads);
      await _markJobItems(
        current.jobId,
        requeuedDownloads.map(_serverTrackId),
        OfflineDownloadStatus.queued,
        materialized: true,
        tracksById: {
          for (final download in requeuedDownloads)
            _serverTrackId(download): download.track,
        },
      );
    }
    final updated = current.copyWith(
      status: OfflineDownloadStatus.queued,
      updatedAt: now,
    );
    _jobs = _jobs
        .map((item) => item.jobId == updated.jobId ? updated : item)
        .toList(growable: false);
    await _storage.upsertDownloadJob(updated);
    _emitJobs();
    _schedule();
  }

  Future<void> cancelDownloadJob(OfflineDownloadJob job) async {
    final current = _jobById(job.jobId);
    if (current == null) {
      return;
    }
    await _deleteRollingJob(current.jobId, removePendingDownloads: true);
  }

  Future<void> removeTrack(String trackId) async {
    final download = findForCurrentServer(trackId);
    if (download == null) {
      return;
    }
    await removeDownload(download);
  }

  Future<void> removeDownload(OfflineTrackDownload download) async {
    await removeDownloads(<OfflineTrackDownload>[download]);
  }

  Future<void> removeDownloads(
    Iterable<OfflineTrackDownload> downloads, {
    OfflineDeletionScope scope = const OfflineDeletionScope.track(),
  }) async {
    await _ensureLoaded();
    final byKey = <String, OfflineTrackDownload>{};
    for (final download in downloads) {
      byKey[_downloadKey(download)] = download;
    }
    if (byKey.isEmpty) {
      return;
    }

    final removeKeys = byKey.keys.toSet();
    final currentByKey = <String, OfflineTrackDownload>{};
    for (final download in _downloads) {
      final key = _downloadKey(download);
      if (removeKeys.contains(key) &&
          download.status != OfflineDownloadStatus.removing) {
        currentByKey[key] = download;
      }
    }
    final removals = currentByKey.values.toList(growable: false);
    if (removals.isEmpty) {
      return;
    }

    final batchIds = <String>{};
    final v2JobIds = <String>{};
    final now = DateTime.now();
    for (final download in removals) {
      final key = _downloadKey(download);
      _removedDownloadKeys.add(key);
      _cancelRequested.add(key);
      _activeCancelPorts[key]?.send(null);
      final batchId = download.batchId;
      if (batchId != null) {
        batchIds.add(batchId);
        if (_downloadBelongsToV2Job(download)) {
          v2JobIds.add(batchId);
        }
      }
    }

    _downloads = _downloads
        .map((download) {
          final key = _downloadKey(download);
          if (!currentByKey.containsKey(key)) {
            return download;
          }
          return download.copyWith(
            status: OfflineDownloadStatus.removing,
            updatedAt: now,
            error: null,
          );
        })
        .toList(growable: false);
    _rebuildDownloadIndexes();
    _emit();

    await _storage.removeDownloadsScoped(
      OfflineDeletionRequest(scope: scope, downloads: removals),
    );
    await _cleanupPendingFileDeletes();
    _downloads = _downloads
        .where((download) => !removeKeys.contains(_downloadKey(download)))
        .toList(growable: false);
    _rebuildDownloadIndexes();
    _emit();
    await _loadLocalUserData();
    for (final batchId in batchIds) {
      if (_isRollingJob(batchId)) {
        await _markJobItems(
          batchId,
          removals
              .where((download) => download.batchId == batchId)
              .map(_serverTrackId),
          OfflineDownloadStatus.canceled,
          materialized: true,
          clearPayload: true,
        );
        await _refreshJobCounts(batchId);
        await _deleteRollingJobIfAbandoned(batchId);
      } else {
        await _refreshBatchCounts(batchId);
      }
    }
    for (final batchId in v2JobIds) {
      await _retireServerDownloadJobIfUnused(batchId);
    }
    _schedule();
    unawaited(_cleanupPendingFileDeletes());
  }

  Future<void> clearFailedAndCorrupt() async {
    final removable = _downloads
        .where(
          (download) =>
              download.status == OfflineDownloadStatus.failed ||
              download.status == OfflineDownloadStatus.corrupt ||
              download.status == OfflineDownloadStatus.canceled,
        )
        .toList(growable: false);
    await removeDownloads(removable);
    final failedJobs = _jobs
        .where(
          (job) =>
              job.status == OfflineDownloadStatus.failed ||
              job.status == OfflineDownloadStatus.corrupt ||
              job.status == OfflineDownloadStatus.canceled,
        )
        .toList(growable: false);
    for (final job in failedJobs) {
      await _deleteRollingJob(job.jobId, removePendingDownloads: true);
    }
  }

  Future<void> resetLocalData() async {
    await _ensureLoaded();
    _resettingLocalData = true;
    try {
      _localUserDataReloadTimer?.cancel();
      _localUserDataReloadTimer = null;
      _pendingArtworkHydration.clear();
      _pendingFileCleanupRequested = false;
      for (final download in _downloads) {
        final key = _downloadKey(download);
        _removedDownloadKeys.add(key);
        _cancelRequested.add(key);
        _activeCancelPorts[key]?.send(null);
      }
      await _topUpFuture;
      await Future.wait(_active.values.toList(), eagerError: false);
      await _pendingFileCleanupFuture;
      await _storage.resetLocalData();
      _downloads = const <OfflineTrackDownload>[];
      _batches = const <OfflineDownloadBatch>[];
      _jobs = const <OfflineDownloadJob>[];
      _localLiked = const <Track>[];
      _localPlaylists = const <Playlist>[];
      _localPlaylistTracks = const <Track>[];
      _localPlaylistTracksId = null;
      _localDownloadedTracksCache = const <Track>[];
      _jobItemsByJobId.clear();
      _jobSourcesByJobId.clear();
      _albumArtPathById.clear();
      _artistArtPathByKey.clear();
      _pausedServerUrls.clear();
      _rebuildDownloadIndexes();
      _emit();
      _emitBatches();
      _emitJobs();
      _emitLocalPlaylists();
      _emitLocalLiked();
      _emitLocalPlaylistTracks();
    } finally {
      _cancelRequested.clear();
      _removedDownloadKeys.clear();
      _artHydrationKeys.clear();
      _pendingArtworkHydration.clear();
      _resettingLocalData = false;
    }
  }

  Future<void> loadLocalPlaylists() async {
    _localPlaylists = await _storage.readLocalPlaylists();
    _rebuildDownloadIndexes();
    _emitLocalPlaylists();
  }

  Future<void> loadLocalPlaylistTracks(String playlistId) async {
    _localPlaylistTracksId = playlistId;
    _localPlaylistTracks = await _storage.readLocalPlaylistTracks(playlistId);
    _emitLocalPlaylistTracks();
  }

  Future<void> loadLocalLikedTracks() async {
    _localLiked = await _storage.readLocalLikedTracks();
    _rebuildDownloadIndexes();
    _emitLocalLiked();
  }

  Future<void> setLocalLike(Track track, bool liked) async {
    final localId = _localTrackId(track);
    if (localId == null) {
      throw StateError('Track must be downloaded before saving local likes.');
    }
    await _storage.setLocalLike(localId, liked);
    await _loadLocalUserData();
  }

  Future<List<LocalLikeState>> readLocalLikeStates() {
    return _storage.readLocalLikeStates();
  }

  Future<List<ServerLikeSync>> readServerLikeSyncs(String serverBaseUrl) {
    return _storage.readServerLikeSyncs(serverBaseUrl);
  }

  Future<void> upsertServerLikeSyncs(List<ServerLikeSync> syncs) {
    return _storage.upsertServerLikeSyncs(syncs);
  }

  Future<void> applySyncedLocalLikeState(
    String localTrackId,
    bool liked,
    int updatedAt,
  ) async {
    await _storage.applySyncedLocalLikeState(localTrackId, liked, updatedAt);
    await _loadLocalUserData();
  }

  Future<Playlist> createLocalPlaylist(
    String name, {
    String? description,
  }) async {
    final playlist = await _storage.createLocalPlaylist(
      name,
      description: description,
    );
    await loadLocalPlaylists();
    return playlist;
  }

  Future<Playlist?> renameLocalPlaylist(
    String playlistId,
    String name, {
    String? description,
  }) async {
    final playlist = await _storage.renameLocalPlaylist(
      playlistId,
      name,
      description: description,
    );
    await loadLocalPlaylists();
    return playlist;
  }

  Future<Playlist?> updateLocalPlaylistImage(
    String playlistId,
    PlaylistImageEdit imageEdit,
  ) async {
    final playlist = await _storage.updateLocalPlaylistImage(
      playlistId,
      imageEdit,
    );
    await loadLocalPlaylists();
    return playlist;
  }

  Future<void> deleteLocalPlaylist(String playlistId) async {
    await _storage.deleteLocalPlaylist(playlistId);
    await loadLocalPlaylists();
    if (_localPlaylistTracksId == playlistId) {
      _localPlaylistTracksId = null;
      _localPlaylistTracks = <Track>[];
      _emitLocalPlaylistTracks();
    }
  }

  Future<Playlist?> addLocalTrackToPlaylist(
    Playlist playlist,
    Track track,
  ) async {
    final localId = _localTrackId(track);
    if (localId == null) {
      throw StateError(
        'Track must be downloaded before saving local playlists.',
      );
    }
    final updated = await _storage.addLocalTrackToPlaylist(
      playlist.id,
      localId,
    );
    await _loadLocalUserData();
    return updated;
  }

  Future<Playlist?> removeLocalTrackFromPlaylist(
    Playlist playlist,
    Track track,
  ) async {
    final localId = _localTrackId(track);
    if (localId == null) {
      return playlist;
    }
    final updated = await _storage.removeLocalTrackFromPlaylist(
      playlist.id,
      localId,
    );
    await _loadLocalUserData();
    return updated;
  }

  Future<void> dispose() async {
    _disposed = true;
    _localUserDataReloadTimer?.cancel();
    _localUserDataReloadTimer = null;
    _downloadsEmitTimer?.cancel();
    _downloadsEmitTimer = null;
    _batchesEmitTimer?.cancel();
    _batchesEmitTimer = null;
    _jobsEmitTimer?.cancel();
    _jobsEmitTimer = null;
    await Future.wait(_active.values.toList(), eagerError: false);
    await _topUpFuture;
    await _localUserDataReloadChain;
    await _pendingFileCleanupFuture;
    await _controller.close();
    await _batchController.close();
    await _jobController.close();
    await _localLikedController.close();
    await _localPlaylistsController.close();
    await _localPlaylistTracksController.close();
  }

  void _schedule() {
    _scheduleTopUp();
    _scheduleQueuedDownloads();
  }

  void _scheduleTopUp() {
    if (_resettingLocalData) {
      return;
    }
    if (_topUpFuture != null) {
      return;
    }
    _topUpFuture = _topUpRollingJobsForCurrentServer().whenComplete(() {
      _topUpFuture = null;
    });
    unawaited(_topUpFuture);
  }

  void _scheduleQueuedDownloads() {
    if (!_loaded || _disposed) {
      return;
    }
    if (_resettingLocalData) {
      return;
    }
    if (connection.token == null || connection.token!.isEmpty) {
      return;
    }
    final baseUrl = connection.baseUrl;
    if (_pausedServerUrls.contains(baseUrl)) {
      return;
    }
    final activeForServer = _active.keys
        .where((key) => key.startsWith('$baseUrl\n'))
        .length;
    var slots = maxParallelDownloadsPerServer - activeForServer;
    if (slots <= 0) {
      return;
    }
    final candidates =
        _downloads
            .where(
              (download) =>
                  download.serverBaseUrl == baseUrl &&
                  download.status == OfflineDownloadStatus.queued &&
                  !_active.containsKey(_downloadKey(download)) &&
                  !_queuedDownloadBlockedByPausedJob(download),
            )
            .toList()
          ..sort(_compareQueuedForScheduling);
    final groups = <String, List<OfflineTrackDownload>>{};
    for (final download in candidates) {
      groups
          .putIfAbsent(_queueGroupKey(download), () => <OfflineTrackDownload>[])
          .add(download);
    }
    while (slots > 0 && groups.isNotEmpty) {
      final groupKey = _nextQueueGroupKey(groups.keys.toList(growable: false));
      final group = groups[groupKey]!;
      final download = group.removeAt(0);
      if (group.isEmpty) {
        groups.remove(groupKey);
      }
      _startQueuedDownload(download);
      _lastScheduledQueueGroup = groupKey;
      slots -= 1;
    }
  }

  void _startQueuedDownload(OfflineTrackDownload download) {
    final key = _downloadKey(download);
    final future = _runDownload(download).whenComplete(() {
      _active.remove(key);
      _activeCancelPorts.remove(key);
      _cancelRequested.remove(key);
      _schedule();
    });
    _active[key] = future;
    unawaited(future);
  }

  String _nextQueueGroupKey(List<String> groupKeys) {
    final last = _lastScheduledQueueGroup;
    if (last == null) {
      return groupKeys.first;
    }
    final lastIndex = groupKeys.indexOf(last);
    if (lastIndex < 0) {
      return groupKeys.first;
    }
    return groupKeys[(lastIndex + 1) % groupKeys.length];
  }

  String _queueGroupKey(OfflineTrackDownload download) {
    final batchId = download.batchId;
    if (batchId != null && batchId.trim().isNotEmpty) {
      return 'batch:${download.serverBaseUrl}\n$batchId';
    }
    return 'track:${_downloadKey(download)}';
  }

  bool _queuedDownloadBlockedByPausedJob(OfflineTrackDownload download) {
    final batchId = download.batchId;
    if (batchId == null || batchId.trim().isEmpty) {
      return false;
    }
    final job = _jobById(batchId);
    return job != null && job.status == OfflineDownloadStatus.paused;
  }

  int _compareQueuedForScheduling(
    OfflineTrackDownload left,
    OfflineTrackDownload right,
  ) {
    final priority = right.priority.compareTo(left.priority);
    if (priority != 0) {
      return priority;
    }
    return left.createdAt.compareTo(right.createdAt);
  }

  Future<int> _queueRollingBatch(
    DownloadBatchManifest manifest, {
    String? label,
  }) async {
    final baseUrl = connection.baseUrl;
    final now = DateTime.now();
    final jobId = manifest.batchId.trim().isEmpty
        ? _stableJobId(
            'batch',
            _rollingJobSignature(
              label: label,
              trackIds: manifest.items.map((item) => item.trackId),
            ),
          )
        : manifest.batchId.trim();
    final existingJob = await _reuseOrClearRollingJob(
      jobId: jobId,
      kind: 'batch',
      serverBaseUrl: baseUrl,
      label: label,
      trackIds: manifest.items.map((item) => item.trackId),
    );
    if (existingJob != null) {
      _scheduleTopUp();
      return 0;
    }
    final job = OfflineDownloadJob(
      jobId: jobId,
      kind: 'batch',
      serverBaseUrl: baseUrl,
      status: OfflineDownloadStatus.queued,
      createdAt: manifest.createdAt,
      updatedAt: now,
      totalCount: manifest.items.length,
      discoveredCount: manifest.items.length,
      label: label,
    );
    final items = <OfflineDownloadJobItem>[
      for (var index = 0; index < manifest.items.length; index += 1)
        OfflineDownloadJobItem(
          jobId: jobId,
          position: index,
          serverTrackId: manifest.items[index].trackId,
          status: OfflineDownloadStatus.queued,
          materialized: false,
          createdAt: now,
          updatedAt: now,
          track: manifest.items[index].offlineMetadata.track.copyWith(
            id: manifest.items[index].trackId,
            serverBaseUrl: baseUrl,
            serverTrackId: manifest.items[index].trackId,
          ),
          offlineMetadata: manifest.items[index].offlineMetadata.copyWith(
            track: manifest.items[index].offlineMetadata.track.copyWith(
              id: manifest.items[index].trackId,
              serverBaseUrl: baseUrl,
              serverTrackId: manifest.items[index].trackId,
            ),
          ),
        ),
    ];
    await _insertRollingJob(job, items: items);
    await _materializeManifestItems(
      job,
      manifest.items.take(_rollingWindowSize).toList(growable: false),
    );
    _scheduleQueuedDownloads();
    return manifest.items.length;
  }

  Future<void> _insertRollingJob(
    OfflineDownloadJob job, {
    List<OfflineDownloadJobItem> items = const <OfflineDownloadJobItem>[],
    List<OfflineDownloadJobSource> sources = const <OfflineDownloadJobSource>[],
  }) async {
    _jobs = [job, ..._jobs.where((item) => item.jobId != job.jobId)];
    _jobItemsByJobId[job.jobId] = items;
    _jobSourcesByJobId[job.jobId] = sources;
    await _storage.upsertDownloadJob(job);
    await _storage.upsertDownloadJobItems(items);
    await _storage.upsertDownloadJobSources(sources);
    await _upsertBatch(
      OfflineDownloadBatch(
        batchId: job.jobId,
        serverBaseUrl: job.serverBaseUrl,
        status: job.status,
        createdAt: job.createdAt,
        updatedAt: job.updatedAt,
        totalCount: job.totalCount > 0 ? job.totalCount : job.discoveredCount,
        completedCount: job.completedCount,
        failedCount: job.failedCount,
        label: job.label,
      ),
    );
    _emitJobs();
  }

  Future<OfflineDownloadJob?> _reuseOrClearRollingJob({
    required String jobId,
    required String kind,
    required String serverBaseUrl,
    required String? label,
    Iterable<String> trackIds = const <String>[],
    Iterable<String> sourceIds = const <String>[],
  }) async {
    final duplicates = _jobs
        .where(
          (job) =>
              job.jobId == jobId ||
              _jobMatchesRollingCollection(
                job,
                kind: kind,
                serverBaseUrl: serverBaseUrl,
                label: label,
                trackIds: trackIds,
                sourceIds: sourceIds,
              ),
        )
        .toList(growable: false);
    if (duplicates.isEmpty) {
      return null;
    }

    final blocking = duplicates
        .where(_jobBlocksNewQueue)
        .toList(growable: false);
    if (blocking.isNotEmpty) {
      final keep = _chooseRollingJobToKeep(blocking);
      for (final duplicate in duplicates) {
        if (duplicate.jobId != keep.jobId) {
          await _deleteRollingJob(
            duplicate.jobId,
            removePendingDownloads: true,
          );
        }
      }
      return keep;
    }

    for (final duplicate in duplicates) {
      await _deleteRollingJob(duplicate.jobId, removePendingDownloads: true);
    }
    return null;
  }

  Future<void> _reconcileLoadedRollingJobs() async {
    for (final job in List<OfflineDownloadJob>.from(_jobs)) {
      final items = List<OfflineDownloadJobItem>.from(
        _jobItemsByJobId[job.jobId] ?? const <OfflineDownloadJobItem>[],
      );
      if (items.isEmpty) {
        await _refreshJobCounts(job.jobId);
        continue;
      }

      final changed = <OfflineDownloadJobItem>[];
      for (var index = 0; index < items.length; index += 1) {
        final item = items[index];
        if (!item.materialized || _terminalStatus(item.status)) {
          continue;
        }
        final download = find(job.serverBaseUrl, item.serverTrackId);
        OfflineDownloadJobItem? updated;
        if (download == null) {
          updated = item.copyWith(
            status: OfflineDownloadStatus.canceled,
            updatedAt: DateTime.now(),
            error: 'download row removed',
          );
        } else if (download.batchId != job.jobId) {
          updated = item.copyWith(
            status: _downloadAvailable(download)
                ? OfflineDownloadStatus.downloaded
                : OfflineDownloadStatus.canceled,
            updatedAt: DateTime.now(),
            track: download.track,
            error: _downloadAvailable(download)
                ? null
                : 'download owned by another job',
          );
        } else if (download.status != item.status || item.track == null) {
          updated = item.copyWith(
            status: download.status,
            updatedAt: download.updatedAt,
            track: download.track,
            error: download.error,
          );
        }
        if (updated == null) {
          continue;
        }
        items[index] = updated;
        changed.add(updated);
      }
      if (changed.isNotEmpty) {
        _jobItemsByJobId[job.jobId] = items;
        await _storage.upsertDownloadJobItems(changed);
      }
      await _refreshJobCounts(job.jobId);
      await _deleteRollingJobIfAbandoned(job.jobId);
    }
  }

  Future<void> _pruneDuplicateRollingJobs() async {
    final groups = <String, List<OfflineDownloadJob>>{};
    for (final job in _jobs) {
      final key = _rollingJobCollectionKey(job);
      if (key == null) {
        continue;
      }
      groups.putIfAbsent(key, () => <OfflineDownloadJob>[]).add(job);
    }

    for (final group in groups.values) {
      if (group.length < 2) {
        continue;
      }
      final keep = _chooseRollingJobToKeep(group);
      for (final job in group) {
        if (job.jobId == keep.jobId) {
          continue;
        }
        await _deleteRollingJob(job.jobId, removePendingDownloads: true);
      }
    }
  }

  Future<void> _deleteRollingJob(
    String jobId, {
    bool removePendingDownloads = false,
  }) async {
    final trimmed = jobId.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final removableDownloads = removePendingDownloads
        ? _downloads
              .where(
                (download) =>
                    download.batchId == trimmed &&
                    download.status != OfflineDownloadStatus.downloaded,
              )
              .toList(growable: false)
        : const <OfflineTrackDownload>[];
    final hadJob = _jobs.any((job) => job.jobId == trimmed);
    final hadBatch = _batches.any((batch) => batch.batchId == trimmed);
    _jobs = _jobs.where((job) => job.jobId != trimmed).toList(growable: false);
    _batches = _batches
        .where((batch) => batch.batchId != trimmed)
        .toList(growable: false);
    _jobItemsByJobId.remove(trimmed);
    _jobSourcesByJobId.remove(trimmed);
    await _storage.deleteDownloadJob(trimmed);
    if (hadJob) {
      _emitJobs();
    }
    if (hadBatch) {
      _emitBatches();
    }
    if (removePendingDownloads) {
      if (removableDownloads.isNotEmpty) {
        await removeDownloads(removableDownloads);
      }
    }
  }

  Future<bool> _deleteRollingJobIfAbandoned(String jobId) async {
    final job = _jobById(jobId);
    if (job == null) {
      return false;
    }
    final hasDownloads = _downloads.any(
      (download) => download.batchId == jobId,
    );
    if (hasDownloads) {
      return false;
    }
    final items = _jobItemsByJobId[jobId] ?? const <OfflineDownloadJobItem>[];
    if (items.isEmpty) {
      return false;
    }
    final sources =
        _jobSourcesByJobId[jobId] ?? const <OfflineDownloadJobSource>[];
    final hasPendingSource = sources.any(
      (source) =>
          source.status == OfflineDownloadStatus.queued ||
          source.status == OfflineDownloadStatus.downloading ||
          source.status == OfflineDownloadStatus.preparing ||
          source.status == OfflineDownloadStatus.validating ||
          source.status == OfflineDownloadStatus.paused,
    );
    if (hasPendingSource) {
      return false;
    }
    final onlyRemovedOrCompleted = items.every(
      (item) =>
          item.status == OfflineDownloadStatus.canceled ||
          item.status == OfflineDownloadStatus.downloaded,
    );
    if (!onlyRemovedOrCompleted) {
      return false;
    }
    await _deleteRollingJob(jobId);
    return true;
  }

  Future<void> _topUpRollingJobsForCurrentServer() async {
    if (_topUpRunning || !_loaded || _disposed) {
      return;
    }
    _topUpRunning = true;
    try {
      final baseUrl = connection.baseUrl;
      if (_pausedServerUrls.contains(baseUrl)) {
        return;
      }
      final runnable = _jobs
          .where(
            (job) =>
                job.serverBaseUrl == baseUrl &&
                (job.status == OfflineDownloadStatus.queued ||
                    job.status == OfflineDownloadStatus.downloading),
          )
          .toList(growable: false);
      for (final job in runnable) {
        await _topUpRollingJob(job);
      }
    } finally {
      _topUpRunning = false;
    }
    _scheduleQueuedDownloads();
  }

  Future<void> _topUpRollingJob(OfflineDownloadJob job) async {
    developer.Timeline.startSync('offline.job.topUp');
    try {
      final latestJob = _jobById(job.jobId);
      if (latestJob == null ||
          latestJob.status == OfflineDownloadStatus.paused ||
          latestJob.status == OfflineDownloadStatus.canceled ||
          _pausedServerUrls.contains(latestJob.serverBaseUrl)) {
        return;
      }
      job = latestJob;
      final activeWindow = _downloads
          .where(
            (download) =>
                download.batchId == job.jobId &&
                _windowOccupyingStatus(download.status),
          )
          .length;
      var slots = _rollingWindowSize - activeWindow;
      if (slots <= 0) {
        return;
      }

      if (job.kind == 'artist') {
        await _discoverArtistJobItems(job, targetUnmaterialized: slots);
      }

      final items =
          _jobItemsByJobId[job.jobId] ?? const <OfflineDownloadJobItem>[];
      final candidates = items
          .where(
            (item) =>
                !item.materialized &&
                item.status == OfflineDownloadStatus.queued &&
                !_downloadQueuedOrAvailable(
                  find(job.serverBaseUrl, item.serverTrackId),
                ),
          )
          .take(slots)
          .toList(growable: false);
      if (candidates.isEmpty) {
        await _refreshJobCounts(job.jobId);
        return;
      }
      await _materializeJobItems(job, candidates);
    } finally {
      developer.Timeline.finishSync();
    }
  }

  Future<void> _discoverArtistJobItems(
    OfflineDownloadJob job, {
    required int targetUnmaterialized,
  }) async {
    if (connection.token == null || connection.token!.isEmpty) {
      return;
    }
    var items = List<OfflineDownloadJobItem>.from(
      _jobItemsByJobId[job.jobId] ?? const <OfflineDownloadJobItem>[],
    );
    int unmaterializedCount() => items
        .where(
          (item) =>
              !item.materialized && item.status == OfflineDownloadStatus.queued,
        )
        .length;
    if (unmaterializedCount() >= targetUnmaterialized) {
      return;
    }

    final sources = List<OfflineDownloadJobSource>.from(
      _jobSourcesByJobId[job.jobId] ?? const <OfflineDownloadJobSource>[],
    );
    final seen = {for (final item in items) item.serverTrackId};
    var nextPosition = items.isEmpty
        ? 0
        : items.map((item) => item.position).reduce((a, b) => a > b ? a : b) +
              1;
    var changed = false;
    final now = DateTime.now();

    for (var i = 0; i < sources.length; i += 1) {
      if (unmaterializedCount() >= targetUnmaterialized) {
        break;
      }
      final source = sources[i];
      if (source.status != OfflineDownloadStatus.queued) {
        continue;
      }
      try {
        final tracks = await connection.fetchTracks(source.sourceId);
        for (final rawTrack in tracks) {
          final id = rawTrack.id.trim();
          if (id.isEmpty || !seen.add(id)) {
            continue;
          }
          final existing = find(job.serverBaseUrl, id);
          if (existing != null) {
            if (_downloadAvailable(existing)) {
              items.add(
                OfflineDownloadJobItem(
                  jobId: job.jobId,
                  position: nextPosition,
                  serverTrackId: id,
                  status: OfflineDownloadStatus.downloaded,
                  materialized: true,
                  createdAt: now,
                  updatedAt: now,
                  track: existing.track,
                  offlineMetadata: existing.offlineMetadata,
                ),
              );
              nextPosition += 1;
              changed = true;
            }
            if (_downloadQueuedOrAvailable(existing)) {
              continue;
            }
            items.add(
              OfflineDownloadJobItem(
                jobId: job.jobId,
                position: nextPosition,
                serverTrackId: id,
                status: OfflineDownloadStatus.queued,
                materialized: false,
                createdAt: now,
                updatedAt: now,
                track: rawTrack.copyWith(
                  id: id,
                  serverBaseUrl: job.serverBaseUrl,
                  serverTrackId: id,
                ),
                offlineMetadata: existing.offlineMetadata,
              ),
            );
            nextPosition += 1;
            changed = true;
            continue;
          }
          items.add(
            OfflineDownloadJobItem(
              jobId: job.jobId,
              position: nextPosition,
              serverTrackId: id,
              status: OfflineDownloadStatus.queued,
              materialized: false,
              createdAt: now,
              updatedAt: now,
              track: rawTrack.copyWith(
                id: id,
                serverBaseUrl: job.serverBaseUrl,
                serverTrackId: id,
              ),
            ),
          );
          nextPosition += 1;
          changed = true;
        }
        sources[i] = source.copyWith(
          status: OfflineDownloadStatus.downloaded,
          updatedAt: now,
          error: null,
        );
      } catch (err) {
        sources[i] = source.copyWith(
          status: OfflineDownloadStatus.failed,
          updatedAt: now,
          error: err.toString(),
        );
      }
      changed = true;
    }
    if (!changed) {
      return;
    }
    _jobItemsByJobId[job.jobId] = items;
    _jobSourcesByJobId[job.jobId] = sources;
    await _storage.upsertDownloadJobItems(items);
    await _storage.upsertDownloadJobSources(sources);
    await _refreshJobCounts(job.jobId);
  }

  Future<void> _materializeJobItems(
    OfflineDownloadJob job,
    List<OfflineDownloadJobItem> items,
  ) async {
    items = await _hydrateMaterializationWindow(job.jobId, items);
    final ids = items.map((item) => item.serverTrackId).toList(growable: false);
    if (ids.isEmpty) {
      return;
    }
    if (connection.token != null && connection.token!.isNotEmpty) {
      try {
        final manifest = await connection.createDownloadBatch(
          ids,
          clientBatchId: job.jobId,
        );
        await _materializeManifestItems(job, manifest.items);
        if (manifest.unavailable.isNotEmpty) {
          await _markJobItems(
            job.jobId,
            manifest.unavailable.map((item) => item.trackId),
            OfflineDownloadStatus.failed,
            error: 'unavailable',
          );
        }
        return;
      } catch (err) {
        AppLogger.warning(
          'Falling back to direct rolling queue for ${job.label ?? job.jobId}: $err',
        );
      }
    }

    final downloads = <OfflineTrackDownload>[];
    final now = DateTime.now();
    for (var index = 0; index < items.length; index += 1) {
      final item = items[index];
      final track = item.track;
      if (track == null) {
        await _markJobItems(
          job.jobId,
          <String>[item.serverTrackId],
          OfflineDownloadStatus.failed,
          error: 'missing offline metadata',
        );
        continue;
      }
      downloads.add(
        OfflineTrackDownload(
          serverBaseUrl: job.serverBaseUrl,
          batchId: job.jobId,
          track: track.copyWith(
            id: item.serverTrackId,
            serverBaseUrl: job.serverBaseUrl,
            serverTrackId: item.serverTrackId,
          ),
          offlineMetadata: item.offlineMetadata?.copyWith(
            track: item.offlineMetadata!.track.copyWith(
              id: item.serverTrackId,
              serverBaseUrl: job.serverBaseUrl,
              serverTrackId: item.serverTrackId,
            ),
          ),
          status: OfflineDownloadStatus.queued,
          createdAt: now,
          updatedAt: now,
          priority: items.length - index,
        ),
      );
    }
    await _persistMaterializedDownloads(job.jobId, downloads);
  }

  Future<List<OfflineDownloadJobItem>> _hydrateMaterializationWindow(
    String jobId,
    List<OfflineDownloadJobItem> items,
  ) async {
    final missingIds = items
        .where((item) => item.track == null || item.offlineMetadata == null)
        .map((item) => item.serverTrackId)
        .toList(growable: false);
    if (missingIds.isEmpty) {
      return items;
    }
    final hydratedItems = await _storage.readDownloadJobItemsForTracks(
      jobId,
      missingIds,
    );
    final tracksById = <String, Track>{
      for (final item in hydratedItems)
        if (item.track != null) item.serverTrackId: item.track!,
    };
    final metadataById = <String, OfflineTrackMetadata>{
      for (final item in hydratedItems)
        if (item.offlineMetadata != null)
          item.serverTrackId: item.offlineMetadata!,
    };
    if (tracksById.isEmpty && metadataById.isEmpty) {
      return items;
    }

    final merged = [
      for (final item in items)
        (item.track == null || item.offlineMetadata == null) &&
                (tracksById.containsKey(item.serverTrackId) ||
                    metadataById.containsKey(item.serverTrackId))
            ? _mergeHydratedJobItem(item, tracksById, metadataById)
            : item,
    ];
    final allItems = List<OfflineDownloadJobItem>.from(
      _jobItemsByJobId[jobId] ?? const <OfflineDownloadJobItem>[],
    );
    for (var index = 0; index < allItems.length; index += 1) {
      final track = tracksById[allItems[index].serverTrackId];
      final metadata = metadataById[allItems[index].serverTrackId];
      if (track != null || metadata != null) {
        allItems[index] = _mergeHydratedJobItem(
          allItems[index],
          tracksById,
          metadataById,
        );
      }
    }
    _jobItemsByJobId[jobId] = allItems;
    return merged;
  }

  OfflineDownloadJobItem _mergeHydratedJobItem(
    OfflineDownloadJobItem item,
    Map<String, Track> tracksById,
    Map<String, OfflineTrackMetadata> metadataById,
  ) {
    var updated = item;
    final track = tracksById[item.serverTrackId];
    if (track != null) {
      updated = updated.copyWith(track: track);
    }
    if (metadataById.containsKey(item.serverTrackId)) {
      updated = updated.copyWith(
        offlineMetadata: metadataById[item.serverTrackId],
      );
    }
    return updated;
  }

  Future<void> _materializeManifestItems(
    OfflineDownloadJob job,
    List<DownloadBatchItem> manifestItems,
  ) async {
    final now = DateTime.now();
    final downloads = <OfflineTrackDownload>[];
    for (var index = 0; index < manifestItems.length; index += 1) {
      final item = manifestItems[index];
      final track = item.offlineMetadata.track.copyWith(
        id: item.trackId,
        serverBaseUrl: job.serverBaseUrl,
        serverTrackId: item.trackId,
      );
      final offlineMetadata = item.offlineMetadata.copyWith(track: track);
      downloads.add(
        OfflineTrackDownload(
          serverBaseUrl: job.serverBaseUrl,
          batchId: job.jobId,
          downloadUrl: item.downloadUrl,
          track: track,
          offlineMetadata: offlineMetadata,
          status: OfflineDownloadStatus.queued,
          createdAt: now,
          updatedAt: now,
          bytesTotal: item.byteLength > 0 ? item.byteLength : null,
          etag: item.etag.isEmpty ? null : item.etag,
          expectedSha256: item.sha256.isEmpty ? null : item.sha256,
          contentType: item.contentType,
          priority: manifestItems.length - index,
        ),
      );
    }
    await _persistMaterializedDownloads(job.jobId, downloads);
  }

  Future<void> _persistMaterializedDownloads(
    String jobId,
    List<OfflineTrackDownload> downloads,
  ) async {
    if (downloads.isEmpty) {
      return;
    }
    final prepared = await _storage.prepareDownloads(downloads);
    for (final download in prepared) {
      _clearObsoleteStopMarkersForQueue(download);
    }
    _replaceManyInMemory(prepared);
    await _storage.upsertDownloads(prepared);
    await _markJobItems(
      jobId,
      prepared.map(_serverTrackId),
      OfflineDownloadStatus.queued,
      materialized: true,
      tracksById: {
        for (final download in prepared)
          _serverTrackId(download): download.track,
      },
      metadataById: {
        for (final download in prepared)
          if (download.offlineMetadata != null)
            _serverTrackId(download): download.offlineMetadata!,
      },
    );
    await _refreshJobCounts(jobId);
  }

  Future<void> _markJobItems(
    String jobId,
    Iterable<String> serverTrackIds,
    OfflineDownloadStatus status, {
    bool? materialized,
    Map<String, Track> tracksById = const <String, Track>{},
    Map<String, OfflineTrackMetadata> metadataById =
        const <String, OfflineTrackMetadata>{},
    bool clearPayload = false,
    String? error,
  }) async {
    final ids = serverTrackIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (ids.isEmpty) {
      return;
    }
    final now = DateTime.now();
    final items = List<OfflineDownloadJobItem>.from(
      _jobItemsByJobId[jobId] ?? const <OfflineDownloadJobItem>[],
    );
    final changed = <OfflineDownloadJobItem>[];
    for (var index = 0; index < items.length; index += 1) {
      final item = items[index];
      if (!ids.contains(item.serverTrackId)) {
        continue;
      }
      var updated = item.copyWith(
        status: status,
        materialized: materialized,
        updatedAt: now,
        error: error,
      );
      if (clearPayload) {
        updated = updated.copyWith(track: null, offlineMetadata: null);
      } else if (tracksById.containsKey(item.serverTrackId)) {
        updated = updated.copyWith(track: tracksById[item.serverTrackId]);
      }
      if (metadataById.containsKey(item.serverTrackId)) {
        updated = updated.copyWith(
          offlineMetadata: metadataById[item.serverTrackId],
        );
      }
      items[index] = updated;
      changed.add(updated);
    }
    if (changed.isEmpty) {
      return;
    }
    _jobItemsByJobId[jobId] = items;
    await _storage.upsertDownloadJobItems(changed);
  }

  Future<void> _syncJobItemFromDownload(OfflineTrackDownload download) async {
    final jobId = download.batchId;
    if (jobId == null || !_jobs.any((job) => job.jobId == jobId)) {
      return;
    }
    await _markJobItems(
      jobId,
      <String>[_serverTrackId(download)],
      download.status,
      materialized: true,
      tracksById: {_serverTrackId(download): download.track},
      metadataById: download.offlineMetadata == null
          ? const <String, OfflineTrackMetadata>{}
          : {_serverTrackId(download): download.offlineMetadata!},
      error: download.error,
    );
    await _refreshJobCounts(jobId);
    if (_terminalStatus(download.status)) {
      _scheduleTopUp();
    }
  }

  Future<void> _refreshJobCounts(String jobId) async {
    final job = _jobById(jobId);
    if (job == null) {
      return;
    }
    final items = _jobItemsByJobId[jobId] ?? const <OfflineDownloadJobItem>[];
    final sources =
        _jobSourcesByJobId[jobId] ?? const <OfflineDownloadJobSource>[];
    final completed = items
        .where((item) => item.status == OfflineDownloadStatus.downloaded)
        .length;
    final failed = items
        .where(
          (item) =>
              item.status == OfflineDownloadStatus.failed ||
              item.status == OfflineDownloadStatus.corrupt,
        )
        .length;
    final canceled = items
        .where((item) => item.status == OfflineDownloadStatus.canceled)
        .length;
    final materialized = items.where((item) => item.materialized).length;
    final active = items.any((item) => _windowOccupyingStatus(item.status));
    final paused = items.any(
      (item) => item.status == OfflineDownloadStatus.paused,
    );
    final pendingItems = items.any(
      (item) =>
          !item.materialized && item.status == OfflineDownloadStatus.queued,
    );
    final pendingSources = sources.any(
      (source) => source.status == OfflineDownloadStatus.queued,
    );
    final sourceFailures = sources
        .where((source) => source.status == OfflineDownloadStatus.failed)
        .length;
    final done = !active && !pendingItems && !pendingSources;
    final status =
        job.status == OfflineDownloadStatus.paused ||
            job.status == OfflineDownloadStatus.canceled
        ? job.status
        : paused
        ? OfflineDownloadStatus.paused
        : done
        ? failed + sourceFailures > 0
              ? OfflineDownloadStatus.failed
              : canceled > 0 && completed == 0
              ? OfflineDownloadStatus.canceled
              : OfflineDownloadStatus.downloaded
        : active
        ? OfflineDownloadStatus.downloading
        : OfflineDownloadStatus.queued;
    final updated = job.copyWith(
      status: status,
      updatedAt: DateTime.now(),
      discoveredCount: items.length,
      completedCount: completed,
      failedCount: failed + sourceFailures,
      materializedCount: materialized,
    );
    if (updated.status == OfflineDownloadStatus.downloaded) {
      await _deleteRollingJob(jobId);
      return;
    }
    if (job.status == updated.status &&
        job.discoveredCount == updated.discoveredCount &&
        job.completedCount == updated.completedCount &&
        job.failedCount == updated.failedCount &&
        job.materializedCount == updated.materializedCount &&
        job.totalCount == updated.totalCount) {
      return;
    }
    _jobs = _jobs
        .map((item) => item.jobId == jobId ? updated : item)
        .toList(growable: false);
    await _storage.upsertDownloadJob(updated);
    await _upsertBatch(
      OfflineDownloadBatch(
        batchId: updated.jobId,
        serverBaseUrl: updated.serverBaseUrl,
        status: updated.status,
        createdAt: updated.createdAt,
        updatedAt: updated.updatedAt,
        totalCount: updated.totalCount > 0
            ? updated.totalCount
            : updated.discoveredCount,
        completedCount: updated.completedCount,
        failedCount: updated.failedCount,
        label: updated.label,
      ),
    );
    _emitJobs();
  }

  bool _windowOccupyingStatus(OfflineDownloadStatus status) {
    return status == OfflineDownloadStatus.queued ||
        status == OfflineDownloadStatus.preparing ||
        status == OfflineDownloadStatus.downloading ||
        status == OfflineDownloadStatus.validating ||
        status == OfflineDownloadStatus.removing;
  }

  bool _terminalStatus(OfflineDownloadStatus status) {
    return status == OfflineDownloadStatus.downloaded ||
        status == OfflineDownloadStatus.failed ||
        status == OfflineDownloadStatus.corrupt ||
        status == OfflineDownloadStatus.canceled;
  }

  Future<void> _runDownload(OfflineTrackDownload queued) async {
    var download = find(queued.serverBaseUrl, _serverTrackId(queued)) ?? queued;
    if (download.status == OfflineDownloadStatus.paused ||
        _queuedDownloadBlockedByPausedJob(download)) {
      return;
    }
    download = download.copyWith(
      status: OfflineDownloadStatus.preparing,
      updatedAt: DateTime.now(),
      error: null,
    );
    if (!await _replace(download, persist: false)) {
      return;
    }

    File? partialFile;
    var bytesDownloaded = 0;
    try {
      if (connection.baseUrl != download.serverBaseUrl ||
          connection.token == null ||
          connection.token!.isEmpty) {
        throw const _DownloadPaused('server disconnected');
      }
      partialFile = await _storage.partialTrackFile(
        serverBaseUrl: download.serverBaseUrl,
        trackId: _serverTrackId(download),
      );
      if (await partialFile.exists()) {
        bytesDownloaded = await partialFile.length();
      }
      final expectedBytes = download.bytesTotal;
      if (expectedBytes != null &&
          expectedBytes > 0 &&
          bytesDownloaded > expectedBytes) {
        throw _DownloadCorrupt('partial file is larger than expected size');
      }

      download = download.copyWith(
        status: OfflineDownloadStatus.downloading,
        updatedAt: DateTime.now(),
        partialPath: partialFile.path,
        bytesDownloaded: bytesDownloaded,
        error: null,
      );
      if (!await _replace(download, persist: false)) {
        return;
      }

      final key = _downloadKey(download);
      final workerResult = await _downloadOnWorker(
        key: key,
        request: _DownloadWorkerRequest(
          serverBaseUrl: download.serverBaseUrl,
          trackId: _serverTrackId(download),
          url: download.downloadUrl?.trim().isEmpty ?? true
              ? connection.buildTrackDownloadUrl(_serverTrackId(download))
              : connection.buildDownloadUrl(
                  _serverTrackId(download),
                  downloadUrl: download.downloadUrl,
                ),
          token: connection.token!,
          partialPath: partialFile.path,
          startByte: bytesDownloaded > 0 ? bytesDownloaded : null,
          ifRange: bytesDownloaded > 0 ? download.etag : null,
          expectedBytes: download.bytesTotal,
          expectedSha256: download.expectedSha256,
          progressIntervalMs: _progressEmitInterval.inMilliseconds,
          progressMinBytes: _progressEmitMinBytes,
          diskFlushBytes: _diskFlushBytes,
          timeoutSeconds: 30,
        ),
        onMetadata: (metadata) async {
          if (_cancelRequested.contains(key) ||
              _removedDownloadKeys.contains(key)) {
            return;
          }
          bytesDownloaded = metadata.bytesDownloaded;
          download = download.copyWith(
            updatedAt: DateTime.now(),
            partialPath: partialFile!.path,
            bytesDownloaded: metadata.bytesDownloaded,
            bytesTotal: metadata.bytesTotal,
            etag: metadata.etag ?? download.etag,
            expectedSha256: metadata.sha256 ?? download.expectedSha256,
            contentType: metadata.contentType ?? download.contentType,
            error: null,
          );
          await _replace(download, persist: true);
        },
        onProgress: (progress) async {
          if (_cancelRequested.contains(key) ||
              _removedDownloadKeys.contains(key)) {
            return;
          }
          bytesDownloaded = progress.bytesDownloaded;
          download = download.copyWith(
            updatedAt: DateTime.now(),
            bytesDownloaded: progress.bytesDownloaded,
            bytesTotal: progress.bytesTotal,
          );
          await _replace(download, persist: false);
        },
      );
      if (_disposed) {
        return;
      }
      _throwIfStopped(download);

      download = download.copyWith(
        status: OfflineDownloadStatus.validating,
        updatedAt: DateTime.now(),
        bytesDownloaded: workerResult.bytesDownloaded,
        bytesTotal: workerResult.bytesTotal,
        etag: workerResult.etag ?? download.etag,
        expectedSha256: workerResult.sha256 ?? download.expectedSha256,
        contentType: workerResult.contentType ?? download.contentType,
      );
      if (!await _replace(download, persist: true)) {
        return;
      }

      final extension =
          OfflineLibraryStorage.extensionFromContentDisposition(
            workerResult.contentDisposition,
          ) ??
          OfflineLibraryStorage.extensionFromContentType(
            workerResult.contentType ?? download.contentType,
          );
      final finalFile = await _storage.trackFile(
        serverBaseUrl: download.serverBaseUrl,
        trackId: _serverTrackId(download),
        extension: extension,
      );
      developer.Timeline.startSync('offline.download.promote');
      late final File promoted;
      try {
        if (await finalFile.exists()) {
          await finalFile.delete();
        }
        promoted = await _promotePartial(partialFile, finalFile);
      } finally {
        developer.Timeline.finishSync();
      }
      final completed = download.copyWith(
        status: OfflineDownloadStatus.downloaded,
        updatedAt: DateTime.now(),
        filePath: promoted.path,
        partialPath: null,
        bytesDownloaded: workerResult.bytesDownloaded,
        bytesTotal: workerResult.bytesTotal,
        error: null,
      );
      if (!await _replace(completed, persist: true)) {
        return;
      }
      _scheduleLocalUserDataReload();
      _queueArtworkHydration(completed);
      AppLogger.status('Downloaded ${download.track.title}');
    } on _DownloadPaused catch (err) {
      if (partialFile != null && await partialFile.exists()) {
        bytesDownloaded = await partialFile.length();
      }
      final latest = find(download.serverBaseUrl, _serverTrackId(download));
      if (latest == null ||
          (latest.status != OfflineDownloadStatus.paused &&
              !_activeDownloadStatus(latest.status))) {
        return;
      }
      if (!await _replace(
        download.copyWith(
          status: OfflineDownloadStatus.paused,
          updatedAt: DateTime.now(),
          partialPath: partialFile?.path,
          bytesDownloaded: bytesDownloaded,
          error: err.message,
        ),
        persist: true,
      )) {
        return;
      }
    } on _DownloadCanceled {
      await _deleteIfExists(partialFile?.path);
      if (!await _replace(
        download.copyWith(
          status: OfflineDownloadStatus.canceled,
          updatedAt: DateTime.now(),
          partialPath: null,
          bytesDownloaded: 0,
          error: null,
        ),
        persist: true,
      )) {
        return;
      }
    } on _DownloadCorrupt catch (err) {
      if (partialFile != null && await partialFile.exists()) {
        bytesDownloaded = await partialFile.length();
      }
      if (!await _replace(
        download.copyWith(
          status: OfflineDownloadStatus.corrupt,
          updatedAt: DateTime.now(),
          partialPath: partialFile?.path,
          bytesDownloaded: bytesDownloaded,
          error: err.message,
        ),
        persist: true,
      )) {
        return;
      }
      AppLogger.warning('Download corrupt for ${download.track.title}: $err');
    } catch (err) {
      if (partialFile != null && await partialFile.exists()) {
        bytesDownloaded = await partialFile.length();
      }
      final shouldPause =
          connection.baseUrl != download.serverBaseUrl ||
          connection.token == null ||
          connection.token!.isEmpty;
      final failed = download.copyWith(
        status: shouldPause
            ? OfflineDownloadStatus.paused
            : OfflineDownloadStatus.failed,
        updatedAt: DateTime.now(),
        partialPath: partialFile?.path,
        bytesDownloaded: bytesDownloaded,
        error: err.toString(),
      );
      if (!await _replace(failed, persist: true)) {
        return;
      }
      AppLogger.warning('Download failed for ${download.track.title}: $err');
    }
  }

  void _throwIfStopped(OfflineTrackDownload download) {
    final key = _downloadKey(download);
    if (_cancelRequested.contains(key)) {
      final latest = find(download.serverBaseUrl, _serverTrackId(download));
      if (latest?.status == OfflineDownloadStatus.canceled) {
        throw const _DownloadCanceled();
      }
      throw const _DownloadPaused('download paused');
    }
    final latest = find(download.serverBaseUrl, _serverTrackId(download));
    if (latest?.status == OfflineDownloadStatus.paused) {
      throw const _DownloadPaused('download paused');
    }
    if (latest?.status == OfflineDownloadStatus.canceled) {
      throw const _DownloadCanceled();
    }
    if (latest != null && _queuedDownloadBlockedByPausedJob(latest)) {
      throw const _DownloadPaused('download job paused');
    }
  }

  Future<File> _promotePartial(File partialFile, File finalFile) async {
    try {
      return await partialFile.rename(finalFile.path);
    } on FileSystemException {
      await partialFile.copy(finalFile.path);
      await partialFile.delete();
      return finalFile;
    }
  }

  Future<_DownloadWorkerComplete> _downloadOnWorker({
    required String key,
    required _DownloadWorkerRequest request,
    required Future<void> Function(_DownloadWorkerMetadata metadata) onMetadata,
    required Future<void> Function(_DownloadWorkerProgress progress) onProgress,
  }) async {
    final receivePort = ReceivePort();
    Isolate? isolate;
    try {
      isolate = await Isolate.spawn(
        _downloadWorkerMain,
        _DownloadWorkerStart(request, receivePort.sendPort),
        debugName: 'phonolite-download-worker',
      );
      await for (final message in receivePort) {
        if (message is _DownloadWorkerReady) {
          _activeCancelPorts[key] = message.cancelPort;
          if (_cancelRequested.contains(key)) {
            message.cancelPort.send(null);
          }
        } else if (message is _DownloadWorkerMetadata) {
          await onMetadata(message);
        } else if (message is _DownloadWorkerProgress) {
          await onProgress(message);
        } else if (message is _DownloadWorkerComplete) {
          return message;
        } else if (message is _DownloadWorkerFailure) {
          if (message.kind == _DownloadWorkerFailureKind.canceled) {
            final latest = find(request.serverBaseUrl, request.trackId);
            if (latest?.status == OfflineDownloadStatus.canceled) {
              throw const _DownloadCanceled();
            }
            throw const _DownloadPaused('download paused');
          }
          if (message.kind == _DownloadWorkerFailureKind.corrupt) {
            throw _DownloadCorrupt(message.message);
          }
          throw Exception(message.message);
        }
      }
      throw Exception('download worker exited before completion');
    } finally {
      _activeCancelPorts.remove(key);
      receivePort.close();
      isolate?.kill(priority: Isolate.immediate);
    }
  }

  void _queueArtworkHydration(OfflineTrackDownload download) {
    final localTrackId = download.localTrackId ?? download.track.localId;
    if (localTrackId == null || localTrackId.isEmpty) {
      return;
    }
    final key = '${download.serverBaseUrl}|$localTrackId';
    _pendingArtworkHydration[key] = download;
    if (!_artHydrationRunning) {
      unawaited(_drainArtworkHydrationQueue());
    }
  }

  Future<void> _drainArtworkHydrationQueue() async {
    if (_artHydrationRunning) {
      return;
    }
    _artHydrationRunning = true;
    final albumArtById = <String, String?>{};
    final artistLogoById = <String, String?>{};
    final artistBannerById = <String, String?>{};
    try {
      while (_pendingArtworkHydration.isNotEmpty &&
          !_disposed &&
          !_resettingLocalData) {
        final key = _pendingArtworkHydration.keys.first;
        final download = _pendingArtworkHydration.remove(key);
        if (download == null) {
          continue;
        }
        await Future<void>.delayed(_artworkHydrationDelay);
        if (_disposed || _resettingLocalData) {
          break;
        }
        await _hydrateArtworkForDownload(
          download,
          albumArtById: albumArtById,
          artistLogoById: artistLogoById,
          artistBannerById: artistBannerById,
        );
      }
    } finally {
      _artHydrationRunning = false;
      if (_pendingArtworkHydration.isNotEmpty &&
          !_disposed &&
          !_resettingLocalData) {
        unawaited(_drainArtworkHydrationQueue());
      }
    }
  }

  Future<void> _hydrateArtworkForDownload(
    OfflineTrackDownload download, {
    Map<String, String?>? albumArtById,
    Map<String, String?>? artistLogoById,
    Map<String, String?>? artistBannerById,
  }) async {
    final localTrackId = download.localTrackId ?? download.track.localId;
    if (localTrackId == null || localTrackId.isEmpty) {
      return;
    }
    final key = '${download.serverBaseUrl}|$localTrackId';
    if (!_artHydrationKeys.add(key)) {
      return;
    }
    try {
      if (_disposed ||
          _resettingLocalData ||
          connection.baseUrl != download.serverBaseUrl ||
          connection.token == null ||
          connection.token!.isEmpty) {
        return;
      }
      final paths = await _fetchAndStoreArtwork(
        download.track,
        albumArtById: albumArtById ?? <String, String?>{},
        artistLogoById: artistLogoById ?? <String, String?>{},
        artistBannerById: artistBannerById ?? <String, String?>{},
      );
      if (paths.isEmpty) {
        return;
      }
      if (_resettingLocalData) {
        return;
      }
      await _storage.updateTrackArtPaths(
        localTrackId,
        albumArtPath: paths.albumArtPath,
        artistArtPath: paths.artistArtPath,
        artistBannerPath: paths.artistBannerPath,
      );
      _applyArtworkPaths(localTrackId, paths);
      _scheduleLocalUserDataReload();
    } catch (err) {
      AppLogger.warning(
        'Failed to cache offline artwork for ${download.track.title}: $err',
      );
    } finally {
      _artHydrationKeys.remove(key);
    }
  }

  Future<_ArtworkPaths> _fetchAndStoreArtwork(
    Track track, {
    required Map<String, String?> albumArtById,
    required Map<String, String?> artistLogoById,
    required Map<String, String?> artistBannerById,
  }) async {
    final albumArtPath =
        _existingArtworkPath(track.albumArtPath) ??
        await _fetchAlbumArt(track.albumId, albumArtById);
    final artistArtPath =
        _existingArtworkPath(track.artistArtPath) ??
        await _fetchArtistArt(track.artistId, 'logo', artistLogoById);
    final artistBannerPath =
        _existingArtworkPath(track.artistBannerPath) ??
        await _fetchArtistArt(track.artistId, 'banner', artistBannerById);
    return _ArtworkPaths(
      albumArtPath: albumArtPath,
      artistArtPath: artistArtPath,
      artistBannerPath: artistBannerPath,
    );
  }

  Future<String?> _fetchAlbumArt(
    String? albumId,
    Map<String, String?> albumArtById,
  ) async {
    final id = albumId?.trim();
    if (id == null || id.isEmpty) {
      return null;
    }
    if (albumArtById.containsKey(id)) {
      return albumArtById[id];
    }
    if (_albumArtPathById.containsKey(id)) {
      final path = _albumArtPathById[id];
      albumArtById[id] = path;
      return path;
    }
    final artwork = await connection.fetchAlbumCoverBytes(id);
    final path = artwork == null ? null : await _storeAlbumArtwork(id, artwork);
    _albumArtPathById[id] = path;
    albumArtById[id] = path;
    return path;
  }

  Future<String?> _fetchArtistArt(
    String? artistId,
    String kind,
    Map<String, String?> artistArtById,
  ) async {
    final id = artistId?.trim();
    if (id == null || id.isEmpty) {
      return null;
    }
    final key = '$id|$kind';
    if (artistArtById.containsKey(key)) {
      return artistArtById[key];
    }
    if (_artistArtPathByKey.containsKey(key)) {
      final path = _artistArtPathByKey[key];
      artistArtById[key] = path;
      return path;
    }
    final artwork = await connection.fetchArtistCoverBytes(id, kind: kind);
    final path = artwork == null
        ? null
        : await _storeArtistArtwork(id, kind, artwork);
    _artistArtPathByKey[key] = path;
    artistArtById[key] = path;
    return path;
  }

  Future<String> _storeAlbumArtwork(
    String albumId,
    ServerArtwork artwork,
  ) async {
    final file = await _storage.albumArtFile(
      albumId: albumId,
      extension: OfflineLibraryStorage.extensionFromImageContentType(
        artwork.contentType,
      ),
    );
    await file.writeAsBytes(artwork.bytes, flush: true);
    return file.path;
  }

  Future<String> _storeArtistArtwork(
    String artistId,
    String kind,
    ServerArtwork artwork,
  ) async {
    final file = await _storage.artistArtFile(
      artistId: artistId,
      kind: kind,
      extension: OfflineLibraryStorage.extensionFromImageContentType(
        artwork.contentType,
      ),
    );
    await file.writeAsBytes(artwork.bytes, flush: true);
    return file.path;
  }

  String? _existingArtworkPath(String? path) {
    final trimmed = path?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return File(trimmed).existsSync() ? trimmed : null;
  }

  void _applyArtworkPaths(String localTrackId, _ArtworkPaths paths) {
    var changed = false;
    _downloads = _downloads
        .map((download) {
          final id = download.localTrackId ?? download.track.localId;
          if (id != localTrackId) {
            return download;
          }
          changed = true;
          return download.copyWith(
            track: _trackWithArtwork(download.track, paths),
          );
        })
        .toList(growable: false);
    if (changed) {
      _rebuildDownloadIndexes();
      _emit();
    }
  }

  Track _trackWithArtwork(Track track, _ArtworkPaths paths) {
    return track.copyWith(
      albumArtPath: paths.albumArtPath ?? track.albumArtPath,
      artistArtPath: paths.artistArtPath ?? track.artistArtPath,
      artistBannerPath: paths.artistBannerPath ?? track.artistBannerPath,
    );
  }

  Future<bool> _replace(
    OfflineTrackDownload download, {
    required bool persist,
  }) async {
    final key = _downloadKey(download);
    if (_removedDownloadKeys.contains(key)) {
      await _recordPendingDownloadFiles(download);
      unawaited(_cleanupPendingFileDeletes());
      return false;
    }
    final prepared = download.localTrackId == null
        ? await _storage.prepareDownload(download)
        : download;
    if (_removedDownloadKeys.contains(_downloadKey(prepared))) {
      await _recordPendingDownloadFiles(prepared);
      unawaited(_cleanupPendingFileDeletes());
      return false;
    }
    var replaced = false;
    final next = <OfflineTrackDownload>[];
    for (final existing in _downloads) {
      final sameTrack =
          existing.serverBaseUrl == prepared.serverBaseUrl &&
          _serverTrackId(existing) == _serverTrackId(prepared);
      if (sameTrack) {
        next.add(prepared);
        replaced = true;
      } else {
        next.add(existing);
      }
    }
    if (!replaced) {
      next.add(prepared);
    }
    _downloads = next;
    _rebuildDownloadIndexes();
    _emit();
    if (persist) {
      await _storage.upsertDownload(prepared);
      await _syncJobItemFromDownload(prepared);
      final batchId = prepared.batchId;
      if (batchId != null && !_isRollingJob(batchId)) {
        await _refreshBatchCounts(batchId);
      }
    }
    return true;
  }

  void _clearObsoleteStopMarkersForQueue(OfflineTrackDownload download) {
    final key = _downloadKey(download);
    if (_active.containsKey(key)) {
      return;
    }
    _cancelRequested.remove(key);
    _removedDownloadKeys.remove(key);
  }

  Future<void> _retireServerDownloadJobIfUnused(String jobId) async {
    if (!_looksLikeV2DownloadJobId(jobId) ||
        _downloads.any((download) => download.batchId == jobId) ||
        connection.token == null ||
        connection.token!.isEmpty) {
      return;
    }
    try {
      await connection.applyDownloadJobAction(jobId: jobId, action: 'delete');
    } catch (err, stackTrace) {
      developer.log(
        'Failed to retire v2 download job after local removal',
        name: 'OfflineDownloadManager',
        error: err,
        stackTrace: stackTrace,
      );
    }
  }

  bool _looksLikeV2DownloadJobId(String jobId) {
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(jobId);
  }

  bool _downloadBelongsToV2Job(OfflineTrackDownload download) {
    final batchId = download.batchId;
    if (batchId == null || !_looksLikeV2DownloadJobId(batchId)) {
      return false;
    }
    final downloadUrl = download.downloadUrl?.trim();
    return downloadUrl != null && downloadUrl.contains('/download/v2/');
  }

  void _replaceManyInMemory(List<OfflineTrackDownload> downloads) {
    if (downloads.isEmpty) {
      return;
    }
    for (final download in downloads) {
      _clearObsoleteStopMarkersForQueue(download);
    }
    final byKey = {
      for (final download in downloads) _downloadKey(download): download,
    };
    final next = <OfflineTrackDownload>[];
    final inserted = <String>{};
    for (final existing in _downloads) {
      final key = _downloadKey(existing);
      final replacement = byKey[key];
      if (replacement == null) {
        next.add(existing);
      } else {
        next.add(replacement);
        inserted.add(key);
      }
    }
    for (final download in downloads) {
      final key = _downloadKey(download);
      if (!inserted.contains(key)) {
        next.add(download);
      }
    }
    _downloads = next;
    _rebuildDownloadIndexes();
    _emit();
  }

  Iterable<List<T>> _chunks<T>(List<T> items, int size) sync* {
    for (var start = 0; start < items.length; start += size) {
      final end = start + size > items.length ? items.length : start + size;
      yield items.sublist(start, end);
    }
  }

  Future<void> _upsertBatch(OfflineDownloadBatch batch) async {
    var replaced = false;
    _batches = _batches.map((existing) {
      if (existing.batchId == batch.batchId) {
        replaced = true;
        return batch;
      }
      return existing;
    }).toList();
    if (!replaced) {
      _batches = [batch, ..._batches];
    }
    _emitBatches();
    await _storage.upsertDownloadBatch(batch);
  }

  Future<void> _refreshBatchCounts(String batchId) async {
    OfflineDownloadBatch? batch;
    for (final item in _batches) {
      if (item.batchId == batchId) {
        batch = item;
        break;
      }
    }
    if (batch == null) {
      return;
    }
    final items = _downloads
        .where((download) => download.batchId == batchId)
        .toList(growable: false);
    final completed = items
        .where((item) => item.status == OfflineDownloadStatus.downloaded)
        .length;
    final failed = items
        .where(
          (item) =>
              item.status == OfflineDownloadStatus.failed ||
              item.status == OfflineDownloadStatus.corrupt ||
              item.status == OfflineDownloadStatus.canceled,
        )
        .length;
    final active = items.any(
      (item) =>
          item.status == OfflineDownloadStatus.preparing ||
          item.status == OfflineDownloadStatus.downloading ||
          item.status == OfflineDownloadStatus.validating ||
          item.status == OfflineDownloadStatus.removing,
    );
    final queued = items.any(
      (item) => item.status == OfflineDownloadStatus.queued,
    );
    final paused =
        items.isNotEmpty &&
        items.every((item) => item.status == OfflineDownloadStatus.paused);
    final status = completed >= batch.totalCount && batch.totalCount > 0
        ? OfflineDownloadStatus.downloaded
        : active
        ? OfflineDownloadStatus.downloading
        : paused
        ? OfflineDownloadStatus.paused
        : failed > 0 && !queued
        ? OfflineDownloadStatus.failed
        : OfflineDownloadStatus.queued;
    final updated = batch.copyWith(
      status: status,
      updatedAt: DateTime.now(),
      completedCount: completed,
      failedCount: failed,
    );
    if (batch.status == updated.status &&
        batch.completedCount == updated.completedCount &&
        batch.failedCount == updated.failedCount &&
        batch.totalCount == updated.totalCount) {
      return;
    }
    _batches = _batches
        .map((item) => item.batchId == batchId ? updated : item)
        .toList(growable: false);
    _emitBatches();
    await _storage.upsertDownloadBatch(updated);
  }

  void _emit() {
    if (_disposed || _controller.isClosed) {
      return;
    }
    if (_downloadsEmitTimer != null) {
      return;
    }
    _downloadsEmitTimer = Timer(_stateEmitCoalesceDelay, () {
      _downloadsEmitTimer = null;
      if (_disposed || _controller.isClosed) {
        return;
      }
      _controller.add(List.unmodifiable(_downloads));
    });
  }

  void _emitBatches() {
    if (_disposed || _batchController.isClosed) {
      return;
    }
    if (_batchesEmitTimer != null) {
      return;
    }
    _batchesEmitTimer = Timer(_stateEmitCoalesceDelay, () {
      _batchesEmitTimer = null;
      if (_disposed || _batchController.isClosed) {
        return;
      }
      _batchController.add(List.unmodifiable(_batches));
    });
  }

  void _emitJobs() {
    if (_disposed || _jobController.isClosed) {
      return;
    }
    if (_jobsEmitTimer != null) {
      return;
    }
    _jobsEmitTimer = Timer(_stateEmitCoalesceDelay, () {
      _jobsEmitTimer = null;
      if (_disposed || _jobController.isClosed) {
        return;
      }
      _jobController.add(List.unmodifiable(_jobs));
    });
  }

  Future<void> _loadLocalUserData() async {
    _localPlaylists = await _storage.readLocalPlaylists();
    _localLiked = await _storage.readLocalLikedTracks();
    final playlistId = _localPlaylistTracksId;
    if (playlistId != null &&
        _localPlaylists.any((playlist) => playlist.id == playlistId)) {
      _localPlaylistTracks = await _storage.readLocalPlaylistTracks(playlistId);
    } else if (playlistId != null) {
      _localPlaylistTracksId = null;
      _localPlaylistTracks = <Track>[];
    }
    _rebuildDownloadIndexes();
    _emitLocalPlaylists();
    _emitLocalLiked();
    _emitLocalPlaylistTracks();
  }

  Future<void> _repairOfflineMetadataFragments() {
    final existing = _metadataRepairFuture;
    if (existing != null) {
      return existing;
    }
    final future = _runOfflineMetadataRepair();
    _metadataRepairFuture = future.whenComplete(() {
      _metadataRepairFuture = null;
    });
    return _metadataRepairFuture!;
  }

  Future<void> _runOfflineMetadataRepair() async {
    if (_disposed || _resettingLocalData) {
      return;
    }
    final token = connection.token;
    if (token == null || token.trim().isEmpty) {
      return;
    }

    final attemptedKeys = <String>{};
    final repairedKeys = <String>{};
    while (attemptedKeys.length < _metadataRepairMaxPerRun &&
        !_disposed &&
        !_resettingLocalData) {
      final remaining = _metadataRepairMaxPerRun - attemptedKeys.length;
      final requests =
          (await _storage.readMetadataRepairRequests(
                connection.baseUrl,
                limit: remaining < _metadataRepairBatchSize
                    ? remaining
                    : _metadataRepairBatchSize,
              ))
              .where(
                (request) => !attemptedKeys.contains(
                  _lookupKey(request.serverBaseUrl, request.serverTrackId),
                ),
              )
              .toList(growable: false);
      if (requests.isEmpty) {
        break;
      }
      for (final request in requests) {
        attemptedKeys.add(
          _lookupKey(request.serverBaseUrl, request.serverTrackId),
        );
      }
      final repaired = await _repairOfflineMetadataRequests(requests);
      if (repaired.isEmpty) {
        break;
      }
      repairedKeys.addAll(repaired);
    }

    if (repairedKeys.isEmpty || _disposed || _resettingLocalData) {
      return;
    }
    await _reloadAfterOfflineMetadataRepair(repairedKeys);
  }

  Future<void> _refreshOfflineMetadataWhere(
    bool Function(OfflineTrackDownload download) matches,
  ) async {
    if (_disposed || _resettingLocalData) {
      return;
    }
    final token = connection.token;
    if (token == null || token.trim().isEmpty) {
      return;
    }
    final requests = <OfflineMetadataRepairRequest>[];
    final seen = <String>{};
    for (final download in _downloads) {
      if (download.serverBaseUrl != connection.baseUrl ||
          !_downloadAvailable(download) ||
          !matches(download)) {
        continue;
      }
      final serverTrackId = _serverTrackId(download).trim();
      if (serverTrackId.isEmpty) {
        continue;
      }
      final key = _lookupKey(download.serverBaseUrl, serverTrackId);
      if (!seen.add(key)) {
        continue;
      }
      requests.add(
        OfflineMetadataRepairRequest(
          serverBaseUrl: download.serverBaseUrl,
          serverTrackId: serverTrackId,
        ),
      );
    }
    if (requests.isEmpty) {
      return;
    }
    final repairedKeys = await _repairOfflineMetadataRequests(requests);
    if (repairedKeys.isEmpty || _disposed || _resettingLocalData) {
      return;
    }
    await _reloadAfterOfflineMetadataRepair(repairedKeys);
  }

  Future<Set<String>> _repairOfflineMetadataRequests(
    List<OfflineMetadataRepairRequest> requests,
  ) async {
    final repairedKeys = <String>{};
    for (
      var index = 0;
      index < requests.length;
      index += _maxParallelMetadataRepairs
    ) {
      if (_disposed || _resettingLocalData) {
        break;
      }
      final chunk = requests
          .skip(index)
          .take(_maxParallelMetadataRepairs)
          .toList(growable: false);
      final results = await Future.wait(
        chunk.map((request) async {
          final repaired = await _repairOfflineMetadata(request);
          return repaired
              ? _lookupKey(request.serverBaseUrl, request.serverTrackId)
              : null;
        }),
      );
      for (final key in results) {
        if (key != null) {
          repairedKeys.add(key);
        }
      }
    }
    return repairedKeys;
  }

  Future<void> _reloadAfterOfflineMetadataRepair(
    Set<String> repairedKeys,
  ) async {
    _downloads = await _storage.readDownloads();
    _rebuildDownloadIndexes();
    await _loadLocalUserData();
    for (final download in _downloads) {
      if (repairedKeys.contains(_downloadKey(download)) &&
          _downloadAvailable(download)) {
        _queueArtworkHydration(download);
      }
    }
    _emit();
  }

  Future<bool> _repairOfflineMetadata(
    OfflineMetadataRepairRequest request,
  ) async {
    try {
      final metadata = await connection.fetchOfflineMetadata(
        request.serverTrackId,
      );
      await _storage.upsertOfflineMetadataFragment(
        request.serverBaseUrl,
        request.serverTrackId,
        metadata,
      );
      return true;
    } catch (err) {
      AppLogger.debug(
        'Failed to repair offline metadata for ${request.serverTrackId}: $err',
      );
      return false;
    }
  }

  void _scheduleLocalUserDataReload() {
    if (_disposed) {
      return;
    }
    _localUserDataReloadTimer?.cancel();
    _localUserDataReloadTimer = Timer(_localUserDataReloadDelay, () {
      _localUserDataReloadChain = _localUserDataReloadChain.then((_) async {
        if (_disposed) {
          return;
        }
        try {
          await _loadLocalUserData();
        } catch (err) {
          AppLogger.warning('Failed to refresh local offline data: $err');
        }
      });
      unawaited(_localUserDataReloadChain);
    });
  }

  void _emitLocalLiked() {
    if (_disposed || _localLikedController.isClosed) {
      return;
    }
    _localLikedController.add(List.unmodifiable(_localLiked));
  }

  void _emitLocalPlaylists() {
    if (_disposed || _localPlaylistsController.isClosed) {
      return;
    }
    _localPlaylistsController.add(List.unmodifiable(_localPlaylists));
  }

  void _emitLocalPlaylistTracks() {
    if (_disposed || _localPlaylistTracksController.isClosed) {
      return;
    }
    _localPlaylistTracksController.add(List.unmodifiable(_localPlaylistTracks));
  }

  void _rebuildDownloadIndexes() {
    final lookup = <String, OfflineTrackDownload>{};
    final localLookup = <String, OfflineTrackDownload>{};
    for (final download in _downloads) {
      void addServer(String? id) {
        final value = id?.trim();
        if (value == null || value.isEmpty) {
          return;
        }
        lookup.putIfAbsent(
          _lookupKey(download.serverBaseUrl, value),
          () => download,
        );
      }

      void addLocal(String? id) {
        final value = id?.trim();
        if (value == null || value.isEmpty) {
          return;
        }
        localLookup.putIfAbsent(value, () => download);
      }

      addServer(download.track.id);
      addServer(download.track.serverTrackId);
      addServer(download.localTrackId);
      addServer(download.track.localId);
      addLocal(download.localTrackId);
      addLocal(download.track.localId);
      addLocal(download.track.id);
      addLocal(download.track.serverTrackId);
    }
    _downloadLookup = lookup;
    _localDownloadLookup = localLookup;
    _localDownloadedTracksCache = _computeLocalDownloadedTracks();
  }

  List<Track> _computeLocalDownloadedTracks() {
    final likedLocalIds = {
      for (final track in _localLiked)
        if (track.localId != null) track.localId!,
    };
    final playlistTrackIds = <String>{};
    for (final playlist in _localPlaylists) {
      playlistTrackIds.addAll(playlist.trackIds);
    }
    final byLocalId = <String, Track>{};
    final newestByLocalId = <String, DateTime>{};
    for (final download in _downloads.where(_downloadPresentInLibrary)) {
      final localId = download.localTrackId ?? download.track.localId;
      if (localId == null || localId.isEmpty) {
        continue;
      }
      final previousUpdatedAt = newestByLocalId[localId];
      if (previousUpdatedAt != null &&
          previousUpdatedAt.isAfter(download.updatedAt)) {
        continue;
      }
      newestByLocalId[localId] = download.updatedAt;
      byLocalId[localId] = download.track.copyWith(
        id: localId,
        localId: localId,
        serverBaseUrl: download.serverBaseUrl,
        serverTrackId: download.track.serverTrackId ?? download.track.id,
        liked: likedLocalIds.contains(localId),
        inPlaylists: playlistTrackIds.contains(localId),
      );
    }
    final tracks = byLocalId.values.toList();
    tracks.sort((a, b) {
      final artist = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
      if (artist != 0) {
        return artist;
      }
      final album = a.album.toLowerCase().compareTo(b.album.toLowerCase());
      if (album != 0) {
        return album;
      }
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return List.unmodifiable(tracks);
  }

  String? _localTrackId(Track track) {
    final localId = track.localId;
    if (localId != null && localId.isNotEmpty) {
      return localId;
    }
    final byLocal = findLocal(track.id);
    if (byLocal?.localTrackId != null) {
      return byLocal!.localTrackId;
    }
    final serverTrackId = track.serverTrackId ?? track.id;
    for (final download in _downloads) {
      if (download.track.id == serverTrackId ||
          download.track.serverTrackId == serverTrackId) {
        return download.localTrackId;
      }
    }
    return null;
  }

  bool _downloadAvailable(OfflineTrackDownload download) {
    final filePath = download.filePath;
    if (!download.isDownloaded || filePath == null || filePath.isEmpty) {
      return false;
    }
    return true;
  }

  bool _downloadPresentInLibrary(OfflineTrackDownload download) {
    final filePath = download.filePath;
    if (filePath == null || filePath.isEmpty) {
      return false;
    }
    if (download.status != OfflineDownloadStatus.downloaded &&
        download.status != OfflineDownloadStatus.removing) {
      return false;
    }
    return true;
  }

  bool _downloadQueuedOrAvailable(OfflineTrackDownload? download) {
    if (download == null) {
      return false;
    }
    switch (download.status) {
      case OfflineDownloadStatus.queued:
      case OfflineDownloadStatus.preparing:
      case OfflineDownloadStatus.downloading:
      case OfflineDownloadStatus.validating:
      case OfflineDownloadStatus.removing:
        return true;
      case OfflineDownloadStatus.downloaded:
        return _downloadAvailable(download);
      case OfflineDownloadStatus.paused:
      case OfflineDownloadStatus.failed:
      case OfflineDownloadStatus.corrupt:
      case OfflineDownloadStatus.canceled:
        return false;
    }
  }

  bool _canPause(OfflineDownloadStatus status) {
    return status == OfflineDownloadStatus.queued ||
        status == OfflineDownloadStatus.preparing ||
        status == OfflineDownloadStatus.downloading ||
        status == OfflineDownloadStatus.validating;
  }

  bool _activeDownloadStatus(OfflineDownloadStatus status) {
    return status == OfflineDownloadStatus.preparing ||
        status == OfflineDownloadStatus.downloading ||
        status == OfflineDownloadStatus.validating;
  }

  bool _canResume(OfflineDownloadStatus status) {
    return status == OfflineDownloadStatus.paused ||
        status == OfflineDownloadStatus.failed ||
        status == OfflineDownloadStatus.corrupt ||
        status == OfflineDownloadStatus.canceled;
  }

  Future<List<OfflineTrackDownload>> _recoverInterruptedDownloads(
    List<OfflineTrackDownload> downloads,
  ) async {
    final now = DateTime.now();
    final recovered = <OfflineTrackDownload>[];
    for (final download in downloads) {
      if (download.status == OfflineDownloadStatus.preparing ||
          download.status == OfflineDownloadStatus.downloading ||
          download.status == OfflineDownloadStatus.validating) {
        recovered.add(
          download.copyWith(
            status: OfflineDownloadStatus.paused,
            updatedAt: now,
            error: 'Paused after app restart',
          ),
        );
        continue;
      }
      if (download.status == OfflineDownloadStatus.downloaded ||
          _downloadNeedsMissingFileRepair(download)) {
        recovered.add(await _recoverCompletedDownload(download, now));
        continue;
      }
      if (download.status == OfflineDownloadStatus.removing) {
        recovered.add(
          download.copyWith(
            status: _downloadFileExistsSync(download)
                ? OfflineDownloadStatus.downloaded
                : OfflineDownloadStatus.canceled,
            updatedAt: now,
            error: 'Removal interrupted',
          ),
        );
        continue;
      }
      recovered.add(download);
    }
    return recovered;
  }

  bool _downloadNeedsMissingFileRepair(OfflineTrackDownload download) {
    return download.status == OfflineDownloadStatus.corrupt &&
        download.error == 'Completed file missing';
  }

  Future<OfflineTrackDownload> _recoverCompletedDownload(
    OfflineTrackDownload download,
    DateTime now,
  ) async {
    if (_downloadFileExistsSync(download)) {
      if (_downloadNeedsMissingFileRepair(download)) {
        return download.copyWith(
          status: OfflineDownloadStatus.downloaded,
          error: null,
        );
      }
      return download;
    }
    final repairedFile = await _storage.findExistingTrackFile(
      serverBaseUrl: download.serverBaseUrl,
      trackId: _serverTrackId(download),
      extensions: _trackFileExtensionCandidates(download),
    );
    if (repairedFile != null) {
      return download.copyWith(
        status: OfflineDownloadStatus.downloaded,
        filePath: repairedFile.path,
        error: null,
      );
    }
    if (_downloadNeedsMissingFileRepair(download)) {
      return download;
    }
    return download.copyWith(
      status: OfflineDownloadStatus.corrupt,
      updatedAt: now,
      filePath: null,
      error: 'Completed file missing',
    );
  }

  Iterable<String> _trackFileExtensionCandidates(
    OfflineTrackDownload download,
  ) sync* {
    final fileExtension = _extensionFromFilePath(download.filePath);
    if (fileExtension != null) {
      yield fileExtension;
    }
    yield OfflineLibraryStorage.extensionFromContentType(download.contentType);
    yield 'audio';
  }

  String? _extensionFromFilePath(String? filePath) {
    final trimmed = filePath?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    final name = trimmed.split(RegExp(r'[/\\]')).last;
    final index = name.lastIndexOf('.');
    if (index < 0 || index == name.length - 1) {
      return null;
    }
    final extension = name.substring(index + 1).trim().toLowerCase();
    if (extension.isEmpty || extension == 'part') {
      return null;
    }
    return extension;
  }

  bool _sameDownloadList(
    List<OfflineTrackDownload> left,
    List<OfflineTrackDownload> right,
  ) {
    if (left.length != right.length) {
      return false;
    }
    for (var i = 0; i < left.length; i += 1) {
      final a = left[i];
      final b = right[i];
      if (a.status != b.status ||
          a.filePath != b.filePath ||
          a.error != b.error) {
        return false;
      }
    }
    return true;
  }

  List<OfflineDownloadJob> _recoverInterruptedJobs(
    List<OfflineDownloadJob> jobs,
  ) {
    final now = DateTime.now();
    return jobs
        .map((job) {
          if (job.status == OfflineDownloadStatus.downloading ||
              job.status == OfflineDownloadStatus.preparing ||
              job.status == OfflineDownloadStatus.validating) {
            return job.copyWith(
              status: OfflineDownloadStatus.queued,
              updatedAt: now,
            );
          }
          return job;
        })
        .toList(growable: false);
  }

  bool _sameJobList(
    List<OfflineDownloadJob> left,
    List<OfflineDownloadJob> right,
  ) {
    if (left.length != right.length) {
      return false;
    }
    for (var i = 0; i < left.length; i += 1) {
      final a = left[i];
      final b = right[i];
      if (a.jobId != b.jobId ||
          a.status != b.status ||
          a.completedCount != b.completedCount ||
          a.failedCount != b.failedCount ||
          a.materializedCount != b.materializedCount ||
          a.sourceId != b.sourceId) {
        return false;
      }
    }
    return true;
  }

  bool _jobBlocksNewQueue(OfflineDownloadJob job) {
    return job.status != OfflineDownloadStatus.paused &&
        job.status != OfflineDownloadStatus.failed &&
        job.status != OfflineDownloadStatus.corrupt &&
        job.status != OfflineDownloadStatus.canceled;
  }

  OfflineDownloadJob? _pausedParentJob(OfflineTrackDownload download) {
    final batchId = download.batchId;
    if (batchId == null || batchId.trim().isEmpty) {
      return null;
    }
    final job = _jobById(batchId);
    if (job == null || job.status != OfflineDownloadStatus.paused) {
      return null;
    }
    return job;
  }

  OfflineDownloadJob _chooseRollingJobToKeep(List<OfflineDownloadJob> jobs) {
    final sorted = List<OfflineDownloadJob>.from(jobs)
      ..sort((left, right) {
        final rank = _jobKeepRank(
          right.status,
        ).compareTo(_jobKeepRank(left.status));
        if (rank != 0) {
          return rank;
        }
        final completed = right.completedCount.compareTo(left.completedCount);
        if (completed != 0) {
          return completed;
        }
        final materialized = right.materializedCount.compareTo(
          left.materializedCount,
        );
        if (materialized != 0) {
          return materialized;
        }
        return right.updatedAt.compareTo(left.updatedAt);
      });
    return sorted.first;
  }

  int _jobKeepRank(OfflineDownloadStatus status) {
    return switch (status) {
      OfflineDownloadStatus.queued ||
      OfflineDownloadStatus.preparing ||
      OfflineDownloadStatus.downloading ||
      OfflineDownloadStatus.validating => 4,
      OfflineDownloadStatus.paused => 3,
      OfflineDownloadStatus.downloaded => 2,
      OfflineDownloadStatus.failed ||
      OfflineDownloadStatus.corrupt ||
      OfflineDownloadStatus.canceled ||
      OfflineDownloadStatus.removing => 1,
    };
  }

  bool _jobMatchesRollingCollection(
    OfflineDownloadJob job, {
    required String kind,
    required String serverBaseUrl,
    required String? label,
    Iterable<String> trackIds = const <String>[],
    Iterable<String> sourceIds = const <String>[],
  }) {
    if (job.kind != kind || job.serverBaseUrl != serverBaseUrl) {
      return false;
    }
    final sourceSignature = _idSignature(sourceIds);
    if (sourceSignature.isNotEmpty) {
      final jobSourceSignature = _idSignature(
        (_jobSourcesByJobId[job.jobId] ?? const <OfflineDownloadJobSource>[])
            .map((source) => source.sourceId),
      );
      return jobSourceSignature.isNotEmpty &&
          jobSourceSignature == sourceSignature;
    }

    final trackSignature = _idSignature(trackIds);
    if (trackSignature.isNotEmpty) {
      final jobTrackSignature = _idSignature(
        (_jobItemsByJobId[job.jobId] ?? const <OfflineDownloadJobItem>[]).map(
          (item) => item.serverTrackId,
        ),
      );
      return jobTrackSignature.isNotEmpty &&
          jobTrackSignature == trackSignature;
    }

    final normalizedLabel = _normalizedJobLabel(label);
    return normalizedLabel.isNotEmpty &&
        _normalizedJobLabel(job.label) == normalizedLabel;
  }

  String? _rollingJobCollectionKey(OfflineDownloadJob job) {
    final sourceSignature = _idSignature(
      (_jobSourcesByJobId[job.jobId] ?? const <OfflineDownloadJobSource>[]).map(
        (source) => source.sourceId,
      ),
    );
    if (sourceSignature.isNotEmpty) {
      return '${job.serverBaseUrl}\n${job.kind}\nsources:$sourceSignature';
    }

    final trackSignature = _idSignature(
      (_jobItemsByJobId[job.jobId] ?? const <OfflineDownloadJobItem>[]).map(
        (item) => item.serverTrackId,
      ),
    );
    if (trackSignature.isNotEmpty) {
      return '${job.serverBaseUrl}\n${job.kind}\ntracks:$trackSignature';
    }

    final label = _normalizedJobLabel(job.label);
    if (label.isEmpty) {
      return null;
    }
    return '${job.serverBaseUrl}\n${job.kind}\nlabel:$label';
  }

  String _stableJobId(String kind, String signature) {
    final digest = sha1
        .convert(utf8.encode('${connection.baseUrl}\n$kind\n$signature'))
        .toString();
    return 'job_${kind}_$digest';
  }

  String _queueAttemptRequestId(String stableJobId) {
    _queueAttemptSequence += 1;
    final nonce = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return '$stableJobId:$nonce:${_queueAttemptSequence.toRadixString(36)}';
  }

  String _rollingJobSignature({
    String? label,
    Iterable<String> trackIds = const <String>[],
    Iterable<String> sourceIds = const <String>[],
  }) {
    final sourceSignature = _idSignature(sourceIds);
    if (sourceSignature.isNotEmpty) {
      return 'sources:$sourceSignature';
    }
    final trackSignature = _idSignature(trackIds);
    if (trackSignature.isNotEmpty) {
      return 'tracks:$trackSignature';
    }
    return 'label:${_normalizedJobLabel(label)}';
  }

  String _idSignature(Iterable<String> ids) {
    final normalized =
        ids
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();
    return normalized.join('|');
  }

  String _normalizedJobLabel(String? label) {
    return label?.trim().toLowerCase() ?? '';
  }

  String _serverTrackId(OfflineTrackDownload download) {
    return download.track.serverTrackId ?? download.track.id;
  }

  String _downloadKey(OfflineTrackDownload download) {
    return _lookupKey(download.serverBaseUrl, _serverTrackId(download));
  }

  String _lookupKey(String serverBaseUrl, String trackId) {
    return '$serverBaseUrl\n$trackId';
  }

  String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  bool _isRollingJob(String batchId) {
    return _jobs.any((job) => job.jobId == batchId);
  }

  OfflineDownloadJob? _jobById(String jobId) {
    for (final job in _jobs) {
      if (job.jobId == jobId) {
        return job;
      }
    }
    return null;
  }

  Future<void> _recordPendingDownloadFiles(
    OfflineTrackDownload download,
  ) async {
    await _storage.recordPendingFileDeletes(<String?>[
      download.filePath,
      download.partialPath,
    ]);
  }

  Future<void> _cleanupPendingFileDeletes() {
    final existing = _pendingFileCleanupFuture;
    if (existing != null) {
      _pendingFileCleanupRequested = true;
      return existing;
    }
    final future = () async {
      do {
        _pendingFileCleanupRequested = false;
        await _runPendingFileCleanup();
      } while (_pendingFileCleanupRequested);
    }();
    _pendingFileCleanupFuture = future.whenComplete(() {
      _pendingFileCleanupFuture = null;
    });
    return _pendingFileCleanupFuture!;
  }

  Future<void> _runPendingFileCleanup() async {
    try {
      final paths = await _storage.readPendingFileDeletes();
      if (paths.isEmpty) {
        return;
      }
      for (final chunk in _chunks(paths, _maxParallelFileDeletes)) {
        final results = await Future.wait(
          chunk.map((path) async {
            final deleted = await _deletePendingFile(path);
            return deleted ? path : null;
          }),
          eagerError: false,
        );
        final completed = results.whereType<String>().toList(growable: false);
        if (completed.isNotEmpty) {
          await _storage.clearPendingFileDeletes(completed);
        }
      }
    } catch (err) {
      AppLogger.warning('Failed to clean up removed download files: $err');
    }
  }

  bool _downloadFileExistsSync(OfflineTrackDownload download) {
    final filePath = download.filePath;
    if (filePath == null || filePath.isEmpty) {
      return false;
    }
    return File(filePath).existsSync();
  }

  Future<bool> _deletePendingFile(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return true;
    }
    try {
      if (!await _storage.isManagedDeletePath(trimmed)) {
        AppLogger.warning(
          'Skipping unmanaged pending delete path outside offline storage: $trimmed',
        );
        return true;
      }
      final file = File(trimmed);
      if (await file.exists()) {
        await file.delete();
      }
      return true;
    } catch (err) {
      AppLogger.warning(
        'Failed to delete removed download file $trimmed: $err',
      );
      return false;
    }
  }

  Future<void> _deleteIfExists(String? path) async {
    if (path == null || path.trim().isEmpty) {
      return;
    }
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

class _DownloadWorkerStart {
  const _DownloadWorkerStart(this.request, this.sendPort);

  final _DownloadWorkerRequest request;
  final SendPort sendPort;
}

class _DownloadWorkerRequest {
  const _DownloadWorkerRequest({
    required this.serverBaseUrl,
    required this.trackId,
    required this.url,
    required this.token,
    required this.partialPath,
    required this.progressIntervalMs,
    required this.progressMinBytes,
    required this.diskFlushBytes,
    required this.timeoutSeconds,
    this.startByte,
    this.ifRange,
    this.expectedBytes,
    this.expectedSha256,
  });

  final String serverBaseUrl;
  final String trackId;
  final String url;
  final String token;
  final String partialPath;
  final int? startByte;
  final String? ifRange;
  final int? expectedBytes;
  final String? expectedSha256;
  final int progressIntervalMs;
  final int progressMinBytes;
  final int diskFlushBytes;
  final int timeoutSeconds;
}

class _DownloadWorkerReady {
  const _DownloadWorkerReady(this.cancelPort);

  final SendPort cancelPort;
}

class _DownloadWorkerMetadata {
  const _DownloadWorkerMetadata({
    required this.bytesDownloaded,
    required this.bytesTotal,
    this.contentType,
    this.contentDisposition,
    this.etag,
    this.sha256,
  });

  final int bytesDownloaded;
  final int? bytesTotal;
  final String? contentType;
  final String? contentDisposition;
  final String? etag;
  final String? sha256;
}

class _DownloadWorkerProgress {
  const _DownloadWorkerProgress({
    required this.bytesDownloaded,
    required this.bytesTotal,
  });

  final int bytesDownloaded;
  final int? bytesTotal;
}

class _DownloadWorkerComplete {
  const _DownloadWorkerComplete({
    required this.bytesDownloaded,
    required this.bytesTotal,
    this.contentType,
    this.contentDisposition,
    this.etag,
    this.sha256,
  });

  final int bytesDownloaded;
  final int bytesTotal;
  final String? contentType;
  final String? contentDisposition;
  final String? etag;
  final String? sha256;
}

class _DownloadWorkerFailure {
  const _DownloadWorkerFailure({required this.kind, required this.message});

  final _DownloadWorkerFailureKind kind;
  final String message;
}

enum _DownloadWorkerFailureKind { canceled, corrupt, error }

Future<void> _downloadWorkerMain(_DownloadWorkerStart start) async {
  final request = start.request;
  final cancelPort = ReceivePort();
  var canceled = false;
  var bytesDownloaded = request.startByte ?? 0;
  HttpClient? client;
  IOSink? sink;
  cancelPort.listen((_) {
    canceled = true;
    client?.close(force: true);
  });
  start.sendPort.send(_DownloadWorkerReady(cancelPort.sendPort));

  try {
    void throwIfCanceled() {
      if (canceled) {
        throw const _DownloadWorkerCanceled();
      }
    }

    final timeout = Duration(seconds: request.timeoutSeconds);
    client = HttpClient();
    throwIfCanceled();
    final httpRequest = await client
        .getUrl(Uri.parse(request.url))
        .timeout(timeout);
    httpRequest.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${request.token}',
    );
    final startByte = request.startByte;
    if (startByte != null && startByte > 0) {
      httpRequest.headers.set(HttpHeaders.rangeHeader, 'bytes=$startByte-');
      final ifRange = request.ifRange;
      if (ifRange != null && ifRange.trim().isNotEmpty) {
        httpRequest.headers.set(HttpHeaders.ifRangeHeader, ifRange.trim());
      }
    }
    throwIfCanceled();
    final response = await httpRequest.close().timeout(timeout);
    if (response.statusCode != HttpStatus.ok &&
        response.statusCode != HttpStatus.partialContent) {
      final body = await response.transform(utf8.decoder).join();
      throw Exception('ApiException(${response.statusCode}): $body');
    }

    final partialFile = File(request.partialPath);
    if (response.statusCode == HttpStatus.ok && bytesDownloaded > 0) {
      await partialFile.writeAsBytes(const <int>[]);
      bytesDownloaded = 0;
    }
    final contentLength = response.contentLength < 0
        ? null
        : response.contentLength;
    final contentRange = response.headers.value(HttpHeaders.contentRangeHeader);
    final bytesTotal =
        request.expectedBytes ??
        _workerResolveBytesTotal(
          contentRange: contentRange,
          contentLength: contentLength,
          statusCode: response.statusCode,
          startByte: bytesDownloaded,
        );
    final contentType = response.headers.value(HttpHeaders.contentTypeHeader);
    final contentDisposition = response.headers.value('content-disposition');
    final etag = response.headers.value(HttpHeaders.etagHeader);
    final sha256Header = response.headers.value('x-phonolite-sha256');
    start.sendPort.send(
      _DownloadWorkerMetadata(
        bytesDownloaded: bytesDownloaded,
        bytesTotal: bytesTotal,
        contentType: contentType,
        contentDisposition: contentDisposition,
        etag: etag,
        sha256: sha256Header,
      ),
    );

    sink = partialFile.openWrite(
      mode:
          response.statusCode == HttpStatus.partialContent &&
              bytesDownloaded > 0
          ? FileMode.append
          : FileMode.write,
    );
    var lastProgressAt = DateTime.fromMillisecondsSinceEpoch(0);
    var lastProgressBytes = bytesDownloaded;
    var bytesSinceFlush = 0;
    await for (final chunk in response) {
      throwIfCanceled();
      sink.add(chunk);
      bytesDownloaded += chunk.length;
      bytesSinceFlush += chunk.length;
      if (bytesTotal != null && bytesDownloaded > bytesTotal) {
        throw const _DownloadWorkerCorrupt(
          'downloaded more bytes than expected',
        );
      }
      if (bytesSinceFlush >= request.diskFlushBytes) {
        bytesSinceFlush = 0;
        await sink.flush();
      }
      final now = DateTime.now();
      if (now.difference(lastProgressAt).inMilliseconds >=
              request.progressIntervalMs &&
          bytesDownloaded - lastProgressBytes >= request.progressMinBytes) {
        lastProgressAt = now;
        lastProgressBytes = bytesDownloaded;
        start.sendPort.send(
          _DownloadWorkerProgress(
            bytesDownloaded: bytesDownloaded,
            bytesTotal: bytesTotal,
          ),
        );
      }
    }
    await sink.flush();
    await sink.close();
    sink = null;
    throwIfCanceled();

    final expectedTotal = bytesTotal ?? bytesDownloaded;
    if (expectedTotal > 0 && bytesDownloaded != expectedTotal) {
      throw _DownloadWorkerCorrupt(
        'downloaded $bytesDownloaded bytes, expected $expectedTotal',
      );
    }

    final expectedSha256 = request.expectedSha256?.trim().toLowerCase();
    final actualSha256 = sha256Header?.trim().toLowerCase();
    if (expectedSha256 != null && expectedSha256.isNotEmpty) {
      final digest = await _sha256Path(request.partialPath);
      if (digest != expectedSha256) {
        await _deleteWorkerFile(request.partialPath);
        throw const _DownloadWorkerCorrupt('checksum mismatch');
      }
    }

    start.sendPort.send(
      _DownloadWorkerComplete(
        bytesDownloaded: bytesDownloaded,
        bytesTotal: expectedTotal,
        contentType: contentType,
        contentDisposition: contentDisposition,
        etag: etag,
        sha256: actualSha256 ?? sha256Header,
      ),
    );
  } on _DownloadWorkerCanceled {
    start.sendPort.send(
      const _DownloadWorkerFailure(
        kind: _DownloadWorkerFailureKind.canceled,
        message: 'download canceled',
      ),
    );
  } on _DownloadWorkerCorrupt catch (err) {
    start.sendPort.send(
      _DownloadWorkerFailure(
        kind: _DownloadWorkerFailureKind.corrupt,
        message: err.message,
      ),
    );
  } catch (err) {
    start.sendPort.send(
      _DownloadWorkerFailure(
        kind: canceled
            ? _DownloadWorkerFailureKind.canceled
            : _DownloadWorkerFailureKind.error,
        message: err.toString(),
      ),
    );
  } finally {
    try {
      await sink?.close();
    } catch (_) {}
    client?.close(force: true);
    cancelPort.close();
  }
}

int? _workerResolveBytesTotal({
  required String? contentRange,
  required int? contentLength,
  required int statusCode,
  required int startByte,
}) {
  final rangeTotal = _workerParseContentRangeTotal(contentRange);
  if (rangeTotal != null) {
    return rangeTotal;
  }
  if (contentLength == null || contentLength <= 0) {
    return null;
  }
  if (statusCode == HttpStatus.partialContent) {
    return startByte + contentLength;
  }
  return contentLength;
}

int? _workerParseContentRangeTotal(String? header) {
  if (header == null) {
    return null;
  }
  final slashIndex = header.lastIndexOf('/');
  if (slashIndex < 0 || slashIndex == header.length - 1) {
    return null;
  }
  final total = header.substring(slashIndex + 1).trim();
  if (total == '*') {
    return null;
  }
  return int.tryParse(total);
}

Future<String> _sha256Path(String path) async {
  final digest = await sha256.bind(File(path).openRead()).first;
  return digest.toString().toLowerCase();
}

Future<void> _deleteWorkerFile(String path) async {
  final file = File(path);
  if (await file.exists()) {
    await file.delete();
  }
}

class _DownloadWorkerCanceled implements Exception {
  const _DownloadWorkerCanceled();
}

class _DownloadWorkerCorrupt implements Exception {
  const _DownloadWorkerCorrupt(this.message);

  final String message;
}

class _ArtworkPaths {
  const _ArtworkPaths({
    this.albumArtPath,
    this.artistArtPath,
    this.artistBannerPath,
  });

  final String? albumArtPath;
  final String? artistArtPath;
  final String? artistBannerPath;

  bool get isEmpty =>
      albumArtPath == null && artistArtPath == null && artistBannerPath == null;
}

class _DownloadPaused implements Exception {
  const _DownloadPaused(this.message);

  final String message;

  @override
  String toString() => message;
}

class _DownloadCanceled implements Exception {
  const _DownloadCanceled();
}

class _DownloadCorrupt implements Exception {
  const _DownloadCorrupt(this.message);

  final String message;

  @override
  String toString() => message;
}
