import 'dart:convert';

/// Host-only collection. Streaming preserves events older than the VM's ring
/// buffer; a final snapshot supplies the newest, not-yet-streamed event blocks.
class UiTimelineCapture {
  UiTimelineCapture(this.startMicros);

  final int startMicros;
  final _events = <Map<String, dynamic>>[];
  final _seen = <String>{};

  Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List) return value.map(_canonical).toList();
    return value;
  }

  void add(Map<String, dynamic> event) {
    final timestamp = event['ts'];
    if (timestamp is num && timestamp < startMicros && event['ph'] != 'M') {
      return;
    }
    if (_seen.add(jsonEncode(_canonical(event)))) _events.add(event);
  }

  Map<String, Object?> finish(int endMicros) {
    final events = _events.where((event) {
      final timestamp = event['ts'];
      return event['ph'] == 'M' || timestamp is! num || timestamp <= endMicros;
    }).toList();
    return {
      'traceEvents': events,
      'capture': {
        'method': 'timeline_stream_plus_snapshot_tail',
        'start_us': startMicros,
        'end_us': endMicros,
        'event_count': events.length,
      },
    };
  }
}
