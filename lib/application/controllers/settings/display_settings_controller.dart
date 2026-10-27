import 'package:flutter/foundation.dart';

import 'package:phonolite_app/application/workflows/serial_action_queue.dart';
import 'package:phonolite_app/data/models/preferences/display_settings.dart';
import 'package:phonolite_app/data/storage/logs/app_log.dart';
import 'package:phonolite_app/data/storage/preferences/display_settings_storage.dart';

/// Application-owned display preferences, retained across server connections.
class DisplaySettingsController extends ChangeNotifier {
  static final instance = DisplaySettingsController();

  final DisplaySettingsStorage _storage;
  final _saves = SerialActionQueue();
  DisplaySettings _settings = const DisplaySettings();
  DisplaySettings _savedSettings = const DisplaySettings();
  Future<void>? _initialization;
  int _mutation = 0;
  bool _ready = false;
  bool _saving = false;
  bool _disposed = false;
  String? _error;

  DisplaySettingsController({DisplaySettingsStorage storage = const DisplaySettingsStorage()}) : _storage = storage;

  DisplaySettings get settings => _settings;

  bool get ready => _ready;

  bool get saving => _saving;

  String? get error => _error;

  Future<void> initialize() => _initialization ??= _initialize();

  /// Waits for initial loading and any accepted write before application shutdown.
  Future<void> flush() async {
    await _initialization;

    await _saves.drain();
  }

  @override
  void dispose() {
    _disposed = true;

    super.dispose();
  }

  Future<void> setLibraryLocalFirst(bool value) => _change(_settings.copyWith(libraryLocalFirst: value));

  Future<void> setPlaylistsLocalFirst(bool value) => _change(_settings.copyWith(playlistsLocalFirst: value));

  Future<void> setLikesLocalFirst(bool value) => _change(_settings.copyWith(likesLocalFirst: value));

  Future<void> _initialize() async {
    if (_disposed) {
      return;
    }

    try {
      final settings = await _storage.read();

      if (_disposed) {
        return;
      }

      _settings = settings;
      _savedSettings = settings;
      _ready = true;
      notifyListeners();
    } catch (error) {
      if (!_disposed) {
        _report('Could not load display settings', error);
        notifyListeners();
      }
    }
  }

  Future<void> _change(DisplaySettings next) {
    if (_disposed || !_ready || next == _settings) {
      return Future<void>.value();
    }

    final mutation = ++_mutation;

    _settings = next;
    _saving = true;
    _error = null;
    final save = _saves.add(() => _save(next, mutation));
    notifyListeners();

    return save;
  }

  Future<void> _save(DisplaySettings next, int mutation) async {
    try {
      await _storage.write(next);

      if (!_disposed) {
        _savedSettings = next;
      }
    } catch (error) {
      if (!_disposed) {
        if (mutation == _mutation) {
          _settings = _savedSettings;
          _report('Could not save display settings', error);
        } else {
          // A newer queued snapshot still contains the user's current choices.
          AppLogger.warning('Could not save earlier display settings: $error');
        }
      }
    } finally {
      if (mutation == _mutation) {
        _saving = false;

        if (!_disposed) {
          notifyListeners();
        }
      }
    }
  }

  void _report(String message, Object error) {
    _error = '$message. $error';
    AppLogger.warning(_error!);
  }
}
