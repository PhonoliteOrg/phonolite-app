import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'library/library_scenarios.dart';
import 'player/player_scenarios.dart';
import 'playlists/playlist_scenarios.dart';
import 'settings/settings_scenarios.dart';
import 'support/feature_scenario.dart';
import 'support/platform_profile.dart';

/// Every registered feature's scenarios. Add a feature's list here when it
/// gains a `*_feature_test.dart` entry point.
final _allScenarios = <String, List<FeatureScenario>>{
  'player': playerScenarios,
  'library': libraryScenarios,
  'playlists': playlistScenarios,
  'settings': settingsScenarios,
};

void main() {
  final catalogIds = _catalogInteractionIds();

  test('scenario IDs are unique', () {
    final ids = _allScenarios.values.expand((scenarios) => scenarios).map((scenario) => scenario.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
  });

  test('scenarios only claim interactions present in the catalog', () {
    for (final scenario in _allScenarios.values.expand((scenarios) => scenarios)) {
      expect(catalogIds, containsAll(scenario.covers), reason: scenario.id);
    }
  });

  test('every scenario applies to at least one platform', () {
    for (final scenario in _allScenarios.values.expand((scenarios) => scenarios)) {
      expect(
        allPlatformProfiles.where((profile) => scenario.inapplicableReason(profile) == null),
        isNotEmpty,
        reason: scenario.id,
      );
    }
  });

  test('prints the feature × platform coverage matrix', () {
    final header = ['scenario', ...allPlatformProfiles.map((profile) => profile.name)];
    final rows = [
      for (final scenario in _allScenarios.values.expand((scenarios) => scenarios))
        [
          scenario.id,
          for (final profile in allPlatformProfiles) scenario.inapplicableReason(profile) == null ? 'run' : 'n/a',
        ],
    ];
    final width = [for (var column = 0; column < header.length; column++) _widest(header, rows, column)];
    String line(List<String> cells) => [for (var i = 0; i < cells.length; i++) cells[i].padRight(width[i])].join('  ');

    // ignore: avoid_print
    print([line(header), ...rows.map(line)].join('\n'));
  });
}

int _widest(List<String> header, List<List<String>> rows, int column) =>
    [header[column], ...rows.map((row) => row[column])].map((cell) => cell.length).reduce((a, b) => a > b ? a : b);

Set<String> _catalogInteractionIds() {
  final files = Directory('integration_test/catalog')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'));

  return {
    for (final file in files)
      for (final interaction in (jsonDecode(file.readAsStringSync()) as Map<String, dynamic>)['interactions'] as List)
        (interaction as Map<String, dynamic>)['id'] as String,
  };
}
