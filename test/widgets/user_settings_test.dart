import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/entities/app_controller.dart';
import 'package:phonolite_app/entities/app_log.dart';
import 'package:phonolite_app/entities/auth_state.dart';
import 'package:phonolite_app/entities/auth_storage.dart';
import 'package:phonolite_app/entities/offline_storage_settings.dart';
import 'package:phonolite_app/entities/server_connection.dart';
import 'package:phonolite_app/pages/login_page.dart';
import 'package:phonolite_app/pages/reset_user_password_page.dart';
import 'package:phonolite_app/pages/settings_page.dart';
import 'package:phonolite_app/widgets/inputs/obsidian_text_field.dart';
import 'package:phonolite_app/widgets/layout/library_header.dart';
import 'package:phonolite_app/widgets/layouts/app_scope.dart';
import 'package:phonolite_app/widgets/modals/modal_action_button.dart';
import 'package:phonolite_app/widgets/navigation/command_link_button.dart';
import 'package:phonolite_app/widgets/ui/obsidian_theme.dart';
import 'package:phonolite_app/widgets/ui/obsidian_widgets.dart';

import '../support/auth_test_helpers.dart';
import '../support/widget_test_helpers.dart';

const _newPassword = 'a new long passphrase';

void main() {
  setUpAll(configureTestFonts);

  for (final status in SessionStatus.values) {
    testWidgets('User settings and password availability for $status', (
      tester,
    ) async {
      final controller = _Controller(status);
      await _pumpSettings(tester, controller);
      final sections = tester
          .widgetList<ObsidianSectionHeader>(find.byType(ObsidianSectionHeader))
          .map((widget) => widget.title);
      expect(sections, ['General', 'User', 'Local Storage', 'Miscellaneous']);
      expect(find.text('Listening statistics'), findsOneWidget);
      expect(find.text('Reset listening statistics'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('reset-user-password')),
        status == SessionStatus.authenticated ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('password settings opens a named page using the shared styles', (
    tester,
  ) async {
    final controller = _Controller(SessionStatus.authenticated);
    await _pumpSettings(tester, controller);
    await _openPassword(tester);
    expect(
      ModalRoute.of(
        tester.element(find.byType(ResetUserPasswordPage)),
      )!.settings.name,
      ResetUserPasswordPage.routeName,
    );
    expect(
      tester.widget<LibraryHeader>(find.byType(LibraryHeader)).title,
      'RESET PASSWORD',
    );
    expect(find.byType(ObsidianTextField), findsNWidgets(3));
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
    expect(_action('Reset password'), findsOneWidget);
    expect(
      tester.widget<CommandLinkButton>(find.byType(CommandLinkButton)).label,
      'Back to settings',
    );
    await tester.tap(find.text('BACK TO SETTINGS'));
    await tester.pumpAndSettle();
    expect(find.byType(ResetUserPasswordPage), findsNothing);
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(controller.changes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('password form validates confirmation and masks every field', (
    tester,
  ) async {
    final controller = _Controller(SessionStatus.authenticated);
    await _pumpSettings(tester, controller);
    await _openPassword(tester);
    for (final field in tester.widgetList<TextField>(
      find.descendant(
        of: find.byType(ResetUserPasswordPage),
        matching: find.byType(TextField),
      ),
    )) {
      expect(field.obscureText, isTrue);
      expect(field.autocorrect, isFalse);
      expect(field.enableSuggestions, isFalse);
      expect(field.enableIMEPersonalizedLearning, isFalse);
      expect(field.smartDashesType, SmartDashesType.disabled);
      expect(field.smartQuotesType, SmartQuotesType.disabled);
    }

    await _fill(tester, 'current-password', 'old password');
    await _fill(tester, 'new-password', '');
    await _fill(tester, 'confirm-new-password', 'different');
    await _tapAction(tester, 'Reset password');
    expect(find.text('Enter your new password.'), findsOneWidget);
    expect(controller.changes, isEmpty);

    await _fill(tester, 'new-password', 'x');
    await _tapAction(tester, 'Reset password');
    expect(find.text('The new passwords do not match.'), findsOneWidget);
    expect(controller.changes, isEmpty);

    await _fill(tester, 'confirm-new-password', 'x');
    await _tapAction(tester, 'Reset password');
    expect(controller.changes, [('old password', 'x')]);
    expect(find.byType(ResetUserPasswordPage), findsOneWidget);
    expect(find.text('PASSWORD UPDATED'), findsOneWidget);
    expect(find.byType(ObsidianTextField), findsNothing);
    expect(controller.authState.isAuthorized, isTrue);
    expect(controller.connection.token, 'session');
    expect(find.textContaining('still signed in'), findsOneWidget);
    expect(_action('Sign in'), findsNothing);
    await _tapAction(tester, 'Done');
    expect(find.byType(ResetUserPasswordPage), findsNothing);
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
    expect(find.byKey(const ValueKey('reset-user-password')), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('password page permits reusing the current password', (
    tester,
  ) async {
    final controller = _Controller(SessionStatus.authenticated);
    await _pumpSettings(tester, controller);
    await _openPassword(tester);
    for (final key in [
      'current-password',
      'new-password',
      'confirm-new-password',
    ]) {
      await _fill(tester, key, 'x');
    }
    await _tapAction(tester, 'Reset password');
    expect(controller.changes, [('x', 'x')]);
    expect(find.text('PASSWORD UPDATED'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account change while form is open cancels secret submission', (
    tester,
  ) async {
    final controller = _Controller(SessionStatus.authenticated);
    await _pumpSettings(tester, controller);
    await _openPassword(tester);
    await _fill(tester, 'current-password', 'old password');
    await _fill(tester, 'new-password', _newPassword);
    await _fill(tester, 'confirm-new-password', _newPassword);
    controller.connection.setToken('a different session');
    controller.authUpdates.add(controller.authState);
    await tester.pumpAndSettle();
    expect(find.byType(ObsidianTextField), findsNothing);
    expect(_action('Reset password'), findsNothing);
    expect(controller.changes, isEmpty);
    expect(
      find.textContaining('connection or account changed'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'password errors never display server payloads and clear fields',
    (tester) async {
      final controller = _Controller(SessionStatus.authenticated)
        ..failure = ApiException(500, 'private server details and secrets');
      await _pumpSettings(tester, controller);
      await _openPassword(tester);
      await _fill(tester, 'current-password', 'old password');
      await _fill(tester, 'new-password', _newPassword);
      await _fill(tester, 'confirm-new-password', _newPassword);
      await _tapAction(tester, 'Reset password');
      expect(find.textContaining('private server details'), findsNothing);
      expect(find.textContaining('could not be confirmed'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(3));
      for (final field in tester.widgetList<TextField>(
        find.byType(TextField),
      )) {
        expect(field.controller!.text, isEmpty);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('pending change prevents duplicate submit and dismissal', (
    tester,
  ) async {
    final controller = _Controller(SessionStatus.authenticated)
      ..pending = Completer<void>();
    await _pumpSettings(tester, controller);
    await _openPassword(tester);
    await _fill(tester, 'current-password', 'old password');
    await _fill(tester, 'new-password', _newPassword);
    await _fill(tester, 'confirm-new-password', _newPassword);
    await tester.ensureVisible(_action('Reset password'));
    await tester.pumpAndSettle();
    await tester.tap(_action('Reset password'));
    await tester.pump();
    expect(controller.changes, hasLength(1));
    expect(
      tester
          .widget<TextButton>(
            find.descendant(
              of: find.byType(CommandLinkButton),
              matching: find.byWidgetPredicate(
                (widget) => widget is TextButton,
              ),
            ),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<ModalActionButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is ModalActionButton &&
                  widget.label == 'Reset password',
              skipOffstage: false,
            ),
          )
          .onPressed,
      isNull,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('UPDATING...'), findsNothing);
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .semanticsLabel,
      'Resetting password',
    );
    for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
      expect(field.enabled, isFalse);
    }
    await tester.tap(find.byType(CircularProgressIndicator));
    await tester.pump();
    expect(controller.changes, hasLength(1));
    await Navigator.of(
      tester.element(find.byType(ResetUserPasswordPage)),
    ).maybePop();
    await tester.pump();
    expect(find.byType(ResetUserPasswordPage), findsOneWidget);
    controller.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.text('PASSWORD UPDATED'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 1280.0]) {
    testWidgets('password page fits $width with larger text and keyboard', (
      tester,
    ) async {
      final controller = _Controller(SessionStatus.authenticated);
      await _pumpSettings(
        tester,
        controller,
        width: width,
        height: 640,
        textScale: 1.4,
        keyboardHeight: 280,
      );
      await _openPassword(tester);
      await _fill(tester, 'current-password', 'old password');
      await _fill(tester, 'new-password', _newPassword);
      await _fill(tester, 'confirm-new-password', _newPassword);
      await tester.ensureVisible(_action('Reset password'));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(_action('Reset password')).bottom,
        lessThanOrEqualTo(360),
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('BACK TO SETTINGS'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('BACK TO SETTINGS'));
      await tester.pumpAndSettle();
      expect(find.byType(ResetUserPasswordPage), findsNothing);
      expect(controller.changes, isEmpty);
    });
  }
}

Future<void> _pumpSettings(
  WidgetTester tester,
  _Controller controller, {
  double width = 430,
  double height = 1000,
  double textScale = 1,
  double keyboardHeight = 0,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.authUpdates.close();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    AppScope(
      controller: controller,
      child: MaterialApp(
        theme: ObsidianTheme.build(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            viewInsets: EdgeInsets.only(bottom: keyboardHeight),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Navigator(
            onGenerateRoute: (_) =>
                MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openPassword(WidgetTester tester) async {
  final tile = find.byKey(const ValueKey('reset-user-password'));
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  await tester.tap(tile);
  await tester.pumpAndSettle();
  expect(find.byType(ResetUserPasswordPage), findsOneWidget);
}

Future<void> _fill(WidgetTester tester, String key, String value) async {
  final field = find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.byType(TextField),
  );
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, value);
  await tester.pumpAndSettle();
}

Finder _action(String label) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is ModalActionButton && widget.label == label,
  ),
  matching: find.byType(TextButton),
);

Future<void> _tapAction(WidgetTester tester, String label) async {
  final action = _action(label);
  await tester.ensureVisible(action);
  await tester.pumpAndSettle();
  await tester.tap(action);
  await tester.pumpAndSettle();
}

class _Controller extends Fake implements AppController {
  _Controller(this.status) {
    connection.setTrust(testServerTrust);
    if (status == SessionStatus.authenticated) connection.setToken('session');
  }

  SessionStatus status;
  final authUpdates = StreamController<AuthState>.broadcast();
  final changes = <(String, String)>[];
  Object? failure;
  Completer<void>? pending;

  @override
  final connection = ServerConnection(baseUrl: 'https://settings.test/api/v1');
  @override
  AuthState get authState =>
      AuthState(baseUrl: connection.baseUrl, status: status);
  @override
  Stream<AuthState> get authStream => authUpdates.stream;
  @override
  bool get localNetworkPermissionSupported => false;
  @override
  LocalNetworkPermissionState get localNetworkPermissionState =>
      LocalNetworkPermissionState.unknown;
  @override
  Stream<LocalNetworkPermissionState> get localNetworkPermissionStream =>
      const Stream.empty();
  @override
  Future<AuthCredentials?> loadSavedCredentials() async => null;
  @override
  List<LogEntry> get messages => [];
  @override
  Stream<List<LogEntry>> get messageStream => const Stream.empty();
  @override
  bool get statsCollectionEnabled => true;
  @override
  Stream<bool> get statsCollectionEnabledStream => const Stream.empty();
  @override
  OfflineStorageLocations? get offlineStorageLocations => null;
  @override
  Stream<OfflineStorageLocations> get offlineStorageLocationsStream =>
      const Stream.empty();
  @override
  Future<void> setStatsCollectionEnabled(bool value) async {}
  @override
  Future<void> resetLocalListeningHistory() async {}
  @override
  Future<void> resetAccountListeningHistory() async {}
  @override
  Future<void> resetListeningStatistics() async {}
  @override
  Future<void> resetUserPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    changes.add((currentPassword, newPassword));
    if (failure != null) throw failure!;
    if (pending != null) await pending!.future;
  }
}
