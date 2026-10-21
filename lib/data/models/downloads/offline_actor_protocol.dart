import 'dart:isolate';
import 'dart:ui' show RootIsolateToken;

import 'package:phonolite_app/data/configuration/downloads/offline_storage_config.dart';
import 'package:phonolite_app/data/models/auth/server_trust.dart';
import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/data/models/downloads/download_batch.dart';
import 'package:phonolite_app/data/models/downloads/download_job.dart';
import 'package:phonolite_app/data/models/downloads/offline_track_download.dart';
import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/server/download_batch_manifest.dart';
import 'package:phonolite_app/data/projections/library/offline_library_views.dart' as offline_views;

class OfflineActorInit {
  final SendPort replyPort;
  final String baseUrl;
  final String? token;
  final ServerTrust? trust;
  final OfflineStorageConfig storageConfig;
  final RootIsolateToken? rootIsolateToken;

  const OfflineActorInit({
    required this.replyPort,
    required this.baseUrl,
    required this.token,
    required this.trust,
    required this.storageConfig,
    required this.rootIsolateToken,
  });
}

class OfflineActorReady {
  final SendPort commandPort;

  const OfflineActorReady(this.commandPort);
}

class OfflineActorCommand {
  final int id;
  final String name;
  final String baseUrl;
  final String? token;
  final ServerTrust? trust;
  final Object? payload;

  const OfflineActorCommand({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.token,
    required this.trust,
    this.payload,
  });
}

class OfflineActorResult {
  final int id;
  final Object? result;
  final String? error;

  const OfflineActorResult({required this.id, this.result, this.error});
}

class OfflineActorDownloadState {
  final List<OfflineTrackDownload> downloads;
  final List<OfflineDownloadBatch> batches;
  final List<OfflineDownloadJob> jobs;
  final int revision;

  const OfflineActorDownloadState({
    required this.downloads,
    required this.batches,
    required this.jobs,
    required this.revision,
  });
}

class OfflineActorLibraryState {
  final List<Track> localLiked;
  final List<Playlist> localPlaylists;
  final List<Track> localPlaylistTracks;
  final List<Track> localDownloadedTracks;
  final List<offline_views.OfflineArtistGroup> offlineArtistGroups;
  final int revision;

  const OfflineActorLibraryState({
    required this.localLiked,
    required this.localPlaylists,
    required this.localPlaylistTracks,
    required this.localDownloadedTracks,
    required this.offlineArtistGroups,
    required this.revision,
  });
}

class OfflineQueueTracksRequest {
  final List<Track> tracks;
  final String? label;
  final String kind;
  final String? sourceId;

  const OfflineQueueTracksRequest(this.tracks, this.label, this.kind, this.sourceId);
}

class OfflineQueueBatchRequest {
  final DownloadBatchManifest manifest;
  final String? label;

  const OfflineQueueBatchRequest(this.manifest, this.label);
}

class OfflineQueueArtistRequest {
  final Artist artist;
  final List<Album> albums;

  const OfflineQueueArtistRequest(this.artist, this.albums);
}

class OfflineTrackBoolRequest {
  final Track track;
  final bool value;

  const OfflineTrackBoolRequest(this.track, this.value);
}

class OfflinePlaylistDetailsRequest {
  final String playlistId;
  final String name;
  final String? description;

  const OfflinePlaylistDetailsRequest(this.playlistId, this.name, this.description);
}

class OfflineDownloadPlaylistRequest {
  final Playlist playlist;
  final List<Track> tracks;
  final String name;
  final String? description;
  final PlaylistImageEdit imageEdit;

  const OfflineDownloadPlaylistRequest(this.playlist, this.tracks, this.name, this.description, this.imageEdit);
}

class OfflinePlaylistImageRequest {
  final String playlistId;
  final PlaylistImageEdit imageEdit;

  const OfflinePlaylistImageRequest(this.playlistId, this.imageEdit);
}

class OfflinePlaylistTrackRequest {
  final Playlist playlist;
  final Track track;

  const OfflinePlaylistTrackRequest(this.playlist, this.track);
}
