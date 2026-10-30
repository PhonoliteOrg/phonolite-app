part of '../app_controller.dart';

class _PreferencesCoordinator {
  final AppController _host;
  CustomShuffleSettings _customShuffleSettings = const CustomShuffleSettings();
  Future<void>? _customShuffleLoadFuture;
  Future<void> _customShuffleSaveChain = Future.value();
  String? _shuffleAccountScope;
  int _shuffleAccountGeneration = 0;
  int _shuffleLoadGeneration = 0;
  int _localShuffleLoadGeneration = 0;
  int _serverShuffleMutation = 0;
  int _localShuffleMutation = 0;
  Future<PlaybackRepeatMode?>? _repeatModeLoadFuture;
  Future<void> _repeatModeSaveChain = Future.value();
  bool _repeatModeTouched = false;
  bool _repeatModeHasLocalValue = false;
  final _volumeSaveDebounce = DebouncedAction();
  Future<void> _volumeSaveChain = Future.value();
  double _pendingVolumeSave = 1.0;
  bool _volumeSaveQueued = false;
  bool _volumeTouched = false;
  bool _collectionListModeTouched = false;
  final _customShuffleSettingsController = StreamController<CustomShuffleSettings>.broadcast();
  final _collectionListModeController = StreamController<bool>.broadcast();
  bool _collectionListMode = false;
  bool _gaplessResampling = false;
  bool _gaplessResamplingTouched = false;
  final _gaplessResamplingController = StreamController<bool>.broadcast();
  Future<void> _gaplessResamplingSaveChain = Future.value();

  _PreferencesCoordinator(this._host);

  Stream<CustomShuffleSettings> get customShuffleSettingsStream => _customShuffleSettingsController.stream;

  Stream<bool> get collectionListModeStream => _collectionListModeController.stream;

  List<String> get customShuffleArtistIds => List.unmodifiable(_customShuffleSettings.artistIds);

  List<String> get customShuffleGenres => List.unmodifiable(_customShuffleSettings.genres);

  List<String> get localCustomShuffleArtistIds => List.unmodifiable(_customShuffleSettings.localArtistIds);

  List<String> get localCustomShuffleGenres => List.unmodifiable(_customShuffleSettings.localGenres);

  bool get collectionListMode => _collectionListMode;

  bool get gaplessResampling => _gaplessResampling;

  Stream<bool> get gaplessResamplingStream => _gaplessResamplingController.stream;

  void setGaplessResampling(bool enabled, {bool persist = true}) {
    if (_host._disposed) return;
    if (persist) _gaplessResamplingTouched = true;
    if (_gaplessResampling == enabled) return;
    _host._gaplessCoordinator.invalidate();
    _gaplessResampling = enabled;
    _host._audio?.setGaplessResampling(enabled);
    _gaplessResamplingController.add(enabled);
    if (persist) {
      _gaplessResamplingSaveChain = _gaplessResamplingSaveChain.then(
        (_) => _host._playbackPreferencesStorage.writeGaplessResampling(enabled),
      );
    }
    final track = _host._playbackState.track;
    if (track != null && (_host._audio?.hasActivePlayer == true || _host._wantsPlayback)) {
      _host._startPlayback(track, startOffset: _host._playbackState.position);
    }
  }

  Future<void> close() async {
    await _gaplessResamplingController.close();
    await Future.wait([_customShuffleSaveChain, _repeatModeSaveChain, _gaplessResamplingSaveChain]);
  }

  Future<void> loadCustomShuffleSettings() async {
    await _ensureCustomShuffleSettingsLoaded(force: true);
  }

