import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../persistence/settings_files.dart';
import 'listening_stats_storage.dart';
import 'models.dart';

/// An opaque ID carries no hardware, filesystem, or network identity.
String newListeningId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

class ListeningArtist {
  const ListeningArtist({required this.id, required this.name});
  final String id;
  final String name;

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
  factory ListeningArtist.fromJson(Map<String, dynamic> json) =>
      ListeningArtist(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
      );
}

List<ListeningArtist> _snapshotArtists(Track track) {
  final artist = listeningPrimaryArtist({
    'artist_id': track.artistId,
    'artist_name': track.artist,
    'artists': [
      for (final credit in track.credits)
        {'id': credit.artistId, 'name': credit.displayName},
    ],
  });
  return List.unmodifiable([
    if (artist != null) ListeningArtist(id: artist.id, name: artist.name),
  ]);
}

/// Capture known genre metadata once at session start, without network work.
/// Statistics use release genres first, then song tags and performer profiles.
/// The server supplies this projection explicitly when its catalog is richer
/// than broad file tags; older clients' downloads can use embedded album data.
List<String> _snapshotGenres(
  Track track, {
  Iterable<Album> cachedAlbums = const [],
  Iterable<Artist> cachedArtists = const [],
}) {
  List<String> normalize(Iterable<String> genres) {
    final values = <String, String>{};
    for (final genre in genres) {
      final value = genre.trim();
      if (value.isNotEmpty) {
        values.putIfAbsent(value.toLowerCase(), () => value);
      }
    }
    return List.unmodifiable(values.values);
  }

  final projected = normalize(track.listeningGenres);
  if (projected.isNotEmpty) return projected;
  final albums = <Album>[
    if (track.offlineAlbum != null &&
        (track.albumId == null || track.offlineAlbum!.id == track.albumId))
      track.offlineAlbum!,
    for (final album in cachedAlbums)
      if (track.albumId?.isNotEmpty == true && album.id == track.albumId) album,
  ];
  for (final album in albums) {
    final genres = normalize(album.genres);
    if (genres.isNotEmpty) return genres;
  }
  final tagged = normalize(track.genres);
  if (tagged.isNotEmpty) return tagged;
  var performerIds = <String>{
    for (final credit in track.credits)
      if (credit.isPerformingArtist && credit.artistId.isNotEmpty)
        credit.artistId,
  };
  if (performerIds.isEmpty) {
    performerIds = {
      for (final album in albums)
        for (final credit in album.credits)
          if (credit.isAlbumArtist && credit.artistId.isNotEmpty)
            credit.artistId,
    };
  }
  final profiles = [
    ...track.offlineArtists,
    if (track.offlineArtist != null) track.offlineArtist!,
    ...cachedArtists,
  ];
  return normalize([
    for (final id in performerIds)
      for (final artist in profiles)
        if (artist.id == id) ...artist.genres,
  ]);
}

/// A small immutable interval of audio actually consumed by the output device.
/// Metadata is normalized to one snapshot per session in the local database.
class ListeningEvent {
  const ListeningEvent({
    required this.eventId,
    required this.sessionId,
    required this.deviceId,
    required this.trackId,
    required this.title,
    required this.artistName,
    required this.albumTitle,
    required this.trackDurationMs,
    required this.sessionStartedAtMs,
    required this.startedAtMs,
    required this.endedAtMs,
    required this.listenedMs,
    this.artistId = '',
    this.albumId = '',
    this.genres = const [],
    this.artists = const [],
    this.ruleVersion = 1,
    this.endReason,
  });

  final String eventId;
  final String sessionId;
  final String deviceId;
  final String trackId;
  final String title;
  final String artistId;
  final String artistName;
  final String albumId;
  final String albumTitle;
  final List<String> genres;
  final List<ListeningArtist> artists;
  final int trackDurationMs;
  final int sessionStartedAtMs;
  final int startedAtMs;
  final int endedAtMs;
  final int listenedMs;
  final int ruleVersion;
  final String? endReason;

