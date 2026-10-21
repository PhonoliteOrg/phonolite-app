import 'dart:async';

import 'package:http/http.dart' as http;

import 'package:phonolite_app/data/models/auth/server_trust.dart';
import 'package:phonolite_app/data/models/collections/like_state.dart';
import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/data/models/downloads/offline_track_metadata.dart';
import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/library/artist_releases.dart';
import 'package:phonolite_app/data/models/library/metadata_update_event.dart';
import 'package:phonolite_app/data/models/library/search_result.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/library/track_match.dart';
import 'package:phonolite_app/data/models/listening_stats/listening_report.dart';
import 'package:phonolite_app/data/models/server/download_batch_manifest.dart';
import 'package:phonolite_app/data/models/server/download_job_v2.dart';
import 'package:phonolite_app/data/models/server/playback_settings_response.dart';
import 'package:phonolite_app/data/models/server/server_artwork.dart';
import 'package:phonolite_app/data/models/server/server_capabilities.dart';
import 'package:phonolite_app/data/models/server/server_errors.dart';
import 'package:phonolite_app/data/models/server/server_ports_response.dart';
import 'package:phonolite_app/data/models/server/track_download_stream.dart';
import 'package:phonolite_app/infrastructure/server/api/artwork_api.dart';
import 'package:phonolite_app/infrastructure/server/api/auth_api.dart';
import 'package:phonolite_app/infrastructure/server/api/collections_api.dart';
import 'package:phonolite_app/infrastructure/server/api/downloads_api.dart';
import 'package:phonolite_app/infrastructure/server/api/library_api.dart';
import 'package:phonolite_app/infrastructure/server/api/listening_stats_api.dart';
import 'package:phonolite_app/infrastructure/server/api/playback_api.dart';
import 'package:phonolite_app/infrastructure/server/api/server_events_api.dart';
import 'package:phonolite_app/infrastructure/server/transport/api_transport.dart';

export 'package:phonolite_app/data/models/server/playback_settings_response.dart';
export 'package:phonolite_app/data/models/server/server_artwork.dart';
export 'package:phonolite_app/data/models/server/server_errors.dart';
export 'package:phonolite_app/data/models/server/server_ports_response.dart';
export 'package:phonolite_app/data/models/server/track_download_stream.dart';

class ServerConnection {
  static const int artistsPageSize = ApiTransport.artistsPageSize;

  final ApiTransport _transport;
  late final AuthApi _authApi = AuthApi(_transport);
  late final LibraryApi _libraryApi = LibraryApi(_transport, fetchArtistsPage: fetchArtistsPage);
  late final CollectionsApi _collectionsApi = CollectionsApi(_transport, updateLikeStates: updateLikeStates);
  late final ListeningStatsApi _listeningStatsApi = ListeningStatsApi(_transport);
  late final DownloadsApi _downloadsApi = DownloadsApi(_transport, trackDownloadUrl: buildTrackDownloadUrl);
  late final ArtworkApi _artworkApi = ArtworkApi(
    _transport,
    albumCoverUrl: buildAlbumCoverUrl,
    playlistCoverUrl: buildPlaylistCoverUrl,
    artistCoverUrl: buildArtistCoverUrl,
  );
  late final PlaybackApi _playbackApi = PlaybackApi(_transport);
  late final ServerEventsApi _serverEventsApi = ServerEventsApi(_transport);

  ServerConnection({required String baseUrl, http.Client? client, ServerReachabilityProbe? serverProbe})
    : _transport = ApiTransport(baseUrl: baseUrl, client: client, serverProbe: serverProbe);

  void Function(Object)? get onTransportFailure => _transport.onTransportFailure;

  set onTransportFailure(void Function(Object)? value) => _transport.onTransportFailure = value;

  String get baseUrl => _transport.baseUrl;

  String? get token => _transport.token;

  ServerTrust? get trust => _transport.trust;

