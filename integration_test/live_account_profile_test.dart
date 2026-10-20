import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phonolite_app/entities/auth_storage.dart';
import 'package:phonolite_app/pages/reset_user_password_page.dart';
import 'package:phonolite_app/widgets/modals/modal_action_button.dart';

import 'account/live_account_host.dart';
import 'support/journey.dart';
import 'support/report_channel.dart';
import 'support/ui_harness.dart';

/// Opt-in actual server mutations. Never included by any other device suite.
/// Passwords are entered privately on the phone, never through Dart defines.
void main() {
  final reports = UiReportChannel()..register();
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('User-confirmed disposable live account mutations', (
    tester,
  ) async {
    expect(kProfileMode, isTrue);
    expect(
      const bool.fromEnvironment('LIVE_DISPOSABLE_ACCOUNT_CONFIRMED'),
      isTrue,
      reason: 'Requires the human user to confirm a disposable account first.',
    );
    const expected = String.fromEnvironment('LIVE_EXPECTED_USERNAME');
    expect(expected, isNotEmpty);
    final saved = await const AuthStorage().read();
    expect(
      saved != null && saved.username == expected,
      isTrue,
      reason:
          'Saved account does not match the user-confirmed disposable username.',
    );
    const selection = String.fromEnvironment(
      'LIVE_ACCOUNT_CASES',
      defaultValue: 'all',
    );
    final requested = selection.split(',').toSet();
    expect(requested.difference({'all', 'password', 'statistics'}), isEmpty);
    final host = await LiveAccountHost.create(saved!);
    final ui = UiHarness(tester, binding);
    Future<void> action(String label) => ui.tap(
      find.byWidgetPredicate((w) => w is ModalActionButton && w.label == label),
    );
    Finder field(String key) => find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byType(TextField),
    );
    final journeys = [
      if (requested.contains('all') || requested.contains('password'))
        UiJourney(
          id: 'live_account.password_change',
          feature: 'authentication',
          description:
              'Submit privately entered passwords to the actual OPAQUE server, retain the session',
          interactions: [
            'password.current',
            'password.new',
            'password.confirm',
            'password.submit',
            'password.done',
          ],
          run: (ui) async {
            await ui.tab('Settings');
            await ui.tap(find.byKey(const ValueKey('reset-user-password')));
            await ui.waitFor(find.byType(ResetUserPasswordPage));
            // Keep the genuine iOS keyboard. The test only examines readiness
            // booleans; no password, field value, or widget tree is exported.
            await ui.tap(field('current-password'));
            debugPrint('[live-account] READY_FOR_PRIVATE_PASSWORD_ENTRY');
            final updated = find.text('PASSWORD UPDATED');
            await ui.waitUntil(
              () {
                if (updated.evaluate().isNotEmpty) return true;
                final fields = [
                  'current-password',
                  'new-password',
                  'confirm-new-password',
                ].map(field).toList();
                if (fields.any((f) => f.evaluate().isEmpty)) return false;
                final controls = fields
                    .map((f) => tester.widget<TextField>(f).controller!)
                    .toList();
                return controls.every((c) => c.text.isNotEmpty) &&
                    controls[1].text == controls[2].text;
              },
              description: 'private password entry on the phone',
              timeout: const Duration(minutes: 3),
            );
            if (updated.evaluate().isEmpty) {
              FocusManager.instance.primaryFocus?.unfocus();
              await action('Reset password');
            }
            await ui.waitFor(updated, timeout: const Duration(seconds: 40));
            expect(host.controller.authState.isAuthorized, isTrue);
            await host.controller.connection
                .fetchPlaylists(); // Authenticated endpoint accepts this session.
            await action('Done');
            await ui.waitUntil(
              () => find.byType(ResetUserPasswordPage).evaluate().isEmpty,
              description: 'password page dismissed',
            );
          },
        ),
      if (requested.contains('all') || requested.contains('statistics'))
        UiJourney(
          id: 'live_account.statistics_reset',
          feature: 'stats',
          description:
              'Reset actual disposable account statistics and verify server generation advances',
          interactions: ['settings.statistics_reset_confirm'],
          run: (ui) async {
            final before = await host.controller.connection
                .fetchListeningCounterState(deviceId: host.history.deviceId);
            await ui.tab('Settings');
            await ui.tap(
              find.byKey(const ValueKey('reset-listening-statistics')),
            );
            await action('Reset statistics');
            await ui.waitUntil(
              () =>
                  host.history.historyGeneration >
                  (before['history_generation'] as num),
              description: 'statistics reset complete',
              timeout: const Duration(seconds: 40),
            );
            final after = await host.controller.connection
                .fetchListeningCounterState(deviceId: host.history.deviceId);
            expect(
              (after['history_generation'] as num) >
                  (before['history_generation'] as num),
              isTrue,
            );
            expect(host.controller.stats?.totalListeningMs ?? 0, 0);
          },
        ),
    ];
    final output = binding.reportData ??= <String, dynamic>{};
    output.addAll({
      'schema_version': 1,
      'build_mode': 'profile',
      'platform': defaultTargetPlatform.name,
      'capture_timeline': false,
      'live_disposable_account': true,
      'client_storage':
          'private temporary databases; credential vault read-only',
      'native_password_entry': true,
      'selected_journeys': journeys.map((j) => j.id).toList(),
      'started_at': DateTime.now().toUtc().toIso8601String(),
    });
    await reports.publish({
      'type': 'run_metadata',
      'metadata': {...output},
    });
    try {
      await ui.ready();
      await host.startup;
      expect(host.controller.authState.isAuthorized, isTrue);
      for (final journey in journeys) {
        try {
          await reports.publish({'type': 'journey_start', 'id': journey.id});
          await ui.measure(journey);
        } finally {
          final result = (output['journeys'] as List?)?.last as Map?;
          if (result?['id'] == journey.id) {
            await reports.publish({
              'type': 'journey_result',
              'journey': result,
            });
            result!.remove('frames');
          }
        }
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await host.close();
      output['client_directory_removed'] = !await host.root.exists();
      output['finished_at'] = DateTime.now().toUtc().toIso8601String();
      await reports.publish({
        'type': 'run_metadata',
        'metadata': Map<String, dynamic>.from(output)..remove('journeys'),
      });
    }
  }, timeout: const Timeout(Duration(minutes: 9)));
}
