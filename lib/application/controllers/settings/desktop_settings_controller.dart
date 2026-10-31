import 'package:flutter/foundation.dart';

import 'package:phonolite_app/application/workflows/serial_action_queue.dart';
import 'package:phonolite_app/data/models/preferences/desktop_settings.dart';
import 'package:phonolite_app/data/storage/logs/app_log.dart';
import 'package:phonolite_app/data/storage/preferences/desktop_settings_storage.dart';
import 'package:phonolite_app/infrastructure/platform/app/desktop_lifecycle_platform.dart';

/// One application-owned lifecycle, independent of sign-in and local-data resets.
class DesktopSettingsController extends ChangeNotifier {
  static final instance = DesktopSettingsController();

  final DesktopSettingsStorage _storage;
  final DesktopLifecyclePlatform _platform;
  final bool Function() _isSupported;
  final SerialActionQueue _changes = SerialActionQueue();
  DesktopSettings _settings = const DesktopSettings();
  DesktopSettings _savedSettings = const DesktopSettings();
  Future<void>? _initialization;
  Future<void>? _quitting;
  Future<void>? _updatePreparation;
  Future<void>? _shutdown;
  Future<void> Function()? _beforeQuit;
  int _mutation = 0;
  bool _ready = false;
  bool _platformInitialized = false;
  bool _backgroundActive = false;
  bool _saving = false;
  bool _disposed = false;
  String? _error;

  DesktopSettingsController({
    this._storage = const DesktopSettingsStorage(),
    DesktopLifecyclePlatform? platform,
    bool Function()? isSupported,
  }) : _platform = platform ?? NativeDesktopLifecyclePlatform(),
       _isSupported = isSupported ?? (() => desktopLifecycleSupported);

  bool get supported => _isSupported();

  DesktopSettings get settings => _settings;

  bool get ready => _ready;

  bool get saving => _saving;

  String? get error => _error;

  Future<void> initialize({required Future<void> Function() beforeQuit}) {
    if (_disposed || _shutdown != null) {
      return Future<void>.value();
    }

    return _initialization ??= _initialize(beforeQuit);
  }

  /// The application owner calls this before releasing its notifier.
  Future<void> shutdown() => _shutdown ??= _shutdownPlatform();

  @override
  void dispose() {
    _disposed = true;

    super.dispose();
  }

  Future<void> setLaunchAtStartup(bool enabled) => _change(_settings.copyWith(launchAtStartup: enabled));

  Future<void> setRunInBackground(bool enabled) => _change(_settings.copyWith(runInBackground: enabled));

  Future<void> closeWindow() async {
    if (!_ready || _disposed || _quitting != null || _updatePreparation != null || _shutdown != null) {
      return;
    }

    if (_saving) {
      await _changes.drain();
    }

    if (_disposed || _quitting != null || _updatePreparation != null || _shutdown != null) {
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

  Future<void> _initialize(Future<void> Function() beforeQuit) async {
    if (!supported) {
      return;
    }

    _beforeQuit = beforeQuit;
    _saving = true;

    try {
      _settings = await _storage.read();
      _savedSettings = _settings;

      if (_disposed) {
        return;
      }

      await _platform.initialize(onClose: closeWindow, onQuit: quit);
      _platformInitialized = true;
    } catch (error) {
      _saving = false;

      try {
        await _platform.dispose();
      } catch (cleanupError) {
        AppLogger.warning('Desktop initialization cleanup failed: $cleanupError');
      }

      _report('Desktop integration could not start', error);
      _notify();

      return;
    }

    // One unavailable OS integration must not prevent the other from working.
    try {
      await _platform.setBackgroundEnabled(_settings.runInBackground);
      _backgroundActive = _settings.runInBackground;
    } catch (error) {
      _report('Background mode could not start', error);
    }

    try {
      await _platform.setLaunchAtStartup(_settings.launchAtStartup);
    } catch (error) {
      _report('Launch at startup could not be applied', error);
    }

    _saving = false;
    _ready = !_disposed && _shutdown == null;
    _notify();
  }

  Future<void> _change(DesktopSettings next) {
    if (!_ready ||
        _disposed ||
        _quitting != null ||
        _updatePreparation != null ||
        _shutdown != null ||
        _sameSettings(next, _settings)) {
      return Future<void>.value();
    }

    final mutation = ++_mutation;

    _settings = next;
    _saving = true;
    _error = null;
    final save = _changes.add(() => _save(next, mutation));
    _notify();

    return save;
  }

  Future<void> _save(DesktopSettings next, int mutation) async {
    final previous = _savedSettings;
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
      _savedSettings = next;
    } catch (error) {
      if (backgroundAttempted) {
        try {
          await _platform.setBackgroundEnabled(backgroundWasActive);
          _backgroundActive = backgroundWasActive;
        } catch (rollbackError) {
          _backgroundActive = false;
          AppLogger.warning('Desktop background rollback failed: $rollbackError');
        }
      }

      if (startupAttempted) {
        try {
          await _platform.setLaunchAtStartup(previous.launchAtStartup);
        } catch (rollbackError) {
          AppLogger.warning('Desktop startup rollback failed: $rollbackError');
        }
      }

      if (mutation == _mutation) {
        _settings = _savedSettings;
        _report('Could not save the desktop setting', error);
      } else {
        AppLogger.warning('Could not save earlier desktop settings: $error');
      }
    } finally {
      if (mutation == _mutation) {
        _saving = false;
        _notify();
      }
    }
  }

  Future<void> _prepareForUpdate() async {
    await _initialization;
    await _changes.drain();
    // Cleanup failure must reach the coordinator before it can replace files.
    await _beforeQuit?.call();
  }

  Future<void> _quit() async {
    if (_saving) {
      await _initialization;
      await _changes.drain();
    }

    try {
      await _beforeQuit?.call();
    } catch (error) {
      AppLogger.warning('Desktop shutdown cleanup failed: $error');
    }

    await _platform.quit();
  }

  Future<void> _shutdownPlatform() async {
    _ready = false;
    await _initialization;
    await _changes.drain();

    if (_platformInitialized) {
      await _platform.dispose();
      _platformInitialized = false;
    }
  }

  bool _sameSettings(DesktopSettings first, DesktopSettings second) =>
      first.launchAtStartup == second.launchAtStartup && first.runInBackground == second.runInBackground;

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _report(String message, Object error) {
    _error = '$message. $error';
    AppLogger.warning(_error!);
  }
}
