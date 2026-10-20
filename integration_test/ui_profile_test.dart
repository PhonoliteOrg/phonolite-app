import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phonolite_app/main.dart' as app;

import 'journeys/all_journeys.dart';
import 'support/report_channel.dart';
import 'support/ui_harness.dart';

void main() {
  final reports = UiReportChannel()..register();
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  const requested = String.fromEnvironment('UI_FEATURES', defaultValue: 'all');
  final features = requested.split(',').map((s) => s.trim()).toSet();
  final selected = allJourneys
      .where(
        (j) =>
            features.contains('all') ||
            features.contains(j.feature) ||
            features.contains(j.id),
      )
      .toList();

  testWidgets('Phonolite on-screen journeys and frame profiles', (
    tester,
  ) async {
    expect(
      kProfileMode,
      isTrue,
      reason: 'Run with flutter drive --profile; debug timings are misleading.',
    );
    expect(UiHarness.repeats, inInclusiveRange(1, 20));
    final known = {
      'all',
      ...allJourneys.map((j) => j.feature),
      ...allJourneys.map((j) => j.id),
    };
    expect(
      features.difference(known),
      isEmpty,
      reason: 'Unknown UI_FEATURES selector',
    );
    expect(selected, isNotEmpty);
    // Profile mode verifies text-input client IDs. The default integration
    // binding leaves the test keyboard unregistered, so injected '-1' client
    // messages that work in debug mode are ignored. Register the test adapter
    // to receive the real framework client ID; native keyboard UI is out of scope.
    binding.testTextInput.register();
    addTearDown(binding.testTextInput.unregister);
    final output = binding.reportData ??= <String, dynamic>{};
    output.addAll({
      'schema_version': 1,
      'build_mode': kProfileMode ? 'profile' : 'debug',
      'platform': defaultTargetPlatform.name,
      'requested': requested,
      'selected_journeys': selected.map((j) => j.id).toList(),
      'repeats': UiHarness.repeats,
      'capture_timeline': UiHarness.captureTimeline,
      'started_at': DateTime.now().toUtc().toIso8601String(),
    });
    await reports.publish({
      'type': 'run_metadata',
      'metadata': {...output},
    });
    await app.main();
    final ui = UiHarness(tester, binding);
    await ui.ready();
    output['signed_in'] = ui.controller.authState.isAuthorized;
    await reports.publish({
      'type': 'run_metadata',
      'metadata': {...output},
    });
    final failures = <String>[];
    try {
      for (final journey in selected) {
        try {
          await ui.resetNavigation();
          await reports.publish({'type': 'journey_start', 'id': journey.id});
          await ui.measure(journey);
        } catch (error, stack) {
          failures.add(journey.id);
          debugPrint('[ui] ${journey.id} failed: $error');
          debugPrintStack(stackTrace: stack);
        } finally {
          final results = (output['journeys'] as List? ?? []).cast<Map>();
          if (results.isNotEmpty && results.last['id'] == journey.id) {
            await reports.publish({
              'type': 'journey_result',
              'journey': results.last,
            });
            // The host already saved raw timings. Keep only the small summary
            // in the SDK's final response instead of accumulating device data.
            results.last.remove('frames');
          }
        }
      }
      output['failed_journeys'] = failures;
      expect(failures, isEmpty, reason: 'See individual journey reports');
    } finally {
      output['finished_at'] = DateTime.now().toUtc().toIso8601String();
      await reports.publish({
        'type': 'run_metadata',
        'metadata': Map<String, dynamic>.from(output)..remove('journeys'),
      });
      // No direct controller calls are used to perform the tested actions.
      await ui.resetNavigation();
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
