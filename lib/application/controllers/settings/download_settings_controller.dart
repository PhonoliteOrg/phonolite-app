import 'package:flutter/foundation.dart';

import 'package:phonolite_app/application/workflows/serial_action_queue.dart';
import 'package:phonolite_app/data/models/downloads/download_quality.dart';
import 'package:phonolite_app/data/models/preferences/download_settings.dart';
import 'package:phonolite_app/data/storage/logs/app_log.dart';
import 'package:phonolite_app/data/storage/preferences/download_settings_storage.dart';

/// Owns the default for future downloads; queued jobs retain their own profile.
class DownloadSettingsController extends ChangeNotifier {
  static final instance = DownloadSettingsController();

  final DownloadSettingsStorage _storage;
  final _saves = SerialActionQueue();
  DownloadSettings _settings = const DownloadSettings();
  DownloadSettings _savedSettings = const DownloadSettings();
  Future<void>? _initialization;
  int _mutation = 0;
  bool _ready = false;
  bool _loading = false;
  bool _saving = false;
  bool _disposed = false;
  String? _error;

  DownloadSettingsController({DownloadSettingsStorage storage = const DownloadSettingsStorage()}) : _storage = storage;

  DownloadSettings get settings => _settings;

  bool get ready => _ready;

  bool get saving => _saving;

  String? get error => _error;

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> retryInitialization() {
    if (_ready || _disposed) return Future<void>.value();
    if (_loading) return _initialization ?? Future<void>.value();

    _initialization = null;

    return initialize();
  }

  Future<void> flush() async {
    try {
      await _initialization;
    } catch (_) {
      // Loading errors are already presented; shutdown still drains accepted saves.
    }
    await _saves.drain();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> setQuality(DownloadQuality quality) {
    if (_disposed || !_ready || quality == _settings.quality) return Future<void>.value();

    final next = DownloadSettings(quality: quality);
    final mutation = ++_mutation;

    _settings = next;
    _saving = true;
    _error = null;
    final save = _saves.add(() => _save(next, mutation));
    notifyListeners();

    return save;
  }

  Future<void> _initialize() async {
    _loading = true;
    try {
      final settings = await _storage.read();

      if (_disposed) return;

      _settings = settings;
      _savedSettings = settings;
      _ready = true;
      _error = null;
    } catch (error) {
      _report('Could not load download settings', error);
      // A queue must not guess a quality when the device preference is unreadable.
      rethrow;
    } finally {
      _loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _save(DownloadSettings next, int mutation) async {
    try {
      await _storage.write(next);

      if (!_disposed) _savedSettings = next;
    } catch (error) {
      if (!_disposed && mutation == _mutation) {
        _settings = _savedSettings;
        _report('Could not save download settings', error);
      }
    } finally {
      if (!_disposed && mutation == _mutation) {
        _saving = false;
        notifyListeners();
      }
    }
  }

  void _report(String message, Object error) {
    if (_disposed) return;

    _error = '$message. $error';
    AppLogger.warning(_error!);
  }
}
