import 'dart:async';
import 'dart:convert';

import 'package:phonolite_app/data/models/listening_stats/listening_counters.dart';
import 'package:phonolite_app/data/models/listening_stats/listening_event.dart';
import 'package:phonolite_app/data/models/listening_stats/listening_report.dart';
import 'package:phonolite_app/data/models/listening_stats/listening_stats_snapshot.dart';
import 'package:phonolite_app/data/storage/listening_stats/database/listening_stats_storage.dart';
import 'package:phonolite_app/data/storage/preferences/settings_files.dart';

/// Offline-first history. Construction is inert; initialization owns a single
/// database worker, which is closed with the controller's application lifetime.
class ListeningStatsService {
  final SettingsFiles _files;
  final String? _databasePath;
  final bool _inMemory;
  final DateTime Function() _clock;
  final StreamController<ListeningStatsSnapshot> _changes = StreamController<ListeningStatsSnapshot>.broadcast();
  ListeningStatsStorage? _storage;
  Future<void>? _initializing;
  Future<void>? _closing;
  Future<void> _operations = Future.value();
  bool _closed = false;
  bool _enabled = true;
  bool _localPreferenceRequested = false;
  int _preferenceRevision = 0;
  int _collectionIntentRevision = 0;
  String _deviceId = '';
  String _accountScope = 'local';
  int _historyGeneration = 1;
  int _cursor = 0;
  int _pendingCount = 0;
  bool _canImportLocalHistory = false;
  DateTime? _lastSyncedAt;
  String? _storageError;

  ListeningStatsService({
    SettingsFiles files = const SettingsFiles(),
    String? databasePath,
    bool inMemory = false,
    DateTime Function()? clock,
  }) : _files = files,
       _databasePath = databasePath,
       _inMemory = inMemory,
       _clock = clock ?? DateTime.now;

  bool get enabled => _enabled;

  int get preferenceRevision => _preferenceRevision;

  int get collectionIntentRevision => _collectionIntentRevision;

  String get deviceId => _deviceId;

  String get accountScope => _accountScope;

  int get historyGeneration => _historyGeneration;

  int get cursor => _cursor;

  int get pendingCount => _pendingCount;

  bool get canImportLocalHistory => _accountScope != 'local' && _canImportLocalHistory;

  DateTime? get lastSyncedAt => _lastSyncedAt;

  String? get storageError => _storageError;

  /// Synchronous state at the time of the read; retained snapshots never change.
  ListeningStatsSnapshot get current => ListeningStatsSnapshot(
    enabled: enabled,
    preferenceRevision: preferenceRevision,
    collectionIntentRevision: collectionIntentRevision,
    deviceId: deviceId,
    accountScope: accountScope,
    historyGeneration: historyGeneration,
    cursor: cursor,
    pendingCount: pendingCount,
    canImportLocalHistory: canImportLocalHistory,
    lastSyncedAt: lastSyncedAt,
    storageError: storageError,
  );

  /// Asynchronous broadcast updates captured when each change is published.
  ///
  /// New listeners receive no initial value or replay. Reading [current] and
  /// subscribing are separate operations. Command failures remain on their
  /// returned futures and in [storageError]; this stream emits no errors.
  /// [close] closes the stream after the outstanding storage operations finish.
  Stream<ListeningStatsSnapshot> get changes => _changes.stream;

  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> close() => _closing ??= _close();

  Future<void> setEnabled(bool value) {
    // Immediately stop queued/network callers while the durable write waits.
    _localPreferenceRequested = true;
    _enabled = value;
    final revision = ++_preferenceRevision;
    _emit();

    return _run(() async {
      await _storage!.request('enabled', {'enabled': value});

      if (_preferenceRevision == revision) {
        _enabled = value;
      }

      await _refreshState();
    }).catchError((Object error, StackTrace stack) {
      // A setting that could not be persisted must never start collection.
      if (_preferenceRevision == revision) {
        _enabled = false;
      }

      _emit();
      Error.throwWithStackTrace(error, stack);
    });
  }

