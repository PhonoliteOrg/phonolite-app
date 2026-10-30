import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/ui/features/settings/sections/playback_settings_section.dart';

import '../support/widget_test_helpers.dart';

void main() {
  setUpAll(configureTestFonts);

  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets('mixed-format playback setting explains native output and applies conversion at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = _Controller();
      addTearDown(controller.changes.close);
      await tester.pumpWidget(wrapInTestApp(Scaffold(body: PlaybackSettingsSection(controller: controller))));
      expect(find.textContaining('Preserve each track'), findsOneWidget);
      expect(find.textContaining('may briefly interrupt'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('gapless-resampling')));
      await tester.pumpAndSettle();
      expect(controller.gaplessResampling, isTrue);
      expect(find.textContaining('Keep one output format'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('gapless-resampling')));
      await tester.pumpAndSettle();
      expect(controller.gaplessResampling, isFalse);
      expect(find.textContaining('Preserve each track'), findsOneWidget);
    });
  }
}

class _Controller extends Fake implements AppController {
  final changes = StreamController<bool>.broadcast();
  @override
  bool gaplessResampling = false;
  @override
  Stream<bool> get gaplessResamplingStream => changes.stream;
  @override
  void setGaplessResampling(bool enabled) {
    gaplessResampling = enabled;
    changes.add(enabled);
  }
}
