import 'dart:async';

import 'package:phonolite_app/data/repositories/preferences_coordinator.dart';
import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/settings/display_settings_controller.dart';
import 'package:phonolite_app/data/models/auth/auth_state.dart';
import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/data/models/downloads/download_status.dart';
import 'package:phonolite_app/data/models/downloads/offline_deletion.dart';
import 'package:phonolite_app/data/models/downloads/offline_download_snapshot.dart';
import 'package:phonolite_app/data/models/downloads/offline_track_download.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/library/artist_releases.dart';
import 'package:phonolite_app/data/models/library/offline_library_snapshot.dart';
import 'package:phonolite_app/data/models/library/search_result.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/preferences/display_settings.dart';
import 'package:phonolite_app/data/projections/library/offline_library_views.dart';
import 'package:phonolite_app/data/storage/preferences/display_settings_storage.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';

import 'offline_library_test_helpers.dart';

const pageTestServerUrl = 'http://server.test/api';

/// One recorded request to remove downloaded tracks from the device.
typedef RecordedRemoval = ({List<String> trackIds, String? label, OfflineDeletionScope scope});

/// A display settings controller that keeps its settings in memory.
Future<DisplaySettingsController> memoryDisplaySettings() async {
  final display = DisplaySettingsController(
    preferences: PreferencesCoordinator(display: _MemoryDisplaySettingsStorage()),
  );
  await display.initialize();

  return display;
}

/// Builds a downloaded local track for [artist]'s [album].
Track downloadedPageTrack(String id, {String artist = 'Artist A', String album = 'Album 1', String title = ''}) =>
    offlineTestTrack(
      id: id,
      title: title.isEmpty ? 'Song $id' : title,
      artist: artist,
      artistId: 'artist-${artist.toLowerCase().replaceAll(' ', '-')}',
      album: album,
      albumId: 'album-${album.toLowerCase().replaceAll(' ', '-')}',
    );

/// An [AppController] whose catalog, downloads and collections are plain fields.
///
/// Every published stream stays silent, so the pages render exactly the field
/// values. Removing downloaded tracks is recorded rather than performed.
class PageTestController extends AppController {
  PageTestController({this.connected = false}) : super(connection: _PageTestConnection());

  bool connected;
  List<Artist> serverArtists = const [];
  ArtistReleases releases = const ArtistReleases();
  List<Track> albumTracks = const [];
  List<Track> downloadedTracks = const [];
  List<Playlist> localPlaylistList = const [];
  List<Playlist> serverPlaylistList = const [];
  List<Track> serverPlaylistTracks = const [];
  List<Track> localLikedTracks = const [];
  List<Track> serverLikedTracks = const [];
  Object? removalError;
  final removals = <RecordedRemoval>[];
  final _authChanges = StreamController<AuthState>.broadcast();

  /// Downloads for every downloaded track, in the shape the download manager publishes.
  List<OfflineTrackDownload> get _downloads => [
    for (final track in {...downloadedTracks, ...serverPlaylistTracks, ...localLikedTracks, ...serverLikedTracks})
      offlineTestDownload(serverBaseUrl: pageTestServerUrl, track: track),
  ];

  @override
  AuthState get authState => AuthState(isAuthorized: connected, baseUrl: connection.baseUrl);
  @override
  Stream<AuthState> get authStream => _authChanges.stream;

  @override
  List<Artist> get artists => serverArtists;
  @override
  Stream<List<Artist>> get artistsStream => const Stream.empty();
  @override
  bool get artistsLoading => false;
  @override
  Stream<bool> get artistsLoadingStream => const Stream.empty();
  @override
  List<SearchResult> get searchResults => const [];
  @override
  Stream<List<SearchResult>> get searchStream => const Stream.empty();
  @override
  bool get searchLoading => false;
  @override
  Stream<bool> get searchLoadingStream => const Stream.empty();

  @override
  ArtistReleases get artistReleases => releases;
  @override
  Stream<ArtistReleases> get artistReleasesStream => const Stream.empty();
  @override
  bool get albumsLoading => false;
  @override
  Stream<bool> get albumsLoadingStream => const Stream.empty();
  @override
  List<Track> get tracks => albumTracks;
  @override
  Stream<List<Track>> get tracksStream => const Stream.empty();
  @override
  bool get tracksLoading => false;
  @override
  Stream<bool> get tracksLoadingStream => const Stream.empty();