  Future<void> setAccount({
    String? serverId,
    String? userId,
    int? historyGeneration,
    bool preserveLocalStatistics = false,
  }) => _run(() async {
    final scope = serverId?.isNotEmpty == true && userId?.isNotEmpty == true ? jsonEncode([serverId, userId]) : 'local';

    if (scope == _accountScope && (historyGeneration == null || historyGeneration == _historyGeneration)) {
      return;
    }

    final state = await _storage!.request('account', {
      'scope': scope,
      if (historyGeneration != null) 'generation': historyGeneration,
      'preserve_local_statistics': preserveLocalStatistics,
    });

    _accountScope = scope;
    _applyState(state as Map);
    _emit();
  });

  Future<void> recordSegment(ListeningEvent event, {String? scope, int? generation}) {
    if (!_enabled || _closed) {
      return Future.value();
    }

    final owner = scope ?? _accountScope;
    final ownerGeneration = generation ?? _historyGeneration;
    final revision = _preferenceRevision;

    return _run(() async {
      if (!_enabled || revision != _preferenceRevision) {
        return;
      }

      await _storage!.request('record', {'scope': owner, 'generation': ownerGeneration, 'event': event.toJson()});

      await _refreshState();
    });
  }

  /// Only the pre-v2 migration queue retains events with their original IDs.
  Future<List<ListeningEvent>> pendingEvents({int limit = 200}) => _run(() async {
    if (!_enabled || _accountScope == 'local') {
      return [];
    }

    final result = await _storage!.request('pending', {'scope': _accountScope, 'limit': limit.clamp(1, 500)});

    return [for (final event in result as List) ListeningEvent.fromJson(Map<String, dynamic>.from(event as Map))];
  });

  Future<void> acknowledge(List<String> ids, {String? scope}) => _run(() async {
    await _storage!.request('acknowledge', {'scope': scope ?? _accountScope, 'ids': ids});

    await _refreshState();
  });

  /// Counter commands share the playback-write/account-reset serialization queue.
  Future<int> counterConsent({String? scope, int? generation}) async =>
      await _counterOperation('consent', scope: scope, generation: generation) as int;

  Future<void> acknowledgeCounterConsent(int consentEpoch, {String? scope, int? generation}) async {
    await _counterOperation(
      'consent_ack',
      scope: scope,
      generation: generation,
      arguments: {'consent_epoch': consentEpoch},
    );
  }

  Future<ListeningCounterBatch?> prepareCounterBatch({
    required int collectionRevision,
    String? scope,
    int? generation,
  }) async {
    final result = await _counterOperation(
      'prepare',
      scope: scope,
      generation: generation,
      arguments: {'collection_revision': collectionRevision},
    );

    return result == null ? null : ListeningCounterBatch.fromJson(Map<String, dynamic>.from(result as Map));
  }

  Future<void> applyCounterCheckpoint(
    ListeningCounterCheckpoint checkpoint, {
    required int collectionRevision,
    String? scope,
    int? generation,
  }) async {
    await _counterOperation(
      'checkpoint',
      scope: scope,
      generation: generation,
      arguments: {'checkpoint': checkpoint.toJson(), 'collection_revision': collectionRevision},
    );
  }

  Future<List<ListeningCounterMonth>> counterMonths({String? scope, int? generation}) async {
    final result = await _counterOperation('months', scope: scope, generation: generation);

    return List<ListeningCounterMonth>.unmodifiable([
      for (final month in result as List) ListeningCounterMonth.fromJson(Map<String, dynamic>.from(month as Map)),
    ]);
  }

  Future<void> applyCounterPage(ListeningCounterPage page, {String after = '', String? scope, int? generation}) async {
    await _counterOperation(
      'snapshot',
      scope: scope,
      generation: generation,
      arguments: {'page': page.toJson(), 'after': after},
    );
  }

