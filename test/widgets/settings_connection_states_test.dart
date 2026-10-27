import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/library/catalog_controller.dart';
import 'package:phonolite_app/data/models/auth/auth_state.dart';
import 'package:phonolite_app/data/models/diagnostics/log_entry.dart';
import 'package:phonolite_app/data/models/preferences/offline_storage_locations.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';
import 'package:phonolite_app/pages/settings/settings_page.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_widgets.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/tech_button.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

import '../support/widget_test_helpers.dart';

// These are isolated UI fixtures, not evidence of a real network outage.
void main() {
  setUpAll(configureTestFonts);

  for (final width in [320.0, 390.0, 1280.0]) {
    for (final status in SessionStatus.values) {
      testWidgets('server actions at $width in $status', (tester) async {
        final controller = _Controller(status);
        await _pump(tester, controller, width);
        if (width < 820 && controller.authState.hasSession) {
          await tester.tap(find.byTooltip('Server actions'));
          await tester.pumpAndSettle();
          expect(find.text('Change server'), findsOneWidget);
          expect(find.text('Disconnect'), findsOneWidget);
          final retry = _popup('Retry');
          expect(retry, status == SessionStatus.serverUnavailable ? findsOneWidget : findsNothing);
          if (retry.evaluate().isNotEmpty) {
            expect(tester.widget<PopupMenuItem<int>>(retry).enabled, isTrue);
          }
        } else {
          final label = switch (status) {
            SessionStatus.authenticated || SessionStatus.serverUnavailable => 'Change server',
            SessionStatus.serverReachable => 'Log in',
            SessionStatus.checking => 'Checking',
            SessionStatus.offline => 'Connect / Log in',
          };
          if (width < 820) {
            final button = find.descendant(of: find.byTooltip(label), matching: find.byType(ObsidianHudIconButton));
            expect(tester.widget<ObsidianHudIconButton>(button).onPressed == null, status == SessionStatus.checking);
          } else {
            expect(tester.widget<TechButton>(_button(label)).onTap == null, status == SessionStatus.checking);
            expect(_button('Disconnect'), controller.authState.hasSession ? findsOneWidget : findsNothing);
            expect(_button('Retry'), status == SessionStatus.serverUnavailable ? findsOneWidget : findsNothing);
          }
        }
        expect(controller.retries, 0);
        expect(controller.logouts, 0);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('retry, recovery and disconnect at $width', (tester) async {
      final controller = _Controller(SessionStatus.serverUnavailable);
      await _pump(tester, controller, width);
      await _action(tester, width, 'Retry');
      expect(controller.retries, 1);
      expect(controller.authState.status, SessionStatus.authenticated);
      if (width < 820) {
        await tester.tap(find.byTooltip('Server actions'));
        await tester.pumpAndSettle();
        expect(find.text('Retry'), findsNothing);
        await tester.tap(find.text('Disconnect'));
        await tester.pumpAndSettle();
      } else {
        expect(_button('Retry'), findsNothing);
        await tester.tap(_button('Disconnect'));
        await tester.pumpAndSettle();
      }
      expect(controller.logouts, 1);
      expect(controller.authState.status, SessionStatus.offline);
      expect(find.byTooltip('Server actions'), findsNothing);
      expect(find.byKey(const ValueKey('reset-user-password')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('in-flight reconnect cannot be submitted twice at $width', (tester) async {
      final controller = _Controller(SessionStatus.serverUnavailable)..reconnecting = true;
      await _pump(tester, controller, width);
      if (width < 820) {
        await tester.tap(find.byTooltip('Server actions'));
        await tester.pumpAndSettle();
        final item = _popup('Reconnecting...');
        expect(tester.widget<PopupMenuItem<int>>(item).enabled, isFalse);
        await tester.tap(find.text('Reconnecting...'));
      } else {
        final button = _button('Reconnecting...');
        expect(tester.widget<TechButton>(button).onTap, isNull);
        await tester.tap(button);
      }
      await tester.pumpAndSettle();
      expect(controller.retries, 0);
      expect(controller.logouts, 0);
      expect(tester.takeException(), isNull);
    });
  }
}

Finder _button(String label) => find.byWidgetPredicate((widget) => widget is TechButton && widget.label == label);

Finder _popup(String label) => find.ancestor(of: find.text(label), matching: find.byType(PopupMenuItem<int>));

Future<void> _action(WidgetTester tester, double width, String label) async {
  if (width < 820) {
    await tester.tap(find.byTooltip('Server actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
  } else {
    await tester.tap(_button(label));
  }
  await tester.pumpAndSettle();
}

Future<void> _pump(WidgetTester tester, _Controller controller, double width) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1000);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.updates.close();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    AppScope(
      controller: controller,
      child: MaterialApp(
        theme: ObsidianTheme.build().copyWith(platform: TargetPlatform.iOS),
        home: const Scaffold(body: SettingsPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _Controller extends Fake implements AppController {
  late final CatalogController _catalog = CatalogController(connection);
  @override
  CatalogController get catalog => _catalog;

  _Controller(this.status);
  SessionStatus status;
  bool reconnecting = false;
  int retries = 0;
  int logouts = 0;
  final updates = StreamController<AuthState>.broadcast();
  @override
  final connection = ServerConnection(baseUrl: 'https://fixture.invalid/api');
  @override
  AuthState get authState => AuthState(baseUrl: connection.baseUrl, status: status, isReconnecting: reconnecting);
  @override
  Stream<AuthState> get authStream => updates.stream;
  @override
  List<LogEntry> get messages => [];
  @override
  Stream<List<LogEntry>> get messageStream => const Stream.empty();
  @override
  bool get statsCollectionEnabled => true;
  @override
  bool get sessionManagementAvailable => false;
  @override
  Stream<bool> get statsCollectionEnabledStream => const Stream.empty();
  @override
  OfflineStorageLocations? get offlineStorageLocations => null;
  @override
  Stream<OfflineStorageLocations> get offlineStorageLocationsStream => const Stream.empty();
  @override
  Future<void> retryServerConnection() async {
    retries++;
    status = SessionStatus.authenticated;
    updates.add(authState);
  }

  @override
  Future<void> logout({bool clearSaved = true}) async {
    logouts++;
    status = SessionStatus.offline;
    updates.add(authState);
  }
}
