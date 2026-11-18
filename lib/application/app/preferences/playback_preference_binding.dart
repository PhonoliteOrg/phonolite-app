part of '../app_controller.dart';

class _PlaybackPreferenceBinding {
  final AppController _host;
  final ShufflePreferences _shuffle;

  final _collectionListModeController = StreamController<bool>.broadcast();
  final _gaplessResamplingController = StreamController<bool>.broadcast();

  _PlaybackPreferenceBinding(this._host) : _shuffle = _host._preferences.shuffleFilters;

  Stream<CustomShuffleSettings> get customShuffleSettingsStream => _shuffle.changes;

  Stream<bool> get collectionListModeStream => _collectionListModeController.stream;

  List<String> get customShuffleArtistIds => _shuffle.value.artistIds;

  List<String> get customShuffleGenres => _shuffle.value.genres;

  List<String> get localCustomShuffleArtistIds => _shuffle.value.localArtistIds;

  List<String> get localCustomShuffleGenres => _shuffle.value.localGenres;

  bool get collectionListMode => _host._preferences.collectionListMode;

  bool get gaplessResampling => _host._preferences.gaplessResampling;

  Stream<bool> get gaplessResamplingStream => _gaplessResamplingController.stream;

  void setVolume(double value) {
    if (!_host._disposed) _host._playbackCoordinator._applyVolume(_host._preferences.setVolume(value));
  }

  void setGaplessResampling(bool enabled, {bool persist = true}) {
    if (_host._disposed) {
      return;
    }

    if (!_host._preferences.setGaplessResampling(enabled, persist: persist)) return;
    _host._gaplessCoordinator.invalidate();
    _host._audio?.setGaplessResampling(enabled);
    _gaplessResamplingController.add(enabled);

    final track = _host._playbackState.track;
    if (track != null && (_host._audio?.hasActivePlayer == true || _host._wantsPlayback)) {
      _host._startPlayback(track, startOffset: _host._playbackState.position);
    }
  }

  Future<void> close() => _gaplessResamplingController.close();

  Future<void> loadCustomShuffleSettings() async {
    await _shuffle.load(force: true);
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

    final accountGeneration = _shuffle.accountGeneration;
    final changesServerFilters = artistIds != null || genres != null;
    final changesLocalFilters = localArtistIds != null || localGenres != null;
    final active = _host._playbackState;
    if (active.shuffleMode == ShuffleMode.custom &&
        (active.shuffleScope == ActionScope.local ? changesLocalFilters : changesServerFilters)) {
      _host._gaplessCoordinator.invalidate();
    }

    final save = _shuffle.update(
      artistIds: artistIds,
      genres: genres,
      localArtistIds: localArtistIds,
      localGenres: localGenres,
    );
    // The new filters are already in effect, so playback follows them even when
    // persisting fails; the save failure still reaches the caller afterwards.
    try {
      await save;
    } finally {
      await _applyCustomShuffleChange(
        accountGeneration,
        changesLocalFilters: changesLocalFilters,
        changesServerFilters: changesServerFilters,
      );
    }
  }

  Future<void> _applyCustomShuffleChange(
    int accountGeneration, {
    required bool changesLocalFilters,
    required bool changesServerFilters,
  }) async {
    if (_host._disposed || _shuffle.accountGeneration != accountGeneration) {
      return;
    }

    await _host._refreshCustomShuffleQueueIfNeeded();

    final state = _host._playbackState;
    final changedActiveFilters = state.shuffleScope == ActionScope.local ? changesLocalFilters : changesServerFilters;

    if (!_host._disposed &&
        _shuffle.accountGeneration == accountGeneration &&
        state.shuffleMode == ShuffleMode.custom &&
        changedActiveFilters) {
      _host._resumeCoordinator.changed();
      _host._gaplessCoordinator.prepare();
    }
  }

  void _setShuffleAccount(String? scope) {
    if (_host._disposed) return;
    final load = _shuffle.selectAccount(scope);
    final generation = _shuffle.accountGeneration;
    unawaited(
      load.catchError((Object error) {
        if (!_host._disposed && generation == _shuffle.accountGeneration) {
          _host._pushMessage('Failed to load custom shuffle settings.', level: LogLevel.warning);
        }
      }),
    );
  }

  void setCollectionListMode(bool value, {bool persist = true}) {
    if (_host._preferences.setCollectionListMode(value, persist: persist)) {
      _collectionListModeController.add(value);
    }
  }

  void toggleCollectionListMode() => _host.setCollectionListMode(!collectionListMode);

