import 'dart:async';

import 'package:phonolite_app/data/models/listening_stats/listening_report.dart';
import 'package:phonolite_app/infrastructure/server/api/json_api_endpoint.dart';

class ListeningStatsApi extends JsonApiEndpoint {
  ListeningStatsApi(super.transport);

  Future<StatsResponse> fetchStats({int? year, int? month}) async {
    var path = '/stats';

    if (year != null && month != null) {
      path = '/stats?year=$year&month=$month';
    } else if (year != null) {
      path = '/stats?year=$year';
    } else if (month != null) {
      path = '/stats?month=$month';
    }

    return getValue(path, StatsResponse.fromJson);
  }

  /// Legacy migration queue only; new listening uses the v2 counter endpoints.
  Future<Map<String, dynamic>> fetchListeningChanges({required String deviceId, int after = 0, int limit = 200}) =>
      transport.get(
        '/stats/sync?device_id=${Uri.encodeQueryComponent(deviceId)}&after=$after&limit=$limit',
        retryable: false,
      );

  Future<Map<String, dynamic>> updateListeningPreference({
    required String deviceId,
    required bool enabled,
    required int revision,
  }) => transport.post('/stats/preferences', {'device_id': deviceId, 'enabled': enabled, 'revision': revision});

  Future<Map<String, dynamic>> uploadListeningEvents({
    required String deviceId,
    required int historyGeneration,
    required List<Map<String, dynamic>> events,
  }) => transport.post('/stats/events', {
    'device_id': deviceId,
    'history_generation': historyGeneration,
    'events': events,
  });

  Future<Map<String, dynamic>> resetListeningHistory({required int historyGeneration}) =>
      transport.post('/stats/reset', {'history_generation': historyGeneration});

  Future<Map<String, dynamic>> fetchListeningCounterState({required String deviceId}) =>
      transport.get('/stats/v2/state?device_id=${Uri.encodeQueryComponent(deviceId)}', retryable: false);

  Future<Map<String, dynamic>> activateListeningCounters({required String deviceId, required int historyGeneration}) =>
      transport.post('/stats/v2/activate', {'device_id': deviceId, 'history_generation': historyGeneration});

  Future<Map<String, dynamic>> uploadListeningCounters(Map<String, dynamic> batch) =>
      transport.post('/stats/v2/batch', batch);

  Future<Map<String, dynamic>> fetchListeningCounterSnapshot({
    required String deviceId,
    required int year,
    required int month,
    int? revision,
    String after = '',
  }) => transport.get(
    '/stats/v2/snapshot?device_id=${Uri.encodeQueryComponent(deviceId)}&year=$year&month=$month'
    '&after=${Uri.encodeQueryComponent(after)}${revision == null ? '' : '&revision=$revision'}',
    retryable: false,
  );
}
