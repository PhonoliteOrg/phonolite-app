import 'dart:async';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/feature_controller.dart';
import 'package:phonolite_app/application/controllers/shared/controller_selection.dart';
import 'package:phonolite_app/application/presentation/genre_labels.dart';
import 'package:phonolite_app/application/workflows/debounced_action.dart';
import 'package:phonolite_app/application/workflows/serial_action_queue.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/playback/custom_shuffle_options.dart';
import 'package:phonolite_app/data/models/playback/custom_shuffle_settings.dart';
import 'package:phonolite_app/data/storage/logs/app_log.dart';

export 'package:phonolite_app/data/models/playback/custom_shuffle_options.dart';

class CustomShuffleController extends FeatureController {
  final AppController _controller;
  final bool _autosave;
  String _artistQuery = '';
  String _genreQuery = '';
  late final ControllerSelection<String> _selection;
  CustomShuffleTarget _target;
  final _saveDebounce = DebouncedAction();
  final _saves = SerialActionQueue();
  bool _initialized = false;

  CustomShuffleController(
    AppController app, {
    CustomShuffleSettings? initialSettings,
    this._autosave = true,
    CustomShuffleTarget initialTarget = CustomShuffleTarget.server,
  }) : _controller = app,
       _target = initialTarget {
    final settings = initialSettings ?? app.customShuffleSettings;

    _selection = ControllerSelection<String>(
      update,
      groups: const ['serverArtists', 'serverGenres', 'localArtists', 'localGenres'],
      initialValues: {
        'serverArtists': settings.artistIds,
        'serverGenres': settings.genres.map(normalizeGenre).where((value) => value.isNotEmpty),
        'localArtists': settings.localArtistIds,
        'localGenres': settings.localGenres.map(normalizeGenre).where((value) => value.isNotEmpty),
      },
    );
    _initialized = true;
  }

  CustomShuffleTarget get target => _target;

  AppController get controller => _controller;

  Set<String> get selectedArtistIds => _selection.keys('serverArtists');

  Set<String> get selectedGenres => _selection.keys('serverGenres');

  Set<String> get selectedLocalArtistIds => _selection.keys('localArtists');

  Set<String> get selectedLocalGenres => _selection.keys('localGenres');

  String get _artistSelectionGroup => showingServerTarget ? 'serverArtists' : 'localArtists';

  String get _genreSelectionGroup => showingServerTarget ? 'serverGenres' : 'localGenres';

  Set<String> get activeArtistSelection =>
      _target == CustomShuffleTarget.server ? selectedArtistIds : selectedLocalArtistIds;

  Set<String> get activeGenreSelection => _target == CustomShuffleTarget.server ? selectedGenres : selectedLocalGenres;

  bool get showingServerTarget => _target == CustomShuffleTarget.server;

  @override
  void dispose() {
    _saveDebounce.cancel();
    _saveInBackground();
    super.dispose();
  }

  @override
  Future<void> initializeFeature() async {
    final app = _controller;

    if (showingServerTarget && app.authState.isAuthorized && app.artists.isEmpty) {
      await app.loadArtists();
    }
  }

  void setGenreQuery(String value) => update(() => _genreQuery = value);

  void setTarget(CustomShuffleTarget value) {
    update(() => _target = value);
    handleArtistSearchChanged(_artistQuery);
  }

  void prepareGenreOptions() {
    final controller = _controller;

    if (showingServerTarget && controller.hasMoreArtists) {
      unawaited(controller.loadAllArtists());
    }
  }

  void loadMoreArtists(double extentAfter, {required bool showingArtists}) {
    final app = _controller;

    if (!showingArtists ||
        !showingServerTarget ||
        _artistQuery.trim().isNotEmpty ||
        !app.authState.isAuthorized ||
        app.artistsLoading ||
        !app.hasMoreArtists ||
        extentAfter > 640) {
      return;
    }

    unawaited(app.loadMoreArtists());
  }

  void toggleArtist(String artistId) {
    _selection.toggle(artistId, group: _artistSelectionGroup, activate: null);
    scheduleSave();
  }

  void selectAllArtists(List<Artist> artists) {
    _selection.replaceGroups({_artistSelectionGroup: artists.map((artist) => artist.id)}, activate: null);
    scheduleSave();
  }

