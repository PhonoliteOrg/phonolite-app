import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phonolite_app/entities/app_controller.dart';
import 'package:phonolite_app/entities/auth_state.dart';
import 'package:phonolite_app/pages/home_page.dart';
import 'package:phonolite_app/widgets/display/download_selection_toolbar.dart';
import 'package:phonolite_app/widgets/layouts/app_scope.dart';
import 'package:phonolite_app/widgets/navigation/command_link_button.dart';
import 'package:phonolite_app/widgets/ui/obsidian_widgets.dart';

import 'frame_metrics.dart';
import 'journey.dart';

/// TooltipVisibility(false) removes RawTooltip semantics in recent Flutter
/// versions. Read the public Tooltip label, not its optional semantic proxy.
Finder tooltipControl(String label) => find.byWidgetPredicate(
  (widget) =>
      widget is Tooltip &&
      (widget.message ?? widget.richMessage?.toPlainText()) == label,
  description: 'tooltip-labelled control $label',
);

Finder commandControl(String label) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is CommandLinkButton && widget.label == label,
    description: 'command labelled $label',
  ),
  // The command's Align can fill the viewport; hit the actual button instead
  // of the centre of that layout wrapper.
  matching: find.byWidgetPredicate((widget) => widget is TextButton),
);

bool hasMatches(Finder finder) {
  try {
    return finder.evaluate().isNotEmpty;
  } on StateError catch (error) {
    // Finder.first may be empty while a stream update builds its control.
    if (error.message == 'No element') return false;
    rethrow;
  }
}

class UiHarness {
  UiHarness(this.tester, this.binding);

  final WidgetTester tester;
  final IntegrationTestWidgetsFlutterBinding binding;
  static const startupTimeout = Duration(seconds: 60);
  static const query = String.fromEnvironment(
    'UI_SEARCH_QUERY',
    defaultValue: 'a',
  );
  static const repeats = int.fromEnvironment('UI_REPEATS', defaultValue: 3);
  static const captureTimeline = bool.fromEnvironment(
    'UI_CAPTURE_TIMELINE',
    defaultValue: true,
  );

  AppController get controller =>
      AppScope.of(tester.element(find.byType(HomePage)));

  Future<void> waitFor(
    Finder finder, {
    Duration timeout = const Duration(seconds: 20),
  }) => waitUntil(
    () => hasMatches(finder),
    // Result descriptions may retain lazy iterators over a previous widget tree.
    // Describe the query without touching those potentially unmounted elements.
    description: finder.toString(describeSelf: true),
    timeout: timeout,
  );