  Future<void> quarantineCounterBatch({String? scope, int? generation}) async {
    await _counterOperation('quarantine', scope: scope, generation: generation);
  }

  Future<void> compactLegacyCounters({String? scope, int? generation}) async {
    await _counterOperation('compact_legacy', scope: scope, generation: generation);
  }

  /// Permanently rejected events remain in local reports but cannot block the
  /// upload queue. They are not mistaken for a successful server ingestion.
  Future<void> reject(List<String> ids, {String? scope}) => _run(() async {
    await _storage!.request('reject', {'scope': scope ?? _accountScope, 'ids': ids});

    await _refreshState();
  });

  Future<void> applyRemote(
    List<ListeningEvent> events, {
    required int cursor,
    required int historyGeneration,
    String? scope,
    Map<String, List<String>> genreMetadata = const {},
  }) => _run(() async {
    await _storage!.request('remote', {
      'scope': scope ?? _accountScope,
      'generation': historyGeneration,
      'cursor': cursor,
      'synced_at': _clock().toUtc().millisecondsSinceEpoch,
      'events': events.map((event) => event.toJson()).toList(),
      'genre_metadata': genreMetadata,
    });

    await _refreshState();
  });

  /// Tracks whose historical reports still use their captured genre tags.
  Future<List<String>> genreMetadataCandidates({int limit = 50, String? afterTrackId}) => _run(() async {
    final result = await _storage!.request('genre_metadata_candidates', {
      'scope': _accountScope,
      'generation': _historyGeneration,
      'limit': limit.clamp(1, 100),
      'after_track_id': afterTrackId,
    });

    return (result as List).cast<String>();
  });

  /// A metadata snapshot in the legacy model supplies exact album/artist identities
  /// when a historical song is no longer available in the current catalog.
  Future<List<ListeningEvent>> genreMetadataCandidateEvents({int limit = 50, String? afterTrackId}) => _run(() async {
    final result = await _storage!.request('genre_metadata_candidate_events', {
      'scope': _accountScope,
      'generation': _historyGeneration,
      'limit': limit.clamp(1, 100),
      'after_track_id': afterTrackId,
    });

    return [for (final event in result as List) ListeningEvent.fromJson(Map<String, dynamic>.from(event as Map))];
  });

  /// Catalog enrichment changes derived reports, never captured wire events.
  /// A caller fetching metadata should pass the scope and generation captured
  /// before its request, so an account switch cannot apply another catalog.
  Future<void> updateGenreMetadata(Map<String, List<String>> genres, {String? scope, int? generation}) {
    final owner = scope ?? _accountScope;
    final ownerGeneration = generation ?? _historyGeneration;

    return _run(() async {
      if (owner != _accountScope || ownerGeneration != _historyGeneration) {
        return;
      }

      final changed = await _storage!.request('genre_metadata', {
        'scope': owner,
        'generation': ownerGeneration,
        'genres': genres,
      });

      if (changed == true) {
        _emit();
      }
    });
  }

  /// Clears only anonymous history; account copies and consent are unchanged.
  Future<void> resetLocalHistory() => _run(() async {
    await _storage!.request('reset_local', const {});

    await _refreshState();
  });

  /// Clear every locally stored account and signed-out copy on this device.
  /// Server generations remain unchanged; the next sync reads their state.
  Future<void> resetDeviceHistory() {
    // Reject queued playback intervals captured before the reset, including
    // intervals for a cached account whose server generation stays unchanged.
    _preferenceRevision++;

    return _run(() async {
      await _storage!.request('reset_device', const {});

      await _refreshState();
    });
  }

