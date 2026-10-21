part of 'package:phonolite_app/application/app/app_controller.dart';

class _PreferencesCoordinator {
  final AppController _host;
  CustomShuffleSettings _customShuffleSettings = const CustomShuffleSettings();
  Future<void>? _customShuffleLoadFuture;
  final _volumeSaveDebounce = DebouncedAction();
  Future<void> _volumeSaveChain = Future.value();
  double _pendingVolumeSave = 1.0;
  bool _volumeSaveQueued = false;
  bool _volumeTouched = false;
  bool _collectionListModeTouched = false;
  final _customShuffleSettingsController = StreamController<CustomShuffleSettings>.broadcast();
  final _collectionListModeController = StreamController<bool>.broadcast();
  bool _collectionListMode = false;

  _PreferencesCoordinator(this._host);

  Stream<CustomShuffleSettings> get customShuffleSettingsStream => _customShuffleSettingsController.stream;

  Stream<bool> get collectionListModeStream => _collectionListModeController.stream;

  List<String> get customShuffleArtistIds => List.unmodifiable(_customShuffleSettings.artistIds);

  List<String> get customShuffleGenres => List.unmodifiable(_customShuffleSettings.genres);

  List<String> get localCustomShuffleArtistIds => List.unmodifiable(_customShuffleSettings.localArtistIds);

  List<String> get localCustomShuffleGenres => List.unmodifiable(_customShuffleSettings.localGenres);

  bool get collectionListMode => _collectionListMode;

  Future<void> loadCustomShuffleSettings() async {
    await _ensureCustomShuffleSettingsLoaded(force: true);
  }

  Future<void> updateCustomShuffleSettings({
    List<String>? artistIds,
    List<String>? genres,
    List<String>? localArtistIds,
    List<String>? localGenres,
  }) async {
    final next = CustomShuffleSettings(
      artistIds: _normalizeCustomList(artistIds ?? _customShuffleSettings.artistIds),
      genres: _normalizeCustomList(genres ?? _customShuffleSettings.genres, lowerCase: true),
      localArtistIds: _normalizeCustomList(localArtistIds ?? _customShuffleSettings.localArtistIds),
      localGenres: _normalizeCustomList(localGenres ?? _customShuffleSettings.localGenres, lowerCase: true),
    );

    _customShuffleSettings = next;
    _customShuffleSettingsController.add(_host.customShuffleSettings);

    await _host._customShuffleStorage.write(next);

    await _host._refreshCustomShuffleQueueIfNeeded();
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

  Future<void> _loadCustomShuffleSettings() async {
    final settings = await _host._customShuffleStorage.read();

    if (_host._disposed) {
      return;
    }

    _customShuffleSettings = settings;
    _customShuffleSettingsController.add(_host.customShuffleSettings);
  }

  Future<void> _loadPlaybackPreferences() async {
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

    if (storedVolume == null) {
      return;
    }

    if (_volumeTouched) {
      return;
    }

    _host._applyVolume(storedVolume, persist: false);
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
    try {
      final settings = await _host.connection.fetchPlaybackSettings();

      _host._updatePlayback(repeatMode: _parseRepeatMode(settings.repeatMode));
    } catch (err) {
      _host._pushMessage('Failed to load playback settings: $err', level: LogLevel.warning);
    }
  }

  Future<void> _persistPlaybackSettings(PlaybackRepeatMode mode) async {
    try {
      await _host.connection.updatePlaybackSettings(repeatMode: mode == PlaybackRepeatMode.one ? 'one' : 'off');
    } catch (err) {
      _host._pushMessage('Failed to update playback settings: $err');
    }
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

  PlaybackRepeatMode _parseRepeatMode(String? value) => _preferencesCoordinator._parseRepeatMode(value);

  Future<void> _loadPlaybackSettings() => _preferencesCoordinator._loadPlaybackSettings();

  Future<void> _persistPlaybackSettings(PlaybackRepeatMode mode) => _preferencesCoordinator._persistPlaybackSettings(mode);
}