  factory ListeningEvent.fromTrack({
    required Track track,
    required String sessionId,
    required String deviceId,
    required int sessionStartedAtMs,
    required int startedAtMs,
    required int endedAtMs,
    required int listenedMs,
    String? eventId,
    String? endReason,
    Iterable<Album> cachedAlbums = const [],
    Iterable<Artist> cachedArtists = const [],
  }) => ListeningEvent(
    eventId: eventId ?? newListeningId(),
    sessionId: sessionId,
    deviceId: deviceId,
    trackId: track.serverTrackId ?? track.id,
    title: track.title,
    artistId: track.artistId ?? '',
    artistName: track.artist,
    albumId: track.albumId ?? '',
    albumTitle: track.album,
    genres: _snapshotGenres(
      track,
      cachedAlbums: cachedAlbums,
      cachedArtists: cachedArtists,
    ),
    artists: _snapshotArtists(track),
    trackDurationMs: track.durationMs,
    sessionStartedAtMs: sessionStartedAtMs,
    startedAtMs: startedAtMs,
    endedAtMs: endedAtMs,
    listenedMs: listenedMs,
    endReason: endReason,
  );

  factory ListeningEvent.fromJson(Map<String, dynamic> json) => ListeningEvent(
    eventId: json['event_id'] as String,
    sessionId: json['session_id'] as String,
    deviceId: json['device_id'] as String,
    trackId: json['track_id'] as String,
    title: json['title'] as String? ?? '',
    artistId: json['artist_id'] as String? ?? '',
    artistName: json['artist_name'] as String? ?? '',
    albumId: json['album_id'] as String? ?? '',
    albumTitle: json['album_title'] as String? ?? '',
    genres: (json['genres'] as List? ?? const []).cast<String>(),
    artists: [
      for (final artist in json['artists'] as List? ?? const [])
        ListeningArtist.fromJson(Map<String, dynamic>.from(artist as Map)),
    ],
    trackDurationMs: (json['track_duration_ms'] as num?)?.toInt() ?? 0,
    sessionStartedAtMs: (json['session_started_at_ms'] as num).toInt(),
    startedAtMs: (json['started_at_ms'] as num).toInt(),
    endedAtMs: (json['ended_at_ms'] as num).toInt(),
    listenedMs: (json['listened_ms'] as num).toInt(),
    ruleVersion: (json['rule_version'] as num?)?.toInt() ?? 1,
    endReason: json['end_reason'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'event_id': eventId,
    'session_id': sessionId,
    'device_id': deviceId,
    'track_id': trackId,
    'title': title,
    'artist_id': artistId,
    'artist_name': artistName,
    'album_id': albumId,
    'album_title': albumTitle,
    'genres': genres,
    'artists': artists.map((artist) => artist.toJson()).toList(),
    'track_duration_ms': trackDurationMs,
    'session_started_at_ms': sessionStartedAtMs,
    'started_at_ms': startedAtMs,
    'ended_at_ms': endedAtMs,
    'listened_ms': listenedMs,
    'rule_version': ruleVersion,
    if (endReason != null) 'end_reason': endReason,
  };
}

/// Offline-first history. Construction is inert; initialization owns a single
/// database worker, which is closed with the controller's application lifetime.
class ListeningStatsService {
  ListeningStatsService({
    SettingsFiles files = const SettingsFiles(),
    String? databasePath,
    bool inMemory = false,
    DateTime Function()? clock,
  }) : _files = files,
       _databasePath = databasePath,
       _inMemory = inMemory,
       _clock = clock ?? DateTime.now;

  final SettingsFiles _files;
  final String? _databasePath;
  final bool _inMemory;
  final DateTime Function() _clock;
  final _changes = StreamController<void>.broadcast();
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

