import 'package:flutter/foundation.dart';

import 'package:phonolite_app/data/repositories/device_preference.dart';
import 'package:phonolite_app/data/storage/logs/app_log.dart';

/// Binds a feature's lifetime to the shared device setting. Disposing a binding
/// ends its notifications while already accepted preference writes finish.
abstract class PersistedSettingsController<T extends Object> extends ChangeNotifier {
  final DevicePreference<T> preference;
  Future<void>? _initialization;
  String? _platformError;
  bool _disposed = false;

  PersistedSettingsController(this.preference) {
    preference.addListener(notifyIfActive);
  }

  T get settings => preference.value;
  bool get ready => preference.ready;
  bool get saving => preference.saving;
  String? get error => _platformError ?? preference.error;

  @protected
  bool get isDisposed => _disposed;
  @protected
  Future<void>? get initialization => _initialization;
  @protected
  bool get acceptsChanges => ready && !_disposed;

  @protected
  Future<void> initializeOnce(Future<void> Function() load) => _initialization ??= load();

  @protected
  void resetInitialization() => _initialization = null;

  @protected
  Future<void> change(T next, {ApplyDevicePreference<T>? apply}) {
    if (!acceptsChanges) return Future.value();
    _platformError = null;
    return preference.change(next, apply: apply);
  }

  @protected
  void reportError(String message, Object error) {
    _platformError = '$message. $error';
    AppLogger.warning(_platformError!);
  }

  @protected
  void notifyIfActive() {
    if (!_disposed) notifyListeners();
  }

  Future<void> flush() async {
    try {
      await _initialization;
    } on Object catch (_) {
      // Initialization errors are reported by the preference or platform owner.
    }
    await preference.flush();
  }

  @override
  void dispose() {
    _disposed = true;
    preference.removeListener(notifyIfActive);
    super.dispose();
  }
}