  @override
  List<Track> get offlineTracks => downloadedTracks;
  @override
  OfflineLibrarySnapshot get offlineLibrarySnapshot => OfflineLibrarySnapshot(
    tracks: downloadedTracks,
    artistGroups: offlineArtistGroups(downloadedTracks),
    liked: localLikedTracks,
    playlists: localPlaylistList,
    playlistTracks: const [],
    revision: 1,
  );
  @override
  Stream<OfflineLibrarySnapshot> get offlineLibrarySnapshotStream => const Stream.empty();
  @override
  List<OfflineTrackDownload> get offlineDownloads => _downloads;
  @override
  Stream<List<OfflineTrackDownload>> get offlineDownloadsStream => const Stream.empty();
  @override
  OfflineDownloadSnapshot get offlineDownloadSnapshot =>
      OfflineDownloadSnapshot(downloads: _downloads, batches: const [], jobs: const [], revision: 0);
  @override
  Stream<OfflineDownloadSnapshot> get offlineDownloadSnapshotStream => const Stream.empty();
  @override
  OfflineTrackDownload? offlineDownloadForTrack(String trackId) =>
      _downloads.where((download) => download.track.id == trackId).firstOrNull;
  @override
  OfflineTrackDownload? availableOfflineDownloadForTrack(String trackId) => _downloads
      .where((download) => download.track.id == trackId && download.status == OfflineDownloadStatus.downloaded)
      .firstOrNull;

  @override
  List<Playlist> get localPlaylists => localPlaylistList;
  @override
  Stream<List<Playlist>> get localPlaylistsStream => const Stream.empty();
  @override
  List<Playlist> get playlists => serverPlaylistList;
  @override
  Stream<List<Playlist>> get playlistsStream => const Stream.empty();
  @override
  bool get serverCollectionsLoaded => false;
  @override
  List<Track> get playlistTracks => serverPlaylistTracks;
  @override
  Stream<List<Track>> get playlistTracksStream => const Stream.empty();

  @override
  List<Track> get localLiked => localLikedTracks;
  @override
  Stream<List<Track>> get localLikedStream => const Stream.empty();
  @override
  List<Track> get liked => serverLikedTracks;
  @override
  Stream<List<Track>> get likedStream => const Stream.empty();

  @override
  Future<void> loadArtists({bool refresh = false}) async {}
  @override
  Future<void> loadMoreArtists() async {}
  @override
  Future<void> search(String query, {String? filter}) async {}
  @override
  Future<void> loadArtistReleases(String artistId) async {}
  @override
  Future<Artist> fetchArtistMetadata(String id, {bool refresh = false}) async =>
      Artist(id: id, name: 'Server Artist', albumCount: 0);
  @override
  Future<void> loadTracks(String albumId) async {}
  @override
  Future<void> loadLocalPlaylists() async {}
  @override
  Future<void> loadPlaylists() async {}
  @override
  Future<void> loadPlaylistTracks(String playlistId) async {}
  @override
  Future<void> loadLocalPlaylistEntries(String playlistId) async {}
  @override
  Future<void> loadLocalLikedTracks() async {}
  @override
  Future<void> loadLikedTracks() async {}

  @override
  Future<void> removeDownloadedTracks(
    Iterable<Track> tracks, {
    String? label,
    OfflineDeletionScope scope = const OfflineDeletionScope.track(),
  }) async {
    removals.add((trackIds: [for (final track in tracks) track.id], label: label, scope: scope));

    final error = removalError;

    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> close() async {
    await _authChanges.close();
    await super.close();
  }
}

class _PageTestConnection extends ServerConnection {
  _PageTestConnection() : super(baseUrl: pageTestServerUrl);

  @override
  String buildAlbumCoverUrl(String albumId) => '';
}

class _MemoryDisplaySettingsStorage extends DisplaySettingsStorage {
  @override
  Future<DisplaySettings> read() async => const DisplaySettings();

  @override
  Future<void> write(DisplaySettings settings) async {}
}
