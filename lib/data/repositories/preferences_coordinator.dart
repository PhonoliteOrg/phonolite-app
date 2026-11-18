import 'dart:async';

import 'package:phonolite_app/data/models/playback/custom_shuffle_settings.dart';
import 'package:phonolite_app/data/models/playback/device_playback_snapshot.dart';
import 'package:phonolite_app/data/models/playback/playback_repeat_mode.dart';
import 'package:phonolite_app/data/models/playback/playback_resume_checkpoint.dart';
import 'package:phonolite_app/data/models/playback/playback_state.dart';
import 'package:phonolite_app/data/models/preferences/desktop_settings.dart';
import 'package:phonolite_app/data/models/preferences/display_settings.dart';
import 'package:phonolite_app/data/models/preferences/download_settings.dart';
import 'package:phonolite_app/data/models/preferences/log_directory_preferences.dart';
import 'package:phonolite_app/data/repositories/device_preference.dart';
import 'package:phonolite_app/data/repositories/listening_stats_service.dart';
import 'package:phonolite_app/data/repositories/shuffle_preferences.dart';
import 'package:phonolite_app/data/storage/logs/app_log.dart';
import 'package:phonolite_app/data/storage/playback/playback_resume_storage.dart';
import 'package:phonolite_app/data/storage/preferences/custom_shuffle_settings_storage.dart';
import 'package:phonolite_app/data/storage/preferences/desktop_settings_storage.dart';
import 'package:phonolite_app/data/storage/preferences/display_settings_storage.dart';
import 'package:phonolite_app/data/storage/preferences/download_settings_storage.dart';
import 'package:phonolite_app/data/storage/preferences/log_storage_settings_storage.dart';
import 'package:phonolite_app/data/storage/preferences/offline_storage_settings_storage.dart';
import 'package:phonolite_app/data/storage/preferences/playback_preferences.dart';
import 'package:phonolite_app/data/structures/async/serial_action_queue.dart';

/// Device preference I/O shared by startup, settings, playback and storage relocation.
class PreferencesCoordinator implements LogDirectoryPreferences {
  static final shared = PreferencesCoordinator();

  final PlaybackPreferencesStorage _playback;
  final CustomShuffleSettingsStorage _shuffle;
  final DisplaySettingsStorage _display;
  final DownloadSettingsStorage _downloads;
  final DesktopSettingsStorage _desktop;
  final OfflineStorageSettingsStorage _offline;
  final LogStorageSettingsStorage _logs;

  bool _collectionListMode = false;
  bool _collectionListModeEdited = false;
  bool _gaplessResampling = false;
  bool _gaplessResamplingEdited = false;
  Future<PlaybackRepeatMode?>? _repeatRead;
  bool _hasRepeatMode = false;
  ShufflePreferences? _activeShuffle;
  Timer? _volumeTimer;
  double? _pendingVolume;
  bool _volumeEdited = false;
  int _playbackGeneration = 0;
  final _playbackWrites = SerialActionQueue();

  PreferencesCoordinator({
    this._playback = const PlaybackPreferencesStorage(),
    this._shuffle = const CustomShuffleSettingsStorage(),
    this._display = const DisplaySettingsStorage(),
    this._downloads = const DownloadSettingsStorage(),
    this._desktop = const DesktopSettingsStorage(),
    this._offline = const OfflineStorageSettingsStorage(),
    this._logs = const LogStorageSettingsStorage(),
  });

  Future<double?> loadVolume() async {
    final generation = _playbackGeneration;
    final stored = await _playback.readVolume();
    return _volumeEdited || generation != _playbackGeneration ? null : stored;
  }

  /// Playback uses the clamped value immediately. Rapid adjustments share a disk write.
  double setVolume(double volume) {
    final value = volume.clamp(0.0, 1.0);
    _volumeEdited = true;
    _pendingVolume = value;
    _volumeTimer?.cancel();
    _volumeTimer = Timer(const Duration(milliseconds: 350), _savePendingVolume);
    return value;
  }

  void _savePendingVolume() {
    _volumeTimer = null;
    final value = _pendingVolume;
    _pendingVolume = null;
    if (value != null) {
      unawaited(
        _playbackWrites.add(() => _playback.writeVolume(value)).catchError((Object error) {
          AppLogger.debug('Volume preference save failed: $error');
        }),
      );
    }
  }

  /// Retires outstanding startup reads and drains every accepted playback preference write.
  Future<void> closePlayback() {
    _volumeTimer?.cancel();
    _savePendingVolume();
    _collectionListMode = false;
    _collectionListModeEdited = false;
    _gaplessResampling = false;
    _gaplessResamplingEdited = false;
    _repeatRead = null;
    _hasRepeatMode = false;
    _playbackGeneration++;
    _volumeEdited = false;
    final shuffle = _activeShuffle;
    _activeShuffle = null;
    return Future.wait([_playbackWrites.drain(), if (shuffle != null) shuffle.close()]);
  }

  bool get collectionListMode => _collectionListMode;
  bool get gaplessResampling => _gaplessResampling;
  bool get hasRepeatMode => _hasRepeatMode;

  bool setCollectionListMode(bool value, {bool persist = true}) {
    if (persist) _collectionListModeEdited = true;
    if (_collectionListMode == value) return false;
    _collectionListMode = value;
    if (persist) _savePlaybackChoice('Collection list mode', () => _playback.writeCollectionListMode(value));
    return true;
  }