  bool get hasTrustedTransport => _transport.hasTrustedTransport;

  int get sessionRevision => _transport.sessionRevision;

  bool get canChangeOwnPassword => _transport.canChangeOwnPassword;

  /// A fresh header map; callers cannot mutate connection authentication state.
  Map<String, String> get authorizationHeaders => _transport.authorizationHeaders;

  void setTrust(ServerTrust value) => _transport.setTrust(value);

  void setBaseUrl(String baseUrl) => _transport.setBaseUrl(baseUrl);

  Future<String> resolveBaseUrl(String input) => _transport.resolveBaseUrl(input);

  /// Verify the entered endpoint without changing the session or trusting a new
  /// identity. A remembered certificate pin is enforced even before sign-in.
  Future<void> verifyServerConnection(String input, {Duration timeout = const Duration(seconds: 10)}) =>
      _transport.verifyServerConnection(input, timeout: timeout);

  void setToken(String? token) => _transport.setToken(token);

  /// A metadata event supersedes reads that began before that update, without
  /// changing the authenticated session or cancelling unrelated repair work.
  void invalidateMetadataReads() => _transport.invalidateMetadataReads();

  Future<String> login({required String username, required String password}) =>
      _authApi.login(username: username, password: password);

  Future<void> logout({Duration timeout = ApiTransport.defaultRequestTimeout}) => _authApi.logout(timeout: timeout);

  /// Changes only the authenticated user's password over the pinned HTTPS
  /// connection. This mutation is never retried or redirected. The controller
  /// keeps the originating session signed in; other account sessions are revoked.
  Future<void> changeOwnPassword({
    required String currentPassword,
    required String newPassword,
    Duration timeout = ApiTransport.defaultRequestTimeout,
  }) => _authApi.changeOwnPassword(currentPassword: currentPassword, newPassword: newPassword, timeout: timeout);

  Future<List<Artist>> fetchArtistsPage({
    int limit = ServerConnection.artistsPageSize,
    int offset = 0,
    bool includeContributors = false,
  }) => _libraryApi.fetchArtistsPage(limit: limit, offset: offset, includeContributors: includeContributors);

  Future<List<Artist>> fetchArtists({int limit = ServerConnection.artistsPageSize, bool includeContributors = false}) =>
      _libraryApi.fetchArtists(limit: limit, includeContributors: includeContributors);

  Future<List<Album>> fetchAlbums(String artistId) => _libraryApi.fetchAlbums(artistId);

  Future<ArtistReleases> fetchArtistReleases(String artistId) => _libraryApi.fetchArtistReleases(artistId);

  Future<List<Track>> fetchTracks(String albumId) => _libraryApi.fetchTracks(albumId);

  Future<List<Playlist>> fetchPlaylists() => _collectionsApi.fetchPlaylists();

  Future<List<Track>> fetchPlaylistTracks(String playlistId) => _collectionsApi.fetchPlaylistTracks(playlistId);

  Future<List<Track>> fetchLikedTracks() => _collectionsApi.fetchLikedTracks();

  Future<List<Track>> fetchShuffleTracks({
    required String mode,
    String? artistId,
    String? albumId,
    List<String>? artistIds,
    List<String>? genres,
  }) => _playbackApi.fetchShuffleTracks(
    mode: mode,
    artistId: artistId,
    albumId: albumId,
    artistIds: artistIds,
    genres: genres,
  );

  Future<StatsResponse> fetchStats({int? year, int? month}) => _listeningStatsApi.fetchStats(year: year, month: month);

  /// Legacy migration queue only; new listening uses the v2 counter endpoints.
  Future<Map<String, dynamic>> fetchListeningChanges({required String deviceId, int after = 0, int limit = 200}) =>
      _listeningStatsApi.fetchListeningChanges(deviceId: deviceId, after: after, limit: limit);

