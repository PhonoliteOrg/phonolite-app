import 'dart:async';
import 'dart:math';

import 'package:phonolite_app/data/models/listening_stats/listening_counters.dart';
import 'package:phonolite_app/data/repositories/listening_stats_service.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';

/// Opportunistic synchronization. Playback never awaits this work.
class ListeningStatsSync {
  final ListeningStatsService history;
  final ServerConnection connection;
  final bool Function() isAuthorized;
  final void Function() onChanged;
  final Future<void> Function(String serverId, String userId) onIdentity;
  Future<void>? _running;
  Future<void>? _pulling;
  Future<void>? _resetting;
  Timer? _retry;
  Timer? _periodic;
  bool _closed = false;
  int _failures = 0;
  final Random _random = Random();
  bool syncing = false;
  bool serverCollectionEnabled = false;
  String? message;

  ListeningStatsSync({
    required this.history,
    required this.connection,
    required this.isAuthorized,
    required this.onChanged,
    required this.onIdentity,
  });

  void start() {
    _periodic ??= Timer.periodic(const Duration(minutes: 5), (_) {
      // Disabled devices still need to learn about account history deletion.
      unawaited(sync());
    });
  }

  Future<void> close() async {
    _closed = true;
    _retry?.cancel();
    _periodic?.cancel();
    // Outstanding HTTP calls have bounded timeouts; late replies are ignored.
  }

  Future<void> sync({bool immediate = false}) {
    if (_resetting != null) {
      return Future<void>.value();
    }

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

    void clearCompletedSync() {
      if (identical(_running, work)) {
        _running = null;
      }
    }

    return work.whenComplete(clearCompletedSync);
  }

  /// Pulls committed account changes without uploading another device response.
  /// Failures propagate so the account event owner retains its pending revision.
  Future<void> refreshFromServer() {
    final pulling = _pulling;

    if (pulling != null) {
      return pulling;
    }

    final work = _refreshFromServer();
    _pulling = work;

    return work.whenComplete(() {
      if (identical(_pulling, work)) {
        _pulling = null;
      }
    });
  }

  Future<void> _refreshFromServer() async {
    while (_running != null) {
      await _running;
    }

    if (_closed || !isAuthorized() || history.deviceId.isEmpty || _resetting != null) {
      throw StateError('Listening statistics are not ready to refresh.');
    }

    final work = _sync(upload: false);
    _running = work;

    try {
      await work;
    } finally {
      if (identical(_running, work)) {
        _running = null;
      }
    }
  }

  Future<void> resetAccountHistory() {
    final resetting = _resetting;
    if (resetting != null) {
      return resetting;
    }

    final work = _resetAccountHistory(connection.sessionRevision);

    return _trackReset(work);
  }

  Future<void> resetListeningStatistics({required bool resetServer}) {
    final resetting = _resetting;
    if (resetting != null) {
      return resetting;
    }

    final revision = connection.sessionRevision;

    Future<void> resetHistory() async {
      _retry?.cancel();
      _retry = null;
      await _running;

      if (_closed || revision != connection.sessionRevision) {
        throw StateError('The connection or signed-in account changed.');
      }

      if (resetServer) {
        await _resetAccountHistory(revision);
      }

      await history.resetDeviceHistory();
      message = null;
      _failures = 0;
      onChanged();
    }

    final work = resetHistory();

    return _trackReset(work);
  }

  Future<void> _trackReset(Future<void> work) {
    _resetting = work;

    void clearCompletedReset() {
      if (identical(_resetting, work)) {
        _resetting = null;
      }
    }

    return work.whenComplete(clearCompletedReset);
  }

  bool _current(int revision, {bool duringReset = false}) =>
      !_closed && (duringReset || _resetting == null) && isAuthorized() && revision == connection.sessionRevision;

  Future<void> _resetAccountHistory(int revision) async {
    _retry?.cancel();
    _retry = null;
    // Finish any upload/download before resetting this account's history.
    await _running;

    void checkSession() {
      if (!_current(revision, duringReset: true)) {
        throw StateError('Connect and sign in to reset account listening statistics.');
      }
    }

    checkSession();

    final state = ListeningCounterState.fromJson(
      await connection.fetchListeningCounterState(deviceId: history.deviceId),
    );

    checkSession();

    final serverId = state.serverId;
    final userId = state.userId;
    final generation = state.historyGeneration ?? 0;

    if (serverId.isEmpty || userId.isEmpty || generation < 1) {
      throw StateError('Missing account listening statistics identity.');
    }

    final result = await connection.resetListeningHistory(historyGeneration: generation);

    checkSession();

    final nextGeneration = (result['history_generation'] as num?)?.toInt() ?? 0;

    if (result['server_id'] != serverId || result['user_id'] != userId || nextGeneration <= generation) {
      throw StateError('Invalid account listening statistics reset response.');
    }

    await history.setAccount(serverId: serverId, userId: userId, historyGeneration: nextGeneration);
    checkSession();
    await onIdentity(serverId, userId);
    message = null;
    _failures = 0;
    onChanged();
  }

