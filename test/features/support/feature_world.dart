import 'dart:async';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/data/models/auth/auth_state.dart';
import 'package:phonolite_app/data/models/collections/local_playlist_entry.dart';
import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/data/models/collections/playlist_image_edit.dart';
import 'package:phonolite_app/data/models/downloads/download_status.dart';
import 'package:phonolite_app/data/models/library/offline_library_snapshot.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/playback/output_device.dart';
import 'package:phonolite_app/data/models/preferences/offline_storage_locations.dart';
import 'package:phonolite_app/data/projections/library/offline_library_views.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';

/// The state a feature scenario starts from, independent of platform.
class FeatureWorld {
  /// The loaded playback queue; empty means nothing is loaded.
  final List<Track> queue;
  final int startIndex;
  final bool startPlaying;
  final List<OutputDevice> outputDevices;

  /// Downloaded tracks shown in the offline library; defaults to [queue].
  final List<Track>? downloads;

  /// Local playlists whose track IDs refer to [library] tracks.
  final List<Playlist> localPlaylists;

  const FeatureWorld({
    this.queue = const [],
    this.startIndex = 0,
    this.startPlaying = false,
    this.outputDevices = const [],
    this.downloads,
    this.localPlaylists = const [],
  });

  List<Track> get library => downloads ?? queue;

  /// Three offline tracks with the first one loaded and paused.
  static final pausedQueue = FeatureWorld(
    queue: [_track('first', 'First Light'), _track('second', 'Second Wind'), _track('third', 'Third Coast')],
    outputDevices: [
      OutputDevice(id: -1, name: 'System default'),
      OutputDevice(id: 7, name: 'Studio Monitors'),
    ],
  );

  /// Two downloaded artists, one with two albums, and nothing loaded.
  static final offlineLibrary = FeatureWorld(
    downloads: [
      _track('first', 'First Light'),
      _track('second', 'Second Wind'),
      _track('third', 'Third Coast'),
      _track('north', 'Northern Lines', album: 'Late Album', albumId: 'late'),
      _track('river', 'River Song', artist: 'Bruno', album: 'Bruno Sessions', albumId: 'bruno'),
    ],
    localPlaylists: [
      Playlist(id: 'road', name: 'Road Trip', trackIds: ['river', 'first']),
      Playlist(id: 'quiet', name: 'Quiet Hours', trackIds: ['north']),
    ],
  );

  static Track _track(
    String id,
    String title, {
    String artist = 'Alice',
    String album = 'Demo Album',
    String albumId = 'album',
  }) => Track(
    id: id,
    title: title,
    artist: artist,
    album: album,
    albumId: albumId,
    durationMs: 180000,
    liked: false,
    inPlaylists: false,
  );
}

/// An [AppController] whose playback and library state come from a
/// [FeatureWorld]. It answers the same commands the real controller does, so
/// scenarios assert on resulting state rather than on platform wiring.
class WorldController extends AppController {
  final FeatureWorld world;
  final _playback = StreamController<PlaybackState>.broadcast();
  // The base constructor may read playback state before this one assigns it.
  PlaybackState? _snapshot;
  final _localPlaylistsUpdates = StreamController<List<Playlist>>.broadcast();
  final _entriesUpdates = StreamController<List<LocalPlaylistEntry>>.broadcast();
  late List<Playlist> _localPlaylists = world.localPlaylists;
  var _createdPlaylists = 0;

  final _statsCollectionUpdates = StreamController<bool>.broadcast();
  final _gaplessUpdates = StreamController<bool>.broadcast();
  var _gaplessResampling = false;
  var _statsCollectionEnabled = true;

  /// How many times the person confirmed resetting local data.
  var localDataResets = 0;
  late List<Track> _queue;
  late int _index;
  int _outputDeviceId = -1;

  WorldController(this.world, {super.downloadSettings})
    : super(connection: ServerConnection(baseUrl: 'http://server.test/api')) {
    _queue = world.queue;
    _index = world.startIndex;
    _snapshot = super.playbackState.copyWith(
      track: world.queue.isEmpty ? null : world.queue[_index],
      isPlaying: world.startPlaying,
      isLocalPlayback: world.queue.isNotEmpty,
      duration: world.queue.isEmpty ? Duration.zero : Duration(milliseconds: world.queue[_index].durationMs),
      queueSource: world.queue.isEmpty ? PlaybackQueueSource.none : PlaybackQueueSource.offline,
      localPlaybackSource: world.queue.isEmpty ? LocalPlaybackSource.none : LocalPlaybackSource.library,
    );
  }