  Future<void> updateCustomShuffleSettings({
    List<String>? artistIds,
    List<String>? genres,
    List<String>? localArtistIds,
    List<String>? localGenres,
  }) async {
    if (_host._disposed) {
      return;
    }

    final scope = _shuffleAccountScope;
    final accountGeneration = _shuffleAccountGeneration;
    final changesServerFilters = artistIds != null || genres != null;
    final changesLocalFilters = localArtistIds != null || localGenres != null;
    final active = _host._playbackState;
    if (active.shuffleMode == ShuffleMode.custom &&
        (active.shuffleScope == ActionScope.local ? changesLocalFilters : changesServerFilters)) {
      _host._gaplessCoordinator.invalidate();
    }
    final next = CustomShuffleSettings(
      artistIds: _normalizeCustomList(artistIds ?? _customShuffleSettings.artistIds),
      genres: _normalizeCustomList(genres ?? _customShuffleSettings.genres, lowerCase: true),
      localArtistIds: _normalizeCustomList(localArtistIds ?? _customShuffleSettings.localArtistIds),
      localGenres: _normalizeCustomList(localGenres ?? _customShuffleSettings.localGenres, lowerCase: true),
    );

    if (changesServerFilters) {
      _serverShuffleMutation++;
    }

    if (changesLocalFilters) {
      _localShuffleMutation++;
    }

    _customShuffleSettings = next;
    _customShuffleSettingsController.add(_host.customShuffleSettings);

    final save = _customShuffleSaveChain.then((_) async {
      if (changesLocalFilters) {
        await _host._customShuffleStorage.writeLocal(next);
      }

      if (changesServerFilters &&
          scope != null &&
          _shuffleAccountScope == scope &&
          _shuffleAccountGeneration == accountGeneration) {
        await _host._customShuffleStorage.writeForAccount(scope, next);
      }
    });

    _customShuffleSaveChain = save.then<void>((_) {}, onError: (Object _, StackTrace __) {});

    await save;

    if (_host._disposed || _shuffleAccountGeneration != accountGeneration) {
      return;
    }

    await _host._refreshCustomShuffleQueueIfNeeded();

    final state = _host._playbackState;
    final changedActiveFilters = state.shuffleScope == ActionScope.local ? changesLocalFilters : changesServerFilters;

    if (!_host._disposed &&
        _shuffleAccountGeneration == accountGeneration &&
        state.shuffleMode == ShuffleMode.custom &&
        changedActiveFilters) {
      _host._resumeCoordinator.changed();
      _host._gaplessCoordinator.prepare();
    }
  }

  void _setShuffleAccount(String? scope) {
    if (_host._disposed ||
        (_shuffleAccountScope == scope &&
            (scope != null || (_customShuffleSettings.artistIds.isEmpty && _customShuffleSettings.genres.isEmpty)))) {
      return;
    }

    _shuffleAccountScope = scope;
    _shuffleAccountGeneration++;
    final accountGeneration = _shuffleAccountGeneration;
    _serverShuffleMutation++;
    _customShuffleSettings = _customShuffleSettings.copyWith(artistIds: const [], genres: const []);
    _customShuffleSettingsController.add(_host.customShuffleSettings);
    _customShuffleLoadFuture = _loadCustomShuffleSettings(loadLocal: false);

    unawaited(
      _customShuffleLoadFuture!.catchError((Object error) {
        if (!_host._disposed && _shuffleAccountScope == scope && _shuffleAccountGeneration == accountGeneration) {
          _host._pushMessage('Failed to load custom shuffle settings.', level: LogLevel.warning);
        }
      }),
    );
  }

  void setCollectionListMode(bool value, {bool persist = true}) {
    if (persist) {
      _collectionListModeTouched = true;
    }

    if (_collectionListMode == value) {
      return;
    }

    _collectionListMode = value;
    _collectionListModeController.add(value);

    if (persist) {
      _persistCollectionListMode(value);
    }
  }

  void toggleCollectionListMode() {
    _host.setCollectionListMode(!_collectionListMode);
  }

  void _persistCollectionListMode(bool value) {
    _volumeSaveChain = _volumeSaveChain.then((_) => _host._playbackPreferencesStorage.writeCollectionListMode(value));
  }

  Future<void> _loadCustomShuffleSettings({bool loadLocal = true}) async {
    final scope = _shuffleAccountScope;
    final generation = ++_shuffleLoadGeneration;
    final localGeneration = loadLocal ? ++_localShuffleLoadGeneration : _localShuffleLoadGeneration;
    final serverMutation = _serverShuffleMutation;
    final localMutation = _localShuffleMutation;
    final settings = loadLocal ? await _host._customShuffleStorage.read() : null;
    final accountSettings = scope == null
        ? const CustomShuffleSettings()
        : await _host._customShuffleStorage.readForAccount(scope);

    if (_host._disposed) {
      return;
    }

    final applyServer =
        generation == _shuffleLoadGeneration &&
        scope == _shuffleAccountScope &&
        serverMutation == _serverShuffleMutation;
    final applyLocal =
        settings != null && localGeneration == _localShuffleLoadGeneration && localMutation == _localShuffleMutation;

    if (!applyServer && !applyLocal) {
      return;
    }

    _customShuffleSettings = CustomShuffleSettings(
      artistIds: applyServer ? accountSettings.artistIds : _customShuffleSettings.artistIds,
      genres: applyServer ? accountSettings.genres : _customShuffleSettings.genres,
      localArtistIds: applyLocal ? settings.localArtistIds : _customShuffleSettings.localArtistIds,
      localGenres: applyLocal ? settings.localGenres : _customShuffleSettings.localGenres,
    );
    _customShuffleSettingsController.add(_host.customShuffleSettings);
  }

