import 'dart:async';

import 'package:phonolite_app/application/workflows/debounced_action.dart';
import 'package:phonolite_app/application/workflows/request_generation.dart';
import 'package:phonolite_app/data/models/library/metadata_update_event.dart';

/// Owns the lifecycle of a session's metadata stream and its pending updates.
/// The caller owns transport and applies domain changes. No I/O starts until
/// [start] is called, and [stop] invalidates queued work as well as timers.
class MetadataEventListener {
  final Stream<MetadataUpdateEvent> Function() _openStream;
  final bool Function(String, String) _isSessionCurrent;
  final Future<void> Function(MetadataUpdateEvent) _applyEvent;
  final void Function(String) _onDiagnostic;
  final void Function()? _onSessionInvalidated;
  final Duration debounceDelay;
  final Duration reconnectDelay;
  final int maxPending;
  StreamSubscription<MetadataUpdateEvent>? _subscription;
  Future<void> _cancellations = Future<void>.value();
  Timer? _reconnectTimer;
  final _debounce = DebouncedAction();
  final Map<String, MetadataUpdateEvent> _pending = {};
  bool _resyncPending = false;
  Future<void>? _flushFuture;
  bool _flushReady = false;
  ({String baseUrl, String token})? _session;
  final _requests = RequestGeneration();

  MetadataEventListener({
    required Stream<MetadataUpdateEvent> Function() openStream,
    required bool Function(String baseUrl, String token) isSessionCurrent,
    required Future<void> Function(MetadataUpdateEvent) applyEvent,
    required void Function(String) onDiagnostic,
    void Function()? onSessionInvalidated,
    this.debounceDelay = const Duration(milliseconds: 250),
    this.reconnectDelay = const Duration(seconds: 3),
    this.maxPending = 128,
  }) : _openStream = openStream,
       _isSessionCurrent = isSessionCurrent,
       _applyEvent = applyEvent,
       _onDiagnostic = onDiagnostic,
       _onSessionInvalidated = onSessionInvalidated;

  void start({required String baseUrl, required String token}) {
    if (token.isEmpty) {
      return;
    }

    final session = (baseUrl: baseUrl, token: token);

    if (_subscription != null && _session == session) {
      return;
    }

    unawaited(stop());
    _session = session;
    final generation = _requests.current;

    try {
      void handleStreamDone() {
        if (!_isCurrent(generation)) {
          return;
        }

        _subscription = null;
        _scheduleReconnect(generation);
      }

      void handleStreamError(Object error, StackTrace stackTrace) {
        if (!_isCurrent(generation)) {
          return;
        }

        _onDiagnostic('Metadata event stream disconnected: $error');
        _subscription = null;
        _scheduleReconnect(generation);
      }

      void handleMetadataEvent(MetadataUpdateEvent event) {
        if (_isCurrent(generation)) {
          if (event.kind == 'session_invalidated' && event.id == 'server_keys_rotated') {
            unawaited(stop());
            _onSessionInvalidated?.call();
            return;
          }
          _queue(event, generation);
        }
      }

      _subscription = _openStream().listen(
        handleMetadataEvent,
        onError: handleStreamError,
        onDone: handleStreamDone,
        cancelOnError: true,
      );
    } catch (error) {
      _onDiagnostic('Metadata event stream disconnected: $error');
      _scheduleReconnect(generation);
    }
  }

  /// Invalidates work immediately and waits for all outstanding subscriptions
  /// to finish cancelling, including subscriptions from previous sessions.
  Future<void> stop() {
    _requests.advance();
    _session = null;

    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    _debounce.cancel();
    _pending.clear();
    _resyncPending = false;
    _flushReady = false;

    final subscription = _subscription;

    _subscription = null;

    if (subscription != null) {
      _cancellations = Future.wait<void>([_cancellations, _cancelSubscription(subscription)]).then((_) {});
    }

    return _cancellations;
  }

  Future<void> _cancelSubscription(StreamSubscription<MetadataUpdateEvent> subscription) async {
    try {
      await subscription.cancel();
    } catch (error) {
      _onDiagnostic('Metadata event stream cancellation failed: $error');
    }
  }

  bool _isCurrent(int generation) {
    final session = _session;

    return _requests.isCurrent(generation) && session != null && _isSessionCurrent(session.baseUrl, session.token);
  }

  void _scheduleReconnect(int generation) {
    if (_reconnectTimer != null || !_isCurrent(generation)) {
      return;
    }

    void reconnectSession() {
      _reconnectTimer = null;

      if (!_isCurrent(generation)) {
        return;
      }

      final session = _session!;

      start(baseUrl: session.baseUrl, token: session.token);
    }

    _reconnectTimer = Timer(reconnectDelay, reconnectSession);
  }

  void _queue(MetadataUpdateEvent event, int generation) {
    if (_resyncPending || _pending.length >= maxPending) {
      _pending.clear();
      _pending['resync:catalogue'] = MetadataUpdateEvent(
        revision: event.revision,
        kind: 'resync',
        id: 'catalogue',
        updatedAt: event.updatedAt,
      );
      _resyncPending = true;
    } else {
      final key = event.kind == 'catalogue' ? 'catalogue' : '${event.kind}:${event.id}';
      _pending[key] = event;
    }
    _debounce.schedule(debounceDelay, () {
      _flushReady = true;
      _startFlush(generation);
    });
  }

  void _startFlush(int generation) {
    if (_flushFuture != null || !_isCurrent(generation) || !_flushReady) {
      return;
    }

    _flushReady = false;
    _flushFuture = _flush(generation).whenComplete(() {
      _flushFuture = null;
      final currentGeneration = _requests.current;

      if (_isCurrent(currentGeneration) && _pending.isNotEmpty && _flushReady) {
        _startFlush(currentGeneration);
      }
    });
  }

  Future<void> _flush(int generation) async {
    if (!_isCurrent(generation) || _pending.isEmpty) {
      return;
    }

    final events = _pending.values.toList(growable: false);

    events.sort((a, b) => a.revision.compareTo(b.revision));
    _pending.clear();
    _resyncPending = false;

    for (final event in events) {
      if (!_isCurrent(generation) || _resyncPending) {
        return;
      }

      try {
        await _applyEvent(event);
      } catch (error) {
        // One failed refresh must not poison the serial processing chain.
        _onDiagnostic('Metadata update failed: $error');
      }
    }
  }
}
