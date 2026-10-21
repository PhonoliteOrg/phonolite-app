import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:phonolite_app/data/models/listening_stats/listening_counters.dart';
import 'package:phonolite_app/data/models/listening_stats/listening_event.dart';
import 'package:phonolite_app/data/repositories/listening_stats_service.dart';

dynamic canonicalCounterJson(dynamic value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()
      ..sort((left, right) {
        final a = left.runes.toList();
        final b = right.runes.toList();
        for (var i = 0; i < a.length && i < b.length; i++) {
          final order = a[i].compareTo(b[i]);
          if (order != 0) return order;
        }
        return a.length.compareTo(b.length);
      });
    return {for (final key in keys) key: canonicalCounterJson(value[key])};
  }
  return value is List ? value.map(canonicalCounterJson).toList() : value;
}

String counterHash(dynamic value) => sha256.convert(utf8.encode(jsonEncode(canonicalCounterJson(value)))).toString();
Map<String, dynamic> counterMetadata(ListeningEvent event) => {
  for (final key in [
    'track_id',
    'title',
    'artist_id',
    'artist_name',
    'album_id',
    'album_title',
    'genres',
    'artists',
    'track_duration_ms',
  ])
    key: event.toJson()[key],
};
Future<Map<String, dynamic>> pendingCounterBatch(ListeningStatsService service) async {
  await service.applyCounterCheckpoint(
    ListeningCounterCheckpoint.fromJson({'upgraded': true, 'last_sequence': 0}),
    collectionRevision: 0,
  );
  return Map<String, dynamic>.from(
    await service.prepareCounterBatch(collectionRevision: 0).then((batch) => batch?.toJson()) as Map,
  );
}

Future<void> confirmCounterBatch(ListeningStatsService service) async {
  final batch = await pendingCounterBatch(service);
  final period = (batch['contributions'] as List).first as Map;
  await service.applyCounterCheckpoint(
    ListeningCounterCheckpoint.fromJson({'upgraded': true, 'last_sequence': batch['batch_sequence']}),
    collectionRevision: 0,
  );
  await service.applyCounterPage(
    ListeningCounterPage.fromJson({
      'history_generation': service.historyGeneration,
      'year': period['year'],
      'month': period['month'],
      'revision': batch['batch_sequence'],
      'checkpoint': {'last_sequence': batch['batch_sequence']},
      'contributions': batch['contributions'],
      'metadata': batch['metadata'],
      'genre_metadata': <String, dynamic>{},
      'next_key': '',
      'has_more': false,
    }),
    after: '',
  );
}
