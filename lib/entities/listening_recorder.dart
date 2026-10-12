import 'dart:math' as math;

/// Cheap playback accounting. This class never performs I/O or inspects PCM.
/// Context is captured at playback start, independently of the current login.
class ListeningRecorder {
  ListeningRecorder({
    required this.emit,
    required this.playbackId,
    Map<String, dynamic>? context,
    DateTime Function()? clock,
  }) : _context = context,
       _clock = clock ?? DateTime.now;

  final void Function(Map<String, dynamic>) emit;
  final int playbackId;
  final DateTime Function() _clock;
  Map<String, dynamic>? _context;
  int _sequence = 0;
  int _pendingMs = 0;
  int _remainder = 0;
  int _sampleUnitsPerSecond = 0;
  int? _startMs;
  int? _endMs;
  bool _heardAudio = false;
  bool _finished = false;

  bool get enabled => _context != null && !_finished;

  void setContext(Map<String, dynamic>? context) {
    if (context == null) {
      // Opt-out discards the uncommitted tail immediately.
      _pendingMs = 0;
      _remainder = 0;
      _startMs = _endMs = null;
    } else if (_context?['session_id'] != context['session_id']) {
      flush(endReason: 'interrupted');
      _heardAudio = false;
      _finished = false;
      _remainder = 0;
    }
    _context = context;
  }

  void addSamples(
    int samples, {
    required int sampleRate,
    required int channels,
  }) {
    if (_context == null || _finished || samples <= 0) return;
    final units = sampleRate * channels;
    if (units <= 0) return;
    if (_sampleUnitsPerSecond != units) {
      _remainder = 0;
      _sampleUnitsPerSecond = units;
    }
    _remainder += samples * 1000;
    final milliseconds = _remainder ~/ units;
    _remainder %= units;
    if (milliseconds <= 0) return;
    final now = _clock().toUtc().millisecondsSinceEpoch;
    _startMs ??= math.max(
      now - milliseconds,
      (_context!['session_started_at_ms'] as num?)?.toInt() ??
          now - milliseconds,
    );
    _endMs = math.max(now, _startMs! + _pendingMs + milliseconds);
    _pendingMs += milliseconds;
    _heardAudio = true;
    if (_pendingMs >= 15000) flush();
  }

  void flush({String? endReason}) {
    final context = _context;
    if (context == null || _finished) return;
    if (_pendingMs == 0 && (endReason == null || !_heardAudio)) return;
    final now = _clock().toUtc().millisecondsSinceEpoch;
    final start = math.max(
      _startMs ?? now,
      (context['session_started_at_ms'] as num?)?.toInt() ?? now,
    );
    final end = math.max(_endMs ?? now, start + _pendingMs);
    final event = <String, dynamic>{
      ...context,
      'event_id': '${context['session_id']}:$playbackId:${_sequence++}',
      'started_at_ms': start,
      'ended_at_ms': end,
      'listened_ms': _pendingMs,
      if (endReason != null) 'end_reason': endReason,
    };
    emit(event);
    _pendingMs = 0;
    _startMs = _endMs = null;
    if (endReason != null) _finished = true;
  }
}
