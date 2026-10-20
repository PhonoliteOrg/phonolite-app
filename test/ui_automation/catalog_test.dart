import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/journeys/all_journeys.dart';
import '../../integration_test/audio/player_controls_suite.dart';

void main() {
  test(
    'interaction IDs, source references and journey coverage stay consistent',
    () {
      final catalog = <String, Map<String, dynamic>>{};
      final directory = Directory('integration_test/catalog');
      for (final file in directory.listSync().whereType<File>().where(
        (f) => f.path.endsWith('.json'),
      )) {
        final feature =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        for (final source in feature['sources'] as List) {
          expect(File(source as String).existsSync(), isTrue, reason: source);
        }
        for (final value in feature['interactions'] as List) {
          final entry = value as Map<String, dynamic>;
          final id = entry['id'] as String;
          expect(catalog.containsKey(id), isFalse, reason: 'Duplicate $id');
          expect(id, matches(r'^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$'));
          expect(entry['action'], isNotEmpty);
          expect(entry['expected'], isNotEmpty);
          catalog[id] = entry;
        }
      }
      final ids = <String>{};
      for (final journey in allJourneys) {
        expect(ids.add(journey.id), isTrue, reason: 'Duplicate ${journey.id}');
        for (final id in journey.interactions) {
          expect(
            catalog.containsKey(id),
            isTrue,
            reason: 'Missing inventory item $id',
          );
          expect(catalog[id]!['journeys'], contains(journey.id), reason: id);
        }
      }
      for (final entry in catalog.values) {
        for (final id in entry['playback_journeys'] as List? ?? []) {
          expect(playerControlIds, contains(id), reason: '${entry['id']}');
        }
        for (final id in entry['journeys'] as List) {
          final journey = allJourneys.singleWhere((j) => j.id == id);
          expect(journey.interactions, contains(entry['id']));
        }
      }
    },
  );
}
