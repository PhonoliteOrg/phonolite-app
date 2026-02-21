import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'entities/app_controller.dart';
import 'entities/server_connection.dart';
import 'entities/auth_state.dart';
import 'pages/home_page.dart';
import 'pages/login_page.dart';
import 'pages/splash_page.dart';
import 'widgets/layouts/app_scope.dart';
import 'widgets/layouts/obsidian_scale.dart';
import 'widgets/ui/obsidian_background.dart';
import 'widgets/ui/obsidian_theme.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  runApp(const PhonoliteApp());
}

class PhonoliteApp extends StatefulWidget {
  const PhonoliteApp({super.key});

  @override
  State<PhonoliteApp> createState() => _PhonoliteAppState();
}

class _PhonoliteAppState extends State<PhonoliteApp> {
  late final AppController _controller;
  late final Future<void> _restoreFuture;

  @override
  void initState() {
    super.initState();
    const baseUrl = String.fromEnvironment(
      'PHONOLITE_URL',
      defaultValue: 'http://127.0.0.1:3000/api/v1',
    );
    final connection = ServerConnection(baseUrl: baseUrl);

    _controller = AppController(connection: connection);
    _restoreFuture = _controller.restoreSession();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: _controller,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = ObsidianScale.compute(constraints.maxWidth);
          return MaterialApp(
            title: 'Phonolite',
            theme: ObsidianTheme.build(scale: scale),
            builder: (context, child) => ObsidianBackground(
              child: ObsidianScale(
                scale: scale,
                child: child ?? const SizedBox.shrink(),
              ),
            ),
            home: StreamBuilder<AuthState>(
              stream: _controller.authStream,
              initialData: _controller.authState,
              builder: (context, snapshot) {
                return FutureBuilder<void>(
                  future: _restoreFuture,
                  builder: (context, restoreSnapshot) {
                    if (restoreSnapshot.connectionState !=
                        ConnectionState.done) {
                      return const SplashPage();
                    }
                    final state = snapshot.data ?? _controller.authState;
                    if (!state.isAuthorized) {
                      return LoginPage(controller: _controller);
                    }
                    return const HomePage();
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}
