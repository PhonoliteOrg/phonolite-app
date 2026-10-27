import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/data/models/auth/auth_state.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/library/offline_library_snapshot.dart';
import 'package:phonolite_app/data/models/playback/custom_shuffle_settings.dart';
import 'package:phonolite_app/data/models/playback/shuffle_preset.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';

ShufflePreset testShufflePreset({String id = 'night', String name = 'Night music', int revision = 1}) =>
    ShufflePreset(id: id, name: name, artistIds: ['alpha'], genres: ['ambient'], revision: revision);

class PresetTestConnection extends Fake implements ServerConnection {
  @override
  int sessionRevision = 1;
}

class PresetTestApp extends Fake implements AppController {
  @override
  final PresetTestConnection connection = PresetTestConnection();
  final presetEvents = StreamController<List<ShufflePreset>>.broadcast(sync: true);
  final authEvents = StreamController<AuthState>.broadcast(sync: true);
  final settingsEvents = StreamController<CustomShuffleSettings>.broadcast(sync: true);
  final writes = <Map<String, Object?>>[];
  final applied = <ShufflePreset>[];
  final deleted = <ShufflePreset>[];
  int loads = 0;
  int imports = 0;
  int localSaves = 0;
  bool conflictOnSave = false;
  Completer<void>? saveGate;

  @override
  List<ShufflePreset> shufflePresets = [testShufflePreset()];

  @override
  bool shufflePresetsAvailable = true;

  @override
  AuthState authState = AuthState(baseUrl: 'https://music.test', isAuthorized: true);

  @override
  CustomShuffleSettings customShuffleSettings = const CustomShuffleSettings(
    artistIds: ['device-artist'],
    genres: ['jazz'],
    localArtistIds: ['downloaded'],
  );

  @override
  Stream<AuthState> get authStream => authEvents.stream;

  @override
  Stream<List<ShufflePreset>> get shufflePresetsStream => presetEvents.stream;

  @override
  Stream<CustomShuffleSettings> get customShuffleSettingsStream => settingsEvents.stream;

  @override
  List<Artist> get artists => [
    Artist(id: 'alpha', name: 'Alpha artist', albumCount: 1, genres: ['Ambient']),
    Artist(id: 'beta', name: 'Beta artist', albumCount: 1, genres: ['Jazz']),
  ];

  @override
  Stream<List<Artist>> get artistsStream => const Stream.empty();

  @override
  bool get artistsLoading => false;

  @override
  Stream<bool> get artistsLoadingStream => const Stream.empty();

  @override
  bool get hasMoreArtists => false;

  @override
  OfflineLibrarySnapshot get offlineLibrarySnapshot => const OfflineLibrarySnapshot(
    tracks: [],
    artistGroups: [],
    liked: [],
    playlists: [],
    playlistTracks: [],
    revision: 1,
  );

  @override
  Stream<OfflineLibrarySnapshot> get offlineLibrarySnapshotStream => const Stream.empty();

  @override
  Future<void> loadAllArtists() async {}

  @override
  Future<void> loadShufflePresets() async => loads++;

  @override
  Future<void> saveShufflePreset({
    String? id,
    required String name,
    required List<String> artistIds,
    required List<String> genres,
    int? expectedRevision,
  }) async {
    writes.add({
      'id': id,
      'name': name,
      'artistIds': artistIds,
      'genres': genres,
      'expectedRevision': expectedRevision,
    });

    if (conflictOnSave) {
      throw ApiException(409, 'Preset changed');
    }

    await saveGate?.future;

    final saved = ShufflePreset(
      id: id ?? 'copy-${writes.length}',
      name: name,
      artistIds: artistIds,
      genres: genres,
      revision: (expectedRevision ?? 0) + 1,
    );
    publish([
      for (final preset in shufflePresets)
        if (preset.id != saved.id) preset,
      saved,
    ]);
  }

  @override
  Future<void> deleteShufflePreset(ShufflePreset preset) async {
    deleted.add(preset);
    publish(shufflePresets.where((item) => item.id != preset.id).toList());
  }

  @override
  Future<void> applyShufflePreset(ShufflePreset preset) async {
    applied.add(preset);
    await updateCustomShuffleSettings(artistIds: preset.artistIds, genres: preset.genres);
  }

  @override
  Future<void> importCustomShufflePreset() async => imports++;

  @override
  Future<void> updateCustomShuffleSettings({
    List<String>? artistIds,
    List<String>? genres,
    List<String>? localArtistIds,
    List<String>? localGenres,
  }) async {
    localSaves++;
    customShuffleSettings = customShuffleSettings.copyWith(
      artistIds: artistIds,
      genres: genres,
      localArtistIds: localArtistIds,
      localGenres: localGenres,
    );
    settingsEvents.add(customShuffleSettings);
  }

  void publish(List<ShufflePreset> presets) {
    shufflePresets = presets;
    presetEvents.add(presets);
  }

  @override
  Future<void> close() async {
    await presetEvents.close();
    await authEvents.close();
    await settingsEvents.close();
  }
}