  Future<void> _sync({bool upload = true}) async {
    final revision = connection.sessionRevision;

    syncing = true;
    onChanged();

    var continueSoon = false;

    try {
      // Check identity/preferences before uploads. Never guess ownership from
      // a username, URL, token or the account that happens to be current later.
      final state = ListeningCounterState.fromJson(
        await connection.fetchListeningCounterState(deviceId: history.deviceId),
      );

      if (!_current(revision)) {
        return;
      }

      final serverId = state.serverId;
      final userId = state.userId;

      if (serverId.isEmpty || userId.isEmpty) {
        throw StateError('Missing account identity');
      }

      final generation = state.historyGeneration ?? 1;

      await history.setAccount(
        serverId: serverId,
        userId: userId,
        historyGeneration: generation,
        preserveLocalStatistics: true,
      );

      if (!_current(revision)) {
        return;
      }

      await onIdentity(serverId, userId);

      if (!_current(revision)) {
        return;
      }

      final scope = history.accountScope;

      serverCollectionEnabled = state.collectionEnabled;
      var serverPreference = state.preferenceRevision;
      var serverEnabled = state.deviceEnabled;
      var acknowledgedIntent = await history.counterConsent(scope: scope, generation: generation);

      final preferenceRevision = history.preferenceRevision;

      if (upload) {
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

          if (!_current(revision) || history.accountScope != scope) {
            return;
          }

          serverPreference = (pref['revision'] as num?)?.toInt() ?? serverPreference;
          serverEnabled = pref['enabled'] == true;

          if (history.enabled == desired && serverEnabled == desired && localRevision == history.preferenceRevision) {
            await history.acknowledgeCounterConsent(intent, scope: scope, generation: generation);
            acknowledgedIntent = intent;
            break;
          }
        }

        if (serverEnabled != history.enabled || acknowledgedIntent != history.collectionIntentRevision) {
          throw StateError('Collection preference not acknowledged');
        }

        if (serverCollectionEnabled && history.enabled) {
          for (var batch = 0; batch < 5; batch++) {
            final events = await history.pendingEvents(limit: 200);

            if (!_current(revision) || !history.enabled || history.accountScope != scope) {
              return;
            }

            if (events.isEmpty) {
              break;
            }

            final result = await connection.uploadListeningEvents(
              deviceId: history.deviceId,
              historyGeneration: generation,
              events: events.map((event) => event.toJson()).toList(),
            );

            if (!_current(revision) || history.accountScope != scope) {
              return;
            }

            final accepted = (result['accepted'] as List? ?? const []).map((id) => id.toString()).toList();

            await history.acknowledge(accepted, scope: scope);

            final rejected = result['rejected'] as List? ?? const [];

            if (rejected.isNotEmpty) {
              // Keep invalid records locally, but do not let one permanently
              // rejected record block every following batch.
              await history.reject(
                rejected.whereType<Map>().map((item) => item['event_id'].toString()).toList(),
                scope: scope,
              );
              message = 'Some listening records could not be synced. Your local history is retained.';
            }

            if (accepted.isEmpty && rejected.isEmpty) {
              throw StateError('Missing upload acknowledgment');
            }

            continueSoon = batch == 4 && (await history.pendingEvents(limit: 1)).isNotEmpty;
          }
        }

        if (!_current(revision) || history.accountScope != scope) {
          return;
        }

        // Drain the old queue using original IDs before retiring this device's
        // v1 writer. The server can then safely discard its old event ledger.
        if ((await history.pendingEvents(limit: 1)).isNotEmpty) {
          continueSoon = history.enabled && serverCollectionEnabled;

          return;
        }

        await connection.activateListeningCounters(deviceId: history.deviceId, historyGeneration: generation);

        if (!_current(revision) || history.accountScope != scope) {
          return;
        }

        await history.compactLegacyCounters(scope: scope, generation: generation);
      }

      for (var pass = 0; pass < 5; pass++) {
        // This read occurs after the preference barrier. A canceled request
        // either committed before the barrier or can never commit afterwards.
        var current = ListeningCounterState.fromJson(
          await connection.fetchListeningCounterState(deviceId: history.deviceId),
        );

        if (!_current(revision) || history.accountScope != scope) {
          return;
        }

        if (current.serverId != serverId || current.userId != userId) {
          return;
        }

        if (current.historyGeneration != generation) {
          await history.setAccount(
            serverId: serverId,
            userId: userId,
            historyGeneration: current.historyGeneration!,
            preserveLocalStatistics: true,
          );
          continueSoon = true;

          if (!upload) {
            throw StateError('Account history changed while refreshing.');
          }

          return;
        }

        ListeningCounterBatch? batch;

        await history.applyCounterCheckpoint(
          current.checkpoint,
          collectionRevision: serverPreference,
          scope: scope,
          generation: generation,
        );

        if (upload) {
          final pendingBeforePrepare = history.pendingCount;
          batch = await history.prepareCounterBatch(
            collectionRevision: serverPreference,
            scope: scope,
            generation: generation,
          );

          if (history.pendingCount < pendingBeforePrepare) {
            message = 'Some listening updates could not be synced. Your local history is retained.';
          }
        }

        if (!_current(revision) || history.accountScope != scope) {
          return;
        }

        if (batch != null && history.enabled && serverEnabled && serverCollectionEnabled) {
          if (preferenceRevision != history.preferenceRevision) {
            continueSoon = true;

            return;
          }

          ListeningCounterCheckpoint result;

          try {
            result = ListeningCounterCheckpoint.fromJson(await connection.uploadListeningCounters(batch.toJson()));
          } on ApiException catch (error) {
            if (![400, 413, 422].contains(error.statusCode)) {
              rethrow;
            }

            if (!_current(revision) || history.accountScope != scope) {
              return;
            }

            await history.quarantineCounterBatch(scope: scope, generation: generation);
            message = 'Some listening updates could not be synced. Your local history is retained.';
            continueSoon = true;

            return;
          }

          if (!_current(revision) || history.accountScope != scope) {
            return;
          }

          if (result.lastSequence < batch.batchSequence) {
            throw StateError('Missing counter acknowledgment');
          }

          current = ListeningCounterState.fromJson(
            await connection.fetchListeningCounterState(deviceId: history.deviceId),
          );

          if (!_current(revision) || history.accountScope != scope) {
            return;
          }

          if (current.historyGeneration != generation || current.serverId != serverId || current.userId != userId) {
            continueSoon = true;

            return;
          }

          await history.applyCounterCheckpoint(
            current.checkpoint,
            collectionRevision: serverPreference,
            scope: scope,
            generation: generation,
          );
        }

        final cached = await history.counterMonths(scope: scope, generation: generation);
        final revisions = {for (final month in cached) month.key: month.revision};
        var changed = 0;

        for (final period in current.months) {
          if (revisions[period.key] == period.revision) {
            continue;
          }

          if (changed++ >= 24) {
            continueSoon = true;
            break;
          }

          var after = '';
          int? monthRevision;

          while (true) {
            final page = ListeningCounterPage.fromJson(
              await connection.fetchListeningCounterSnapshot(
                deviceId: history.deviceId,
                year: period.year,
                month: period.month,
                revision: monthRevision,
                after: after,
              ),
            );

            if (!_current(revision) || history.accountScope != scope) {
              return;
            }

            if (page.historyGeneration != generation) {
              continueSoon = true;

              if (!upload) {
                throw StateError('Account history changed while refreshing.');
              }

              return;
            }

            await history.applyCounterPage(page, after: after, scope: scope, generation: generation);

            if (!page.hasMore) {
              break;
            }

            monthRevision = page.revision;
            after = page.nextKey;
          }
        }

        if (batch == null || !history.enabled || !serverCollectionEnabled) {
          break;
        }

        continueSoon = pass == 4 && history.pendingCount > 0;
      }

      if (!upload && continueSoon) {
        throw StateError('More account history remains to refresh.');
      }

      if (message?.startsWith('Some listening') != true) {
        message = null;
      }

      _failures = 0;
    } on ApiException catch (error) {
      if (!_current(revision)) {
        return;
      }

      if (!upload) {
        rethrow;
      }

      if (error.statusCode == 404 || error.statusCode == 405) {
        message = 'This server needs an update to sync listening history. Listening is saved on this device.';
      } else if (error.statusCode == 401) {
        message = 'Sign in again to sync listening history.';
      } else if (error.statusCode == 403) {
        message = history.enabled ? 'Server collection is unavailable. Listening is saved on this device.' : null;
      } else {
        message = 'Waiting to sync. Listening is saved on this device.';
        _scheduleRetry();
      }
    } catch (_) {
      if (!upload) {
        rethrow;
      }

      if (_current(revision)) {
        message = 'Waiting to sync. Listening is saved on this device.';
        _scheduleRetry();
      }
    } finally {
      syncing = false;

      if (!_closed) {
        onChanged();
      }

      if (upload && continueSoon && !_closed && _resetting == null && history.enabled) {
        _scheduleRetry(soon: true);
      }
    }
  }

  void _scheduleRetry({bool soon = false}) {
    _retry?.cancel();

    if (_closed) {
      return;
    }

    final seconds = soon ? 2 : min(300, 5 * (1 << min(_failures++, 6))) + _random.nextInt(5);

    void retryWhenDue() {
      _retry = null;
      unawaited(sync());
    }

    _retry = Timer(Duration(seconds: seconds), retryWhenDue);
  }
}
