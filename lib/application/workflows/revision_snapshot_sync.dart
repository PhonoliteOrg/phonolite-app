import 'dart:async';
import 'dart:math';

import 'package:phonolite_app/application/workflows/debounced_action.dart';
import 'package:phonolite_app/application/workflows/request_generation.dart';
import 'package:phonolite_app/data/models/server/revision_event.dart';
import 'package:phonolite_app/data/models/server/server_errors.dart';

/// Owns reconnects, bounded coalescing, retries and subscribe-before-snapshot recovery.
/// Revision comparison belongs to the domain: scalar and vector clocks share
/// the same lifecycle. Applying callbacks guard their own async state mutations.
/// Construction is inert; stop invalidates reads and awaits stream cancellation.
class RevisionSnapshotSync<TSnapshot, TRevision> {
  final Stream<RevisionEvent<TRevision>> Function() _openStream;
  final Future<TSnapshot> Function() _fetchSnapshot;
  final Future<void> Function(TSnapshot) _applySnapshot;
  final bool Function(String, String) _isSessionCurrent;
  final void Function(String) _onDiagnostic;
  final void Function()? _onUnauthorized;
  final void Function()? _onUnsupported;
  final TRevision Function(TSnapshot) _revisionOf;
  final TRevision Function(TRevision, TRevision) _merge;
  final bool Function(TRevision, TRevision) _isAhead;
  final bool Function(TRevision, TRevision) _isRollback;
  final Duration debounceDelay;
  final Duration retryDelay;
  final Duration reconnectDelay;
  final Duration maximumReconnectDelay;
  final Duration idleTimeout;
  final double reconnectJitter;
  final bool refreshUnchangedEvents;
  final Random _random;
  final _requests = RequestGeneration();
  final _debounce = DebouncedAction();

  ({String baseUrl, String token})? _session;
  StreamSubscription<RevisionEvent<TRevision>>? _subscription;
  Future<void> _cancellations = Future<void>.value();
  Future<void>? _refreshing;
  Timer? _reconnectTimer;
  Timer? _retryTimer;
  Timer? _idleTimer;
  int _connectionEpoch = 0;
  int _refreshEpoch = 0;
  TRevision? _observedRevision;
  TRevision? _appliedRevision;
  int _reconnectAttempts = 0;
  bool _ready = false;
  bool _dirty = false;
  bool _allowLowerRevision = false;

  RevisionSnapshotSync({
    required Stream<RevisionEvent<TRevision>> Function() openStream,
    required Future<TSnapshot> Function() fetchSnapshot,
    required Future<void> Function(TSnapshot) applySnapshot,
    required bool Function(String baseUrl, String token) isSessionCurrent,
    required void Function(String) onDiagnostic,
    required TRevision Function(TSnapshot) revisionOf,
    required TRevision Function(TRevision, TRevision) merge,
    required bool Function(TRevision, TRevision) isAhead,
    required bool Function(TRevision, TRevision) isRollback,
    void Function()? onUnauthorized,
    void Function()? onUnsupported,
    this.debounceDelay = const Duration(milliseconds: 250),
    this.retryDelay = const Duration(seconds: 2),
    this.reconnectDelay = const Duration(seconds: 1),
    this.maximumReconnectDelay = const Duration(seconds: 30),
    this.idleTimeout = const Duration(seconds: 45),
    this.reconnectJitter = 0.2,
    this.refreshUnchangedEvents = false,
    Random? random,
  }) : _openStream = openStream,
       _fetchSnapshot = fetchSnapshot,
       _applySnapshot = applySnapshot,
       _isSessionCurrent = isSessionCurrent,
       _onDiagnostic = onDiagnostic,
       _revisionOf = revisionOf,
       _merge = merge,
       _isAhead = isAhead,
       _isRollback = isRollback,
       _onUnauthorized = onUnauthorized,
       _onUnsupported = onUnsupported,
       _random = random ?? Random();

  TRevision? get appliedRevision => _appliedRevision;

