import 'ui_harness.dart';

/// One discoverable, independently reported trip through the visible UI.
class UiJourney {
  const UiJourney({
    required this.id,
    required this.feature,
    required this.description,
    required this.interactions,
    required this.run,
  });

  final String id;
  final String feature;
  final String description;
  final List<String> interactions;
  final Future<void> Function(UiHarness ui) run;
}

/// Missing device data is a reported prerequisite, never a passing assertion.
class MissingPrerequisite implements Exception {
  const MissingPrerequisite(this.reason);
  final String reason;

  @override
  String toString() => reason;
}
