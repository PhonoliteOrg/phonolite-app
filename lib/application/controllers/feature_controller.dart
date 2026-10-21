import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:phonolite_app/application/workflows/request_generation.dart';
import 'package:phonolite_app/data/storage/logs/app_log.dart';

/// Screen-scoped functional state. The widget owns and disposes its controller.
/// Async completions may update state only while the controller is alive.
abstract class FeatureController extends ChangeNotifier {
  bool _disposed = false;
  Future<void>? _initialization;
  final _subscriptions = <StreamSubscription<Object?>>[];
  final _requests = <RequestGeneration>[];

  bool get isDisposed => _disposed;

  /// Starts feature I/O once, after inert construction and before view binding.
  /// The returned future completes when the initial work has finished.
  @nonVirtual
  Future<void> initialize() {
    if (_disposed) {
      return Future<void>.value();
    }

    final existing = _initialization;
    if (existing != null) {
      return existing;
    }

    final completion = Completer<void>();

    _initialization = completion.future;
    completion.complete(Future<void>.sync(initializeFeature));

    return completion.future;
  }

  @override
  void dispose() {
    _disposed = true;

    for (final requests in _requests) {
      requests.advance();
    }

    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }

    _subscriptions.clear();

    super.dispose();
  }

  /// Supplies initial feature work. Called once; asynchronous completions must
  /// continue to respect the controller's disposal and request-generation guards.
  @protected
  FutureOr<void> initializeFeature() {}

  /// Reports failures of initialization detached by a synchronous view lifecycle.
  void reportInitializationFailure(Object error, StackTrace stackTrace) {
    AppLogger.warning('$runtimeType could not initialize: $error');
  }

  /// Binds an external state stream to this controller's lifetime.
  @protected
  StreamSubscription<T> listenTo<T>(Stream<T> stream, void Function(T) onData) {
    assert(!_disposed);

    void deliverWhileAlive(T value) {
      if (!_disposed) {
        onData(value);
      }
    }

    final subscription = stream.listen(deliverWhileAlive);

    _subscriptions.add(subscription);

    return subscription;
  }

  /// Results captured before disposal can no longer be current afterwards.
  @protected
  RequestGeneration createRequestGeneration() {
    final requests = RequestGeneration(isActive: () => !_disposed);

    _requests.add(requests);

    return requests;
  }

  @protected
  void update(VoidCallback change) {
    if (_disposed) {
      return;
    }

    change();
    notifyListeners();
  }
}
