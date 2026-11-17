import 'package:flutter_test/flutter_test.dart';

import 'app_driver.dart';
import 'feature_world.dart';
import 'platform_profile.dart';

/// One expected behavior, written once and run on every platform profile.
class FeatureScenario {
  final String id;
  final String description;

  /// Interaction IDs from `integration_test/catalog/*.json` this scenario proves.
  final List<String> covers;

  /// Capabilities a profile must offer for this scenario to apply.
  final Set<Capability> requires;

  /// Player surfaces this scenario applies to; empty means all of them.
  final Set<PlayerSurface> surfaces;
  final FeatureWorld Function() world;
  final Future<void> Function(AppDriver app) run;

  const FeatureScenario({
    required this.id,
    required this.description,
    required this.covers,
    required this.world,
    required this.run,
    this.requires = const {},
    this.surfaces = const {},
  });

  /// Why [profile] cannot run this scenario, or null when it applies.
  String? inapplicableReason(PlatformProfile profile) {
    final missing = requires.where((capability) => !profile.supports(capability));

    if (missing.isNotEmpty) {
      return 'needs ${missing.map((capability) => capability.name).join(', ')}';
    }

    if (surfaces.isNotEmpty && !surfaces.contains(profile.playerSurface)) {
      return 'needs ${surfaces.map((surface) => surface.name).join(' or ')} player';
    }

    return null;
  }
}

/// Registers every scenario × profile pair. Inapplicable pairs stay visible
/// as skipped tests so the platform matrix is complete in every report.
void runFeatureScenarios(
  String feature,
  List<FeatureScenario> scenarios, {
  List<PlatformProfile> profiles = allPlatformProfiles,
}) {
  group(feature, () {
    for (final scenario in scenarios) {
      group(scenario.id, () {
        for (final profile in profiles) {
          final reason = scenario.inapplicableReason(profile);
          final name = reason == null ? profile.name : '${profile.name} (n/a: $reason)';

          testWidgets(name, skip: reason != null, (tester) async {
            final app = await AppDriver.launch(tester, profile, scenario.world());

            try {
              await scenario.run(app);
              expect(tester.takeException(), isNull);
            } finally {
              await app.close();
            }
          });
        }
      });
    }
  });
}