  void start({required String baseUrl, required String token}) {
    final session = (baseUrl: baseUrl, token: token);

    if (token.isEmpty || _session == session) {
      return;
    }

    unawaited(stop());
    _session = session;
    _connect(_requests.current);
  }

  Future<void> stop() {
    _requests.advance();
    _session = null;
    _ready = false;
    _dirty = false;
    _allowLowerRevision = false;
    _observedRevision = null;
    _appliedRevision = null;
    _reconnectAttempts = 0;
    _connectionEpoch++;
    _refreshEpoch++;
    _debounce.cancel();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _idleTimer?.cancel();
    _idleTimer = null;

    final subscription = _subscription;
    _subscription = null;

    if (subscription != null) {
      _cancellations = Future.wait<void>([_cancellations, _cancel(subscription)]).then((_) {});
    }

    return _cancellations;
  }

  /// Requests a fresh snapshot, or reconnects if no stream is established.
  ///
  /// This schedules work; completion is observed through the applied snapshot.
  void refresh() {
    final generation = _requests.current;

    if (!_isCurrent(generation)) {
      return;
    }

    if (!_ready) {
      if (_subscription == null) {
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        _connect(generation);
      }

      return;
    }

    _refreshEpoch++;
    _dirty = true;
    _scheduleRefresh(generation, Duration.zero);
  }

  bool _isCurrent(int generation) {
    final session = _session;

    return _requests.isCurrent(generation) && session != null && _isSessionCurrent(session.baseUrl, session.token);
  }

  Future<void> _cancel(StreamSubscription<RevisionEvent<TRevision>> subscription) async {
    try {
      await subscription.cancel();
    } catch (error) {
      _onDiagnostic('Account event cancellation failed: $error');
    }
  }

  bool _handleTerminalError(Object error, {bool allowUnsupported = true}) {
    if (error is! ApiException) {
      return false;
    }

    final unauthorized = error.statusCode == 401 || error.statusCode == 403;
    final unsupported = allowUnsupported && (error.statusCode == 404 || error.statusCode == 405);

    if (!unauthorized && !unsupported) {
      return false;
    }

    unawaited(stop());

    if (unauthorized) {
      _onUnauthorized?.call();
    } else {
      _onUnsupported?.call();
    }

    return true;
  }

  void _watchConnection(int generation, int connectionEpoch) {
    _idleTimer?.cancel();
    _idleTimer = Timer(idleTimeout, () {
      if (!_isCurrent(generation) || connectionEpoch != _connectionEpoch) {
        return;
      }

      final subscription = _subscription;
      _subscription = null;

      if (subscription != null) {
        _cancellations = Future.wait<void>([_cancellations, _cancel(subscription)]).then((_) {});
      }

      _disconnected(generation, connectionEpoch);
    });
  }

  void _connect(int generation) {
    if (!_isCurrent(generation) || _subscription != null) {
      return;
    }

    _ready = false;
    final connectionEpoch = ++_connectionEpoch;
    _watchConnection(generation, connectionEpoch);

    void receive(RevisionEvent<TRevision> event) {
      if (_isCurrent(generation) && connectionEpoch == _connectionEpoch) {
        _watchConnection(generation, connectionEpoch);
        _receive(event, generation);
      }
    }

    void fail(Object error, StackTrace stackTrace) {
      if (!_isCurrent(generation) || connectionEpoch != _connectionEpoch) {
        return;
      }

      _subscription = null;
      _onDiagnostic('Account event stream disconnected: $error');

      if (!_handleTerminalError(error)) {
        _disconnected(generation, connectionEpoch);
      }
    }

    try {
      _subscription = _openStream().listen(
        receive,
        onError: fail,
        onDone: () => _disconnected(generation, connectionEpoch),
        cancelOnError: true,
      );
    } catch (error, stackTrace) {
      fail(error, stackTrace);
    }
  }

