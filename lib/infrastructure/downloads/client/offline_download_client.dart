import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import 'package:phonolite_app/data/configuration/downloads/offline_storage_config.dart';
import 'package:phonolite_app/data/files/download_integrity.dart';
import 'package:phonolite_app/data/models/collections/local_playlist_entry.dart';
import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/data/models/downloads/download_outcomes.dart';
import 'package:phonolite_app/data/models/downloads/download_quality.dart';
import 'package:phonolite_app/data/models/downloads/download_worker_protocol.dart';
import 'package:phonolite_app/data/models/downloads/offline_actor_protocol.dart';
import 'package:phonolite_app/data/models/downloads/offline_download_snapshot.dart';
import 'package:phonolite_app/data/models/downloads/offline_track_metadata.dart';
import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/library/offline_library_snapshot.dart';
import 'package:phonolite_app/data/models/library/source_track_ref.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/library/track_source_match.dart';
import 'package:phonolite_app/data/models/server/download_batch_manifest.dart';
import 'package:phonolite_app/data/models/server/download_job_v2.dart';
import 'package:phonolite_app/data/projections/library/offline_library_views.dart' as offline_views;
import 'package:phonolite_app/data/rules/downloads/download_progress_throttle.dart';
import 'package:phonolite_app/data/rules/downloads/download_queue_rules.dart';
import 'package:phonolite_app/data/rules/downloads/offline_snapshot_comparison.dart';
import 'package:phonolite_app/data/storage/logs/app_log.dart';
import 'package:phonolite_app/data/storage/offline/library/offline_library.dart';
import 'package:phonolite_app/data/storage/preferences/offline_storage_settings_storage.dart';
import 'package:phonolite_app/data/structures/downloads/offline_download_index.dart';
import 'package:phonolite_app/infrastructure/downloads/http/download_range.dart';
import 'package:phonolite_app/infrastructure/security/server_trust.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';

part 'actor/offline_actor.dart';
part 'actor/offline_actor_client.dart';
part 'actor/offline_command_dispatcher.dart';
part 'artwork/download_artwork_hydrator.dart';
part 'collections/local_collection_commands.dart';
part 'collections/local_playlist_downloads.dart';
part 'deletion/remove_downloads.dart';
part 'deletion/reset_local_download_data.dart';
part 'download_runtime.dart';
part 'metadata/offline_metadata_repair.dart';
part 'planning/artist_job_discovery.dart';
part 'planning/compressed_download_jobs.dart';
part 'planning/download_job_materializer.dart';
part 'planning/download_planner.dart';
part 'planning/rolling_download_jobs.dart';
part 'planning/server_download_job_adapter.dart';
part 'recovery/interrupted_download_recovery.dart';
part 'recovery/pending_file_cleanup.dart';
part 'scheduling/download_commands.dart';
part 'scheduling/download_scheduler.dart';
part 'snapshots/download_state_store.dart';
part 'snapshots/offline_snapshot_publisher.dart';
part 'transfer/download_worker.dart';
part 'transfer/transfer_track.dart';

class OfflineDownloadClient with _OfflineSnapshotPublisherFacade, _OfflineActorClientFacade {
  static const int maxParallelDownloadsPerServer = 1;

  @override
  late final _OfflineActorClient _ownerActor;
  @override
  late final _OfflineSnapshotPublisher _ownerSnapshots;
  final Future<DownloadQuality> Function()? _qualityProvider;
  final ServerConnection connection;
  final OfflineStorageConfig _storageConfig;
  final _OfflineDownloadActorCore? _inlineCore;
  int _nextCommandId = 1;

  OfflineDownloadClient({
    required this.connection,
    OfflineLibraryStorage storage = const OfflineLibraryStorage(),
    Future<DownloadQuality> Function()? qualityProvider,
  }) : _qualityProvider = qualityProvider,
       _storageConfig = OfflineStorageConfig.fromStorage(storage),
       _inlineCore = _canUseActor(storage)
           ? null
           : _OfflineDownloadActorCore(connection: connection, storage: storage) {
    // Create state owners in the same zone as the parent and before UI subscriptions.
    _ownerActor = _OfflineActorClient(this);
    _ownerSnapshots = _OfflineSnapshotPublisher(this);

    _listenToInlineCore();
  }

