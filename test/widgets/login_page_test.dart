import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/data/models/auth/auth_credentials.dart';
import 'package:phonolite_app/data/models/auth/auth_state.dart';
import 'package:phonolite_app/pages/auth/login_page.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_text_field.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_scale.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/modal_action_button.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

import '../support/auth_test_helpers.dart';
import '../support/widget_test_helpers.dart';

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is ObsidianTextField && widget.label == label,
);

Finder _input(String label) =>
    find.descendant(of: _field(label), matching: find.byType(TextField));

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

Future<void> _pump(
  WidgetTester tester,
  _LoginController controller, {
  double width = 390,
  double height = 844,
  double textScale = 1,
  double keyboardHeight = 0,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final scale = ObsidianScale.compute(width);
  await tester.pumpWidget(
    MaterialApp(
      theme: ObsidianTheme.build(scale: scale),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          viewInsets: EdgeInsets.only(bottom: keyboardHeight),
        ),
        child: ObsidianScale(scale: scale, child: child!),
      ),
      home: Scaffold(body: LoginPage(controller: controller)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(configureTestFonts);

  testWidgets('forced sign-in retains the server and opens password entry directly', (tester) async {
    final controller = _LoginController().._auth = AuthState(
      baseUrl: 'https://rotated.test:8443/api', requiresSignIn: true,
      error: 'Server keys changed. Sign in again to verify the new server key.');
    await _pump(tester, controller);
    expect(find.text('SIGN IN'), findsNWidgets(2));
    expect(_input('Username'), findsOneWidget);
    expect(_action('Change server'), findsOneWidget);
    expect(_action('Forget server'), findsNothing);
    expect(find.textContaining('Server keys changed.'), findsOneWidget);
    await tester.enterText(_input('Username'), 'listener');
    await tester.enterText(_input('Password'), 'correct-password');
    await _tapAction(tester, 'Sign in');
    expect(controller.probes, isEmpty);
    expect(controller.login?.baseUrl, 'https://rotated.test:8443/api');
    expect(controller.login?.password, 'correct-password');
  });

  testWidgets('previous server address and port are not populated', (tester) async {
    final controller = _LoginController()
      .._auth = AuthState(baseUrl: 'https://fresh.test/api');
    await _pump(tester, controller);
    expect(tester.widget<TextField>(_input('Server address')).controller!.text, isEmpty);
    expect(tester.widget<TextField>(_input('Port')).controller!.text, isEmpty);
    expect(_action('Forget server'), findsNothing);
    await _tapAction(tester, 'Connect');
    expect(controller.probes, isEmpty);
    expect(find.text('Server address is required'), findsOneWidget);
    expect(_action('Forget server'), findsNothing);
  });

  testWidgets('server address rejects invalid input and disables keyboard rewriting', (tester) async {
    await _pump(tester, _LoginController());
    final field = tester.widget<TextField>(_input('Server address'));
    expect(field.autocorrect, isFalse);
    expect(field.enableSuggestions, isFalse);
    expect(field.smartDashesType, SmartDashesType.disabled);
    expect(field.smartQuotesType, SmartQuotesType.disabled);

    await tester.enterText(_input('Server address'), 'music.test');
    await tester.enterText(_input('Server address'), 'my server.test');
    expect(tester.widget<TextField>(_input('Server address')).controller!.text, 'music.test');
    await tester.enterText(_input('Server address'), 'music.test😀');
    expect(tester.widget<TextField>(_input('Server address')).controller!.text, 'music.test');

    await tester.enterText(_input('Server address'), 'https://[2001:db8::1]:8443/api');
    expect(tester.widget<TextField>(_input('Server address')).controller!.text, '[2001:db8::1]');
    expect(tester.widget<TextField>(_input('Port')).controller!.text, '8443');
  });

  testWidgets('port filters nondigits while connection validation checks its range', (tester) async {
    final controller = _LoginController();
    await _pump(tester, controller);
    await tester.enterText(_input('Server address'), 'music.test');
    await tester.enterText(_input('Port'), '8a4 43');
    expect(tester.widget<TextField>(_input('Port')).controller!.text, '8443');
    await tester.enterText(_input('Port'), '65536');
    await _tapAction(tester, 'Connect');
    expect(controller.probes, isEmpty);
    expect(find.text('Port must be a number between 1 and 65535'), findsOneWidget);
  });

  testWidgets('change server disconnects and clears credentials before reconnecting', (tester) async {
    final controller = _LoginController()
      .._auth = AuthState(baseUrl: 'https://fresh.test:8443/api', requiresSignIn: true)
      ..saved = const AuthCredentials(
        baseUrl: 'https://fresh.test:8443/api',
        token: 'old-token',
        username: 'listener',
        trust: testServerTrust,
      );
    await _pump(tester, controller);
    await tester.enterText(_input('Password'), 'old-password');

    await _tapAction(tester, 'Change server');
    expect(controller.logouts, 1);
    expect(controller.saved, isNull);
    expect(controller.authState.baseUrl, isEmpty);
    expect(tester.widget<TextField>(_input('Server address')).controller!.text, isEmpty);
    expect(tester.widget<TextField>(_input('Port')).controller!.text, isEmpty);
    expect(_action('Forget server'), findsNothing);

    await tester.enterText(_input('Server address'), 'new-server.test');
    await tester.enterText(_input('Port'), '8443');
    await _tapAction(tester, 'Connect');
    expect(controller.probes, ['https://new-server.test:8443']);
    expect(tester.widget<TextField>(_input('Username')).controller!.text, isEmpty);
    expect(tester.widget<TextField>(_input('Password')).controller!.text, isEmpty);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    await _tapAction(tester, 'Sign in');
    expect(find.text('Username and password are required'), findsOneWidget);
    expect(controller.login, isNull);

    await tester.enterText(_input('Username'), 'new-listener');
    await tester.enterText(_input('Password'), 'new-password');
    await _tapAction(tester, 'Sign in');
    expect(controller.login?.password, 'new-password');
    expect(controller.login?.rememberMe, isFalse);
  });

  testWidgets('change server waits for disconnect and preserves credentials if it fails', (tester) async {
    final pending = Completer<void>();
    final controller = _LoginController()
      .._auth = AuthState(baseUrl: 'https://fresh.test:3000/api', requiresSignIn: true)
      ..logoutResult = pending.future;
    await _pump(tester, controller);
    await tester.enterText(_input('Username'), 'listener');
    await tester.enterText(_input('Password'), 'entered-password');
    final queuedChange = tester.widget<TextButton>(_action('Change server')).onPressed;
    await tester.tap(_action('Change server'));
    await tester.pump();
    expect(controller.logouts, 1);
    expect(tester.widget<TextButton>(_action('Change server')).onPressed, isNull);
    expect(tester.widget<TextButton>(_action('Sign in')).onPressed, isNull);
    queuedChange?.call();
    await tester.pump();
    expect(controller.logouts, 1);

    pending.completeError(StateError('disconnect failed'));
    await tester.pumpAndSettle();
    expect(find.text('Could not disconnect from this server. Try again.'), findsOneWidget);
    expect(tester.widget<TextField>(_input('Username')).controller!.text, 'listener');
    expect(tester.widget<TextField>(_input('Password')).controller!.text, 'entered-password');
    expect(tester.widget<TextButton>(_action('Change server')).onPressed, isNotNull);
  });

  for (final width in [320.0, 390.0, 700.0, 1280.0]) {
    for (final textScale in [1.0, 1.4]) {
      testWidgets('both login stages fit $width at text scale $textScale', (
        tester,
      ) async {
        final controller = _LoginController();
        await _pump(tester, controller, width: width, textScale: textScale);
        expect(tester.takeException(), isNull);
        expect(find.text('CONNECT TO SERVER'), findsOneWidget);

        for (final label in ['Server address', 'Port']) {
          final surface = find
              .descendant(of: _field(label), matching: find.byType(ClipPath))
              .first;
          final rect = tester.getRect(surface);
          expect(rect.height, greaterThanOrEqualTo(width < 820 ? 56 : 48));
          expect(rect.center.dx, width / 2);
          expect(rect.right, lessThanOrEqualTo(width - 20));
        }
        expect(
          tester.getSize(_action('Connect')).height,
          greaterThanOrEqualTo(48),
        );

        await tester.enterText(_input('Server address'), 'server.test');
        await _tapAction(tester, 'Connect');
        expect(controller.probes, ['https://server.test:3000']);
        expect(find.text('SIGN IN'), findsNWidgets(2));
        expect(_input('Password'), findsOneWidget);
        expect(
          tester.widget<TextField>(_input('Password')).obscureText,
          isTrue,
        );
        await tester.ensureVisible(_action('Sign in'));
        await tester.pumpAndSettle();
        expect(
          tester.getSize(_action('Sign in')).height,
          greaterThanOrEqualTo(48),
        );
        expect(tester.takeException(), isNull);

        await _tapAction(tester, 'Change server');
        expect(
          tester.widget<TextField>(_input('Server address')).controller!.text,
          isEmpty,
        );
        expect(tester.widget<TextField>(_input('Port')).controller!.text, isEmpty);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('pasted URL uses encryption and preserves password whitespace', (
    tester,
  ) async {
    final controller = _LoginController();
    await _pump(tester, controller);
    await tester.enterText(
      _input('Server address'),
      'http://music.test:8443/api',
    );
    expect(
      tester.widget<TextField>(_input('Server address')).controller!.text,
      'music.test',
    );
    expect(tester.widget<TextField>(_input('Port')).controller!.text, '8443');
    expect(find.text('HTTP'), findsNothing);
    await _tapAction(tester, 'Connect');
    expect(controller.probes, ['https://music.test:8443']);
    await tester.enterText(_input('Username'), 'listener');
    await tester.enterText(_input('Password'), ' password ');
    await tester.tap(find.text('Remember me'));
    await _tapAction(tester, 'Sign in');
    expect(controller.login, (
      baseUrl: 'https://music.test:8443',
      username: 'listener',
      password: ' password ',
      rememberMe: true,
    ));
    expect(controller.authState.isAuthorized, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'pending connections disable inputs and prevent duplicate submits',
    (tester) async {
      final pending = Completer<bool>();
      final controller = _LoginController()..probeResult = pending.future;
      await _pump(tester, controller);
      await tester.enterText(_input('Server address'), 'server.test');
      final queuedSubmit = tester.widget<TextField>(_input('Port')).onSubmitted;
      final buttonRect = tester.getRect(_action('Connect'));
      await tester.tap(_action('Connect'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester
            .widget<CircularProgressIndicator>(
              find.byType(CircularProgressIndicator),
            )
            .semanticsLabel,
        'Connecting',
      );
      expect(find.text('CONNECT TO SERVER'), findsOneWidget);
      expect(_input('Username'), findsNothing);
      expect(tester.getRect(_action('Connect')), buttonRect);
      expect(
        tester.getCenter(find.byType(CircularProgressIndicator)),
        buttonRect.center,
      );
      expect(
        tester.widget<TextField>(_input('Server address')).enabled,
        isFalse,
      );
      expect(tester.widget<TextButton>(_action('Connect')).onPressed, isNull);
      queuedSubmit?.call('');
      expect(controller.probes, hasLength(1));
      pending.complete(false);
      await tester.pumpAndSettle();
      expect(find.text('Connection failed'), findsOneWidget);
      expect(
        tester.widget<TextField>(_input('Server address')).enabled,
        isTrue,
      );
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(MaterialBanner), findsNothing);
      expect(find.text('CONNECT TO SERVER'), findsOneWidget);
      expect(_input('Username'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      controller.probeResult = Future.value(true);
      await _tapAction(tester, 'Connect');
      expect(controller.probes, hasLength(2));
      expect(_input('Username'), findsOneWidget);
      expect(find.text('Connection failed'), findsNothing);
    },
  );

  testWidgets('successful verification keeps the spinner until completion', (
    tester,
  ) async {
    final pending = Completer<bool>();
    final controller = _LoginController()..probeResult = pending.future;
    await _pump(tester, controller);
    await tester.enterText(_input('Server address'), 'server.test');
    await tester.tap(_action('Connect'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(_input('Username'), findsNothing);
    pending.complete(true);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(_input('Username'), findsOneWidget);
    expect(_input('Server address'), findsNothing);
  });

  testWidgets(
    'short phone keeps actions reachable with keyboard and inline errors',
    (tester) async {
      final controller = _LoginController();
      await _pump(
        tester,
        controller,
        width: 320,
        height: 640,
        keyboardHeight: 280,
        textScale: 1.4,
      );
      await _tapAction(tester, 'Connect');
      expect(find.text('Server address is required'), findsOneWidget);
      await tester.ensureVisible(_input('Server address'));
      await tester.enterText(_input('Server address'), 'server.test');
      await tester.ensureVisible(_input('Port'));
      await tester.enterText(_input('Port'), '65536');
      await _tapAction(tester, 'Connect');
      expect(
        find.text('Port must be a number between 1 and 65535'),
        findsOneWidget,
      );
      expect(controller.probes, isEmpty);
      await tester.ensureVisible(_input('Port'));
      await tester.enterText(_input('Port'), '3000');
      await _tapAction(tester, 'Connect');
      expect(controller.probes, ['https://server.test:3000']);
      await tester.ensureVisible(_action('Sign in'));
      await tester.pumpAndSettle();
      expect(tester.getRect(_action('Sign in')).bottom, lessThanOrEqualTo(360));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('remembered sign-in leaves server address and port empty', (
    tester,
  ) async {
    final controller = _LoginController()
      ..saved = const AuthCredentials(
        baseUrl: 'https://saved.test:8443/api',
        token: 'token',
        username: 'listener',
        trust: testServerTrust,
      );
    await _pump(tester, controller);
    expect(
      tester.widget<TextField>(_input('Server address')).controller!.text,
      isEmpty,
    );
    expect(tester.widget<TextField>(_input('Port')).controller!.text, isEmpty);
    await tester.enterText(_input('Server address'), 'saved.test');
    await tester.enterText(_input('Port'), '8443');
    await _tapAction(tester, 'Connect');
    expect(
      tester.widget<TextField>(_input('Username')).controller!.text,
      'listener',
    );
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
  });
}

class _LoginController extends Fake implements AppController {
  AuthState _auth = AuthState(baseUrl: '');
  AuthCredentials? saved;
  Future<bool>? probeResult;
  Future<void>? logoutResult;
  int logouts = 0;
  final probes = <String>[];
  ({String baseUrl, String username, String password, bool rememberMe})? login;

  @override
  AuthState get authState => _auth;

  @override
  bool get localNetworkPermissionSupported => false;

  @override
  LocalNetworkPermissionState get localNetworkPermissionState =>
      LocalNetworkPermissionState.unknown;

  @override
  Stream<LocalNetworkPermissionState> get localNetworkPermissionStream =>
      const Stream.empty();

  @override
  Future<AuthCredentials?> loadSavedCredentials() async => saved;

  @override
  Future<void> logout() async {
    logouts++;
    await (logoutResult ?? Future<void>.value());
    saved = null;
    _auth = AuthState(baseUrl: '');
  }

  @override
  Future<bool> probeServer(String input) async {
    probes.add(input);
    final ok = await (probeResult ?? Future.value(true));
    _auth = AuthState(baseUrl: input);
    return ok;
  }

  @override
  Future<void> loginWithPassword({
    required String baseUrl,
    required String username,
    required String password,
    bool rememberMe = false,
  }) async {
    login = (
      baseUrl: baseUrl,
      username: username,
      password: password,
      rememberMe: rememberMe,
    );
    _auth = AuthState(baseUrl: baseUrl, isAuthorized: true);
  }
}