  Future<Map<String, dynamic>> updateListeningPreference({
    required String deviceId,
    required bool enabled,
    required int revision,
  }) => _listeningStatsApi.updateListeningPreference(deviceId: deviceId, enabled: enabled, revision: revision);

  Future<Map<String, dynamic>> uploadListeningEvents({
    required String deviceId,
    required int historyGeneration,
    required List<Map<String, dynamic>> events,
  }) => _listeningStatsApi.uploadListeningEvents(
    deviceId: deviceId,
    historyGeneration: historyGeneration,
    events: events,
  );

  Future<Map<String, dynamic>> resetListeningHistory({required int historyGeneration}) =>
      _listeningStatsApi.resetListeningHistory(historyGeneration: historyGeneration);

  Future<Map<String, dynamic>> fetchListeningCounterState({required String deviceId}) =>
      _listeningStatsApi.fetchListeningCounterState(deviceId: deviceId);

  Future<Map<String, dynamic>> activateListeningCounters({required String deviceId, required int historyGeneration}) =>
      _listeningStatsApi.activateListeningCounters(deviceId: deviceId, historyGeneration: historyGeneration);

  Future<Map<String, dynamic>> uploadListeningCounters(Map<String, dynamic> batch) =>
      _listeningStatsApi.uploadListeningCounters(batch);

  Future<Map<String, dynamic>> fetchListeningCounterSnapshot({
    required String deviceId,
    required int year,
    required int month,
    int? revision,
    String after = '',
  }) => _listeningStatsApi.fetchListeningCounterSnapshot(
    deviceId: deviceId,
    year: year,
    month: month,
    revision: revision,
    after: after,
  );

  Future<List<SearchResult>> search(String query, {String filter = 'all'}) => _libraryApi.search(query, filter: filter);

  Future<Album> fetchAlbumById(String albumId) => _libraryApi.fetchAlbumById(albumId);

  Future<Artist> fetchArtistById(String artistId) => _libraryApi.fetchArtistById(artistId);

  Future<Track> fetchTrackById(String trackId) => _libraryApi.fetchTrackById(trackId);

  Future<OfflineTrackMetadata> fetchOfflineMetadata(String trackId) => _libraryApi.fetchOfflineMetadata(trackId);

  Future<DownloadBatchManifest> createDownloadBatch(List<String> trackIds, {String? clientBatchId}) =>
      _downloadsApi.createDownloadBatch(trackIds, clientBatchId: clientBatchId);

  Future<ServerCapabilities> fetchCapabilities() => _downloadsApi.fetchCapabilities();

  Future<DownloadJobV2> createDownloadJob({
    required String clientId,
    required String clientRequestId,
    required DownloadJobScopeV2 scope,
  }) => _downloadsApi.createDownloadJob(clientId: clientId, clientRequestId: clientRequestId, scope: scope);

  Future<List<DownloadJobV2>> fetchDownloadJobs({String? clientId, String? scopeKind, String? scopeId}) =>
      _downloadsApi.fetchDownloadJobs(clientId: clientId, scopeKind: scopeKind, scopeId: scopeId);

  Future<void> applyDownloadJobAction({required String jobId, required String action}) =>
      _downloadsApi.applyDownloadJobAction(jobId: jobId, action: action);

  Future<List<TrackMatchResult>> matchTracks(List<TrackMatchDescriptor> tracks) => _libraryApi.matchTracks(tracks);

  Future<void> likeTrack(String trackId) => _collectionsApi.likeTrack(trackId);

  Future<void> unlikeTrack(String trackId) => _collectionsApi.unlikeTrack(trackId);

  Future<List<ServerLikeState>> updateLikeStates(
    Map<String, bool> states, {
    Map<String, int> updatedAtByTrack = const <String, int>{},
  }) => _collectionsApi.updateLikeStates(states, updatedAtByTrack: updatedAtByTrack);

  Future<ServerLikeState?> setLikeState(String trackId, bool liked) => _collectionsApi.setLikeState(trackId, liked);

