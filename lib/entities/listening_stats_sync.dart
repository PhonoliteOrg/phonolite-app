import 'dart:async';
import 'dart:math';

import 'listening_stats.dart';
import 'server_connection.dart';

/// Opportunistic synchronization. Playback never awaits this work.
class ListeningStatsSync {
  ListeningStatsSync({
    required this.history,
    required this.connection,
    required this.isAuthorized,
    required this.onChanged,
    required this.onIdentity,
  });

  final ListeningStatsService history;
  final ServerConnection connection;
  final bool Function() isAuthorized;
  final void Function() onChanged;
  final Future<void> Function(String serverId, String userId) onIdentity;
  Future<void>? _running;
  Future<void>? _resetting;
  Timer? _retry;
  Timer? _periodic;
  bool _closed = false;
  int _failures = 0;
  final Random _random = Random();
  bool syncing = false;
  bool serverCollectionEnabled = false;
  String? message;

  void start() {
    _periodic ??= Timer.periodic(const Duration(minutes: 5), (_) {
      // Disabled devices still need to learn about account history deletion.
      unawaited(sync());
    });
  }

  Future<void> sync({bool immediate = false}) {
    if (_resetting != null) return Future<void>.value();
    if (_closed || !isAuthorized() || history.deviceId.isEmpty) {
      return Future<void>.value();
    }
    if (immediate) {
      _retry?.cancel();
      _retry = null;
    } else if (_retry != null) {
      return Future<void>.value();
    }
    final running = _running;
    if (running != null) {
      // In particular, an opt-out arriving during upload must still deliver
      // its preference after the current request finishes.
      return immediate ? running.then((_) => sync(immediate: true)) : running;
    }
    final work = _sync();
    _running = work;
    return work.whenComplete(() {
      if (identical(_running, work)) _running = null;
    });
  }

  bool _current(int revision, {bool duringReset = false}) =>
      !_closed &&
      (duringReset || _resetting == null) &&
      isAuthorized() &&
      revision == connection.sessionRevision;

  Future<void> resetAccountHistory() {
    final resetting = _resetting;
    if (resetting != null) return resetting;
    final work = _resetAccountHistory(connection.sessionRevision);
    _resetting = work;
    return work.whenComplete(() {
      if (identical(_resetting, work)) _resetting = null;
    });
  }

  Future<void> _resetAccountHistory(int revision) async {
    _retry?.cancel();
    _retry = null;
    // Finish any upload/download before resetting this account's history.
    await _running;
    void checkSession() {
      if (!_current(revision, duringReset: true)) {
        throw StateError('Connect and sign in to reset account history.');
      }
    }

    checkSession();
    final state = await connection.fetchListeningCounterState(
      deviceId: history.deviceId,
    );
    checkSession();
    final serverId = state['server_id']?.toString() ?? '';
    final userId = state['user_id']?.toString() ?? '';
    final generation = (state['history_generation'] as num?)?.toInt() ?? 0;
    if (serverId.isEmpty || userId.isEmpty || generation < 1) {
      throw StateError('Missing account history identity.');
    }
    final result = await connection.resetListeningHistory(
      historyGeneration: generation,
    );
    checkSession();
    final nextGeneration = (result['history_generation'] as num?)?.toInt() ?? 0;
    if (result['server_id'] != serverId ||
        result['user_id'] != userId ||
        nextGeneration <= generation) {
      throw StateError('Invalid account reset response.');
    }
    await history.setAccount(
      serverId: serverId,
      userId: userId,
      historyGeneration: nextGeneration,
    );
    checkSession();
    await onIdentity(serverId, userId);
    message = null;
    _failures = 0;
    onChanged();
  }