  Future<void> waitUntil(
    bool Function() condition, {
    required String description,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final clock = Stopwatch()..start();
    while (!condition()) {
      if (clock.elapsed >= timeout) fail('Timed out waiting for $description');
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Bounded pumps work even with continuous progress indicators/marquees.
  Future<void> animate([int milliseconds = 450]) async {
    for (var elapsed = 0; elapsed < milliseconds; elapsed += 50) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> ready() async {
    await waitFor(find.byType(HomePage), timeout: startupTimeout);
    await waitUntil(
      () => controller.isInitialized,
      description: 'controller initialization',
      timeout: startupTimeout,
    );
    // Wait for the app's own session restoration instead of triggering login.
    await animate(1500);
    await waitUntil(
      () => controller.authState.status != SessionStatus.checking,
      description: 'session restoration',
      timeout: startupTimeout,
    );
    var rendered = false;
    void onFrames(List<FrameTiming> frames) {
      rendered |= frames.isNotEmpty;
    }

    binding.addTimingsCallback(onFrames);
    try {
      binding.scheduleFrame();
      await waitUntil(
        () => rendered,
        description:
            'real engine frame timings; keep Phonolite visible on the unlocked device',
        timeout: const Duration(seconds: 10),
      );
    } finally {
      binding.removeTimingsCallback(onFrames);
    }
  }

  Finder nav(String label) => find.byWidgetPredicate(
    (widget) => widget is ObsidianNavIcon && widget.label == label,
    description: 'navigation destination $label',
  );

  Future<void> tab(String label) async {
    await tap(nav(label));
  }

  Future<void> tap(Finder target) async {
    await waitFor(target);
    final hit = target.hitTestable();
    if (hit.evaluate().isEmpty) {
      await tester.ensureVisible(target.first);
      await animate(100);
    }
    expect(
      target.hitTestable(),
      findsAtLeastNWidgets(1),
      reason: 'Control must actually be visible and hittable',
    );
    await tester.tap(target.hitTestable().first);
    await animate();
  }

  Future<void> text(String label) => tap(find.text(label));
  Future<void> tooltip(String label) => tap(tooltipControl(label));
  Finder command(String label) => commandControl(label);

  Finder semanticControl(String label) => find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.label == label,
    description: 'control labelled $label',
  );

  Finder get scrollable => find.byType(Scrollable).hitTestable();

  Future<void> scrollRoundTrip() async {
    if (scrollable.evaluate().isEmpty) {
      throw const MissingPrerequisite('No visible scrollable in this layout');
    }
    final candidates =
        scrollable.evaluate().where((e) {
          final direction = (e.widget as Scrollable).axisDirection;
          return direction == AxisDirection.down ||
              direction == AxisDirection.up;
        }).toList()..sort((a, b) {
          double extent(Element e) {
            final p =
                ((e as StatefulElement).state as ScrollableState).position;
            return p.maxScrollExtent - p.minScrollExtent;
          }

          return extent(b).compareTo(extent(a));
        });
    if (candidates.isEmpty) {
      throw const MissingPrerequisite('No vertical scrollable');
    }
    final target = find.byWidget(candidates.first.widget);
    final before = tester.state<ScrollableState>(target).position.pixels;
    var moved = false;
    for (var n = 0; n < repeats; n++) {
      await tester.fling(target, const Offset(0, -380), 900);
      await animate(600);
      moved |=
          (tester.state<ScrollableState>(target).position.pixels - before)
              .abs() >
          1;
      await tester.fling(target, const Offset(0, 380), 900);
      await animate(600);
    }
    if (!moved) {
      throw const MissingPrerequisite(
        'Content fits the viewport; scrolling was not exercised',
      );
    }
  }

  Future<void> back(String label) async {
    await tap(commandControl(label));
    expect(commandControl(label), findsNothing);
  }

  Future<void> closeDialog() async {
    await tap(find.text('CLOSE'));
  }

  /// Recovery only: journeys themselves navigate through visible controls.
  Future<void> resetNavigation() async {
    FocusManager.instance.primaryFocus?.unfocus();
    for (final element
        in find.byType(Navigator, skipOffstage: false).evaluate()) {
      final state = (element as StatefulElement).state as NavigatorState;
      state.popUntil((route) => route.isFirst);
    }
    await animate();
    await tab('Library');
    for (final element
        in find.byType(Scrollable, skipOffstage: false).evaluate()) {
      final position =
          ((element as StatefulElement).state as ScrollableState).position;
      if (position.hasPixels && position.pixels != 0) position.jumpTo(0);
    }
    await animate(150);
    if (find.byType(DownloadSelectionToolbar).evaluate().isNotEmpty) {
      await tooltip('Cancel');
    }
  }

  /// Find an already-built settings row while scrolling its real viewport.
  Future<void> reveal(Finder target) async {
    await waitFor(target);
    await Scrollable.ensureVisible(
      tester.element(target.first),
      duration: const Duration(milliseconds: 300),
      alignment: .25,
    );
    await animate();
  }

  Future<Map<String, Object?>> measure(UiJourney journey) async {
    debugPrint('[ui] start ${journey.id}');
    final frames = <Map<String, int>>[];
    final result = <String, Object?>{
      'id': journey.id,
      'feature': journey.feature,
      'description': journey.description,
      'declared_interactions': journey.interactions,
      'covered_interactions': <String>[],
      'status': 'running',
    };
    final output = binding.reportData ??= <String, dynamic>{};
    final results =
        output.putIfAbsent('journeys', () => <Map<String, Object?>>[]) as List;
    results.add(result);
    var truncated = false;
    void onFrames(List<FrameTiming> batch) {
      for (final f in batch) {
        if (frames.length >= 12000) {
          truncated = true;
          break;
        }
        frames.add({
          'number': f.frameNumber,
          'start_us': f.timestampInMicroseconds(FramePhase.buildStart),
          'build_us': f.buildDuration.inMicroseconds,
          'raster_us': f.rasterDuration.inMicroseconds,
          'vsync_overhead_us': f.vsyncOverhead.inMicroseconds,
          'total_span_us': f.totalSpan.inMicroseconds,
        });
      }
    }

    // Let the engine deliver old timing batches before registering our watcher.
    await animate(250);
    final stopwatch = Stopwatch()..start();
    binding.addTimingsCallback(onFrames);
    try {
      await journey.run(this);
      expect(tester.takeException(), isNull, reason: journey.id);
      result['status'] = 'passed';
      result['covered_interactions'] = journey.interactions;
    } on MissingPrerequisite catch (error) {
      result['status'] = 'skipped';
      result['reason'] = error.reason;
    } catch (error) {
      result['status'] = 'failed';
      result['diagnostics'] = {
        'lifecycle': binding.lifecycleState?.name,
        'collection_list_mode': controller.collectionListMode,
        'tooltips': tester
            .widgetList<Tooltip>(find.byType(Tooltip))
            .map((widget) => widget.message)
            .whereType<String>()
            .toList(),
      };
      // Avoid serializing widget trees, server addresses, or text field values.
      result['reason'] = 'Journey failed; see the flutter drive test output.';
      rethrow;
    } finally {
      await animate(350);
      binding.removeTimingsCallback(onFrames);
      stopwatch.stop();
      final requestedFps = double.tryParse(
        const String.fromEnvironment('UI_TARGET_FPS'),
      );
      final displayFps = tester.view.display.refreshRate;
      final targetFps = requestedFps ?? (displayFps > 0 ? displayFps : 60.0);
      result.addAll({
        'catalog_artist_count': controller.artists.length,
        'elapsed_ms': stopwatch.elapsedMilliseconds,
        'metrics': summarizeFrames(frames, targetFps: targetFps),
        'frames_truncated': truncated,
        'frames': frames,
      });
      debugPrint(
        '[ui] ${result['status']} ${journey.id}: ${frames.length} frames',
      );
    }
    return result;
  }
}
