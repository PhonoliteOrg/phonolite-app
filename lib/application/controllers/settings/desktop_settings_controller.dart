import 'package:phonolite_app/application/controllers/settings/persisted_settings_controller.dart';
import 'package:phonolite_app/data/models/preferences/desktop_settings.dart';
import 'package:phonolite_app/data/storage/logs/app_log.dart';
import 'package:phonolite_app/data/storage/preferences/desktop_settings_storage.dart';
import 'package:phonolite_app/infrastructure/platform/app/desktop_lifecycle_platform.dart';

/// One application-owned lifecycle, independent of sign-in and local-data resets.
///
/// Each saved change is applied to the operating system before it is stored; a failure
/// undoes the native changes it already made, and the shared base restores [settings].
class DesktopSettingsController extends PersistedSettingsController<DesktopSettings> {
  static final instance = DesktopSettingsController();

  final DesktopSettingsStorage _storage;
  final DesktopLifecyclePlatform _platform;
  final bool Function() _isSupported;
  Future<void>? _quitting;
  Future<void>? _updatePreparation;
  Future<void>? _shutdown;
  Future<void> Function()? _beforeQuit;
  bool _starting = false;
  bool _started = false;
  bool _platformInitialized = false;
  bool _backgroundActive = false;

  DesktopSettingsController({
    this._storage = const DesktopSettingsStorage(),
    DesktopLifecyclePlatform? platform,
    bool Function()? isSupported,
  }) : _platform = platform ?? NativeDesktopLifecyclePlatform(),
       _isSupported = isSupported ?? (() => desktopLifecycleSupported),
       super(const DesktopSettings());

  bool get supported => _isSupported();

  /// Ready once the stored values are loaded and their native state has been applied.
  @override
  bool get ready => super.ready && _started && _shutdown == null;

  /// Startup counts as saving so a close request waits for the initial native state.
  @override
  bool get saving => _starting || super.saving;

  @override
  String get settingsLabel => 'desktop settings';

  @override
  bool get acceptsChanges =>
      super.acceptsChanges && _quitting == null && _updatePreparation == null && _shutdown == null;

  Future<void> initialize({required Future<void> Function() beforeQuit}) {
    if (isDisposed || _shutdown != null) {
      return Future<void>.value();
    }

    return initializeOnce(() => _initialize(beforeQuit));
  }

  /// The application owner calls this before releasing its notifier.
  Future<void> shutdown() => _shutdown ??= _shutdownPlatform();

  Future<void> setLaunchAtStartup(bool enabled) => change(settings.copyWith(launchAtStartup: enabled));

  Future<void> setRunInBackground(bool enabled) => change(settings.copyWith(runInBackground: enabled));

  Future<void> closeWindow() async {
    if (!ready || isDisposed || _quitting != null || _updatePreparation != null || _shutdown != null) {
      return;
    }

    if (saving) {
      await flush();
    }

    if (isDisposed || _quitting != null || _updatePreparation != null || _shutdown != null) {
      return;
    }

    if (_backgroundActive) {
      await _platform.hide();
    } else {
      await quit();
    }
  }

  Future<void> prepareForUpdate() => _updatePreparation ??= _prepareForUpdate();

  Future<void> quitForUpdate() async {
    await prepareForUpdate();
    await _platform.quit();
  }

  Future<void> quit() => _quitting ??= _quit();

  @override
  bool sameSettings(DesktopSettings first, DesktopSettings second) =>
      first.launchAtStartup == second.launchAtStartup && first.runInBackground == second.runInBackground;

  @override
  Future<void> persist(DesktopSettings next, DesktopSettings previous) async {
    final backgroundWasActive = _backgroundActive;
    var startupAttempted = false;
    var backgroundAttempted = false;

    try {
      if (next.launchAtStartup != previous.launchAtStartup) {
        startupAttempted = true;
        await _platform.setLaunchAtStartup(next.launchAtStartup);
      }

      if (next.runInBackground != previous.runInBackground) {
        backgroundAttempted = true;
        await _platform.setBackgroundEnabled(next.runInBackground);
        _backgroundActive = next.runInBackground;
      }

      await _storage.write(next);
    } catch (_) {
      if (backgroundAttempted) {
        await _restoreBackground(backgroundWasActive);
      }

      if (startupAttempted) {
        await _restoreLaunchAtStartup(previous.launchAtStartup);
      }

      rethrow;
    }
  }

  Future<void> _initialize(Future<void> Function() beforeQuit) async {
    if (!supported) {
      return;
    }

    _beforeQuit = beforeQuit;
    _starting = true;

    try {
      acceptLoadedSettings(await _storage.read());

      if (isDisposed) {
        return;
      }

      await _platform.initialize(onClose: closeWindow, onQuit: quit);
      _platformInitialized = true;
    } catch (error) {
      _starting = false;
      await _disposePlatformAfterFailedStart();
      reportError('Desktop integration could not start', error);
      notifyIfActive();

      return;
    }

    await _applyStartupSettings();

    _starting = false;
    _started = !isDisposed;
    notifyIfActive();
  }

  /// One unavailable OS integration must not prevent the other from working.
  Future<void> _applyStartupSettings() async {
    try {
      await _platform.setBackgroundEnabled(settings.runInBackground);
      _backgroundActive = settings.runInBackground;
    } catch (error) {
      reportError('Background mode could not start', error);
    }

    try {
      await _platform.setLaunchAtStartup(settings.launchAtStartup);
    } catch (error) {
      reportError('Launch at startup could not be applied', error);
    }
  }

  Future<void> _disposePlatformAfterFailedStart() async {
    try {
      await _platform.dispose();
    } catch (cleanupError) {
      AppLogger.warning('Desktop initialization cleanup failed: $cleanupError');
    }
  }

  Future<void> _restoreBackground(bool active) async {
    try {
      await _platform.setBackgroundEnabled(active);
      _backgroundActive = active;
    } catch (rollbackError) {
      _backgroundActive = false;
      AppLogger.warning('Desktop background rollback failed: $rollbackError');
    }
  }

  Future<void> _restoreLaunchAtStartup(bool enabled) async {
    try {
      await _platform.setLaunchAtStartup(enabled);
    } catch (rollbackError) {
      AppLogger.warning('Desktop startup rollback failed: $rollbackError');
    }
  }

  Future<void> _prepareForUpdate() async {
    await flush();
    // Cleanup failure must reach the coordinator before it can replace files.
    await _beforeQuit?.call();
  }

  Future<void> _quit() async {
    if (saving) {
      await flush();
    }

    try {
      await _beforeQuit?.call();
    } catch (error) {
      AppLogger.warning('Desktop shutdown cleanup failed: $error');
    }

    await _platform.quit();
  }

  Future<void> _shutdownPlatform() async {
    await flush();

    if (_platformInitialized) {
      await _platform.dispose();
      _platformInitialized = false;
    }
  }
}
