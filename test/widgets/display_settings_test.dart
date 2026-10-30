import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/library/catalog_controller.dart';
import 'package:phonolite_app/application/controllers/settings/display_settings_controller.dart';
import 'package:phonolite_app/data/models/auth/auth_state.dart';
import 'package:phonolite_app/data/models/diagnostics/log_entry.dart';
import 'package:phonolite_app/data/models/preferences/display_settings.dart';
import 'package:phonolite_app/data/models/preferences/offline_storage_locations.dart';
import 'package:phonolite_app/data/storage/preferences/display_settings_storage.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';
import 'package:phonolite_app/pages/settings/settings_page.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_switch.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_section_header.dart';

import '../support/widget_test_helpers.dart';

const _toggleKeys = ['display-library-local-first', 'display-playlists-local-first', 'display-likes-local-first'];

void main() {
  setUpAll(configureTestFonts);

  for (final width in [320.0, 390.0, 1280.0]) {
    for (final status in SessionStatus.values) {
      testWidgets('Display settings require a connected session at $width in $status', (tester) async {
        final app = _AppController(status);
        final display = DisplaySettingsController(storage: _MemoryStorage());
        await display.initialize();
        await _pump(tester, app, display, width: width);

        final expected = status == SessionStatus.authenticated ? findsOneWidget : findsNothing;

        expect(_displayHeader(), expected);

        for (final key in _toggleKeys) {
          expect(find.byKey(ValueKey(key)), expected);
        }

        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('connection changes hide the empty category and preserve preferences through reconnect', (tester) async {
    final app = _AppController(SessionStatus.offline);
    final display = DisplaySettingsController(storage: _MemoryStorage());
    await display.initialize();
    await _pump(tester, app, display);

    expect(_displayHeader(), findsNothing);

    app.setStatus(SessionStatus.authenticated);
    await tester.pumpAndSettle();

    expect(_displayHeader(), findsOneWidget);
    await _tapToggle(tester, _toggleKeys.first);

    expect(display.settings.libraryLocalFirst, isFalse);

    for (final disconnected in [SessionStatus.serverUnavailable, SessionStatus.offline, SessionStatus.checking]) {
      app.setStatus(disconnected);
      await tester.pumpAndSettle();

      expect(_displayHeader(), findsNothing);

      for (final key in _toggleKeys) {
        expect(find.byKey(ValueKey(key)), findsNothing);
      }
    }

    app.setStatus(SessionStatus.authenticated);
    await tester.pumpAndSettle();

    expect(_displayHeader(), findsOneWidget);
    expect(tester.widget<ObsidianSwitch>(find.byKey(ValueKey(_toggleKeys.first))).value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('display toggles update only their own page preference', (tester) async {
    final app = _AppController(SessionStatus.authenticated);
    final storage = _MemoryStorage();
    final display = DisplaySettingsController(storage: storage);
    await display.initialize();
    await _pump(tester, app, display);

    await _tapToggle(tester, _toggleKeys[0]);

    expect(display.settings.toJson(), {
      'libraryLocalFirst': false,
      'playlistsLocalFirst': true,
      'likesLocalFirst': true,
    });

    await _tapToggle(tester, _toggleKeys[1]);

    expect(display.settings.toJson(), {
      'libraryLocalFirst': false,
      'playlistsLocalFirst': false,
      'likesLocalFirst': true,
    });

    await _tapToggle(tester, _toggleKeys[2]);

    expect(storage.saved.toJson(), {
      'libraryLocalFirst': false,
      'playlistsLocalFirst': false,
      'likesLocalFirst': false,
    });

    await _tapToggle(tester, _toggleKeys[0]);

    expect(display.settings.libraryLocalFirst, isTrue);
    expect(display.settings.playlistsLocalFirst, isFalse);
    expect(display.settings.likesLocalFirst, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending display saves keep every switch enabled and update titles immediately', (tester) async {
    final app = _AppController(SessionStatus.authenticated);
    final storage = _DelayedStorage();
    final display = DisplaySettingsController(storage: storage);
    addTearDown(storage.finishWrites);
    await display.initialize();
    await _pump(tester, app, display);
    await _tapToggle(tester, _toggleKeys[0]);

    expect(display.saving, isTrue);
    expect(find.text('Library: server first'), findsOneWidget);
    expect(find.text('Playlists: local first'), findsOneWidget);
    expect(find.text('Likes: local first'), findsOneWidget);

    for (final key in _toggleKeys) {
      expect(tester.widget<ObsidianSwitch>(find.byKey(ValueKey(key))).onChanged, isNotNull);
    }

    await _tapToggle(tester, _toggleKeys[1]);
    await _tapToggle(tester, _toggleKeys[0]);

    expect(display.saving, isTrue);
    expect(find.text('Library: local first'), findsOneWidget);
    expect(find.text('Playlists: server first'), findsOneWidget);
    expect(tester.widget<ObsidianSwitch>(find.byKey(ValueKey(_toggleKeys[0]))).value, isTrue);
    expect(tester.widget<ObsidianSwitch>(find.byKey(ValueKey(_toggleKeys[1]))).value, isFalse);

    for (final key in _toggleKeys) {
      expect(tester.widget<ObsidianSwitch>(find.byKey(ValueKey(key))).onChanged, isNotNull);
    }

    storage.finishWrites();
    await tester.pumpAndSettle();

    expect(display.saving, isFalse);
    expect(storage.saved, const DisplaySettings(playlistsLocalFirst: false));
    expect(tester.takeException(), isNull);
  });
}

Finder _displayHeader() =>
    find.byWidgetPredicate((widget) => widget is ObsidianSectionHeader && widget.title == 'Display');

Future<void> _tapToggle(WidgetTester tester, String key) async {
  final toggle = find.byKey(ValueKey(key));

  await tester.ensureVisible(toggle);
  await tester.pumpAndSettle();
  await tester.tap(toggle);
  await tester.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester tester,
  _AppController app,
  DisplaySettingsController display, {
  double width = 390,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1000);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await app.updates.close();
    app.connection.close();
    display.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    AppScope(
      controller: app,
      child: wrapInTestApp(SettingsPage(displaySettings: display)),
    ),
  );
  await tester.pumpAndSettle();
}

class _MemoryStorage extends DisplaySettingsStorage {
  DisplaySettings saved = const DisplaySettings();

  @override
  Future<DisplaySettings> read() async => saved;

  @override
  Future<void> write(DisplaySettings settings) async => saved = settings;
}

class _DelayedStorage extends _MemoryStorage {
  final _writes = Completer<void>();

  void finishWrites() {
    if (!_writes.isCompleted) {
      _writes.complete();
    }
  }

  @override
  Future<void> write(DisplaySettings settings) async {
    await _writes.future;

    await super.write(settings);
  }
}

class _AppController extends Fake implements AppController {
  @override
  bool get gaplessResampling => false;
  @override
  Stream<bool> get gaplessResamplingStream => const Stream.empty();
  @override
  void setGaplessResampling(bool enabled) {}

  @override
  final connection = ServerConnection(
    baseUrl: 'https://display.test/api',
    client: MockClient((_) async => throw StateError('Display settings must not make server requests')),
  );
  final updates = StreamController<AuthState>.broadcast();
  late final CatalogController _catalog = CatalogController(connection);
  SessionStatus status;

  _AppController(this.status);

  @override
  CatalogController get catalog => _catalog;

  @override
  AuthState get authState => AuthState(baseUrl: connection.baseUrl, status: status);

  @override
  Stream<AuthState> get authStream => updates.stream;

  @override
  List<LogEntry> get messages => const [];

  @override
  Stream<List<LogEntry>> get messageStream => const Stream.empty();

  @override
  bool get sessionManagementAvailable => false;

  @override
  bool get statsCollectionEnabled => true;

  @override
  Stream<bool> get statsCollectionEnabledStream => const Stream.empty();

  @override
  OfflineStorageLocations? get offlineStorageLocations => null;

  @override
  Stream<OfflineStorageLocations> get offlineStorageLocationsStream => const Stream.empty();

  void setStatus(SessionStatus next) {
    status = next;
    updates.add(authState);
  }

  @override
  Future<void> setStatsCollectionEnabled(bool value) async {}
}
