import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/application/controllers/settings/app_updates_controller.dart';
import 'package:phonolite_app/data/models/updates/app_update_configuration.dart';
import 'package:phonolite_app/data/models/updates/app_update_release.dart';
import 'package:phonolite_app/infrastructure/platform/app/app_update_platform.dart';
import 'package:phonolite_app/infrastructure/updates/app_update_feed.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _UpdatePlatform platform;
  late _Feed feed;
  late AppUpdatesController controller;

  setUp(() {
    platform = _UpdatePlatform();
    feed = _Feed();
    controller = AppUpdatesController(platform: platform, feed: feed, isSupported: () => true);
  });

  tearDown(() async {
    await controller.shutdown();
    controller.dispose();
  });

  Future<void> initialize() => controller.initialize(onInstall: () async {});

  Future<void> withPollingController(Future<void> Function(AppUpdatesController) verify) async {
    final polling = AppUpdatesController(platform: platform, feed: feed, isSupported: () => true);
    try {
      await polling.initialize(onInstall: () async {});
      await verify(polling);
    } finally {
      await polling.shutdown();
      polling.dispose();
    }
  }

  test('unsupported builds make no native or feed requests', () async {
    final unsupported = AppUpdatesController(platform: platform, feed: feed, isSupported: () => false);
    await unsupported.initialize(onInstall: () async {});
    await unsupported.installLatestUpdate();
    await unsupported.shutdown();
    expect(platform.calls, isEmpty);
    expect(feed.checks, 0);
    unsupported.dispose();
  });

  test('Windows debug builds show the disabled tile without starting update checks', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final development = AppUpdatesController(platform: platform, feed: feed);
    try {
      expect(development.showInSettings, isTrue);
      expect(development.supported, isFalse);
      expect(development.disabledReason, contains('disabled in debug builds'));
      await development.initialize(onInstall: () async {});
      await development.installLatestUpdate();
      await development.shutdown();
      expect(development.canInstall, isFalse);
      expect(platform.calls, isEmpty);
      expect(feed.checks, 0);
    } finally {
      development.dispose();
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('startup checks exactly once without opening WinSparkle UI', () async {
    feed.release = const AppUpdateRelease(version: '0.2.1.0');
    await Future.wait([initialize(), initialize()]);
    expect(platform.calls, ['initialize']);
    expect(feed.checks, 1);
    expect(feed.configuration?.currentVersion, '0.2.0.0');
    expect(controller.latestRelease?.displayVersion, '0.2.1');
    expect(controller.canInstall, isTrue);
  });

  testWidgets('checks every two hours, refreshes availability and cancels on shutdown', (tester) async {
    await withPollingController((polling) async {
      expect(feed.checks, 1);
      await tester.pump(const Duration(hours: 1, minutes: 59, seconds: 59));
      expect(feed.checks, 1);
      feed.release = const AppUpdateRelease(version: '0.3.0.0');
      await tester.pump(const Duration(seconds: 1));
      expect(feed.checks, 2);
      expect(polling.canInstall, isTrue);
      feed.release = null;
      await tester.pump(const Duration(hours: 2));
      expect(feed.checks, 3);
      expect(polling.canInstall, isFalse);
      expect(platform.calls, ['initialize']);
      await polling.shutdown();
      await tester.pump(const Duration(hours: 4));
      expect(feed.checks, 3);
      expect(platform.calls, ['initialize', 'dispose']);
    });
  });

  testWidgets('retries a failed startup probe and clears stale availability after a later failure', (tester) async {
    feed.fail = true;
    await withPollingController((polling) async {
      expect(polling.error, isNotNull);
      feed.fail = false;
      feed.release = const AppUpdateRelease(version: '0.2.1.0');
      await tester.pump(const Duration(hours: 2));
      expect(feed.checks, 2);
      expect(polling.canInstall, isTrue);
      expect(polling.error, isNull);
      feed.fail = true;
      await tester.pump(const Duration(hours: 2));
      expect(feed.checks, 3);
      expect(polling.canInstall, isFalse);
      expect(polling.latestRelease, isNull);
      expect(polling.error, contains('offline'));
    });
  });

  testWidgets('periodic checks do not overlap a pending probe or updater action', (tester) async {
    await withPollingController((polling) async {
      feed.pending = Completer<AppUpdateRelease?>();
      await tester.pump(const Duration(hours: 2));
      expect(feed.checks, 2);
      expect(polling.busy, isTrue);
      await tester.pump(const Duration(hours: 2));
      expect(feed.checks, 2);
      feed.pending!.complete(const AppUpdateRelease(version: '0.2.1.0'));
      await tester.pump();
      feed.pending = null;
      platform.pendingShow = Completer<void>();
      final opening = polling.installLatestUpdate();
      await tester.pump(const Duration(hours: 2));
      expect(feed.checks, 2);
      platform.pendingShow!.complete();
      await opening;
      await tester.pump(const Duration(hours: 2));
      expect(feed.checks, 3);
    });
  });

  for (final target in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('$target never shows, initializes or schedules the desktop updater', (tester) async {
      debugDefaultTargetPlatformOverride = target;
      final mobile = AppUpdatesController(platform: platform, feed: feed);
      try {
        expect(mobile.showInSettings, isFalse);
        expect(mobile.supported, isFalse);
        await mobile.initialize(onInstall: () async {});
        await mobile.installLatestUpdate();
        await tester.pump(const Duration(hours: 4));
        await mobile.shutdown();
        expect(platform.calls, isEmpty);
        expect(feed.checks, 0);
        expect(mobile.canInstall, isFalse);
      } finally {
        mobile.dispose();
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  test('no newer release keeps installation disabled', () async {
    await initialize();
    await controller.installLatestUpdate();
    expect(controller.ready, isTrue);
    expect(controller.canInstall, isFalse);
    expect(controller.error, isNull);
    expect(platform.calls, ['initialize']);
  });

  test('a pending probe keeps the tile disabled until a newer release arrives', () async {
    feed.pending = Completer<AppUpdateRelease?>();
    final starting = initialize();
    await Future<void>.delayed(Duration.zero);
    expect(controller.busy, isTrue);
    await controller.installLatestUpdate();
    expect(platform.calls, ['initialize']);
    feed.pending!.complete(const AppUpdateRelease(version: '0.2.2.3'));
    await starting;
    expect(controller.busy, isFalse);
    expect(controller.canInstall, isTrue);
  });

  test('failed startup probes stay disabled and report the failure', () async {
    feed.fail = true;
    await initialize();
    expect(controller.canInstall, isFalse);
    expect(controller.busy, isFalse);
    expect(controller.error, contains('offline'));
    expect(platform.calls, ['initialize']);
  });

  test('opening the updater serializes clicks and allows retry after failure', () async {
    feed.release = const AppUpdateRelease(version: '0.3.0.0');
    await initialize();
    platform.pendingShow = Completer<void>();
    final showing = controller.installLatestUpdate();
    await controller.installLatestUpdate();
    expect(platform.calls, ['initialize', 'show']);
    platform.pendingShow!.completeError(StateError('not ready'));
    await showing;
    expect(controller.error, contains('not ready'));
    expect(controller.canInstall, isTrue);
    platform.pendingShow = null;
    await controller.installLatestUpdate();
    expect(platform.calls, ['initialize', 'show', 'show']);
    expect(controller.error, isNull);
  });

  test('installer requests await graceful shutdown and coalesce duplicates', () async {
    final closing = Completer<void>();
    var shutdowns = 0;
    feed.release = const AppUpdateRelease(version: '0.2.1.0');
    await controller.initialize(
      onInstall: () {
        shutdowns++;
        return closing.future;
      },
    );
    final first = platform.onInstall!();
    final second = platform.onInstall!();
    await controller.installLatestUpdate();
    expect(shutdowns, 1);
    expect(platform.calls, ['initialize']);
    closing.complete();
    await Future.wait([first, second]);
  });

  test('shutdown during native initialization prevents a late network probe', () async {
    platform.pendingInitialization = Completer<AppUpdateConfiguration>();
    final starting = initialize();
    final stopping = controller.shutdown();
    platform.pendingInitialization!.complete(_UpdatePlatform.configuration);
    await Future.wait([starting, stopping]);
    expect(controller.ready, isFalse);
    expect(feed.checks, 0);
    expect(platform.calls, ['initialize', 'dispose']);
  });

  test('shutdown cancels the feed and prevents late availability', () async {
    feed.pending = Completer<AppUpdateRelease?>();
    final starting = initialize();
    await Future<void>.delayed(Duration.zero);
    await controller.shutdown();
    await starting;
    expect(feed.closed, isTrue);
    expect(controller.canInstall, isFalse);
    expect(controller.latestRelease, isNull);
    expect(platform.calls, ['initialize', 'dispose']);
  });
}

class _UpdatePlatform implements AppUpdatePlatform {
  static const configuration = AppUpdateConfiguration(
    available: true,
    feedUrl: 'https://github.com/PhonoliteOrg/phonolite-app/releases/latest/download/windows-appcast.xml',
    currentVersion: '0.2.0.0',
  );

  final calls = <String>[];
  Future<void> Function()? onInstall;
  Completer<void>? pendingShow;
  Completer<AppUpdateConfiguration>? pendingInitialization;

  @override
  Future<AppUpdateConfiguration> initialize({required Future<void> Function() onInstall}) async {
    calls.add('initialize');
    this.onInstall = onInstall;
    return pendingInitialization?.future ?? configuration;
  }

  @override
  Future<void> showUpdate() async {
    calls.add('show');
    await pendingShow?.future;
  }

  @override
  Future<void> dispose() async => calls.add('dispose');
}

class _Feed implements AppUpdateFeed {
  int checks = 0;
  bool fail = false;
  bool closed = false;
  AppUpdateConfiguration? configuration;
  AppUpdateRelease? release;
  Completer<AppUpdateRelease?>? pending;

  @override
  Future<AppUpdateRelease?> latest(AppUpdateConfiguration configuration) async {
    checks++;
    this.configuration = configuration;
    if (fail) throw StateError('offline');
    return pending?.future ?? release;
  }

  @override
  void close() {
    closed = true;
    if (pending case final request? when !request.isCompleted) {
      request.completeError(StateError('closed'));
    }
  }
}
