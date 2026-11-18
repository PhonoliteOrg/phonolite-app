import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/data/repositories/preferences_coordinator.dart';
import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/settings/display_settings_controller.dart';
import 'package:phonolite_app/data/models/auth/auth_state.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/preferences/display_settings.dart';
import 'package:phonolite_app/data/storage/preferences/display_settings_storage.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';
import 'package:phonolite_app/pages/favorites/liked_page.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/shared/music/tracks/track_row_tile.dart';

import '../support/offline_library_test_helpers.dart';
import '../support/widget_test_helpers.dart';

void main() {
  testWidgets('tapping a local liked track plays the local liked queue', (tester) async {
    final app = _Controller();
    await _pumpLiked(tester, app);

    await tester.tap(find.text('Local song'));
    await tester.pumpAndSettle();

    expect(app.calls, ['play local liked:local']);

    await _dispose(tester, app);
  });

  testWidgets('tapping a server liked track plays the server liked queue', (tester) async {
    final app = _Controller();
    await _pumpLiked(tester, app);

    await tester.tap(find.text('Server song'));
    await tester.pumpAndSettle();

    expect(app.calls, ['play server liked:server']);

    await _dispose(tester, app);
  });

  testWidgets('the like toggle unlikes a local row locally and a server row on the server', (tester) async {
    final app = _Controller();
    await _pumpLiked(tester, app);

    await tester.tap(_unlikeButton('Local song'));
    await tester.pumpAndSettle();
    await tester.tap(_unlikeButton('Server song'));
    await tester.pumpAndSettle();

    expect(app.calls, ['toggle local like:local', 'toggle server like:server']);

    await _dispose(tester, app);
  });
}

Track _likedTrack(String id, String title) => offlineTestTrack(id: id, title: title).copyWith(liked: true);

Finder _unlikeButton(String title) => find.descendant(
  of: find.ancestor(of: find.text(title), matching: find.byType(TrackRowTile)),
  matching: find.bySemanticsLabel('Unlike'),
);

Future<void> _pumpLiked(WidgetTester tester, _Controller app) async {
  tester.view.physicalSize = const Size(1000, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final display = DisplaySettingsController(preferences: PreferencesCoordinator(display: _MemoryStorage()));
  await display.initialize();
  addTearDown(display.dispose);

  await tester.pumpWidget(
    AppScope(
      controller: app,
      child: wrapInTestApp(LikedPage(displaySettings: display)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _dispose(WidgetTester tester, _Controller app) async {
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox.shrink());
  await app.close();
}

class _MemoryStorage extends DisplaySettingsStorage {
  @override
  Future<DisplaySettings> read() async => const DisplaySettings();

  @override
  Future<void> write(DisplaySettings settings) async {}
}

class _Controller extends AppController {
  final _authChanges = StreamController<AuthState>.broadcast();
  final calls = <String>[];

  _Controller() : super(connection: ServerConnection(baseUrl: 'http://server.test/api'));

  @override
  AuthState get authState => AuthState(isAuthorized: true, baseUrl: connection.baseUrl);

  @override
  Stream<AuthState> get authStream => _authChanges.stream;

  @override
  List<Track> get localLiked => [_likedTrack('local', 'Local song')];

  @override
  Stream<List<Track>> get localLikedStream => const Stream.empty();

  @override
  List<Track> get liked => [_likedTrack('server', 'Server song')];

  @override
  Stream<List<Track>> get likedStream => const Stream.empty();

  @override
  Future<void> loadLocalLikedTracks() async {}

  @override
  Future<void> loadLikedTracks() async {}

  @override
  Future<void> playLocalLikedTrack(String trackId) async => calls.add('play local liked:$trackId');

  @override
  Future<void> playLikedTrack(String trackId) async => calls.add('play server liked:$trackId');

  @override
  Future<void> toggleLocalLike(Track track) async => calls.add('toggle local like:${track.id}');

  @override
  Future<void> toggleLike(Track track) async => calls.add('toggle server like:${track.id}');

  @override
  Future<void> close() async {
    await _authChanges.close();
    await super.close();
  }
}
