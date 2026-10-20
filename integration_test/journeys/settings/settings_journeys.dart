import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/entities/app_log.dart';
import 'package:phonolite_app/pages/custom_shuffle_settings_page.dart';
import 'package:phonolite_app/pages/logs_page.dart';
import 'package:phonolite_app/pages/login_page.dart';
import 'package:phonolite_app/pages/reset_user_password_page.dart';
import 'package:phonolite_app/widgets/modals/confirmation_modal.dart';
import 'package:phonolite_app/widgets/modals/modal_action_button.dart';
import 'package:phonolite_app/widgets/inputs/obsidian_toggle_option.dart';

import '../../support/journey.dart';
import '../../support/ui_harness.dart';

final settingsJourneys = [
  UiJourney(
    id: 'settings.server_menu',
    feature: 'settings',
    description:
        'Inspect connected server actions and leave Change server without submitting',
    interactions: ['settings.server_actions', 'settings.change_server'],
    run: (ui) async {
      await ui.tab('Settings');
      if (!ui.controller.authState.hasSession) {
        throw const MissingPrerequisite(
          'Server actions menu requires a saved session',
        );
      }
      if (tooltipControl('Server actions').evaluate().isEmpty) {
        throw const MissingPrerequisite(
          'Compact server actions menu is absent in this layout',
        );
      }
      final originalRevision = ui.controller.connection.sessionRevision;
      final originalStatus = ui.controller.authState.status;
      await ui.tooltip('Server actions');
      expect(find.text('Disconnect'), findsOneWidget);
      await ui.text('Change server');
      expect(find.byType(LoginPage), findsOneWidget);
      await ui.back('Back to settings');
      expect(ui.controller.connection.sessionRevision, originalRevision);
      expect(ui.controller.authState.status, originalStatus);
    },
  ),
  UiJourney(
    id: 'settings.password_browse',
    feature: 'settings',
    description: 'Open password form, validate an empty submission, and return',
    interactions: ['settings.password_open'],
    run: (ui) async {
      await ui.tab('Settings');
      if (!ui.controller.authState.isAuthorized) {
        throw const MissingPrerequisite(
          'Password form requires an authenticated account',
        );
      }
      final revision = ui.controller.connection.sessionRevision;
      await ui.tap(find.byKey(const ValueKey('reset-user-password')));
      expect(find.byType(ResetUserPasswordPage), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(3));
      for (final field in ui.tester.widgetList<TextField>(
        find.byType(TextField),
      )) {
        expect(field.obscureText, isTrue);
        expect(field.controller!.text, isEmpty);
      }
      // Empty validation cannot send a password-change request.
      await ui.tap(
        find.byWidgetPredicate(
          (w) => w is ModalActionButton && w.label == 'Reset password',
        ),
      );
      expect(find.text('Enter your current password.'), findsOneWidget);
      await ui.back('Back to settings');
      expect(ui.controller.connection.sessionRevision, revision);
      expect(ui.controller.authState.isAuthorized, isTrue);
    },
  ),
  UiJourney(
    id: 'settings.statistics_controls',
    feature: 'settings',
    description:
        'Toggle statistics collection, cancel reset, and restore the setting',
    interactions: [
      'settings.statistics_toggle',
      'settings.statistics_reset_open',
      'settings.statistics_reset_cancel',
    ],
    run: (ui) async {
      await ui.tab('Settings');
      final initial = ui.controller.statsCollectionEnabled;
      final toggle = find.byKey(const ValueKey('listening-statistics-switch'));
      try {
        await ui.tap(toggle);
        await ui.waitUntil(
          () => ui.controller.statsCollectionEnabled != initial,
          description: 'statistics toggle applied',
        );
        await ui.tap(toggle);
        expect(ui.controller.statsCollectionEnabled, initial);
        if (!initial) await ui.tap(toggle);
        await ui.tap(find.byKey(const ValueKey('reset-listening-statistics')));
        expect(find.text('Reset listening statistics?'), findsOneWidget);
        await ui.text('CANCEL');
        expect(find.byType(ConfirmationModal), findsNothing);
      } finally {
        // Cleanup must also run if a finder/assertion failed while a modal was open.
        if (ui.controller.statsCollectionEnabled != initial) {
          await ui.controller.setStatsCollectionEnabled(initial);
        }
      }
      expect(ui.controller.statsCollectionEnabled, initial);
    },
  ),
  UiJourney(
    id: 'settings.reset_cancel',
    feature: 'settings',
    description:
        'Open full local reset confirmation and cancel without deleting data',
    interactions: ['settings.reset_open', 'settings.reset_cancel'],
    run: (ui) async {
      await ui.tab('Settings');
      await ui.reveal(tooltipControl('Full reset'));
      await ui.tooltip('Full reset');
      expect(find.byType(ConfirmationModal), findsOneWidget);
      expect(find.text('Reset local data'), findsWidgets);
      await ui.text('CANCEL');
      expect(find.byType(ConfirmationModal), findsNothing);
    },
  ),
  UiJourney(
    id: 'settings.custom_shuffle_scopes',
    feature: 'settings',
    description:
        'Switch Server/Local and Artists/Genres without changing saved filters',
    interactions: ['settings.custom_shuffle', 'custom_shuffle.target'],
    run: (ui) async {
      await ui.tab('Settings');
      final initial = ui.controller.customShuffleSettings.toJson();
      await ui.text('Custom Shuffle');
      for (final target in ['LOCAL', 'SERVER']) {
        for (final label in [target, 'GENRES', 'ARTISTS']) {
          final option = find.byWidgetPredicate(
            (w) => w is ObsidianToggleOption && w.label.toUpperCase() == label,
          );
          if (option.evaluate().isEmpty) {
            throw const MissingPrerequisite(
              'Compact shuffle view tabs are absent in this layout',
            );
          }
          await ui.tap(option);
          expect(
            ui.tester.widget<ObsidianToggleOption>(option).isActive,
            isTrue,
          );
        }
      }
      await ui.back('Back to settings');
      expect(ui.controller.customShuffleSettings.toJson(), initial);
    },
  ),
  UiJourney(
    id: 'settings.scroll',
    feature: 'settings',
    description:
        'Scroll through General, User, Local Storage, and Miscellaneous',
    interactions: ['settings.scroll'],
    run: (ui) async {
      await ui.tab('Settings');
      await ui.scrollRoundTrip();
    },
  ),
  UiJourney(
    id: 'settings.custom_shuffle_browse',
    feature: 'settings',
    description:
        'Browse artist/genre shuffle filters without changing selections',
    interactions: [
      'settings.custom_shuffle',
      'custom_shuffle.artists_view',
      'custom_shuffle.genres_view',
      'custom_shuffle.search',
      'custom_shuffle.back',
    ],
    run: (ui) async {
      debugPrint('[ui] custom shuffle: navigate to Settings');
      await ui.tab('Settings');
      debugPrint('[ui] custom shuffle: open page');
      await ui.text('Custom Shuffle');
      debugPrint('[ui] custom shuffle: inspect page');
      expect(find.byType(CustomShuffleSettingsPage), findsOneWidget);
      // Do not claim compact tab coverage on layouts that show both panels.
      final genres = find.text('GENRES').hitTestable();
      if (genres.evaluate().isEmpty) {
        throw const MissingPrerequisite(
          'Compact Artists/Genres tabs are absent in this layout',
        );
      }
      await ui.tap(genres);
      debugPrint('[ui] custom shuffle: edit genre query');
      final fields = find.byType(TextField).hitTestable();
      expect(fields, findsAtLeastNWidgets(1));
      await ui.tester.enterText(fields.first, 'a');
      await ui.animate(350);
      expect(ui.tester.widget<TextField>(fields.first).controller!.text, 'a');
      await ui.tester.enterText(fields.first, '');
      FocusManager.instance.primaryFocus?.unfocus();
      await ui.animate();
      final artists = find.text('ARTISTS').hitTestable();
      expect(artists, findsOneWidget);
      // GENRES loads the full server catalog. Compare the same populated list
      // on each repeat instead of mixing pagination/network waits with toggles.
      if (ui.controller.authState.isAuthorized) {
        await ui.waitUntil(
          () => !ui.controller.artistsLoading && !ui.controller.hasMoreArtists,
          description: 'full artist catalog for genre filters',
          timeout: const Duration(seconds: 60),
        );
      }
      debugPrint(
        '[ui] custom shuffle: ${ui.controller.artists.length} artists',
      );
      for (var repeat = 0; repeat < UiHarness.repeats; repeat++) {
        debugPrint('[ui] custom shuffle: view cycle ${repeat + 1}');
        await ui.tap(artists);
        await ui.tap(find.text('GENRES').hitTestable());
      }
      await ui.tap(artists);
      debugPrint('[ui] custom shuffle: return to Settings');
      await ui.back('Back to settings');
    },
  ),
  UiJourney(
    id: 'settings.logs_filters',
    feature: 'settings',
    description: 'Open Logs and visit every category; preserve log history',
    interactions: [
      'settings.logs',
      'logs.filter_all',
      'logs.filter_info',
      'logs.filter_activities',
      'logs.filter_warnings',
      'logs.filter_errors',
      'logs.filter_issues',
      'logs.filter_debug',
      'logs.back',
    ],
    run: (ui) async {
      await ui.tab('Settings');
      await ui.reveal(find.text('Logs'));
      await ui.text('Logs');
      expect(find.byType(LogsPage), findsOneWidget);
      for (final category in LogCategory.values) {
        final option = find.byWidgetPredicate(
          (w) => w is ObsidianToggleOption && w.label == category.label,
        );
        await ui.tap(option);
        expect(ui.tester.widget<ObsidianToggleOption>(option).isActive, isTrue);
      }
      await ui.back('Back to settings');
    },
  ),
];