  /// Anonymous listening is never automatically claimed by a signed-in user.
  Future<void> importLocalHistory() {
    // Consent belongs to the account and history visible when import is
    // requested, even if another account change is ahead in the writer queue.
    final scope = _accountScope;
    final generation = _historyGeneration;
    final preference = _preferenceRevision;

    return _run(() async {
      if (!_enabled ||
          scope == 'local' ||
          scope != _accountScope ||
          generation != _historyGeneration ||
          preference != _preferenceRevision) {
        return;
      }

      await _storage!.request('import', {'scope': scope});

      await _refreshState();
    });
  }

  Future<StatsResponse> stats({int? year, int? month}) => _run(() async {
    final result = await _storage!.request('stats', {
      'scope': _accountScope,
      'year': year ?? _clock().toUtc().year,
      'month': month,
    });

    return StatsResponse.fromJson(Map<String, dynamic>.from(result as Map));
  });

  Future<void> _initialize() async {
    if (_closed) {
      throw StateError('Listening history is closed');
    }

    try {
      final path = _inMemory
          ? ':memory:'
          : _databasePath ?? (await _files.resolve('stats.sqlite', createDirectory: true)).path;
      final storage = ListeningStatsStorage();

      _storage = storage;
      final state = await storage.initialize(path, deviceId: newListeningId());

      // A toggle made while opening the database already expresses the latest
      // local intent. Reading an older saved value must not undo it, even for
      // the short interval before its queued durable write is processed.
      if (!_localPreferenceRequested) {
        _enabled = state['enabled'] as bool;
      }

      _deviceId = state['device_id'] as String;
      _applyState(state);
      _emit();
    } catch (error) {
      // If a saved privacy preference cannot be read, fail closed. Never
      // silently replace a damaged database with default-enabled history.
      _enabled = false;
      _storageError = error.toString();
      _emit();

      rethrow;
    }
  }

  Future<T> _run<T>(Future<T> Function() operation) {
    final result = _operations.then((_) async {
      await initialize();

      if (_closed) {
        throw StateError('Listening history is closed');
      }

      try {
        final result = await operation();

        _storageError = null;

        return result;
      } catch (error) {
        _storageError = error.toString();
        _emit();

        rethrow;
      }
    });

    _operations = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});

    return result;
  }

  Future<void> _refreshState() async {
    final state = await _storage!.request('state', {'scope': _accountScope});

    _applyState(state as Map);
    _emit();
  }

  Future<Object?> _counterOperation(
    String command, {
    String? scope,
    int? generation,
    Map<String, dynamic> arguments = const {},
  }) => _run(() async {
    final result = await _storage!.request('counter_$command', {
      'scope': scope ?? _accountScope,
      'generation': generation ?? _historyGeneration,
      ...arguments,
    });

    await _refreshState();

    return result;
  });

  void _applyState(Map state) {
    _collectionIntentRevision = state['consent_epoch'] as int;
    _historyGeneration = state['generation'] as int;
    _cursor = state['cursor'] as int;
    _pendingCount = state['pending_count'] as int;
    _canImportLocalHistory = state['has_local_history'] as bool;

    final synced = state['synced_at'] as int?;

    _lastSyncedAt = synced == null ? null : DateTime.fromMillisecondsSinceEpoch(synced, isUtc: true);
  }

  void _emit() {
    if (!_changes.isClosed) {
      _changes.add(current);
    }
  }

  Future<void> _close() async {
    if (_closed) {
      return;
    }

    await _operations;

    if (_initializing != null) {
      try {
        await _initializing;
      } catch (_) {
        // A failed initialization still needs its ports closed.
      }
    }

    _closed = true;
    await _storage?.close();

    final hasListeners = _changes.hasListener;
    final closingChanges = _changes.close();

    if (hasListeners) {
      await closingChanges;
    } else {
      // A cold controller can be constructed in a widget's fake clock zone
      // and disposed with runAsync. With no listeners, the stream completion
      // is scheduled in that suspended zone and has nothing useful to await.
      unawaited(closingChanges);
    }
  }
}
