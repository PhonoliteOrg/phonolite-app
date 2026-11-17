import 'package:flutter/foundation.dart';

import 'package:phonolite_app/application/workflows/serial_action_queue.dart';
import 'package:phonolite_app/data/storage/logs/app_log.dart';

/// Shared lifecycle for device preferences that apply immediately and persist in order.
///
/// An accepted change becomes [settings] at once and is saved after every earlier accepted
/// change. When the newest save fails, [settings] returns to the last saved value and [error]
/// describes the failure. A failed save that a newer change has already superseded is logged
/// without undoing the user's newer choice.
///
/// Specializations supply [settingsLabel] and [persist], start loading through
/// [initializeOnce], and may narrow [acceptsChanges] for their own lifecycle.
abstract class PersistedSettingsController<T extends Object> extends ChangeNotifier {
  final SerialActionQueue _saves = SerialActionQueue();
  T _settings;
  T _savedSettings;
  Future<void>? _initialization;
  int _mutation = 0;
  bool _ready = false;
  bool _saving = false;
  bool _disposed = false;
  String? _error;

  PersistedSettingsController(T defaults) : _settings = defaults, _savedSettings = defaults;

  T get settings => _settings;

  /// Whether the stored value has been loaded and changes can be accepted.
  bool get ready => _ready;

  /// Whether an accepted change is still being saved.
  bool get saving => _saving;

  String? get error => _error;

  @protected
  bool get isDisposed => _disposed;

  /// The current initialization, when one has started.
  @protected
  Future<void>? get initialization => _initialization;

  /// Names these settings in messages, such as `display settings`.
  @protected
  String get settingsLabel;

  /// Whether [change] may accept a value now. Overrides should combine with `super`.
  @protected
  bool get acceptsChanges => ready && !_disposed;

  /// Waits for initialization and every accepted save, typically before application shutdown.
  /// Initialization failures were already reported, so they do not stop the drain.
  Future<void> flush() async {
    try {
      await _initialization;
    } on Object catch (_) {
      // Reported by the initialization owner; accepted saves still need to finish.
    }

    await _saves.drain();
  }

  @override
  @mustCallSuper
  void dispose() {
    _disposed = true;

    super.dispose();
  }

  /// Applies and stores [next], given the last successfully saved [previous] value.
  ///
  /// A specialization with side effects beyond storage undoes them before rethrowing;
  /// the base restores [settings] and reports the failure.
  @protected
  Future<void> persist(T next, T previous);

  /// Whether two values need no save between them. Defaults to `==`.
  @protected
  bool sameSettings(T first, T second) => first == second;

  /// Runs [load] on the first call and returns the same operation afterwards.
  @protected
  Future<void> initializeOnce(Future<void> Function() load) => _initialization ??= load();

  /// Allows a later [initializeOnce] to start a new attempt after a failed load.
  @protected
  void resetInitialization() {
    _initialization = null;
  }

  /// Reads the stored value and accepts it. A read failure is reported and rethrown;
  /// the specialization decides whether its startup can continue without the value.
  @protected
  Future<void> loadSettings(Future<T> Function() read) async {
    final T loaded;

    try {
      loaded = await read();
    } on Object catch (error) {
      reportError('Could not load $settingsLabel', error);
      notifyIfActive();

      rethrow;
    }

    if (_disposed) {
      return;
    }

    acceptLoadedSettings(loaded);
    notifyIfActive();
  }

  /// Installs a value read from storage as both the current and the last saved settings.
  @protected
  void acceptLoadedSettings(T loaded) {
    _settings = loaded;
    _savedSettings = loaded;
    _ready = true;
    _error = null;
  }

  /// Applies [next] immediately and completes once its save has been attempted.
  /// Save failures are reported through [error], not thrown.
  @protected
  Future<void> change(T next) {
    if (!acceptsChanges || sameSettings(next, _settings)) {
      return Future<void>.value();
    }

    final mutation = ++_mutation;

    _settings = next;
    _saving = true;
    _error = null;
    final save = _saves.add(() => _save(next, mutation));
    notifyIfActive();

    return save;
  }

  /// Records a failure as the current [error] and logs it.
  @protected
  void reportError(String message, Object error) {
    _error = '$message. $error';
    AppLogger.warning(_error!);
  }

  @protected
  void notifyIfActive() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> _save(T next, int mutation) async {
    try {
      await persist(next, _savedSettings);

      _savedSettings = next;
    } on Object catch (error) {
      if (mutation == _mutation) {
        _settings = _savedSettings;
        reportError('Could not save $settingsLabel', error);
      } else {
        // A newer queued value still holds the user's current choice.
        AppLogger.warning('Could not save earlier $settingsLabel: $error');
      }
    } finally {
      if (mutation == _mutation) {
        _saving = false;
        notifyIfActive();
      }
    }
  }
}