  bool setGaplessResampling(bool value, {bool persist = true}) {
    if (persist) _gaplessResamplingEdited = true;
    if (_gaplessResampling == value) return false;
    _gaplessResampling = value;
    if (persist) _savePlaybackChoice('Gapless resampling', () => _playback.writeGaplessResampling(value));
    return true;
  }

  void _savePlaybackChoice(String label, Future<void> Function() write) {
    unawaited(
      _playbackWrites.add(write).catchError((Object error) {
        AppLogger.debug('$label preference save failed: $error');
      }),
    );
  }

  Future<void> restorePlayback({
    required bool Function() isCurrent,
    required void Function(PlaybackRepeatMode) applyRepeat,
    required void Function(bool) applyCollectionMode,
    required void Function(double) applyVolume,
    required void Function(bool) applyGapless,
  }) async {
    await restoreRepeatMode(applyRepeat, isCurrent: isCurrent);
    if (!isCurrent()) return;
    // Collection layout and volume can be applied while the resampling preference loads.
    // Finish both before resampling can restart the audio engine.
    bool? storedGapless;
    await Future.wait([
      _restoreLayoutAndVolume(isCurrent, applyCollectionMode, applyVolume),
      _playback.readGaplessResampling().then<void>((value) => storedGapless = value),
    ]);
    final gapless = storedGapless;
    if (isCurrent() && !_gaplessResamplingEdited && gapless != null) applyGapless(gapless);
  }

  Future<void> _restoreLayoutAndVolume(
    bool Function() isCurrent,
    void Function(bool) applyCollectionMode,
    void Function(double) applyVolume,
  ) async {
    final listMode = await _playback.readCollectionListMode();
    if (!isCurrent()) return;
    if (!_collectionListModeEdited && listMode != null) applyCollectionMode(listMode);
    final volume = await loadVolume();
    if (isCurrent() && volume != null) applyVolume(volume);
  }

  Future<void> restoreRepeatMode(void Function(PlaybackRepeatMode) apply, {required bool Function() isCurrent}) async {
    final stored = await (_repeatRead ??= _playback.readRepeatMode());
    if (isCurrent() && !_hasRepeatMode && stored != null) {
      _hasRepeatMode = true;
      apply(stored);
    }
  }

  Future<void> saveRepeatMode(PlaybackRepeatMode mode) {
    _hasRepeatMode = true;
    return _playbackWrites.add(() => _playback.writeRepeatMode(mode));
  }

  Future<CustomShuffleSettings> loadLocalShuffle() => _shuffle.read();

  ShufflePreferences get shuffleFilters => _activeShuffle ??= ShufflePreferences(_shuffle);

  late final display = DevicePreference(
    const DisplaySettings(),
    label: 'display settings',
    read: _display.read,
    write: _display.write,
  );
  late final downloads = DevicePreference(
    const DownloadSettings(),
    label: 'download settings',
    read: _downloads.read,
    write: _downloads.write,
  );
  late final desktop = DevicePreference(
    const DesktopSettings(),
    label: 'desktop settings',
    read: _desktop.read,
    write: _desktop.write,
  );

  // The worker constructs default stores in its own isolate. Custom stores stay inline.
  bool get usesDefaultOfflineStore => identical(_offline, const OfflineStorageSettingsStorage());
  bool get usesManagedOfflineDirectories => _offline.usesManagedStoragePaths;
  Future<OfflineStorageSettings> loadOfflineDirectories() => _offline.read();
  Future<OfflineStorageSettings> loadLegacyOfflineDirectories() => _offline.readRaw();
  Future<void> saveOfflineDirectories(OfflineStorageSettings value) => _offline.write(value);

  @override
  bool get usesManagedLogDirectory => _logs.usesManagedStoragePaths;
  @override
  Future<String?> loadLogDirectory() => _logs.read();
  @override
  Future<void> saveLogDirectory(String? directory) => _logs.write(directory);

  // Shuffle modes and scope share a record with the resume checkpoint. Store one
  // consistent snapshot even when only the remembered modes have changed.
  Future<DevicePlaybackSnapshot?> loadDevicePlayback(PlaybackResumeStorage storage) => storage.readLocal();

  Future<void> resetDevicePlayback(PlaybackResumeStorage storage) => storage.clearLocal();

  Future<void> saveDevicePlayback(
    PlaybackResumeStorage storage, {
    required PlaybackState state,
    required PlaybackResumeCheckpoint? checkpoint,
    required List<String> queueTrackIds,
    required bool activate,
  }) async {
    final previous = activate && checkpoint != null ? null : await storage.readLocal();
    final snapshot = DevicePlaybackSnapshot(
      checkpoint: activate ? checkpoint ?? previous?.checkpoint : previous?.checkpoint,
      queueTrackIds: activate && state.track != null ? queueTrackIds : previous?.queueTrackIds ?? const [],
      localShuffleMode: state.localShuffleMode,
      serverShuffleMode: state.serverShuffleMode,
      shuffleScope: state.shuffleScope,
      positionMs: activate && state.track != null ? state.position.inMilliseconds : previous?.positionMs ?? 0,
    );
    await storage.writeLocal(snapshot, activate: activate);
  }

  // Consent and its sync revision must commit in the history worker's same transaction.
  Future<void> loadListeningConsent(ListeningStatsService history) => history.initialize();
  Future<void> setListeningConsent(ListeningStatsService history, bool enabled) => history.setEnabled(enabled);
}