  bool get enabled => _enabled;
  int get preferenceRevision => _preferenceRevision;
  int get collectionIntentRevision => _collectionIntentRevision;
  String get deviceId => _deviceId;
  String get accountScope => _accountScope;
  int get historyGeneration => _historyGeneration;
  int get cursor => _cursor;
  int get pendingCount => _pendingCount;
  bool get canImportLocalHistory =>
      _accountScope != 'local' && _canImportLocalHistory;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  String? get storageError => _storageError;
  Stream<void> get changes => _changes.stream;

  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    if (_closed) throw StateError('Listening history is closed');
    try {
      final path = _inMemory
          ? ':memory:'
          : _databasePath ??
                (await _files.resolve(
                  'stats.sqlite',
                  createDirectory: true,
                )).path;
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
      if (_closed) throw StateError('Listening history is closed');
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
    _operations = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  Future<void> setEnabled(bool value) {
    // Immediately stop queued/network callers while the durable write waits.
    _localPreferenceRequested = true;
    _enabled = value;
    final revision = ++_preferenceRevision;
    _emit();
    return _run(() async {
      await _storage!.request('enabled', {'enabled': value});
      if (_preferenceRevision == revision) _enabled = value;
      await _refreshState();
    }).catchError((Object error, StackTrace stack) {
      // A setting that could not be persisted must never start collection.
      if (_preferenceRevision == revision) _enabled = false;
      _emit();
      Error.throwWithStackTrace(error, stack);
    });
  }

  Future<void> setAccount({
    String? serverId,
    String? userId,
    int? historyGeneration,
  }) => _run(() async {
    final scope = serverId?.isNotEmpty == true && userId?.isNotEmpty == true
        ? jsonEncode([serverId, userId])
        : 'local';
    if (scope == _accountScope &&
        (historyGeneration == null ||
            historyGeneration == _historyGeneration)) {
      return;
    }
    final state = await _storage!.request('account', {
      'scope': scope,
      if (historyGeneration != null) 'generation': historyGeneration,
    });
    _accountScope = scope;
    _applyState(state as Map);
    _emit();
  });

  Future<void> recordSegment(
    ListeningEvent event, {
    String? scope,
    int? generation,
  }) {
    if (!_enabled || _closed) return Future.value();
    final owner = scope ?? _accountScope;
    final ownerGeneration = generation ?? _historyGeneration;
    final revision = _preferenceRevision;
    return _run(() async {
      if (!_enabled || revision != _preferenceRevision) return;
      await _storage!.request('record', {
        'scope': owner,
        'generation': ownerGeneration,
        'event': event.toJson(),
      });
      await _refreshState();
    });
  }

  /// Only the pre-v2 migration queue retains events with their original IDs.
  Future<List<ListeningEvent>> pendingEvents({int limit = 200}) =>
      _run(() async {
        if (!_enabled || _accountScope == 'local') return [];
        final result = await _storage!.request('pending', {
          'scope': _accountScope,
          'limit': limit.clamp(1, 500),
        });
        return [
          for (final event in result as List)
            ListeningEvent.fromJson(Map<String, dynamic>.from(event as Map)),
        ];
      });

  Future<void> acknowledge(List<String> ids, {String? scope}) => _run(() async {
    await _storage!.request('acknowledge', {
      'scope': scope ?? _accountScope,
      'ids': ids,
    });
    await _refreshState();
  });

  /// Counter operations are serialized with playback writes and account resets.
  Future<dynamic> counterOperation(
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

  /// Permanently rejected events remain in local reports but cannot block the
  /// upload queue. They are not mistaken for a successful server ingestion.
  Future<void> reject(List<String> ids, {String? scope}) => _run(() async {
    await _storage!.request('reject', {
      'scope': scope ?? _accountScope,
      'ids': ids,
    });
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
  Future<List<String>> genreMetadataCandidates({
    int limit = 50,
    String? afterTrackId,
  }) => _run(() async {
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
  Future<List<ListeningEvent>> genreMetadataCandidateEvents({
    int limit = 50,
    String? afterTrackId,
  }) => _run(() async {
    final result = await _storage!.request('genre_metadata_candidate_events', {
      'scope': _accountScope,
      'generation': _historyGeneration,
      'limit': limit.clamp(1, 100),
      'after_track_id': afterTrackId,
    });
    return [
      for (final event in result as List)
        ListeningEvent.fromJson(Map<String, dynamic>.from(event as Map)),
    ];
  });

  /// Catalog enrichment changes derived reports, never captured wire events.
  /// A caller fetching metadata should pass the scope and generation captured
  /// before its request, so an account switch cannot apply another catalog.
  Future<void> updateGenreMetadata(
    Map<String, List<String>> genres, {
    String? scope,
    int? generation,
  }) {
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
      if (changed == true) _emit();
    });
  }

  /// Clears only anonymous history; account copies and consent are unchanged.
  Future<void> resetLocalHistory() => _run(() async {
    await _storage!.request('reset_local', const {});
    await _refreshState();
  });

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

  Future<void> _refreshState() async {
    final state = await _storage!.request('state', {'scope': _accountScope});
    _applyState(state as Map);
    _emit();
  }

  void _applyState(Map state) {
    _collectionIntentRevision = state['consent_epoch'] as int;
    _historyGeneration = state['generation'] as int;
    _cursor = state['cursor'] as int;
    _pendingCount = state['pending_count'] as int;
    _canImportLocalHistory = state['has_local_history'] as bool;
    final synced = state['synced_at'] as int?;
    _lastSyncedAt = synced == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(synced, isUtc: true);
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    if (_closed) return;
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
