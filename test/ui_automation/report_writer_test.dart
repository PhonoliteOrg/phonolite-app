import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/report_writer.dart';

void main() {
  test('live account mutation reports identify their environment', () async {
    final output = await Directory.systemTemp.createTemp('account-report-');
    addTearDown(() => output.delete(recursive: true));
    await writeUiReport(
      output,
      {
        'live_disposable_account': true,
        'journeys': [
          {
            'id': 'live_account.test',
            'status': 'passed',
            'covered_interactions': ['test.tap'],
          },
        ],
      },
      [
        {'id': 'test.tap'},
      ],
    );
    final coverage =
        jsonDecode(await File('${output.path}/coverage.json').readAsString())
            as List;
    expect(coverage.single['environment'], 'live_disposable_account');
    expect(
      await File('${output.path}/REPORT.md').readAsString(),
      contains('Live disposable account'),
    );
  });

  test('skipped, failed and unrun journeys never count as covered', () async {
    final output = await Directory.systemTemp.createTemp(
      'phonolite-ui-report-',
    );
    addTearDown(() => output.delete(recursive: true));
    final catalog = [
      for (final id in ['a.tap', 'b.tap', 'c.tap', 'd.tap']) {'id': id},
    ];
    await writeUiReport(output, {
      'selected_journeys': ['a.test', 'b.test', 'c.test', 'd.test'],
      'journeys': [
        {
          'id': 'a.test',
          'status': 'passed',
          'covered_interactions': ['a.tap'],
        },
        {
          'id': 'b.test',
          'status': 'skipped',
          'covered_interactions': ['b.tap'],
        },
        {
          'id': 'c.test',
          'status': 'failed',
          'covered_interactions': ['c.tap'],
        },
      ],
      'timeline.a.test': {'traceEvents': []},
    }, catalog);
    final coverage =
        jsonDecode(await File('${output.path}/coverage.json').readAsString())
            as List;
    expect(
      coverage.where((entry) => entry['execution'] == 'covered').length,
      1,
    );
    final run =
        jsonDecode(await File('${output.path}/run.json').readAsString()) as Map;
    expect(run['unrun_journeys'], ['d.test']);
    expect(File('${output.path}/a.test.timeline.json').existsSync(), isTrue);
    expect(
      await File('${output.path}/REPORT.md').readAsString(),
      contains('1/4'),
    );
    // Later partial checkpoints must preserve a trace already saved by the host.
    await writeUiReport(output, {
      'run_status': 'interrupted',
      'selected_journeys': ['a.test', 'd.test'],
      'journeys': [
        {'id': 'a.test', 'status': 'passed'},
      ],
    }, catalog);
    expect(File('${output.path}/a.test.timeline.json').existsSync(), isTrue);
    expect(
      await File('${output.path}/REPORT.md').readAsString(),
      contains('Run: interrupted'),
    );
  });
}