  Future<void> _loadPlaybackPreferences() async {
    await _loadLocalRepeatMode();

    final gaplessRead = _host._playbackPreferencesStorage.readGaplessResampling();
    final storedCollectionListMode = await _host._playbackPreferencesStorage.readCollectionListMode();

    if (_host._disposed) {
      return;
    }

    if (!_collectionListModeTouched && storedCollectionListMode != null) {
      _host.setCollectionListMode(storedCollectionListMode, persist: false);
    }

    final storedVolume = await _host._playbackPreferencesStorage.readVolume();

    if (_host._disposed) {
      return;
    }

    if (storedVolume != null && !_volumeTouched) {
      _host._applyVolume(storedVolume, persist: false);
    }
    final storedGaplessResampling = await gaplessRead;
    if (_host._disposed) return;
    if (!_gaplessResamplingTouched && storedGaplessResampling != null) {
      setGaplessResampling(storedGaplessResampling, persist: false);
    }
  }

  Future<void> _ensureCustomShuffleSettingsLoaded({bool force = false}) async {
    if (force || _customShuffleLoadFuture == null) {
      _customShuffleLoadFuture = _loadCustomShuffleSettings();
    }

    await _customShuffleLoadFuture;
  }

  List<String> _normalizeCustomList(List<String> values, {bool lowerCase = false}) {
    final seen = <String>{};
    final result = <String>[];

    for (final raw in values) {
      var value = raw.trim();

      if (value.isEmpty) {
        continue;
      }

      if (lowerCase) {
        value = value.toLowerCase();
      }

      if (seen.add(value)) {
        result.add(value);
      }
    }

    return result;
  }

  PlaybackRepeatMode _parseRepeatMode(String? value) {
    switch (value?.toLowerCase().trim()) {
      case 'one':
        return PlaybackRepeatMode.one;
      default:
        return PlaybackRepeatMode.off;
    }
  }

  Future<void> _loadPlaybackSettings() async {
    final revision = _host.connection.sessionRevision;

    await _loadLocalRepeatMode();

    if (_repeatModeHasLocalValue || _host._disposed || !_host._sessionCoordinator._isServerSessionCurrent(revision)) {
      return;
    }

    try {
      final settings = await _host.connection.fetchPlaybackSettings();

      await _adoptLegacyRepeatMode(settings.repeatMode, sessionRevision: revision);
    } catch (err) {
      if (!_host._sessionCoordinator._isServerSessionCurrent(revision)) return;
      _host._pushMessage('Failed to load playback settings: $err', level: LogLevel.warning);
    }
  }

  Future<void> _adoptLegacyRepeatMode(String? value, {required int sessionRevision}) async {
    await _loadLocalRepeatMode();

    if (_host._disposed ||
        _repeatModeHasLocalValue ||
        _repeatModeTouched ||
        !_host._sessionCoordinator._isServerSessionCurrent(sessionRevision)) {
      return;
    }

    final mode = _parseRepeatMode(value);

    _repeatModeHasLocalValue = true;
    _host._updatePlayback(repeatMode: mode);

    await _saveRepeatMode(mode);
  }

  Future<void> _persistPlaybackSettings(PlaybackRepeatMode mode) async {
    _repeatModeTouched = true;
    _repeatModeHasLocalValue = true;

    try {
      await _saveRepeatMode(mode);
    } catch (err) {
      if (_host._disposed) return;
      _host._pushMessage('Failed to update playback settings: $err');
    }
  }

  Future<void> _loadLocalRepeatMode() async {
    _repeatModeLoadFuture ??= _host._playbackPreferencesStorage.readRepeatMode();

    final mode = await _repeatModeLoadFuture;

    if (_host._disposed || _repeatModeTouched || _repeatModeHasLocalValue || mode == null) {
      return;
    }

    _repeatModeHasLocalValue = true;
    _host._updatePlayback(repeatMode: mode);
  }

