import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/ui/shared/design_system/layout/responsive_breakpoints.dart';

void main() {
  for (final platform in [TargetPlatform.windows, TargetPlatform.macOS, TargetPlatform.linux]) {
    test('$platform desktop layout follows width while short tiled windows retain navigation', () {
      for (final layout in [
        (size: const Size(599, 800), mode: ObsidianLayoutMode.compact),
        (size: const Size(600, 360), mode: ObsidianLayoutMode.narrow),
        (size: const Size(640, 360), mode: ObsidianLayoutMode.narrow),
        (size: const Size(768, 432), mode: ObsidianLayoutMode.narrow),
        (size: const Size(960, 540), mode: ObsidianLayoutMode.narrow),
        (size: const Size(979, 800), mode: ObsidianLayoutMode.narrow),
        (size: const Size(980, 360), mode: ObsidianLayoutMode.expanded),
        (size: const Size(1280, 720), mode: ObsidianLayoutMode.expanded),
      ]) {
        expect(obsidianLayoutModeFor(layout.size, platform), layout.mode, reason: '${layout.size}');
      }
    });
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS, TargetPlatform.fuchsia]) {
    test('$platform keeps landscape phones compact and uses available tablet window space', () {
      for (final layout in [
        (size: const Size(390, 844), mode: ObsidianLayoutMode.compact),
        (size: const Size(844, 390), mode: ObsidianLayoutMode.compact),
        (size: const Size(1200, 430), mode: ObsidianLayoutMode.compact),
        (size: const Size(540, 1024), mode: ObsidianLayoutMode.compact),
        (size: const Size(1024, 599), mode: ObsidianLayoutMode.compact),
        (size: const Size(600, 900), mode: ObsidianLayoutMode.narrow),
        (size: const Size(768, 1024), mode: ObsidianLayoutMode.narrow),
        (size: const Size(979, 600), mode: ObsidianLayoutMode.narrow),
        (size: const Size(980, 600), mode: ObsidianLayoutMode.expanded),
        (size: const Size(1024, 768), mode: ObsidianLayoutMode.expanded),
      ]) {
        expect(obsidianLayoutModeFor(layout.size, platform), layout.mode, reason: '${layout.size}');
      }
    });
  }
}
