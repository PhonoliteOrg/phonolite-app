import 'dart:async';

import 'package:phonolite_app/data/models/server/server_errors.dart';

/// Best-effort, ephemeral server playback presence, independent of listening
/// history consent. At most one request and one replacement are retained.
class PlaybackPresenceReporter {
  static const heartbeatInterval = Duration(seconds: 5);
  static const requestTimeout = Duration(seconds: 3);

  final String clientId;
  final Future<void> Function(String clientId, int sequence, bool playing) _send;
  final int Function()? _nextSequence;
  Timer? _heartbeat;
  (int, bool)? _pending;
  Future<void>? _draining;
  int _sequence = 0;
  bool _running = false;
  bool _playing = false;
  bool _closed = false;
  bool _unsupported = false;

  PlaybackPresenceReporter({
    required this.clientId,
    required Future<void> Function(String clientId, int sequence, bool playing) send,
    int Function()? nextSequence,
  }) : _send = send,
       _nextSequence = nextSequence;

  void update(bool playing) {
    if (_closed || _unsupported || playing == _playing) return;
    _playing = playing;
    _heartbeat?.cancel();
    _heartbeat = playing ? Timer.periodic(heartbeatInterval, (_) => _queue()) : null;
    _queue();
  }

  Future<void> close() {
    if (!_closed) {
      update(false);
      _closed = true;
      _heartbeat?.cancel();
      _heartbeat = null;
    }
    return _draining ?? Future<void>.value();
  }

  void _queue() {
    if (_unsupported) return;
    // Allocate before sending: a retired session's delayed stop must remain
    // older than a replacement session's start, even if requests finish late.
    _pending = (_nextSequence?.call() ?? ++_sequence, _playing);
    if (!_running) _draining = _drain();
  }

  Future<void> _drain() async {
    _running = true;
    try {
      while (_pending != null && !_unsupported) {
        final (sequence, playing) = _pending!;
        _pending = null;
        try {
          await _send(clientId, sequence, playing).timeout(requestTimeout);
        } on ApiException catch (error) {
          if (error.statusCode == 404) {
            _unsupported = true;
            _pending = null;
            _heartbeat?.cancel();
            _heartbeat = null;
          }
        } catch (_) {
          // The next heartbeat retries active playback. Lost stop reports
          // expire on the server without affecting audio or authentication.
        }
      }
    } finally {
      _running = false;
    }
  }
}