  Future<void> _sync() async {
    final revision = connection.sessionRevision;
    syncing = true;
    onChanged();
    var continueSoon = false;
    try {
      // Check identity/preferences before uploads. Never guess ownership from
      // a username, URL, token or the account that happens to be current later.
      final state = await connection.fetchListeningCounterState(
        deviceId: history.deviceId,
      );
      if (!_current(revision)) return;
      final serverId = state['server_id']?.toString() ?? '';
      final userId = state['user_id']?.toString() ?? '';
      if (serverId.isEmpty || userId.isEmpty) {
        throw StateError('Missing account identity');
      }
      final generation = (state['history_generation'] as num?)?.toInt() ?? 1;
      await history.setAccount(
        serverId: serverId,
        userId: userId,
        historyGeneration: generation,
      );
      if (!_current(revision)) return;
      await onIdentity(serverId, userId);
      if (!_current(revision)) return;
      final scope = history.accountScope;
      serverCollectionEnabled = state['collection_enabled'] == true;
      var serverPreference =
          (state['preference_revision'] as num?)?.toInt() ?? 0;
      var serverEnabled = state['device_enabled'] != false;
      var acknowledgedIntent =
          await history.counterOperation(
                'consent',
                scope: scope,
                generation: generation,
              )
              as int;
      // A toggle can occur while a request is in flight. Complete the latest
      // preference before sending any further listening events.
      for (var attempt = 0; attempt < 4; attempt++) {
        final desired = history.enabled;
        final localRevision = history.preferenceRevision;
        final intent = history.collectionIntentRevision;
        if (serverEnabled == desired && acknowledgedIntent == intent) {
          break;
        }
        final pref = await connection.updateListeningPreference(
          deviceId: history.deviceId,
          enabled: desired,
          revision: max(localRevision, serverPreference + 1),
        );
        if (!_current(revision) || history.accountScope != scope) return;
        serverPreference =
            (pref['revision'] as num?)?.toInt() ?? serverPreference;
        serverEnabled = pref['enabled'] == true;
        if (history.enabled == desired &&
            serverEnabled == desired &&
            localRevision == history.preferenceRevision) {
          await history.counterOperation(
            'consent_ack',
            scope: scope,
            generation: generation,
            arguments: {'consent_epoch': intent},
          );
          acknowledgedIntent = intent;
          break;
        }
      }
      if (serverEnabled != history.enabled ||
          acknowledgedIntent != history.collectionIntentRevision) {
        throw StateError('Collection preference not acknowledged');
      }
      final preferenceRevision = history.preferenceRevision;
      if (serverCollectionEnabled && history.enabled) {
        for (var batch = 0; batch < 5; batch++) {
          final events = await history.pendingEvents(limit: 200);
          if (!_current(revision) ||
              !history.enabled ||
              history.accountScope != scope) {
            return;
          }
          if (events.isEmpty) break;
          final result = await connection.uploadListeningEvents(
            deviceId: history.deviceId,
            historyGeneration: generation,
            events: events.map((event) => event.toJson()).toList(),
          );
          if (!_current(revision) || history.accountScope != scope) return;
          final accepted = (result['accepted'] as List? ?? const [])
              .map((id) => id.toString())
              .toList();
          await history.acknowledge(accepted, scope: scope);
          final rejected = result['rejected'] as List? ?? const [];
          if (rejected.isNotEmpty) {
            // Keep invalid records locally, but do not let one permanently
            // rejected record block every following batch.
            await history.reject(
              rejected
                  .whereType<Map>()
                  .map((item) => item['event_id'].toString())
                  .toList(),
              scope: scope,
            );
            message =
                'Some listening records could not be synced. Your local history is retained.';
          }
          if (accepted.isEmpty && rejected.isEmpty) {
            throw StateError('Missing upload acknowledgment');
          }
          continueSoon =
              batch == 4 && (await history.pendingEvents(limit: 1)).isNotEmpty;
        }
      }
      if (!_current(revision) || history.accountScope != scope) return;
      // Drain the old queue using original IDs before retiring this device's
      // v1 writer. The server can then safely discard its old event ledger.
      if ((await history.pendingEvents(limit: 1)).isNotEmpty) {
        continueSoon = history.enabled && serverCollectionEnabled;
        return;
      }
      await connection.activateListeningCounters(
        deviceId: history.deviceId,
        historyGeneration: generation,
      );
      if (!_current(revision) || history.accountScope != scope) return;
      await history.counterOperation(
        'compact_legacy',
        scope: scope,
        generation: generation,
      );
      for (var pass = 0; pass < 5; pass++) {
        // This read occurs after the preference barrier. A canceled request
        // either committed before the barrier or can never commit afterwards.
        var current = await connection.fetchListeningCounterState(
          deviceId: history.deviceId,
        );
        if (!_current(revision) || history.accountScope != scope) return;
        if (current['server_id'] != serverId || current['user_id'] != userId) {
          return;
        }
        if (current['history_generation'] != generation) {
          await history.setAccount(
            serverId: serverId,
            userId: userId,
            historyGeneration: current['history_generation'] as int,
          );
          continueSoon = true;
          return;
        }
        await history.counterOperation(
          'checkpoint',
          scope: scope,
          generation: generation,
          arguments: {
            'checkpoint': current['checkpoint'],
            'collection_revision': serverPreference,
          },
        );
        final pendingBeforePrepare = history.pendingCount;
        final batch =
            await history.counterOperation(
                  'prepare',
                  scope: scope,
                  generation: generation,
                  arguments: {'collection_revision': serverPreference},
                )
                as Map?;
        if (history.pendingCount < pendingBeforePrepare) {
          message =
              'Some listening updates could not be synced. Your local history is retained.';
        }
        if (!_current(revision) || history.accountScope != scope) return;
        if (batch != null &&
            history.enabled &&
            serverEnabled &&
            serverCollectionEnabled) {
          if (preferenceRevision != history.preferenceRevision) {
            continueSoon = true;
            return;
          }
          Map<String, dynamic> result;
          try {
            result = await connection.uploadListeningCounters(
              Map<String, dynamic>.from(batch),
            );
          } on ApiException catch (error) {
            if (![400, 413, 422].contains(error.statusCode)) rethrow;
            if (!_current(revision) || history.accountScope != scope) return;
            await history.counterOperation(
              'quarantine',
              scope: scope,
              generation: generation,
            );
            message =
                'Some listening updates could not be synced. Your local history is retained.';
            continueSoon = true;
            return;
          }
          if (!_current(revision) || history.accountScope != scope) return;
          if ((result['last_sequence'] as int? ?? 0) <
              (batch['batch_sequence'] as int)) {
            throw StateError('Missing counter acknowledgment');
          }
          current = await connection.fetchListeningCounterState(
            deviceId: history.deviceId,
          );
          if (!_current(revision) || history.accountScope != scope) return;
          if (current['history_generation'] != generation ||
              current['server_id'] != serverId ||
              current['user_id'] != userId) {
            continueSoon = true;
            return;
          }
          await history.counterOperation(
            'checkpoint',
            scope: scope,
            generation: generation,
            arguments: {
              'checkpoint': current['checkpoint'],
              'collection_revision': serverPreference,
            },
          );
        }
        final cached =
            await history.counterOperation(
                  'months',
                  scope: scope,
                  generation: generation,
                )
                as List;
        final revisions = {
          for (final item in cached)
            '${(item as Map)['year']}:${item['month']}': item['revision'],
        };
        var changed = 0;
        for (final item in current['months'] as List? ?? const []) {
          final period = item as Map;
          if (revisions['${period['year']}:${period['month']}'] ==
              period['revision']) {
            continue;
          }
          if (changed++ >= 24) {
            continueSoon = true;
            break;
          }
          var after = '';
          int? monthRevision;
          while (true) {
            final page = await connection.fetchListeningCounterSnapshot(
              deviceId: history.deviceId,
              year: period['year'] as int,
              month: period['month'] as int,
              revision: monthRevision,
              after: after,
            );
            if (!_current(revision) || history.accountScope != scope) return;
            if (page['history_generation'] != generation) {
              continueSoon = true;
              return;
            }
            await history.counterOperation(
              'snapshot',
              scope: scope,
              generation: generation,
              arguments: {'page': page, 'after': after},
            );
            if (page['has_more'] != true) break;
            monthRevision = page['revision'] as int;
            after = page['next_key'] as String;
          }
        }
        if (batch == null || !history.enabled || !serverCollectionEnabled) {
          break;
        }
        continueSoon = pass == 4 && history.pendingCount > 0;
      }
      if (message?.startsWith('Some listening') != true) message = null;
      _failures = 0;
    } on ApiException catch (error) {
      if (!_current(revision)) return;
      if (error.statusCode == 404 || error.statusCode == 405) {
        message =
            'This server needs an update to sync listening history. Listening is saved on this device.';
      } else if (error.statusCode == 401) {
        message = 'Sign in again to sync listening history.';
      } else if (error.statusCode == 403) {
        message = history.enabled
            ? 'Server collection is unavailable. Listening is saved on this device.'
            : null;
      } else {
        message = 'Waiting to sync. Listening is saved on this device.';
        _scheduleRetry();
      }
    } catch (_) {
      if (_current(revision)) {
        message = 'Waiting to sync. Listening is saved on this device.';
        _scheduleRetry();
      }
    } finally {
      syncing = false;
      if (!_closed) onChanged();
      if (continueSoon && !_closed && _resetting == null && history.enabled) {
        _scheduleRetry(soon: true);
      }
    }
  }

  void _scheduleRetry({bool soon = false}) {
    _retry?.cancel();
    if (_closed) return;
    final seconds = soon
        ? 2
        : min(300, 5 * (1 << min(_failures++, 6))) + _random.nextInt(5);
    _retry = Timer(Duration(seconds: seconds), () {
      _retry = null;
      unawaited(sync());
    });
  }

  Future<void> close() async {
    _closed = true;
    _retry?.cancel();
    _periodic?.cancel();
    // Outstanding HTTP calls have bounded timeouts; late replies are ignored.
  }
}