  Future<void> _saveRepeatMode(PlaybackRepeatMode mode) {
    final save = _repeatModeSaveChain.then((_) => _host._playbackPreferencesStorage.writeRepeatMode(mode));

    _repeatModeSaveChain = save.then<void>((_) {}, onError: (Object _, StackTrace __) {});

    return save;
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _PreferencesFacade {
  _PreferencesCoordinator get _preferencesCoordinator;

  CustomShuffleSettings get _customShuffleSettings => _preferencesCoordinator._customShuffleSettings;

  Future<void>? get _customShuffleLoadFuture => _preferencesCoordinator._customShuffleLoadFuture;

  set _customShuffleLoadFuture(Future<void>? value) => _preferencesCoordinator._customShuffleLoadFuture = value;

  DebouncedAction get _volumeSaveDebounce => _preferencesCoordinator._volumeSaveDebounce;

  Future<void> get _volumeSaveChain => _preferencesCoordinator._volumeSaveChain;

  set _volumeSaveChain(Future<void> value) => _preferencesCoordinator._volumeSaveChain = value;

  double get _pendingVolumeSave => _preferencesCoordinator._pendingVolumeSave;

  set _pendingVolumeSave(double value) => _preferencesCoordinator._pendingVolumeSave = value;

  bool get _volumeSaveQueued => _preferencesCoordinator._volumeSaveQueued;

  set _volumeSaveQueued(bool value) => _preferencesCoordinator._volumeSaveQueued = value;

  set _volumeTouched(bool value) => _preferencesCoordinator._volumeTouched = value;

  StreamController<CustomShuffleSettings> get _customShuffleSettingsController =>
      _preferencesCoordinator._customShuffleSettingsController;

  StreamController<bool> get _collectionListModeController => _preferencesCoordinator._collectionListModeController;

  Stream<CustomShuffleSettings> get customShuffleSettingsStream => _preferencesCoordinator.customShuffleSettingsStream;

  Stream<bool> get collectionListModeStream => _preferencesCoordinator.collectionListModeStream;

  List<String> get customShuffleArtistIds => _preferencesCoordinator.customShuffleArtistIds;

  List<String> get customShuffleGenres => _preferencesCoordinator.customShuffleGenres;

  List<String> get localCustomShuffleArtistIds => _preferencesCoordinator.localCustomShuffleArtistIds;

  List<String> get localCustomShuffleGenres => _preferencesCoordinator.localCustomShuffleGenres;

  bool get collectionListMode => _preferencesCoordinator.collectionListMode;

  bool get gaplessResampling => _preferencesCoordinator.gaplessResampling;

  Stream<bool> get gaplessResamplingStream => _preferencesCoordinator.gaplessResamplingStream;

  void setGaplessResampling(bool enabled) => _preferencesCoordinator.setGaplessResampling(enabled);

  Future<void> loadCustomShuffleSettings() => _preferencesCoordinator.loadCustomShuffleSettings();

  Future<void> updateCustomShuffleSettings({
    List<String>? artistIds,
    List<String>? genres,
    List<String>? localArtistIds,
    List<String>? localGenres,
  }) => _preferencesCoordinator.updateCustomShuffleSettings(
    artistIds: artistIds,
    genres: genres,
    localArtistIds: localArtistIds,
    localGenres: localGenres,
  );

  void setCollectionListMode(bool value, {bool persist = true}) =>
      _preferencesCoordinator.setCollectionListMode(value, persist: persist);

  void toggleCollectionListMode() => _preferencesCoordinator.toggleCollectionListMode();

  Future<void> _loadCustomShuffleSettings() => _preferencesCoordinator._loadCustomShuffleSettings();

  Future<void> _loadPlaybackPreferences() => _preferencesCoordinator._loadPlaybackPreferences();

  Future<void> _ensureCustomShuffleSettingsLoaded({bool force = false}) =>
      _preferencesCoordinator._ensureCustomShuffleSettingsLoaded(force: force);

  Future<void> _loadPlaybackSettings() => _preferencesCoordinator._loadPlaybackSettings();

  Future<void> _persistPlaybackSettings(PlaybackRepeatMode mode) =>
      _preferencesCoordinator._persistPlaybackSettings(mode);
}
