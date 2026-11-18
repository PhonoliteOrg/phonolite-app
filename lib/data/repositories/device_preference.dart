import 'package:flutter/foundation.dart';

import 'package:phonolite_app/data/storage/logs/app_log.dart';
import 'package:phonolite_app/data/structures/async/serial_action_queue.dart';

typedef UndoPreferenceChange = Future<void> Function();
typedef ApplyDevicePreference<T> = Future<UndoPreferenceChange?> Function(T next, T previous);

/// The preferences owner shares this state across every consumer of one typed setting.
class DevicePreference<T extends Object> extends ChangeNotifier {
  final String label;
  final Future<T> Function() _read;
  final Future<void> Function(T) _write;
  final _writes = SerialActionQueue();
  T _value;
  T _saved;
  Future<void>? _loading;
  int _revision = 0;
  bool _ready = false;
  bool _saving = false;
  String? _error;

  DevicePreference(T initial, {required this.label, required this._read, required this._write})
    : _value = initial,
      _saved = initial;

  T get value => _value;
  bool get ready => _ready;
  bool get saving => _saving;
  String? get error => _error;

  Future<void> load() {
    if (_ready) return Future.value();
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  Future<void> _load() async {
    try {
      _saved = _value = await _read();
      _ready = true;
      _error = null;
    } on Object catch (error) {
      _error = 'Could not load $label. $error';
      AppLogger.warning(_error!);
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  /// Publishes immediately. A platform operation can return its undo action so a
  /// failed disk write also restores the previous operating-system setting.
  Future<void> change(T next, {ApplyDevicePreference<T>? apply}) {
    if (!_ready || _value == next) return Future.value();
    final revision = ++_revision;
    _value = next;
    _saving = true;
    _error = null;
    final save = _writes.add(() async {
      UndoPreferenceChange? undo;
      try {
        if (apply != null) undo = await apply(next, _saved);
        await _write(next);
        _saved = next;
      } on Object catch (error) {
        if (undo != null) {
          try {
            await undo();
          } on Object catch (rollbackError) {
            AppLogger.warning('Could not restore $label: $rollbackError');
          }
        }
        if (revision == _revision) {
          _value = _saved;
          _error = 'Could not save $label. $error';
          AppLogger.warning(_error!);
        } else {
          AppLogger.warning('Could not save earlier $label: $error');
        }
      } finally {
        if (revision == _revision) {
          _saving = false;
          notifyListeners();
        }
      }
    });
    notifyListeners();
    return save;
  }

  Future<void> flush() => _writes.drain();
}
