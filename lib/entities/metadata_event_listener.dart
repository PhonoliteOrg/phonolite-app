import 'dart:async';

import 'models.dart';

/// Owns the lifecycle of a session's metadata stream and its pending updates.
/// The caller owns transport and applies domain changes. No I/O starts until
/// [start] is called, and [stop] invalidates queued work as well as timers.
class MetadataEventListener {
  MetadataEventListener({
    required Stream<MetadataUpdateEvent> Function() openStream,
    required bool Function(String baseUrl, String token) isSessionCurrent,
    required Future<void> Function(MetadataUpdateEvent) applyEvent,
    required void Function(String) onDiagnostic,
    this.debounceDelay = const Duration(milliseconds: 250),
    this.reconnectDelay = const Duration(seconds: 3),
  }) : _openStream = openStream,
       _isSessionCurrent = isSessionCurrent,
       _applyEvent = applyEvent,
       _onDiagnostic = onDiagnostic;

  final Stream<MetadataUpdateEvent> Function() _openStream;
  final bool Function(String, String) _isSessionCurrent;
  final Future<void> Function(MetadataUpdateEvent) _applyEvent;
  final void Function(String) _onDiagnostic;
  final Duration debounceDelay;
  final Duration reconnectDelay;
  StreamSubscription<MetadataUpdateEvent>? _subscription;
  Timer? _reconnectTimer;
  Timer? _debounce;
  final Map<String, MetadataUpdateEvent> _pending = {};
  Future<void> _chain = Future<void>.value();
  ({String baseUrl, String token})? _session;
  int _generation = 0;

  void start({required String baseUrl, required String token}) {
    if (token.isEmpty) return;
    final session = (baseUrl: baseUrl, token: token);
    if (_subscription != null && _session == session) return;
    stop();
    _session = session;
    final generation = _generation;
    try {
      _subscription = _openStream().listen(
        (event) {
          if (_isCurrent(generation)) _queue(event, generation);
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!_isCurrent(generation)) return;
          _onDiagnostic('Metadata event stream disconnected: $error');
          _subscription = null;
          _scheduleReconnect(generation);
        },
        onDone: () {
          if (!_isCurrent(generation)) return;
          _subscription = null;
          _scheduleReconnect(generation);
        },
        cancelOnError: true,
      );
    } catch (error) {
      _onDiagnostic('Metadata event stream disconnected: $error');
      _scheduleReconnect(generation);
    }
  }

  void stop() {
    _generation++;
    _session = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _debounce?.cancel();
    _debounce = null;
    _pending.clear();
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) unawaited(subscription.cancel());
  }

  bool _isCurrent(int generation) {
    final session = _session;
    return generation == _generation &&
        session != null &&
        _isSessionCurrent(session.baseUrl, session.token);
  }

  void _scheduleReconnect(int generation) {
    if (_reconnectTimer != null || !_isCurrent(generation)) return;
    _reconnectTimer = Timer(reconnectDelay, () {
      _reconnectTimer = null;
      if (!_isCurrent(generation)) return;
      final session = _session!;
      start(baseUrl: session.baseUrl, token: session.token);
    });
  }

  void _queue(MetadataUpdateEvent event, int generation) {
    _pending['${event.kind}:${event.id}'] = event;
    _debounce?.cancel();
    _debounce = Timer(debounceDelay, () {
      _debounce = null;
      _chain = _chain.then((_) => _flush(generation));
    });
  }

  Future<void> _flush(int generation) async {
    if (!_isCurrent(generation) || _pending.isEmpty) return;
    final events = _pending.values.toList(growable: false)
      ..sort((a, b) => a.revision.compareTo(b.revision));
    _pending.clear();
    for (final event in events) {
      if (!_isCurrent(generation)) return;
      try {
        await _applyEvent(event);
      } catch (error) {
        // One failed refresh must not poison the serial processing chain.
        _onDiagnostic('Metadata update failed: $error');
      }
    }
  }
}
