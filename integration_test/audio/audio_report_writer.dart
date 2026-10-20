import 'dart:convert';
import 'dart:io';

/// Host-only report writer; raw observations never enter production builds.
Future<void> writeAudioReport(
  Directory destination,
  Map<String, dynamic> data,
) async {
  await destination.create(recursive: true);
  const encoder = JsonEncoder.withIndent('  ');
  Future<void> json(String name, Object? value) => File(
    '${destination.path}/$name.json',
  ).writeAsString(encoder.convert(value));
  final journeys = (data['journeys'] as List? ?? []).cast<Map>();
  final selected = (data['selected_journeys'] as List? ?? []).cast<String>();
  final unrun = selected
      .where((id) => !journeys.any((j) => j['id'] == id))
      .toList();
  final summaries = <Map>[];
  final report = StringBuffer('''# Phonolite audio profile

Run: ${data['run_status']} · ${data['build_mode']} · ${data['platform']}
Timeline capture: ${data['capture_timeline'] == false ? 'disabled' : 'enabled'}

${data['control_suite'] == true ? 'Visible compact/expanded playbar gestures → production controller → native audio output. Controller calls are used for fixture setup and restoration. Independent wire probes inspect the same server/track quality profiles after playback stops.' : 'Real controller → transport/cache → decoder → native output. Navigation creates UI load during the sustained streaming case. This suite issues controller commands; it does not count them as on-screen gesture coverage.'}

| Scenario | Result | First native progress ms | Progress/wall | Stalls | Refills | Errors | Note |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
''');
  for (final journey in journeys) {
    final id = journey['id'] as String;
    if (!RegExp(r'^audio\.[a-z0-9_]+$').hasMatch(id)) {
      throw FormatException('Invalid audio scenario ID');
    }
    final audio = journey['audio'] as Map?;
    final metrics = audio?['metrics'] as Map? ?? {};
    final ratio = metrics['rendered_to_wall_ratio'] as num?;
    final issues = (metrics['issues'] as List? ?? []).join('; ');
    final note =
        journey['reason'] ??
        (issues.isEmpty ? metrics['sample_quality'] ?? '' : issues);
    report.writeln(
      '| $id | ${journey['status']} | ${metrics['first_output_progress_ms'] ?? '—'} | '
      '${ratio?.toStringAsFixed(3) ?? '—'} | ${metrics['stall_count'] ?? '—'} | '
      '${metrics['rebuffer_count'] ?? '—'} | ${metrics['engine_error_count'] ?? '—'} | '
      '${'$note'.replaceAll('|', r'\|').replaceAll('\n', ' ')} |',
    );
    await json('$id.frames', {...journey}..remove('audio'));
    if (audio != null) await json('$id.audio', audio);
    summaries.add(
      {
        ...journey,
        if (audio != null) 'audio': {'metrics': metrics},
      }..remove('frames'),
    );
  }
  await json('run', {...data, 'journeys': summaries, 'unrun_journeys': unrun});
  final wires = journeys.where((j) => j['wire'] != null).toList();
  if (wires.isNotEmpty) {
    report.writeln('\n## Encoded quality samples\n');
    report.writeln(
      '| Quality | Header target kbps | Encoded payload kbps | Packets | Media ms |',
    );
    report.writeln('| --- | ---: | ---: | ---: | ---: |');
    for (final journey in wires) {
      final wire = journey['wire'] as Map;
      final header = wire['header'] as Map? ?? {};
      report.writeln(
        '| ${wire['requested_quality']} | ${(header['bitrate_bps'] as num?) == null ? '—' : (header['bitrate_bps'] as num) / 1000} | '
        '${(wire['encoded_payload_kbps'] as num?)?.toStringAsFixed(1) ?? '—'} | '
        '${wire['packet_count']} | ${wire['encoded_media_ms']} |',
      );
    }
    report.writeln(
      '\nPayload rate uses encoded bytes / media duration, not network burst download speed. '
      'Opus variable bitrate may differ from the declared encoder target. These independent requests '
      'are distinct from the playback connection; the UI cases separately check the exact engine request and real output.',
    );
  }
  final controlChecks = journeys.where((j) => j['checks'] != null).toList();
  if (controlChecks.isNotEmpty) {
    report.writeln('\n## Observed control effects\n');
    for (final journey in controlChecks) {
      report.writeln(
        '- **${journey['id']} (${journey['status']})**: '
        '${jsonEncode(journey['checks'])}',
      );
    }
  }
  if (data['cleanup_errors'] != null) {
    report.writeln(
      '\nRestoration errors: ${jsonEncode(data['cleanup_errors'])}.',
    );
  }
  if (unrun.isNotEmpty) report.writeln('\nNot run: ${unrun.join(', ')}.');
  report.writeln('''

First native progress includes the engine's 250 ms reporting cadence and native buffer-completion latency. It is an upper-bound proxy for first sound, not an acoustic measurement. Seek latency requires progress near the requested position.

Progress/wall compares completed-output position with monotonic wall time after initial progress. A ratio below 0.95 fails. Steady output needs at least two seconds of observations. Pause allows 750 ms for callbacks in flight, then permits at most 100 ms drift.

Stalls are observed no-progress intervals of at least ${data['stall_threshold_ms'] ?? 750} ms, including a trailing stall. Shorter glitches can be missed. Buffer-low events are engine refills, not a hardware underrun counter. Sparse telemetry (fewer than 8 observations or steady gaps over 1000 ms) is inconclusive and fails validation. Intentional pause/seek/startup are measured separately.

The native output exposes no underrun counter; it is reported as null. Buffered-ahead includes encoded network cache, not just queued PCM. No microphone/loopback recording was taken: routing, volume, silence in the source, distortion, pops and sub-threshold dropouts require acoustic capture or listening.

Per-scenario `.audio.json` contains metrics, raw observations and categorized events. `.frames.json` and `.timeline.json` retain UI frame timings and host traces. Reports stay local. Missing downloads/session/catalog prerequisites are skipped, never counted as verified audio.
''');
  await File('${destination.path}/REPORT.md').writeAsString(report.toString());
}