  PlaybackState get _state => _snapshot ?? super.playbackState;

  Track? get currentTrack => _state.track;

  @override
  Future<void> close() async {
    await _playback.close();
    await _localPlaylistsUpdates.close();
    await _entriesUpdates.close();
    await _statsCollectionUpdates.close();
    await _gaplessUpdates.close();
    await super.close();
  }

  void _publish(PlaybackState next) {
    _snapshot = next;
    _playback.add(next);
  }

  void _moveTo(int index, {bool? playing}) {
    _index = index.clamp(0, _queue.length - 1);
    final track = _queue[_index];
    _publish(
      _state.copyWith(
        track: track,
        isPlaying: playing,
        position: Duration.zero,
        duration: Duration(milliseconds: track.durationMs),
        isLocalPlayback: true,
        queueSource: PlaybackQueueSource.offline,
        localPlaybackSource: LocalPlaybackSource.library,
      ),
    );
  }

  // Playback commands.

  @override
  PlaybackState get playbackState => _state;

  @override
  Stream<PlaybackState> get playbackStream => _playback.stream;

  @override
  Future<void> pause(bool paused) async => _publish(_state.copyWith(isPlaying: !paused));

  @override
  Future<void> nextTrack({bool fromAutoAdvance = false}) async => _moveTo(_index + 1);

  @override
  Future<void> prevTrack({bool fromAutoAdvance = false}) async => _moveTo(_index - 1);

  @override
  Future<void> stop() async => _publish(_state.copyWith(isPlaying: false, position: Duration.zero));

  @override
  Future<void> playOfflineTrack(String trackId, {List<Track>? tracks, bool localLikedQueue = false}) async {
    _queue = tracks ?? world.library;
    _moveTo(_queue.indexWhere((track) => track.id == trackId), playing: true);
  }

  @override
  void toggleRepeatMode() => _publish(
    _state.copyWith(
      repeatMode: _state.repeatMode == PlaybackRepeatMode.off ? PlaybackRepeatMode.one : PlaybackRepeatMode.off,
    ),
  );

  @override
  void updateShuffleMode(ShuffleMode mode, {ActionScope? scope}) =>
      _publish(_state.copyWith(shuffleMode: mode, shuffleScope: scope));

  @override
  void setVolume(double value) => _publish(_state.copyWith(volume: value));

  @override
  void toggleMute() => _publish(_state.copyWith(volume: _state.volume == 0 ? 1 : 0));

  // Local playlists, kept in memory and published like the download manager.

  @override
  List<Playlist> get localPlaylists => List.unmodifiable(_localPlaylists);

  @override
  Stream<List<Playlist>> get localPlaylistsStream => _localPlaylistsUpdates.stream;

  @override
  List<LocalPlaylistEntry> get localPlaylistEntries => [
    for (final playlist in _localPlaylists)
      for (final (position, track) in _playlistTracks(playlist).indexed)
        LocalPlaylistEntry(
          entryKey: '${playlist.id}-$position',
          playlistId: playlist.id,
          position: position,
          track: track,
          localTrackId: track.id,
          status: OfflineDownloadStatus.downloaded,
          isPending: false,
        ),
  ];

  @override
  Stream<List<LocalPlaylistEntry>> get localPlaylistEntriesStream => _entriesUpdates.stream;

  @override
  Future<void> createLocalPlaylist(
    String name, {
    String? description,
    PlaylistImageEdit imageEdit = const PlaylistImageEdit.keep(),
    List<Track> tracks = const <Track>[],
  }) async {
    _createdPlaylists++;
    final playlist = Playlist(
      id: 'created-$_createdPlaylists',
      name: name,
      description: description,
      trackIds: [for (final track in tracks) track.id],
    );
    _publishPlaylists([..._localPlaylists, playlist]);
  }

  @override
  Future<void> renameLocalPlaylist(
    String playlistId,
    String name, {
    String? description,
    PlaylistImageEdit imageEdit = const PlaylistImageEdit.keep(),
  }) async => _publishPlaylists([
    for (final playlist in _localPlaylists)
      playlist.id == playlistId
          ? Playlist(id: playlist.id, name: name, description: description, trackIds: playlist.trackIds)
          : playlist,
  ]);