  Future<void> _loadPlaybackPreferences() => _host._preferences.restorePlayback(
    isCurrent: () => !_host._disposed,
    applyRepeat: (mode) => _host._updatePlayback(repeatMode: mode),
    applyCollectionMode: (value) => _host.setCollectionListMode(value, persist: false),
    applyVolume: _host._playbackCoordinator._applyVolume,
    applyGapless: (value) => setGaplessResampling(value, persist: false),
  );

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

    if (_host._preferences.hasRepeatMode ||
        _host._disposed ||
        !_host._sessionCoordinator._isServerSessionCurrent(revision)) {
      return;
    }

    try {
      final settings = await _host.connection.fetchPlaybackSettings();

      await _adoptLegacyRepeatMode(settings.repeatMode, sessionRevision: revision);
    } on Object catch (err) {
      if (!_host._sessionCoordinator._isServerSessionCurrent(revision)) {
        return;
      }

      _host._pushMessage('Failed to load playback settings: $err', level: LogLevel.warning);
    }
  }

  Future<void> _adoptLegacyRepeatMode(String? value, {required int sessionRevision}) async {
    await _loadLocalRepeatMode();

    if (_host._disposed ||
        _host._preferences.hasRepeatMode ||
        !_host._sessionCoordinator._isServerSessionCurrent(sessionRevision)) {
      return;
    }

    final mode = _parseRepeatMode(value);

    _host._updatePlayback(repeatMode: mode);

    await _host._preferences.saveRepeatMode(mode);
  }

  Future<void> _persistPlaybackSettings(PlaybackRepeatMode mode) async {
    try {
      await _host._preferences.saveRepeatMode(mode);
    } on Object catch (err) {
      if (_host._disposed) {
        return;
      }

      _host._pushMessage('Failed to update playback settings: $err');
    }
  }

  Future<void> _loadLocalRepeatMode() => _host._preferences.restoreRepeatMode(
    (mode) => _host._updatePlayback(repeatMode: mode),
    isCurrent: () => !_host._disposed,
  );
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _PreferencesFacade {
  _PlaybackPreferenceBinding get _playbackPreferences;

  CustomShuffleSettings get _customShuffleSettings => _playbackPreferences._shuffle.value;

  StreamController<bool> get _collectionListModeController => _playbackPreferences._collectionListModeController;

  Stream<CustomShuffleSettings> get customShuffleSettingsStream => _playbackPreferences.customShuffleSettingsStream;

  Stream<bool> get collectionListModeStream => _playbackPreferences.collectionListModeStream;

  List<String> get customShuffleArtistIds => _playbackPreferences.customShuffleArtistIds;

  List<String> get customShuffleGenres => _playbackPreferences.customShuffleGenres;

  List<String> get localCustomShuffleArtistIds => _playbackPreferences.localCustomShuffleArtistIds;

  List<String> get localCustomShuffleGenres => _playbackPreferences.localCustomShuffleGenres;

  bool get collectionListMode => _playbackPreferences.collectionListMode;

  bool get gaplessResampling => _playbackPreferences.gaplessResampling;

  Stream<bool> get gaplessResamplingStream => _playbackPreferences.gaplessResamplingStream;

  void setVolume(double value) => _playbackPreferences.setVolume(value);

  void setGaplessResampling(bool enabled) => _playbackPreferences.setGaplessResampling(enabled);

  Future<void> loadCustomShuffleSettings() => _playbackPreferences.loadCustomShuffleSettings();

  Future<void> updateCustomShuffleSettings({
    List<String>? artistIds,
    List<String>? genres,
    List<String>? localArtistIds,
    List<String>? localGenres,
  }) => _playbackPreferences.updateCustomShuffleSettings(
    artistIds: artistIds,
    genres: genres,
    localArtistIds: localArtistIds,
    localGenres: localGenres,
  );

  void setCollectionListMode(bool value, {bool persist = true}) =>
      _playbackPreferences.setCollectionListMode(value, persist: persist);

  void toggleCollectionListMode() => _playbackPreferences.toggleCollectionListMode();

  Future<void> _loadPlaybackPreferences() => _playbackPreferences._loadPlaybackPreferences();

  Future<void> _ensureCustomShuffleSettingsLoaded({bool force = false}) =>
      _playbackPreferences._shuffle.load(force: force);

  Future<void> _loadPlaybackSettings() => _playbackPreferences._loadPlaybackSettings();

  Future<void> _persistPlaybackSettings(PlaybackRepeatMode mode) => _playbackPreferences._persistPlaybackSettings(mode);
}
