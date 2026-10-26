import 'package:flutter/foundation.dart';

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
  DesktopSettings _settings = const DesktopSettings();
  Future<void>? _initialization;
  Future<void>? _quitting;
  Future<void> Function()? _beforeQuit;
  bool _ready = false;
  bool _backgroundActive = false;
  bool _saving = false;
  String? _error;

  DesktopSettingsController({
    DesktopSettingsStorage storage = const DesktopSettingsStorage(),
    DesktopLifecyclePlatform? platform,
    bool Function()? isSupported,
  }) : _storage = storage,
       _platform = platform ?? NativeDesktopLifecyclePlatform(),
       _isSupported = isSupported ?? (() => desktopLifecycleSupported);

  bool get supported => _isSupported();
  DesktopSettings get settings => _settings;
  bool get ready => _ready;
  bool get saving => _saving;
  String? get error => _error;

  Future<void> initialize({required Future<void> Function() beforeQuit}) => _initialization ??= _initialize(beforeQuit);

  Future<void> _initialize(Future<void> Function() beforeQuit) async {
    if (!supported) {
      return;
    }

    _beforeQuit = beforeQuit;
    _saving = true;

    try {
      _settings = await _storage.read();
      await _platform.initialize(onClose: closeWindow, onQuit: quit);
      _ready = true;
    } catch (error) {
      _saving = false;
      try {
        await _platform.dispose();
      } catch (cleanupError) {
        AppLogger.warning('Desktop initialization cleanup failed: $cleanupError');
      }

      _report('Desktop integration could not start', error);
      notifyListeners();

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
    notifyListeners();
  }

  Future<void> setLaunchAtStartup(bool enabled) => _change(_settings.copyWith(launchAtStartup: enabled), startup: true);

  Future<void> setRunInBackground(bool enabled) =>
      _change(_settings.copyWith(runInBackground: enabled), startup: false);

  Future<void> _change(DesktopSettings next, {required bool startup}) async {
    if (!_ready || _saving || _quitting != null) {
      return;
    }

    _saving = true;
    _error = null;
    notifyListeners();

    final previous = _settings;

    Future<void> apply(DesktopSettings value) => startup
        ? _platform.setLaunchAtStartup(value.launchAtStartup)
        : _platform.setBackgroundEnabled(value.runInBackground);

    try {
      await apply(next);
      await _storage.write(next);

      _settings = next;

      if (!startup) {
        _backgroundActive = next.runInBackground;
      }
    } catch (error) {
      try {
        await apply(previous);
      } catch (rollbackError) {
        _backgroundActive = false;
        AppLogger.warning('Desktop setting rollback failed: $rollbackError');
      }

      _report('Could not save the desktop setting', error);
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  Future<void> closeWindow() async {
    if (_quitting != null || _saving) {
      return;
    }

    if (_backgroundActive) {
      await _platform.hide();
    } else {
      await quit();
    }
  }

  Future<void> quit() => _quitting ??= _quit();

  Future<void> _quit() async {
    try {
      await _beforeQuit?.call();
    } catch (error) {
      AppLogger.warning('Desktop shutdown cleanup failed: $error');
    }

    await _platform.quit();
  }

  /// The application owner calls this before releasing its notifier.
  Future<void> shutdown() async {
    if (supported && _ready) {
      await _platform.dispose();
      _ready = false;
    }
  }

  void _report(String message, Object error) {
    _error = '$message. $error';
    AppLogger.warning(_error!);
  }
}