  @override
  Future<void> deleteLocalPlaylist(String playlistId) async => _publishPlaylists([
    for (final playlist in _localPlaylists)
      if (playlist.id != playlistId) playlist,
  ]);

  @override
  Future<void> playLocalPlaylistFromTop(String playlistId) => queueLocalPlaylist(playlistId);

  @override
  Future<void> queueLocalPlaylist(String playlistId, {String? startTrackId}) async {
    final tracks = _playlistTracks(_localPlaylists.firstWhere((playlist) => playlist.id == playlistId));
    await playOfflineTrack(startTrackId ?? tracks.first.id, tracks: tracks);
  }

  List<Track> _playlistTracks(Playlist playlist) => [
    for (final id in playlist.trackIds) world.library.firstWhere((track) => track.id == id),
  ];

  void _publishPlaylists(List<Playlist> playlists) {
    _localPlaylists = playlists;
    _localPlaylistsUpdates.add(localPlaylists);
    _entriesUpdates.add(localPlaylistEntries);
  }

  // Preferences stay in memory instead of reaching device storage. Real
  // writes chain file I/O that close() awaits, and widget tests' fake clock
  // never completes that I/O.

  @override
  bool get gaplessResampling => _gaplessResampling;

  @override
  Stream<bool> get gaplessResamplingStream => _gaplessUpdates.stream;

  @override
  void setGaplessResampling(bool enabled) {
    _gaplessResampling = enabled;
    _gaplessUpdates.add(enabled);
  }

  // Listening statistics. The real service runs a SQLite isolate whose replies
  // never arrive under the widget test's fake clock.

  @override
  bool get statsCollectionEnabled => _statsCollectionEnabled;

  @override
  Stream<bool> get statsCollectionEnabledStream => _statsCollectionUpdates.stream;

  @override
  Future<void> setStatsCollectionEnabled(bool value) async {
    _statsCollectionEnabled = value;
    _statsCollectionUpdates.add(value);
  }

  // Local data: fixed default folders, and resets are recorded, not performed.

  @override
  OfflineStorageLocations get offlineStorageLocations => const OfflineStorageLocations(
    metadataDirectory: '/phonolite/metadata',
    downloadsDirectory: '/phonolite/downloads',
    metadataDirectoryIsDefault: true,
    downloadsDirectoryIsDefault: true,
  );

  @override
  Future<void> loadOfflineStorageLocations() async {}

  @override
  Future<void> resetOfflineData() async => localDataResets++;

  @override
  void setCollectionListMode(bool value, {bool persist = true}) => super.setCollectionListMode(value, persist: false);

  @override
  int get outputDeviceId => _outputDeviceId;

  @override
  Future<List<OutputDevice>> listOutputDevices({bool refresh = false}) async => world.outputDevices;

  @override
  Future<void> selectOutputDevice(OutputDevice device) async => _outputDeviceId = device.id;

  // An offline library containing the queue, so pages render without a server.

  @override
  AuthState get authState => AuthState(isAuthorized: false, baseUrl: connection.baseUrl);

  @override
  List<Track> get tracks => world.library;

  @override
  List<Track> get offlineTracks => world.library;

  @override
  OfflineLibrarySnapshot get offlineLibrarySnapshot => OfflineLibrarySnapshot(
    tracks: world.library,
    artistGroups: offlineArtistGroups(world.library),
    liked: const [],
    playlists: const [],
    playlistTracks: const [],
    revision: 1,
  );

  @override
  bool get hasMoreArtists => false;

  @override
  List<Playlist> get playlists => const [];

  @override
  List<Track> get playlistTracks => const [];

  @override
  List<Track> get localPlaylistTracks => const [];

  @override
  Future<void> loadArtists({bool refresh = false}) async {}

  @override
  Future<void> loadTracks(String albumId) async {}

  @override
  Future<void> loadArtistReleases(String artistId) async {}

  @override
  Future<void> loadPlaylists() async {}

  @override
  Future<void> loadLocalPlaylists() async {}

  @override
  Future<void> loadPlaylistTracks(String playlistId) async {}

  @override
  Future<void> loadLocalPlaylistTracks(String playlistId) async {}

  @override
  Future<void> loadLocalPlaylistEntries(String playlistId) async {}

  @override
  Future<void> loadLikedTracks() async {}

  @override
  Future<void> loadLocalLikedTracks() async {}

  @override
  Future<void> loadStats({int? year, int? month}) async {}
}