  Future<void> selectAllAvailableArtists() async {
    final controller = _controller;

    if (!showingServerTarget) {
      final localArtists = controller.offlineLibrarySnapshot.artistGroups
          .map((group) => group.toArtist())
          .toList(growable: false);

      selectAllArtists(localArtists);

      return;
    }

    await controller.loadAllArtists();

    if (isDisposed) {
      return;
    }

    selectAllArtists(controller.artists);
  }

  void clearArtists() {
    _selection.replaceGroups({_artistSelectionGroup: const []}, activate: null);
    scheduleSave();
  }

  void toggleGenre(String genreKey) {
    _selection.toggle(genreKey, group: _genreSelectionGroup, activate: null);
    scheduleSave();
  }

  void selectAllGenres(List<GenreOption> genres) {
    _selection.replaceGroups({_genreSelectionGroup: genres.map((genre) => genre.key)}, activate: null);
    scheduleSave();
  }

  void clearGenres() {
    _selection.replaceGroups({_genreSelectionGroup: const []}, activate: null);
    scheduleSave();
  }

  void scheduleSave() {
    if (!_autosave) {
      return;
    }

    _saveDebounce.schedule(const Duration(milliseconds: 350), _saveInBackground);
  }

  /// Replaces a draft only after an explicit reload; live updates never call it.
  void replaceServerSelection({required List<String> artistIds, required List<String> genres}) {
    _selection.replaceGroups({
      'serverArtists': artistIds,
      'serverGenres': genres.map(normalizeGenre).where((value) => value.isNotEmpty),
    }, activate: null);
  }

  void handleArtistSearchChanged(String value) {
    update(() => _artistQuery = value);

    final controller = _controller;

    if (!showingServerTarget) {
      return;
    }

    if (_artistQuery.trim().isNotEmpty && controller.hasMoreArtists && !controller.artistsLoading) {
      unawaited(controller.loadAllArtists());
    }
  }

  /// Saves the current selection after any earlier accepted saves.
  /// Completes when this save finishes; its failure propagates without blocking later saves.
  Future<void> flushSave() {
    if (!_initialized || !_autosave) {
      return Future<void>.value();
    }

    final controller = _controller;
    final artistIds = selectedArtistIds.toList();
    final genres = selectedGenres.toList();

    genres.sort();

    final localArtistIds = selectedLocalArtistIds.toList();
    final localGenres = selectedLocalGenres.toList();

    localGenres.sort();

    return _saves.add(
      () => controller.updateCustomShuffleSettings(
        artistIds: artistIds,
        genres: genres,
        localArtistIds: localArtistIds,
        localGenres: localGenres,
      ),
    );
  }

  /// Debounced and disposal saves have no awaiting caller, so they report failures here.
  void _saveInBackground() {
    unawaited(flushSave().catchError(_reportSaveFailure));
  }

  void _reportSaveFailure(Object error) {
    AppLogger.warning('Could not save custom shuffle filters: $error');
  }

  List<Artist> filterArtists(List<Artist> artists) {
    final query = _artistQuery.trim().toLowerCase();

    if (query.isEmpty) {
      return artists;
    }

    return artists.where((artist) => artist.name.toLowerCase().contains(query)).toList();
  }

  List<GenreOption> buildGenreOptions(List<Artist> artists) {
    final labels = <String, String>{};

    for (final artist in artists) {
      for (final genre in artist.genres) {
        final normalized = normalizeGenre(genre);

        if (normalized.isEmpty) {
          continue;
        }

        labels.putIfAbsent(normalized, () => genre.trim());
      }
    }

    for (final selected in activeGenreSelection) {
      if (selected.trim().isEmpty) {
        continue;
      }

      labels.putIfAbsent(selected, () => selected);
    }

    final options = labels.entries
        .map((entry) => GenreOption(key: entry.key, label: genreDisplayLabel(entry.value)))
        .toList();

    options.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

    return options;
  }

  List<GenreOption> filterGenres(List<GenreOption> genres) {
    final query = _genreQuery.trim().toLowerCase();

    if (query.isEmpty) {
      return genres;
    }

    return genres.where((genre) => genre.label.toLowerCase().contains(query)).toList();
  }

  String normalizeGenre(String genre) => genre.trim().toLowerCase();
}
