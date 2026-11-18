import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/data/repositories/preferences_coordinator.dart';
import 'package:phonolite_app/application/controllers/settings/app_settings_controllers.dart';
import 'package:phonolite_app/application/controllers/settings/app_updates_controller.dart';
import 'package:phonolite_app/application/controllers/settings/desktop_settings_controller.dart';
import 'package:phonolite_app/application/controllers/settings/display_settings_controller.dart';
import 'package:phonolite_app/application/controllers/settings/download_settings_controller.dart';
import 'package:phonolite_app/bootstrap/phonolite_app_shell.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/playback/playback_state.dart';
import 'package:phonolite_app/pages/home/home_page.dart';
import 'package:phonolite_app/ui/features/playback/widgets/now_playing_bar.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_nav_icon.dart';

import 'feature_world.dart';
import 'platform_profile.dart';

/// Intent-level operations on the running app. Scenarios say what a person
/// does ("go back", "dismiss this"); the driver chooses the gesture, pointer
/// kind and surface that the current [PlatformProfile] implies.
///
/// Feature-specific steps live in extensions beside this file
/// (`player_steps.dart`, `library_steps.dart`) and build on [activate].
class AppDriver {
  final WidgetTester tester;
  final PlatformProfile profile;
  final WorldController controller;

  /// App-support, cache and documents directory for this run only, so
  /// settings files never reach the developer's profile or leak between runs.
  final Directory storage;

  /// Settings controllers owned by this run, so preference state and pending
  /// saves never carry over from an earlier scenario.
  final AppSettingsControllers settings;

  static const _pathProvider = MethodChannel('plugins.flutter.io/path_provider');

  AppDriver._(this.tester, this.profile, this.controller, this.storage, this.settings);

  /// Pumps the real application shell at the profile's size and platform.
  static Future<AppDriver> launch(WidgetTester tester, PlatformProfile profile, FeatureWorld world) async {
    debugDefaultTargetPlatformOverride = profile.target;
    tester.view.devicePixelRatio = profile.devicePixelRatio;
    tester.view.physicalSize = profile.screen * profile.devicePixelRatio;

    final storage = Directory.systemTemp.createTempSync('phonolite_feature_');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_pathProvider, (_) async => storage.path);

    final preferences = PreferencesCoordinator();
    final settings = AppSettingsControllers(
      display: DisplaySettingsController(preferences: preferences),
      download: DownloadSettingsController(preferences: preferences),
      desktop: DesktopSettingsController(preferences: preferences),
      updates: AppUpdatesController(),
    );
    final controller = (await tester.runAsync(
      () async => WorldController(world, downloadSettings: settings.download),
    ))!;
    final driver = AppDriver._(tester, profile, controller, storage, settings);

    await tester.pumpWidget(PhonoliteAppShell(controller: controller, settings: settings));
    await driver.settle();
    driver._expectProfileSurface();

