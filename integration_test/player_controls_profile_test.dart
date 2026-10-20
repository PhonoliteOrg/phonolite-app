import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'audio/audio_probe.dart';
import 'audio/audio_test_host.dart';
import 'audio/player_controls_suite.dart';
import 'audio/quality_probe_service.dart';
import 'support/report_channel.dart';
import 'support/ui_harness.dart';

void main() {
  final reports = UiReportChannel()..register();
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('Visible playbar controls and real streaming qualities', (
    tester,
  ) async {
    expect(kProfileMode, isTrue);
    binding.testTextInput.register();
    addTearDown(binding.testTextInput.unregister);
    final output = binding.reportData ??= <String, dynamic>{};
    output.addAll({
      'schema_version': 1,
      'suite': 'audio',
      'control_suite': true,
      'build_mode': 'profile',
      'platform': defaultTargetPlatform.name,
      'selected_journeys': playerControlIds,
      'capture_timeline': UiHarness.captureTimeline,
      'started_at': DateTime.now().toUtc().toIso8601String(),
      'action_layer':
          'visible compact and expanded playbar gestures; controller setup/cleanup only',
      'stall_threshold_ms': 750,
      'acoustic_recording': false,
    });
    await reports.publish({
      'type': 'run_metadata',
      'metadata': {...output},
    });
    final probe = AudioProbe();
    registerQualityProbe(probe);
    await startAudioTestHost(probe);
    final ui = UiHarness(tester, binding);
    await ui.ready();
    final suite = PlayerControlsSuite(ui, probe, reports, output);
    try {
      await suite.seed();
      await reports.publish({
        'type': 'run_metadata',
        'metadata': {...output},
      });
      await suite.run();
      output['failed_journeys'] = suite.failures;
      expect(
        suite.failures,
        isEmpty,
        reason: 'See individual playbar/quality results',
      );
    } finally {
      await suite.cleanup();
      output['finished_at'] = DateTime.now().toUtc().toIso8601String();
      await reports.publish({
        'type': 'run_metadata',
        'metadata': Map<String, dynamic>.from(output)..remove('journeys'),
      });
    }
  }, timeout: const Timeout(Duration(minutes: 20)));
}
