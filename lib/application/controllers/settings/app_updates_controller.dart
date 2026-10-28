import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:phonolite_app/data/models/updates/app_update_configuration.dart';
import 'package:phonolite_app/data/models/updates/app_update_release.dart';
import 'package:phonolite_app/data/storage/logs/app_log.dart';
import 'package:phonolite_app/infrastructure/platform/app/app_update_platform.dart';
import 'package:phonolite_app/infrastructure/updates/app_update_feed.dart';

class AppUpdatesController extends ChangeNotifier {
  static const checkInterval = Duration(hours: 2);
  static final instance = AppUpdatesController();

  final AppUpdatePlatform _platform;
  final AppUpdateFeed _feed;
  final bool Function()? _isSupported;
  Future<void>? _initialization;
  Future<void>? _installation;
  Timer? _checkTimer;
  AppUpdateConfiguration? _configuration;
  bool _ready = false;
  AppUpdateRelease? _latestRelease;
  bool _busy = false;
  bool _openingUpdater = false;
  int _generation = 0;
  String? _error;

  AppUpdatesController({AppUpdatePlatform? platform, AppUpdateFeed? feed, bool Function()? isSupported})
    : _platform = platform ?? WindowsAppUpdatePlatform(),
      _feed = feed ?? HttpAppUpdateFeed(),
      _isSupported = isSupported;

  bool get showInSettings => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  bool get supported => _isSupported?.call() ?? (showInSettings && !kDebugMode);

  String? get disabledReason => showInSettings && !supported && kDebugMode
      ? 'Update checks are disabled in debug builds. Use a release build to check for updates.'
      : null;

  bool get ready => _ready;

  AppUpdateRelease? get latestRelease => _latestRelease;

  bool get canCheckForUpdates => _ready && !_busy && _installation == null;

  bool get canInstall => canCheckForUpdates && _latestRelease != null;

  bool get busy => _busy;

  bool get openingUpdater => _openingUpdater;

  String? get error => _error;

  Future<void> initialize({required Future<void> Function() onInstall}) => _initialization ??= _initialize(onInstall);

  Future<void> shutdown() async {
    ++_generation;
    _checkTimer?.cancel();
    _checkTimer = null;
    _feed.close();

    if (supported && _initialization != null) {
      try {
        await _initialization;
        await _platform.dispose();
      } catch (error) {
        AppLogger.warning('App updater cleanup failed: $error');
      }
    }

    _ready = false;
    _busy = false;
    _openingUpdater = false;
    _latestRelease = null;
    _configuration = null;
    _installation = null;
    _initialization = null;
  }

  Future<void> installLatestUpdate() async {
    if (!canInstall) {
      return;
    }

    final generation = _generation;

    _busy = true;
    _openingUpdater = true;
    _error = null;
    notifyListeners();

    try {
      await _platform.showUpdate();
    } catch (error) {
      if (generation == _generation) {
        _report('Could not open the app updater', error);
      }
    } finally {
      if (generation == _generation) {
        _busy = false;
        _openingUpdater = false;
        notifyListeners();
      }
    }
  }

  Future<void> _initialize(Future<void> Function() onInstall) async {
    if (!supported) {
      return;
    }

    final generation = _generation;

    _busy = true;
    _error = null;
    notifyListeners();

    try {
      final configuration = await _platform.initialize(onInstall: () => _installation ??= Future<void>.sync(onInstall));

      if (generation != _generation) {
        return;
      }

      _ready = configuration.available;

      if (_ready) {
        _configuration = configuration;
        _checkTimer = Timer.periodic(checkInterval, (_) => unawaited(checkForUpdates()));
      } else {
        _error = 'Update checks are unavailable in this build.';
      }
    } catch (error) {
      if (generation != _generation) {
        return;
      }

      _report('Could not check for app updates', error);
    } finally {
      if (generation == _generation) {
        _busy = false;
        notifyListeners();
      }
    }

    if (generation == _generation && _ready) {
      await checkForUpdates();
    }
  }

  Future<void> checkForUpdates() async {
    final configuration = _configuration;

    if (!canCheckForUpdates || configuration == null) {
      return;
    }

    final generation = _generation;

    _busy = true;
    _error = null;
    notifyListeners();

    try {
      final release = await _feed.latest(configuration);

      if (generation == _generation) {
        _latestRelease = release;
      }
    } catch (error) {
      if (generation == _generation) {
        _latestRelease = null;
        _report('Could not check for app updates', error);
      }
    } finally {
      if (generation == _generation) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  void _report(String message, Object error) {
    _error = '$message. $error';
    AppLogger.warning(_error!);
  }
}
