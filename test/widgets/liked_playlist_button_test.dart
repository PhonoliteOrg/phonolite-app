import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/settings/display_settings_controller.dart';
import 'package:phonolite_app/data/models/auth/auth_state.dart';
import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/preferences/display_settings.dart';
import 'package:phonolite_app/data/storage/preferences/display_settings_storage.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';
import 'package:phonolite_app/pages/favorites/liked_page.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/features/playlists/widgets/playlist_editor_modal.dart';

import '../support/offline_library_test_helpers.dart';
import '../support/widget_test_helpers.dart';

void main() {
  setUpAll(configureTestFonts);

  const tooltip = 'Create playlist from liked tracks';

  testWidgets('the liked-tracks playlist button is disabled without liked tracks', (tester) async {
    final app = _Controller(connected: false);
    await _pumpLiked(tester, app);

    expect(find.byTooltip(tooltip), findsOneWidget);

    await tester.tap(find.byTooltip(tooltip));
    await tester.pumpAndSettle();
    expect(find.byType(PlaylistEditorModal), findsNothing);

    await _dispose(tester, app);
  });

  testWidgets('the button opens the create playlist modal and saves local liked tracks', (tester) async {
    final app = _Controller(connected: false, localTracks: [_track('b'), _track('a')]);
    await _pumpLiked(tester, app);

    await tester.tap(find.byTooltip(tooltip));
    await tester.pumpAndSettle();

    final modal = tester.widget<PlaylistEditorModal>(find.byType(PlaylistEditorModal));
    expect(modal.title, 'Create playlist from liked tracks');
    expect(modal.showTargetSelector, isFalse);
    expect(
      find.text('Your 2 local liked tracks will be added to this new local playlist, in the order shown.'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField).first, 'From likes');
    await tester.pump();
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();

    expect(app.calls, ['local:From likes:b,a']);
    expect(find.byType(PlaylistEditorModal), findsNothing);

    await _dispose(tester, app);
  });

  testWidgets('with both sources the modal offers a target and saves server liked tracks', (tester) async {
    final app = _Controller(connected: true, localTracks: [_track('l')], serverTracks: [_track('s2'), _track('s1')]);
    await _pumpLiked(tester, app, localFirst: false);

    await tester.tap(find.byTooltip(tooltip));
    await tester.pumpAndSettle();

    final modal = tester.widget<PlaylistEditorModal>(find.byType(PlaylistEditorModal));
    expect(modal.showTargetSelector, isTrue);
    expect(modal.initialTarget, PlaylistEditorTarget.server);
    expect(
      find.text('Your 2 server liked tracks will be added to this new server playlist, in the order shown.'),
      findsOneWidget,
    );

    await tester.tap(find.text('LOCAL'));
    await tester.pumpAndSettle();
    expect(
      find.text('Your 1 local liked track will be added to this new local playlist, in the order shown.'),
      findsOneWidget,
    );
    await tester.tap(find.text('SERVER'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Server likes');
    await tester.pump();
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();

    expect(app.calls, ['server:Server likes:s2,s1']);

    await _dispose(tester, app);
  });
}

Track _track(String id) => offlineTestTrack(id: id, title: id);

Future<void> _pumpLiked(WidgetTester tester, _Controller app, {bool localFirst = true}) async {
  tester.view.physicalSize = const Size(1000, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final display = DisplaySettingsController(storage: _MemoryStorage());
  await display.initialize();
  await display.setLikesLocalFirst(localFirst);
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
  final bool connected;
  final List<Track> localTracks;
  final List<Track> serverTracks;
  final _authChanges = StreamController<AuthState>.broadcast();
  final calls = <String>[];

  _Controller({required this.connected, this.localTracks = const [], this.serverTracks = const []})
    : super(connection: ServerConnection(baseUrl: 'http://server.test/api'));

  @override
  AuthState get authState => AuthState(isAuthorized: connected, baseUrl: connection.baseUrl);

  @override
  Stream<AuthState> get authStream => _authChanges.stream;

  @override
  List<Track> get localLiked => localTracks;

  @override
  Stream<List<Track>> get localLikedStream => const Stream.empty();

  @override
  List<Track> get liked => serverTracks;

  @override
  Stream<List<Track>> get likedStream => const Stream.empty();

  @override
  Future<void> loadLocalLikedTracks() async {}

  @override
  Future<void> loadLikedTracks() async {}

  @override
  Future<void> createLocalPlaylist(
    String name, {
    String? description,
    PlaylistImageEdit imageEdit = const PlaylistImageEdit.keep(),
    List<Track> tracks = const <Track>[],
  }) async => calls.add('local:$name:${tracks.map((track) => track.id).join(',')}');

  @override
  Future<void> createPlaylist(
    String name, {
    String? description,
    PlaylistImageEdit imageEdit = const PlaylistImageEdit.keep(),
    List<Track> tracks = const <Track>[],
  }) async => calls.add('server:$name:${tracks.map((track) => track.id).join(',')}');

  @override
  Future<void> close() async {
    await _authChanges.close();
    await super.close();
  }
}