  Stream<List<OfflineTrackDownload>> get stream => _inlineCore?.stream ?? _controller.stream;

  Stream<List<OfflineDownloadBatch>> get batchStream => _inlineCore?.batchStream ?? _batchController.stream;

  Stream<List<OfflineDownloadJob>> get jobStream => _inlineCore?.jobStream ?? _jobController.stream;

  /// Broadcast changes after [downloadSnapshot] is updated; no initial replay.
  ///
  /// Delivery is asynchronous and may coalesce progress updates. Reading the
  /// snapshot and subscribing are separate operations, not an atomic handoff.
  /// Command failures complete their futures rather than entering this stream.
  /// This client closes the stream during [dispose].
  Stream<OfflineDownloadSnapshot> get downloadSnapshotStream => _downloadSnapshotController.stream;

  /// Broadcast library changes after [librarySnapshot] is updated, without replay.
  ///
  /// Like [downloadSnapshotStream], delivery is asynchronous and coalesced,
  /// failures use command futures, and [dispose] closes the stream.
  Stream<OfflineLibrarySnapshot> get librarySnapshotStream => _librarySnapshotController.stream;

  Stream<List<Track>> get localLikedStream => _inlineCore?.localLikedStream ?? _localLikedController.stream;

  Stream<List<Playlist>> get localPlaylistsStream =>
      _inlineCore?.localPlaylistsStream ?? _localPlaylistsController.stream;

  Stream<List<Track>> get localPlaylistTracksStream =>
      _inlineCore?.localPlaylistTracksStream ?? _localPlaylistTracksController.stream;

  List<OfflineTrackDownload> get downloads => _inlineCore?.downloads ?? List.unmodifiable(_downloads);

  List<OfflineDownloadBatch> get batches => _inlineCore?.batches ?? List.unmodifiable(_batches);

  List<OfflineDownloadJob> get jobs => _inlineCore?.jobs ?? List.unmodifiable(_jobs);

  /// Current download state. Observe subsequent updates with
  /// [downloadSnapshotStream]; a read does not start or subscribe to work.
  OfflineDownloadSnapshot get downloadSnapshot => _inlineCore == null
      ? _downloadSnapshot
      : OfflineDownloadSnapshot(
          downloads: _inlineCore.downloads,
          batches: _inlineCore.batches,
          jobs: _inlineCore.jobs,
          jobItems: _inlineCore.jobItems,
          revision: _downloadSnapshot.revision,
        );

  /// Current library state; subsequent updates use [librarySnapshotStream].
  /// The two snapshot streams are independently published, not an atomic pair.
  OfflineLibrarySnapshot get librarySnapshot => _inlineCore == null
      ? _librarySnapshot
      : OfflineLibrarySnapshot(
          tracks: _inlineCore.localDownloadedTracks(),
          artistGroups: offline_views.offlineArtistGroups(_inlineCore.localDownloadedTracks()),
          liked: _inlineCore.localLiked,
          playlists: _inlineCore.localPlaylists,
          playlistTracks: _inlineCore.localPlaylistTracks,
          playlistEntries: _inlineCore.localPlaylistEntries,
          revision: _librarySnapshot.revision,
        );

  List<Track> get localLiked => _inlineCore?.localLiked ?? List.unmodifiable(_localLiked);

  List<Playlist> get localPlaylists => _inlineCore?.localPlaylists ?? List.unmodifiable(_localPlaylists);

  List<Track> get localPlaylistTracks => _inlineCore?.localPlaylistTracks ?? List.unmodifiable(_localPlaylistTracks);

  List<LocalPlaylistEntry> get localPlaylistEntries => librarySnapshot.playlistEntries;

  Stream<List<LocalPlaylistEntry>> get localPlaylistEntriesStream =>
      librarySnapshotStream.map((snapshot) => snapshot.playlistEntries);