  Future<Playlist> createPlaylist(String name, {String? description}) =>
      _collectionsApi.createPlaylist(name, description: description);

  Future<Playlist> renamePlaylist(String playlistId, String name, {String? description}) =>
      _collectionsApi.renamePlaylist(playlistId, name, description: description);

  Future<void> deletePlaylist(String playlistId) => _collectionsApi.deletePlaylist(playlistId);

  String buildPlaylistCoverUrl(String playlistId, {String? imageRef}) =>
      _artworkApi.buildPlaylistCoverUrl(playlistId, imageRef: imageRef);

  Future<Playlist> uploadPlaylistCover(String playlistId, List<int> bytes, String contentType) =>
      _collectionsApi.uploadPlaylistCover(playlistId, bytes, contentType);

  Future<Playlist> deletePlaylistCover(String playlistId) => _collectionsApi.deletePlaylistCover(playlistId);

  Future<Playlist> updatePlaylistTracks(String playlistId, List<String> trackIds) =>
      _collectionsApi.updatePlaylistTracks(playlistId, trackIds);

  Future<PlaybackSettingsResponse> fetchPlaybackSettings({
    Duration timeout = ApiTransport.defaultRequestTimeout,
    bool retryable = true,
  }) => _playbackApi.fetchPlaybackSettings(timeout: timeout, retryable: retryable);

  Future<void> updatePlaybackSettings({required String repeatMode}) =>
      _playbackApi.updatePlaybackSettings(repeatMode: repeatMode);

  Future<ServerPortsResponse> fetchServerPorts({
    Duration timeout = ApiTransport.defaultRequestTimeout,
    bool retryable = true,
  }) => _playbackApi.fetchServerPorts(timeout: timeout, retryable: retryable);

  Stream<MetadataUpdateEvent> streamMetadataEvents() => _serverEventsApi.streamMetadataEvents();

  String buildAlbumCoverUrl(String albumId) => _artworkApi.buildAlbumCoverUrl(albumId);

  String buildArtistCoverUrl(String artistId, {String? kind, String? ref}) =>
      _artworkApi.buildArtistCoverUrl(artistId, kind: kind, ref: ref);

  Future<ServerArtwork?> fetchAlbumCoverBytes(
    String albumId, {
    Duration timeout = ApiTransport.defaultRequestTimeout,
  }) => _artworkApi.fetchAlbumCoverBytes(albumId, timeout: timeout);

  Future<ServerArtwork?> fetchPlaylistCoverBytes(
    String playlistId, {
    String? imageRef,
    Duration timeout = ApiTransport.defaultRequestTimeout,
  }) => _artworkApi.fetchPlaylistCoverBytes(playlistId, imageRef: imageRef, timeout: timeout);

  Future<ServerArtwork?> fetchArtistCoverBytes(
    String artistId, {
    String kind = 'logo',
    Duration timeout = ApiTransport.defaultRequestTimeout,
  }) => _artworkApi.fetchArtistCoverBytes(artistId, kind: kind, timeout: timeout);

  String buildTrackDownloadUrl(String trackId) => _downloadsApi.buildTrackDownloadUrl(trackId);

  String buildDownloadUrl(String trackId, {String? downloadUrl}) =>
      _downloadsApi.buildDownloadUrl(trackId, downloadUrl: downloadUrl);

  Future<TrackDownloadStream> openTrackDownload(
    String trackId, {
    int? startByte,
    String? ifRange,
    Duration timeout = ApiTransport.defaultRequestTimeout,
  }) => _downloadsApi.openTrackDownload(trackId, startByte: startByte, ifRange: ifRange, timeout: timeout);

  Future<int?> pingHealthMs({Duration timeout = const Duration(seconds: 3)}) =>
      _transport.pingHealthMs(timeout: timeout);

  Future<bool> hasServerIdentityChanged() => _transport.hasServerIdentityChanged();
}