  void _disconnected(int generation, int connectionEpoch) {
    if (!_isCurrent(generation) || connectionEpoch != _connectionEpoch) {
      return;
    }

    _subscription = null;
    _ready = false;
    _connectionEpoch++;
    _idleTimer?.cancel();
    _idleTimer = null;
    _debounce.cancel();
    _retryTimer?.cancel();
    _retryTimer = null;

    if (_reconnectTimer != null) {
      return;
    }

    final multiplier = 1 << min(_reconnectAttempts++, 10);
    final milliseconds = min(reconnectDelay.inMilliseconds * multiplier, maximumReconnectDelay.inMilliseconds);
    final jitter = 1 + (_random.nextDouble() * 2 - 1) * reconnectJitter;
    final delay = Duration(milliseconds: max(0, (milliseconds * jitter).round()));

    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      _connect(generation);
    });
  }

  void _receive(RevisionEvent<TRevision> event, int generation) {
    if (event.kind == RevisionEventKind.ready) {
      _ready = true;
      _reconnectAttempts = 0;
      _observedRevision = event.revision;
      _allowLowerRevision = true;
      _refreshEpoch++;
      _dirty = true;
      _scheduleRefresh(generation, Duration.zero);

      return;
    }

    if (!_ready) {
      return;
    }

    final appliedRevision = _appliedRevision;

    if (event.kind == RevisionEventKind.revision &&
        appliedRevision != null &&
        _isRollback(event.revision, appliedRevision)) {
      _observedRevision = event.revision;
      _allowLowerRevision = true;
      _refreshEpoch++;
      _dirty = true;
    } else {
      final observed = _observedRevision;
      _observedRevision = observed == null ? event.revision : _merge(observed, event.revision);
      _dirty =
          _dirty ||
          (refreshUnchangedEvents && event.kind == RevisionEventKind.changed) ||
          appliedRevision == null ||
          _isAhead(_observedRevision as TRevision, appliedRevision);
    }

    if (_dirty) {
      _scheduleRefresh(generation, debounceDelay);
    }
  }

  void _scheduleRefresh(int generation, Duration delay) {
    if (delay == Duration.zero) {
      _debounce.cancel();
      _startRefresh(generation);

      return;
    }

    _debounce.schedule(delay, () => _startRefresh(generation));
  }

  void _startRefresh(int generation) {
    if (!_isCurrent(generation) || !_ready || !_dirty || _refreshing != null || _retryTimer != null) {
      return;
    }

    final connectionEpoch = _connectionEpoch;
    _refreshing = _reconcile(generation, connectionEpoch).whenComplete(() {
      _refreshing = null;
      final currentGeneration = _requests.current;

      if (_isCurrent(currentGeneration) && _ready && _dirty && _retryTimer == null) {
        _scheduleRefresh(currentGeneration, debounceDelay);
      }
    });
  }

  Future<void> _reconcile(int generation, int connectionEpoch) async {
    final refreshEpoch = _refreshEpoch;
    final allowLowerRevision = _allowLowerRevision;
    var applyingSnapshot = false;

    bool isCurrent() => _isCurrent(generation) && _ready && connectionEpoch == _connectionEpoch;

    try {
      final snapshot = await _fetchSnapshot();

      if (!isCurrent() || refreshEpoch != _refreshEpoch) {
        return;
      }

      final appliedRevision = _appliedRevision;

      if (!allowLowerRevision && appliedRevision != null && _isRollback(_revisionOf(snapshot), appliedRevision)) {
        throw const FormatException('Account snapshot is older than applied state');
      }

      applyingSnapshot = true;
      await _applySnapshot(snapshot);

      if (!isCurrent() || refreshEpoch != _refreshEpoch) {
        return;
      }

      _appliedRevision = _revisionOf(snapshot);
      _allowLowerRevision = false;
      final observed = _observedRevision;
      _dirty = observed != null && _isAhead(observed, _revisionOf(snapshot));
    } catch (error) {
      if (!isCurrent()) {
        return;
      }

      _onDiagnostic('Account snapshot reconciliation failed: $error');

      if (_handleTerminalError(error, allowUnsupported: !applyingSnapshot)) {
        return;
      }

      _dirty = true;
      _retryTimer = Timer(retryDelay, () {
        _retryTimer = null;
        _startRefresh(generation);
      });
    }
  }
}