  Future<void> addSourceToLocalPlaylist(String playlistId, Track track, SourceTrackRef source) => _commandOrInline(
    'addSourceToLocalPlaylist',
    OfflinePlaylistSourceRequest(playlistId: playlistId, track: track, source: source),
    (core) => core.addSourceToLocalPlaylist(playlistId, track, source),
  );

  Future<void> retryLocalPlaylistEntry(LocalPlaylistEntry entry) =>
      _commandOrInline('retryLocalPlaylistEntry', entry, (core) => core.retryLocalPlaylistEntry(entry));

  Future<void> resumeLocalPlaylistEntry(LocalPlaylistEntry entry) =>
      _commandOrInline('resumeLocalPlaylistEntry', entry, (core) => core.resumeLocalPlaylistEntry(entry));

  Future<String?> resolveLocalPlaylistTrackId(Track track) {
    final core = _inlineCore;

    return core != null
        ? core.resolveLocalPlaylistTrackId(track)
        : _send<String?>('resolveLocalPlaylistTrackId', track);
  }

  Future<List<TrackSourceMatch>> readServerTrackMatches(String serverBaseUrl, String localTrackId) {
    final core = _inlineCore;

    return core != null
        ? core._storage.readServerTrackMatches(serverBaseUrl, localTrackId)
        : _send<List<TrackSourceMatch>>('readTrackSourceMatch', OfflineTrackMatchRequest(localTrackId, serverBaseUrl));
  }

  Future<void> saveTrackSourceMatch(TrackSourceMatch match) =>
      _commandOrInline('saveTrackSourceMatch', match, (core) => core._storage.saveTrackSourceMatch(match));

  Future<void> removeTrackSourceMatch(SourceTrackRef source) =>
      _commandOrInline('removeTrackSourceMatch', source, (core) => core._storage.removeTrackSourceMatch(source));

  Future<void> dispose() async {
    _disposed = true;

    _inlineDownloadTimer?.cancel();
    _inlineLibraryTimer?.cancel();

    for (final subscription in _inlineSubscriptions) {
      await subscription.cancel();
    }

    _inlineSubscriptions.clear();

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

    return _downloadIndex.findServer(serverBaseUrl, trackId);
  }

  OfflineTrackDownload? findLocal(String localTrackId) {
    final core = _inlineCore;
    if (core != null) {
      return core.findLocal(localTrackId);
    }

    return _downloadIndex.findLocal(localTrackId);
  }

  List<Track> localDownloadedTracks() {
    final core = _inlineCore;
    if (core != null) {
      return core.localDownloadedTracks();
    }

    return List.unmodifiable(_librarySnapshot.tracks);
  }

  Future<int> downloadTrack(Track track) => _withQueueQuality(() => _downloadTrack(track));

  Future<int> _downloadTrack(Track track) {
    final core = _inlineCore;
    if (core != null) {
      return core.downloadTrack(track);
    }

    return _send<int>('downloadTrack', track);
  }

  Future<int> queueTracks(Iterable<Track> tracks, {String? label, String kind = 'tracks', String? sourceId}) =>
      _withQueueQuality(() => _queueTracks(tracks, label: label, kind: kind, sourceId: sourceId));

  Future<int> _queueTracks(Iterable<Track> tracks, {String? label, String kind = 'tracks', String? sourceId}) {
    final core = _inlineCore;
    if (core != null) {
      return core.queueTracks(tracks, label: label, kind: kind, sourceId: sourceId);
    }

    return _send<int>('queueTracks', OfflineQueueTracksRequest(tracks.toList(growable: false), label, kind, sourceId));
  }

  Future<int> queueBatch(DownloadBatchManifest manifest, {String? label}) {
    final core = _inlineCore;
    if (core != null) {
      return core.queueBatch(manifest, label: label);
    }

    return _send<int>('queueBatch', OfflineQueueBatchRequest(manifest, label));
  }

  Future<int> queueArtist(Artist artist, List<Album> albums) => _withQueueQuality(() => _queueArtist(artist, albums));

  Future<int> _queueArtist(Artist artist, List<Album> albums) {
    final core = _inlineCore;
    if (core != null) {
      return core.queueArtist(artist, albums);
    }

    return _send<int>('queueArtist', OfflineQueueArtistRequest(artist, albums));
  }

