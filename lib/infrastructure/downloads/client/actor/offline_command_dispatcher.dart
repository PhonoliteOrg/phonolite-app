part of 'package:phonolite_app/infrastructure/downloads/client/offline_download_client.dart';

Future<Object?> _handleOfflineActorCommand(_OfflineDownloadActorCore core, OfflineActorCommand command) async {
  switch (command.name) {
    case 'load':
      await core.load();

      return null;
    case 'downloadTrack':
      return core.downloadTrack(command.payload! as Track);
    case 'queueTracks':
      final request = command.payload! as OfflineQueueTracksRequest;

      return core.queueTracks(request.tracks, label: request.label, kind: request.kind, sourceId: request.sourceId);
    case 'queueBatch':
      final request = command.payload! as OfflineQueueBatchRequest;

      return core.queueBatch(request.manifest, label: request.label);
    case 'queueArtist':
      final request = command.payload! as OfflineQueueArtistRequest;

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
        await core.removeDownloads((payload as List).cast<OfflineTrackDownload>());
      }

      return null;
    case 'clearFailedAndCorrupt':
      await core.clearFailedAndCorrupt();

      return null;
    case 'resetLocalData':
      await core.resetLocalData();

      return null;
    case 'clearUnfinishedDownloads':
      await core.clearUnfinishedDownloads();

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
      final request = command.payload! as OfflineTrackBoolRequest;

      await core.setLocalLike(request.track, request.value);

      return null;
    case 'readLocalLikeStates':
      return core.readLocalLikeStates();
    case 'createLocalPlaylist':
      final request = command.payload! as OfflinePlaylistDetailsRequest;

      return core.createLocalPlaylist(request.name, description: request.description);
    case 'downloadPlaylist':
      return core.downloadPlaylist(command.payload! as OfflineDownloadPlaylistRequest);
    case 'renameLocalPlaylist':
      final request = command.payload! as OfflinePlaylistDetailsRequest;

      return core.renameLocalPlaylist(request.playlistId, request.name, description: request.description);
    case 'updateLocalPlaylistImage':
      final request = command.payload! as OfflinePlaylistImageRequest;

      return core.updateLocalPlaylistImage(request.playlistId, request.imageEdit);
    case 'deleteLocalPlaylist':
      await core.deleteLocalPlaylist(command.payload! as String);

      return null;
    case 'addLocalTrackToPlaylist':
      final request = command.payload! as OfflinePlaylistTrackRequest;

      return core.addLocalTrackToPlaylist(request.playlist, request.track);
    case 'removeLocalTrackFromPlaylist':
      final request = command.payload! as OfflinePlaylistTrackRequest;

      return core.removeLocalTrackFromPlaylist(request.playlist, request.track);
    case 'dispose':
      await core.dispose();

      return null;
    default:
      throw StateError('Unknown offline actor command ${command.name}');
  }
}
