part of 'package:phonolite_app/infrastructure/downloads/client/offline_download_client.dart';

class _OfflineDownloadActorCore
    with
        _DownloadStateStoreFacade,
        _LocalCollectionCommandsFacade,
        _RollingDownloadJobsFacade,
        _DownloadSchedulerFacade,
        _DownloadCommandsFacade,
        _TrackDownloadTransferFacade,
        _DownloadArtworkHydratorFacade,
        _DownloadDataResetFacade,
        _DownloadPlannerFacade,
        _OfflineMetadataRepairFacade,
        _PendingFileCleanupFacade,
        _ServerDownloadJobAdapterFacade,
        _DownloadRemovalFacade,
        _ArtistJobDiscoveryFacade,
        _DownloadJobMaterializerFacade,
        _InterruptedDownloadRecoveryFacade {
  static const int maxParallelDownloadsPerServer = OfflineDownloadClient.maxParallelDownloadsPerServer;
  static const Duration _progressEmitInterval = Duration(milliseconds: 200);
  static const Duration _artworkHydrationDelay = Duration(milliseconds: 500);
  static const Duration _localUserDataReloadDelay = Duration(milliseconds: 800);
  static const Duration _stateEmitCoalesceDelay = Duration(milliseconds: 80);
  static const int _diskFlushBytes = 8 * 1024 * 1024;
  static const int _queuePersistChunkSize = 20;
  static const int _rollingWindowSize = 20;
  static const Duration _queuePersistYieldDelay = Duration(milliseconds: 8);
  static const int _maxParallelFileDeletes = 4;
  static const int _metadataRepairBatchSize = 32;
  static const int _metadataRepairMaxPerRun = 256;
  static const int _maxParallelMetadataRepairs = 4;

  @override
  late final _InterruptedDownloadRecovery _ownerRecovery;
  @override
  late final _DownloadJobMaterializer _ownerMaterialize;
  @override
  late final _ArtistJobDiscovery _ownerDiscovery;
  @override
  late final _DownloadRemoval _ownerDeletion;
  @override
  late final _ServerDownloadJobAdapter _ownerV2;
  @override
  late final _PendingFileCleanup _ownerCleanup;
  @override
  late final _OfflineMetadataRepair _ownerMetadata;
  @override
  late final _DownloadPlanner _ownerPlanning;
  @override
  late final _DownloadDataReset _ownerReset;
  @override
  late final _DownloadArtworkHydrator _ownerArtwork;
  @override
  late final _TrackDownloadTransfer _ownerTransfer;
  @override
  late final _DownloadCommands _ownerControl;
  @override
  late final _DownloadScheduler _ownerScheduler;
  @override
  late final _RollingDownloadJobs _ownerRolling;
  @override
  late final _LocalCollectionCommands _ownerCollections;
  @override
  late final _DownloadStateStore _ownerState;
  final ServerConnection connection;
  final OfflineLibraryStorage _storage;

  _OfflineDownloadActorCore({required this.connection, OfflineLibraryStorage storage = const OfflineLibraryStorage()})
    : _storage = storage {
    // Create state owners in the same zone as the parent and before UI subscriptions.
    _ownerRecovery = _InterruptedDownloadRecovery(this);
    _ownerMaterialize = _DownloadJobMaterializer(this);
    _ownerDiscovery = _ArtistJobDiscovery(this);
    _ownerDeletion = _DownloadRemoval(this);
    _ownerV2 = _ServerDownloadJobAdapter(this);
    _ownerCleanup = _PendingFileCleanup(this);
    _ownerMetadata = _OfflineMetadataRepair(this);
    _ownerPlanning = _DownloadPlanner(this);
    _ownerReset = _DownloadDataReset(this);
    _ownerArtwork = _DownloadArtworkHydrator(this);
    _ownerTransfer = _TrackDownloadTransfer(this);
    _ownerControl = _DownloadCommands(this);
    _ownerScheduler = _DownloadScheduler(this);
    _ownerRolling = _RollingDownloadJobs(this);
    _ownerCollections = _LocalCollectionCommands(this);
    _ownerState = _DownloadStateStore(this);
  }

  Stream<List<OfflineTrackDownload>> get stream => _controller.stream;

  Stream<List<OfflineDownloadBatch>> get batchStream => _batchController.stream;

  Stream<List<OfflineDownloadJob>> get jobStream => _jobController.stream;

  Stream<List<Track>> get localLikedStream => _localLikedController.stream;

  Stream<List<Playlist>> get localPlaylistsStream => _localPlaylistsController.stream;

  Stream<List<Track>> get localPlaylistTracksStream => _localPlaylistTracksController.stream;

  List<OfflineTrackDownload> get downloads => List.unmodifiable(_downloads);

  List<OfflineDownloadBatch> get batches => List.unmodifiable(_batches);

  List<OfflineDownloadJob> get jobs => List.unmodifiable(_jobs);

  List<Track> get localLiked => List.unmodifiable(_localLiked);

  List<Playlist> get localPlaylists => List.unmodifiable(_localPlaylists);

  List<Track> get localPlaylistTracks => List.unmodifiable(_localPlaylistTracks);

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

    while (_pendingStorageOperations.isNotEmpty) {
      await Future.wait(_pendingStorageOperations.toList(), eagerError: false);
    }

    await _controller.close();
    await _batchController.close();
    await _jobController.close();
    await _localLikedController.close();
    await _localPlaylistsController.close();
    await _localPlaylistTracksController.close();
  }

  Future<void> load() {
    if (_resettingLocalData) {
      return _resetLocalDataFuture!;
    }

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

    _jobItemsByJobId.clear();

    Future<MapEntry<String, List<OfflineDownloadJobItem>>> readJobItems(OfflineDownloadJob job) async {
      return MapEntry(job.jobId, await _storage.readDownloadJobItemsLean(job.jobId));
    }

    _jobItemsByJobId.addEntries(await Future.wait(_jobs.map(readJobItems)));

    _jobSourcesByJobId.clear();

    Future<MapEntry<String, List<OfflineDownloadJobSource>>> readJobSources(OfflineDownloadJob job) async {
      return MapEntry(job.jobId, await _storage.readDownloadJobSources(job.jobId));
    }

    _jobSourcesByJobId.addEntries(await Future.wait(_jobs.map(readJobSources)));

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
}