  Future<void> pauseDownload(OfflineTrackDownload download) =>
      _commandOrInline('pauseDownload', download, (core) => core.pauseDownload(download));

  Future<void> resumeDownload(OfflineTrackDownload download) =>
      _commandOrInline('resumeDownload', download, (core) => core.resumeDownload(download));

  Future<void> retryDownload(OfflineTrackDownload download) =>
      _commandOrInline('retryDownload', download, (core) => core.retryDownload(download));

  Future<void> cancelDownload(OfflineTrackDownload download) =>
      _commandOrInline('cancelDownload', download, (core) => core.cancelDownload(download));

  Future<void> pauseDownloadsForServer(String serverBaseUrl) =>
      _commandOrInline('pauseDownloadsForServer', serverBaseUrl, (core) => core.pauseDownloadsForServer(serverBaseUrl));

  Future<void> resumePausedForCurrentServer() =>
      _commandOrInline('resumePausedForCurrentServer', null, (core) => core.resumePausedForCurrentServer());

  Future<void> repairOfflineMetadataFragments() =>
      _commandOrInline('repairOfflineMetadataFragments', null, (core) => core.repairOfflineMetadataFragments());

  Future<void> refreshOfflineMetadataForAlbum(String albumId) => _commandOrInline(
    'refreshOfflineMetadataForAlbum',
    albumId,
    (core) => core.refreshOfflineMetadataForAlbum(albumId),
  );

  Future<void> refreshOfflineMetadataForArtist(String artistId) => _commandOrInline(
    'refreshOfflineMetadataForArtist',
    artistId,
    (core) => core.refreshOfflineMetadataForArtist(artistId),
  );

  Future<void> pauseDownloadJob(OfflineDownloadJob job) =>
      _commandOrInline('pauseDownloadJob', job, (core) => core.pauseDownloadJob(job));

  Future<void> resumeDownloadJob(OfflineDownloadJob job) =>
      _commandOrInline('resumeDownloadJob', job, (core) => core.resumeDownloadJob(job));

  Future<void> cancelDownloadJob(OfflineDownloadJob job) =>
      _commandOrInline('cancelDownloadJob', job, (core) => core.cancelDownloadJob(job));

  Future<void> removeTrack(String trackId) =>
      _commandOrInline('removeTrack', trackId, (core) => core.removeTrack(trackId));

  Future<void> removeDownload(OfflineTrackDownload download) => removeDownloads(<OfflineTrackDownload>[download]);

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

  Future<void> clearFailedAndCorrupt() =>
      _commandOrInline('clearFailedAndCorrupt', null, (core) => core.clearFailedAndCorrupt());

  Future<void> resetLocalData() => _commandOrInline('resetLocalData', null, (core) => core.resetLocalData());

  Future<void> clearUnfinishedDownloads() =>
      _commandOrInline('clearUnfinishedDownloads', null, (core) => core.clearUnfinishedDownloads());

  Future<void> loadLocalPlaylists() =>
      _commandOrInline('loadLocalPlaylists', null, (core) => core.loadLocalPlaylists());

  Future<void> loadLocalPlaylistTracks(String playlistId) =>
      _commandOrInline('loadLocalPlaylistTracks', playlistId, (core) => core.loadLocalPlaylistTracks(playlistId));

  Future<void> loadLocalLikedTracks() =>
      _commandOrInline('loadLocalLikedTracks', null, (core) => core.loadLocalLikedTracks());

  Future<void> setLocalLike(Track track, bool liked) {
    final core = _inlineCore;
    if (core != null) {
      return core.setLocalLike(track, liked);
    }

    return _send<void>('setLocalLike', OfflineTrackBoolRequest(track, liked));
  }

  Future<List<LocalLikeState>> readLocalLikeStates() {
    final core = _inlineCore;
    if (core != null) {
      return core.readLocalLikeStates();
    }

    return _send<List<LocalLikeState>>('readLocalLikeStates');
  }

