part of '../offline_download_client.dart';

void _offlineDownloadActorMain(OfflineActorInit init) {
  installServerTrustOverrides();

  if (init.trust != null) {
    ServerTrustRegistry.register(init.baseUrl, init.trust!);
  }

  final token = init.rootIsolateToken;

  if (token != null) {
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  }

  final commandPort = ReceivePort();
  final connection = ServerConnection(baseUrl: init.baseUrl);

  connection.setToken(init.token);

  final core = _OfflineDownloadActorCore(connection: connection, storage: init.storageConfig.createStorage());
  var revision = 0;
  Timer? downloadStateTimer;
  Timer? libraryStateTimer;
  List<Track> lastLocalLiked = const <Track>[];
  List<Playlist> lastLocalPlaylists = const <Playlist>[];
  List<Track> lastLocalPlaylistTracks = const <Track>[];
  List<LocalPlaylistEntry> lastLocalPlaylistEntries = const [];
  List<Track> lastLocalDownloadedTracks = const <Track>[];
  final subscriptions = <StreamSubscription<dynamic>>[];

  void sendDownloadState() {
    developer.Timeline.startSync('offline.actor.downloadState');

    try {
      init.replyPort.send(
        OfflineActorDownloadState(
          downloads: core.downloads,
          batches: core.batches,
          jobs: core.jobs,
          revision: ++revision,
        ),
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
      final localPlaylistTracks = List<Track>.unmodifiable(core.localPlaylistTracks);
      final localDownloadedTracks = List<Track>.unmodifiable(core.localDownloadedTracks());

      if (sameOfflineTrackSnapshots(lastLocalLiked, localLiked) &&
          sameOfflinePlaylistSnapshots(lastLocalPlaylists, localPlaylists) &&
          sameOfflineTrackSnapshots(lastLocalPlaylistTracks, localPlaylistTracks) &&
          sameLocalPlaylistEntries(lastLocalPlaylistEntries, core.localPlaylistEntries) &&
          sameOfflineTrackSnapshots(lastLocalDownloadedTracks, localDownloadedTracks)) {
        return;
      }

      lastLocalLiked = localLiked;
      lastLocalPlaylists = localPlaylists;
      lastLocalPlaylistTracks = localPlaylistTracks;
      lastLocalPlaylistEntries = core.localPlaylistEntries;
      lastLocalDownloadedTracks = localDownloadedTracks;

      init.replyPort.send(
        OfflineActorLibraryState(
          localLiked: localLiked,
          localPlaylists: localPlaylists,
          localPlaylistTracks: localPlaylistTracks,
          localPlaylistEntries: lastLocalPlaylistEntries,
          localDownloadedTracks: localDownloadedTracks,
          offlineArtistGroups: offline_views.offlineArtistGroups(localDownloadedTracks),
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

    void publishScheduledDownloadState() {
      downloadStateTimer = null;
      sendDownloadState();
    }

    downloadStateTimer = Timer(_OfflineDownloadActorCore._stateEmitCoalesceDelay, publishScheduledDownloadState);
  }

  void scheduleLibraryState() {
    if (libraryStateTimer != null) {
      return;
    }

    void publishScheduledLibraryState() {
      libraryStateTimer = null;
      sendLibraryState();
    }

    libraryStateTimer = Timer(_OfflineDownloadActorCore._stateEmitCoalesceDelay, publishScheduledLibraryState);
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

  void scheduleChangedState(List<OfflineTrackDownload> _) {
    scheduleDownloadState();
    scheduleLibraryState();
  }

  subscriptions.add(core.stream.listen(scheduleChangedState));
  subscriptions.add(core.batchStream.listen((_) => scheduleDownloadState()));
  subscriptions.add(core.jobStream.listen((_) => scheduleDownloadState()));
  subscriptions.add(core.localLikedStream.listen((_) => scheduleLibraryState()));
  subscriptions.add(core.localPlaylistsStream.listen((_) => scheduleLibraryState()));
  subscriptions.add(core.localPlaylistTracksStream.listen((_) => scheduleLibraryState()));

  init.replyPort.send(OfflineActorReady(commandPort.sendPort));

  Future<void> commandChain = Future<void>.value();

  Future<void> handleCommand(OfflineActorCommand message) async {
    final task = developer.TimelineTask();

    task.start('offline.actor.command');

    try {
      connection.setBaseUrl(message.baseUrl);

      if (message.trust != null) {
        connection.setTrust(message.trust!);
      }

      connection.setToken(message.token);

      final result = await _handleOfflineActorCommand(core, message);

      if (_offlineActorCommandNeedsDownloadState(message.name)) {
        sendDownloadStateNow();
      }

      if (_offlineActorCommandMayChangeLibraryState(message.name)) {
        sendLibraryStateNow();
      }

      init.replyPort.send(OfflineActorResult(id: message.id, result: result));

      if (message.name == 'dispose') {
        downloadStateTimer?.cancel();
        libraryStateTimer?.cancel();

        for (final subscription in subscriptions) {
          await subscription.cancel();
        }

        commandPort.close();
      }
    } catch (err, stack) {
      init.replyPort.send(OfflineActorResult(id: message.id, error: '$err\n$stack'));
    } finally {
      task.finish();
    }
  }

  void enqueueCommand(Object? message) {
    if (message is! OfflineActorCommand) {
      return;
    }

    commandChain = commandChain.then((_) => handleCommand(message));
    unawaited(commandChain);
  }

  commandPort.listen(enqueueCommand);
}

bool _offlineActorCommandNeedsDownloadState(String name) {
  return switch (name) {
    'readLocalLikeStates' ||
    'loadLocalPlaylists' ||
    'loadLocalPlaylistTracks' ||
    'loadLocalLikedTracks' ||
    'setLocalLike' ||
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
    'clearUnfinishedDownloads' ||
    'resetLocalData' ||
    'loadLocalPlaylists' ||
    'loadLocalPlaylistTracks' ||
    'loadLocalLikedTracks' ||
    'setLocalLike' ||
    'createLocalPlaylist' ||
    'downloadPlaylist' ||
    'renameLocalPlaylist' ||
    'updateLocalPlaylistImage' ||
    'deleteLocalPlaylist' ||
    'addLocalTrackToPlaylist' ||
    'addSourceToLocalPlaylist' ||
    'retryLocalPlaylistEntry' ||
    'resumeLocalPlaylistEntry' ||
    'removeLocalTrackFromPlaylist' => true,
    _ => false,
  };
}