    return driver;
  }

  PlaybackState get playback => controller.playbackState;

  Track? get currentTrack => controller.currentTrack;

  bool get isPlayerOpen => find.byType(NowPlayingExpandedSheet).evaluate().isNotEmpty;

  /// Releases the app and restores the platform and view overrides.
  Future<void> close() async {
    // Pop overlays first: the expanded sheet records that it is open until its
    // route completes, and an unmounted route never completes.
    final home = find.byType(HomePage);

    if (home.evaluate().isNotEmpty) {
      Navigator.of(tester.element(home), rootNavigator: true).popUntil((route) => route.isFirst);
      await settle();
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(controller.close);
    settings.display.dispose();
    settings.download.dispose();
    settings.desktop.dispose();
    settings.updates.dispose();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_pathProvider, null);
    await tester.runAsync(() => storage.delete(recursive: true));
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    debugDefaultTargetPlatformOverride = null;
  }

  /// Pumps until the UI is idle, for at most about two seconds. Unlike
  /// pumpAndSettle this tolerates playing-state animations that never stop.
  /// When frames go idle it also lets the real event loop run briefly, so
  /// file I/O (into [storage]) can complete and update the UI.
  Future<void> settle() async {
    var realTurns = 0;

    for (var elapsed = 0; elapsed < 2000; elapsed += 50) {
      await tester.pump(const Duration(milliseconds: 50));

      if (tester.binding.hasScheduledFrame) {
        continue;
      }

      if (realTurns++ == 3) {
        return;
      }

      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    }
  }

  /// Waits for background work such as file I/O to reach [condition],
  /// alternating real event-loop turns with frames, for at most five seconds.
  Future<void> waitUntil(bool Function() condition, {required String description}) async {
    for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(condition(), isTrue, reason: 'timed out waiting for $description on ${profile.name}');
  }

  // Input.

  /// Presses a visible control with the profile's primary pointer.
  Future<void> activate(Finder target) async {
    final hittable = target.hitTestable();

    if (hittable.evaluate().isEmpty && target.evaluate().isNotEmpty) {
      await tester.ensureVisible(target.first);
      await settle();
    }

    expect(
      target.hitTestable(),
      findsAtLeastNWidgets(1),
      reason: 'control must be visible and hittable on ${profile.name}',
    );

    final kind = profile.input == PrimaryInput.touch ? PointerDeviceKind.touch : PointerDeviceKind.mouse;
    await tester.tap(target.hitTestable().first, kind: kind);
    await settle();
  }

  /// Presses and holds a control (long-press on touch, held click with a mouse).
  Future<void> hold(Finder target) async {
    expect(target.hitTestable(), findsAtLeastNWidgets(1), reason: 'control must be hittable on ${profile.name}');

    final kind = profile.input == PrimaryInput.touch ? PointerDeviceKind.touch : PointerDeviceKind.mouse;
    await tester.longPress(target.hitTestable().first, kind: kind);
    await settle();
  }

  Future<void> pressKey(LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await settle();
  }

  // Navigation.

  Future<void> openTab(String label) => activate(
    find.byWidgetPredicate(
      (widget) => widget is ObsidianNavIcon && widget.label == label,
      description: 'navigation destination $label',
    ),
  );

  /// Returns one screen using the platform's own back mechanism, not an
  /// on-screen Back control.
  Future<void> goBack() async {
    switch (profile.back) {
      case BackNavigation.systemBack:
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'flutter/navigation',
          const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
          (_) {},
        );
      case BackNavigation.edgeSwipe:
        final gesture = await tester.startGesture(Offset(4, profile.screen.height / 2));

        for (var step = 0; step < 10; step++) {
          await gesture.moveBy(Offset(profile.screen.width * .07, 0));
          await tester.pump(const Duration(milliseconds: 16));
        }

        await gesture.up();
      case BackNavigation.mouseBackButton:
        await _sideButton(kBackMouseButton);
    }

    await settle();
  }

  /// Uses the page's own visible Back link, such as "Back to artist".
  Future<void> tapBackLink(String label) => activate(find.text(label.toUpperCase()));

  /// Reopens the screen [goBack] just left (mouse Forward button).
  Future<void> goForward() async {
    expect(profile.supports(Capability.mouseForward), isTrue, reason: 'scenario must require mouseForward');
    await _sideButton(kForwardMouseButton);
    await settle();
  }

  // Dialogs and generic content.

  /// Leaves the top dialog without committing a choice: Escape with a
  /// keyboard, the visible Close action with touch.
  Future<void> dismissDialog() async {
    if (profile.supports(Capability.keyboardDismiss)) {
      await pressKey(LogicalKeyboardKey.escape);

      return;
    }

    await activate(find.text('CLOSE'));
  }

  Future<void> choose(String label) => activate(find.text(label).last);

  /// A control identified by its label: an icon control's tooltip message,
  /// or a text button's caption (rendered uppercase). The shell hides tooltip
  /// overlays, so match the Tooltip widget rather than its semantics.
  Finder labelled(String label) => find.byWidgetPredicate(
    (widget) =>
        (widget is Tooltip && (widget.message ?? widget.richMessage?.toPlainText()) == label) ||
        (widget is Text && widget.data == label.toUpperCase()),
    description: 'control labelled $label',
  );

  /// A modal action button such as Save, Yes or Cancel (shown uppercase).
  Future<void> modalAction(String label) => activate(find.text(label.toUpperCase()));

  void expectVisible(String text) => expect(find.text(text), findsWidgets);

  void expectNotVisible(String text) => expect(find.text(text), findsNothing);

  /// Asserts [text] is shown on exactly the platforms whose profile offers
  /// [capability], and absent everywhere else.
  void expectShownExactlyWhen(Capability capability, String text) => expect(
    find.text(text),
    profile.supports(capability) ? findsWidgets : findsNothing,
    reason: '"$text" should ${profile.supports(capability) ? '' : 'not '}appear on ${profile.name}',
  );

  /// Asserts [T] is the frontmost page of the selected tab.
  void expectPage<T extends Widget>() {
    final page = find.byType(T);
    expect(page, findsOneWidget, reason: 'expected $T on ${profile.name}');
    expect(ModalRoute.of(tester.element(page))?.isCurrent, isTrue, reason: '$T should be the current route');
  }

  // Implementation.

  void _expectProfileSurface() {
    switch (profile.playerSurface) {
      case PlayerSurface.expandableSheet:
        expect(find.byType(NowPlayingMiniBar), findsOneWidget, reason: '${profile.name} should show the mini bar');
        expect(find.byType(NowPlayingBar), findsNothing);
      case PlayerSurface.dockedBar:
        expect(find.byType(NowPlayingBar), findsOneWidget, reason: '${profile.name} should dock the player bar');
        expect(find.byType(NowPlayingMiniBar), findsNothing);
    }
  }

  Future<void> _sideButton(int button) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse, buttons: button);
    await gesture.down(tester.getCenter(find.byType(HomePage)));
    await gesture.up();
    await gesture.removePointer();
  }
}