  Future<Playlist> createLocalPlaylist(String name, {String? description}) {
    final core = _inlineCore;
    if (core != null) {
      return core.createLocalPlaylist(name, description: description);
    }

    return _send<Playlist>('createLocalPlaylist', OfflinePlaylistDetailsRequest('', name, description));
  }

  Future<Playlist> downloadPlaylist(
    Playlist playlist,
    List<Track> tracks, {
    required String name,
    String? description,
    PlaylistImageEdit imageEdit = const PlaylistImageEdit.keep(),
  }) {
    final request = OfflineDownloadPlaylistRequest(
      playlist.copyWith(trackIds: List.unmodifiable(playlist.trackIds)),
      List.unmodifiable(tracks),
      name,
      description,
      imageEdit,
    );
    final core = _inlineCore;
    if (core != null) {
      return _withQueueQuality(() => core.downloadPlaylist(request));
    }

    return _send<Playlist>('downloadPlaylist', request);
  }

  Future<Playlist?> renameLocalPlaylist(String playlistId, String name, {String? description}) {
    final core = _inlineCore;
    if (core != null) {
      return core.renameLocalPlaylist(playlistId, name, description: description);
    }

    return _send<Playlist?>('renameLocalPlaylist', OfflinePlaylistDetailsRequest(playlistId, name, description));
  }

  Future<Playlist?> updateLocalPlaylistImage(String playlistId, PlaylistImageEdit imageEdit) {
    final core = _inlineCore;
    if (core != null) {
      return core.updateLocalPlaylistImage(playlistId, imageEdit);
    }

    return _send<Playlist?>('updateLocalPlaylistImage', OfflinePlaylistImageRequest(playlistId, imageEdit));
  }

  Future<void> deleteLocalPlaylist(String playlistId) =>
      _commandOrInline('deleteLocalPlaylist', playlistId, (core) => core.deleteLocalPlaylist(playlistId));

  Future<Playlist?> addLocalTrackToPlaylist(Playlist playlist, Track track) {
    final core = _inlineCore;
    if (core != null) {
      return core.addLocalTrackToPlaylist(playlist, track);
    }

    return _send<Playlist?>('addLocalTrackToPlaylist', OfflinePlaylistTrackRequest(playlist, track));
  }

  Future<Playlist?> removeLocalTrackFromPlaylist(Playlist playlist, Track track) {
    final core = _inlineCore;
    if (core != null) {
      return core.removeLocalTrackFromPlaylist(playlist, track);
    }

    return _send<Playlist?>('removeLocalTrackFromPlaylist', OfflinePlaylistTrackRequest(playlist, track));
  }

  static bool _canUseActor(OfflineLibraryStorage storage) {
    return storage.runtimeType == OfflineLibraryStorage &&
        storage.settingsStorage.runtimeType == OfflineStorageSettingsStorage &&
        storage.baseDirectory == null &&
        storage.defaultDirectoryProvider == null &&
        storage.metadataDirectory == null &&
        storage.downloadsDirectory == null;
  }

  Future<T> _withQueueQuality<T>(Future<T> Function() operation) async {
    final inherited = Zone.current[#downloadQueueProfile] as String?;
    final profile = inherited ?? (await _qualityProvider?.call() ?? DownloadQuality.original).wireValue;

    return runZoned(operation, zoneValues: {#downloadQueueProfile: profile});
  }

  Future<T> _send<T>(String name, [Object? payload]) async {
    if (_disposed && name != 'dispose') {
      throw StateError('Offline download manager disposed');
    }

    final profile =
        Zone.current[#downloadQueueProfile] as String? ??
        (await _qualityProvider?.call() ?? DownloadQuality.original).wireValue;
    await _ensureActor();

    final port = _actorPort;
    if (port == null) {
      throw StateError('Offline download actor unavailable');
    }

    final id = _nextCommandId++;
    final completer = Completer<Object?>();

    _pending[id] = completer;
    port.send(
      OfflineActorCommand(
        id: id,
        profile: profile,
        name: name,
        payload: payload,
        baseUrl: connection.baseUrl,
        token: connection.token,
        trust: connection.trust,
      ),
    );

    final result = await completer.future;

    return result as T;
  }
}
