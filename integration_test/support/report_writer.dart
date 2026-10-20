import 'dart:convert';
import 'dart:io';

String _journeyId(String id) {
  if (!RegExp(r'^[a-z][a-z0-9_.]*$').hasMatch(id)) {
    throw FormatException('Invalid journey ID');
  }
  return id;
}

Future<void> writeUiTimeline(
  Directory destination,
  String id,
  Object timeline,
) async {
  await destination.create(recursive: true);
  await File(
    '${destination.path}/${_journeyId(id)}.timeline.json',
  ).writeAsString(jsonEncode(timeline));
}

/// Host-only writer. Tests and phone app do no report filesystem I/O.
Future<void> writeUiReport(
  Directory destination,
  Map<String, dynamic> data,
  List<Map<String, dynamic>> catalog,
) async {
  await destination.create(recursive: true);
  const encoder = JsonEncoder.withIndent('  ');
  Future<void> json(String name, Object? value) => File(
    '${destination.path}/$name.json',
  ).writeAsString(encoder.convert(value));
  final journeys = (data['journeys'] as List? ?? []).cast<Map>();
  final covered = journeys
      .where((j) => j['status'] == 'passed')
      .expand((j) => (j['covered_interactions'] as List? ?? []).cast<String>())
      .toSet();
  final coverage = [
    for (final item in catalog)
      {
        ...item,
        'execution': covered.contains(item['id']) ? 'covered' : 'not_exercised',
        if (data['live_disposable_account'] == true)
          'environment': 'live_disposable_account',
      },
  ];
  final selected = (data['selected_journeys'] as List? ?? []).cast<String>();
  final observed = journeys.map((j) => j['id']).toSet();
  final unrun = selected.where((id) => !observed.contains(id)).toList();
  await json('run', {
    ...data,
    'covered_count': covered.length,
    'unrun_journeys': unrun,
  });
  await json('coverage', coverage);
  String cell(Object? value) =>
      '$value'.replaceAll('|', r'\|').replaceAll('\n', ' ');
  String millis(Object? value) =>
      value is num ? (value / 1000).toStringAsFixed(2) : '—';
  final accountNotice = data['live_disposable_account'] == true
      ? '**Live disposable account.** Actual server account mutations; private temporary client databases. Passwords are entered privately on the phone and are not captured in reports.\n\n'
      : '';
  final report = StringBuffer('''# Phonolite UI profile

Build: ${data['build_mode'] ?? 'unknown'} · Platform: ${data['platform'] ?? 'unknown'}
Run: ${data['run_status'] ?? 'unknown'}

$accountNotice
${covered.length}/${catalog.length} catalogued interaction patterns exercised successfully in this run.
Missing prerequisites, unselected journeys, and failures do not count as coverage.
Coverage applies to the current data/layout; it is not a claim about every input or state.

| Journey | Result | Frames | Jank % | Build p95 ms | Raster p95 ms | Note |
| --- | --- | ---: | ---: | ---: | ---: | --- |
''');
  for (final journey in journeys) {
    final id = _journeyId(journey['id'] as String);
    final metrics = journey['metrics'] as Map? ?? {};
    final note = journey['reason'] ?? metrics['sample_quality'] ?? '';
    report.writeln(
      '| $id | ${journey['status']} | ${metrics['frame_count'] ?? 0} | '
      '${(metrics['jank_percent'] as num?)?.toStringAsFixed(2) ?? '—'} | '
      '${millis(metrics['build_p95_us'])} | ${millis(metrics['raster_p95_us'])} | ${cell(note)} |',
    );
    await json('$id.frames', journey);
    final trace = data['timeline.$id'];
    if (trace != null) {
      // Chrome/Perfetto trace-event format; not a DevTools export snapshot.
      await writeUiTimeline(destination, id, trace);
    }
  }
  if (unrun.isNotEmpty) report.writeln('\nNot run: ${unrun.join(', ')}.');
  report.writeln('''

Frame budgets use the reported display refresh rate, or UI_TARGET_FPS when supplied.
A frame exceeds budget when its build OR raster duration exceeds it; durations are not added.
Short captures (<30 frames) are marked insufficient. Test harness/tracing overhead is present;
compare like-for-like runs on the same physical device. These are scripted workload measurements,
not recordings of all possible manual gestures. No observed-FPS estimate is inferred from idle gaps.

Per-journey `.frames.json` includes raw timings and the slowest frames. Open `.timeline.json`
in a Chrome trace-event compatible viewer (for example Perfetto). It is not a DevTools export.
Raw traces can contain application timeline arguments; review before sharing outside your machine.
''');
  await File('${destination.path}/REPORT.md').writeAsString(report.toString());
}
