import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/audio/audio_report_writer.dart';

void main() {
  test(
    'encoded probes retain successful and incomplete samples without breaking reports',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'phonolite-wire-report-',
      );
      addTearDown(() => directory.delete(recursive: true));
      await writeAudioReport(directory, {
        'control_suite': true,
        'run_status': 'failed',
        'build_mode': 'profile',
        'platform': 'ios',
        'journeys': [
          {
            'id': 'audio.wire_high',
            'status': 'passed',
            'checks': {'target_verified': true},
            'wire': {
              'requested_quality': 'high',
              'header': {'bitrate_bps': 160000},
              'encoded_payload_kbps': 151.25,
              'packet_count': 100,
              'encoded_media_ms': 2000,
            },
          },
          {
            'id': 'audio.wire_low',
            'status': 'failed',
            'wire': {
              'requested_quality': 'low',
              'header': null,
              'encoded_payload_kbps': null,
              'packet_count': 0,
              'encoded_media_ms': 0,
              'failure': 'timeout_before_header',
            },
          },
        ],
      });
      final report = await File('${directory.path}/REPORT.md').readAsString();
      expect(report, contains('Visible compact/expanded'));
      expect(report, contains('151.3'));
      expect(report, contains('target_verified'));
      final data =
          jsonDecode(await File('${directory.path}/run.json').readAsString())
              as Map;
      expect(
        (data['journeys'] as List).last['wire']['failure'],
        'timeout_before_header',
      );
    },
  );

  test(
    'partial reports retain failures, skips and unrun cases with raw samples separate',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'phonolite-audio-',
      );
      addTearDown(() => directory.delete(recursive: true));
      await writeAudioReport(directory, {
        'run_status': 'interrupted',
        'build_mode': 'profile',
        'platform': 'ios',
        'selected_journeys': ['audio.stream', 'audio.local', 'audio.resume'],
        'journeys': [
          {
            'id': 'audio.stream',
            'status': 'failed',
            'frames': [],
            'audio': {
              'samples': [
                {'position_ms': 100},
              ],
              'events': [],
              'metrics': {
                'issues': ['stalled'],
                'stall_count': 1,
              },
            },
          },
          {'id': 'audio.local', 'status': 'skipped', 'reason': 'No downloads'},
        ],
      });
      final data =
          jsonDecode(await File('${directory.path}/run.json').readAsString())
              as Map;
      expect(data['unrun_journeys'], ['audio.resume']);
      expect((data['journeys'] as List).first['audio']['samples'], isNull);
      expect(
        File('${directory.path}/audio.stream.audio.json').existsSync(),
        isTrue,
      );
      expect(
        File('${directory.path}/audio.local.audio.json').existsSync(),
        isFalse,
      );
      final report = await File('${directory.path}/REPORT.md').readAsString();
      expect(report, contains('interrupted'));
      expect(report, contains('stalled'));
      expect(report, contains('No downloads'));
      expect(report, contains('no underrun counter'));
    },
  );
}
