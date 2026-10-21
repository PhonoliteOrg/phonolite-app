/// A server/device checkpoint whose wire form remains lossless during storage.
class ListeningCounterCheckpoint {
  final int lastSequence;
  final String? lastHash;
  final bool upgraded;
  final _CounterPayload _payload;

  ListeningCounterCheckpoint._({
    required this.lastSequence,
    required this.lastHash,
    required this.upgraded,
    required _CounterPayload payload,
  }) : _payload = payload;

  factory ListeningCounterCheckpoint.fromJson(Map<String, dynamic> json) => ListeningCounterCheckpoint._(
    lastSequence: json['last_sequence'] as int? ?? 0,
    lastHash: json['last_hash'] as String?,
    upgraded: json['upgraded'] == true,
    payload: _CounterPayload(json),
  );

  Map<String, dynamic> toJson() => _payload.toJson();
}

/// One revision of the counters stored for a calendar month.
class ListeningCounterMonth {
  final int year;
  final int month;
  final int revision;

  const ListeningCounterMonth({required this.year, required this.month, required this.revision});

  factory ListeningCounterMonth.fromJson(Map<String, dynamic> json) =>
      ListeningCounterMonth(year: json['year'] as int, month: json['month'] as int, revision: json['revision'] as int);

  String get key => '$year:$month';

  @override
  bool operator ==(Object other) =>
      other is ListeningCounterMonth &&
      runtimeType == other.runtimeType &&
      year == other.year &&
      month == other.month &&
      revision == other.revision;

  @override
  int get hashCode => Object.hash(runtimeType, year, month, revision);
}

/// A frozen upload. The complete wire payload, including unknown fields, is
/// retained because the server hashes it to recognize retries of this sequence.
/// Construction and [toJson] both isolate nested maps/lists from the caller.
class ListeningCounterBatch {
  final int batchSequence;
  final _CounterPayload _payload;

  ListeningCounterBatch._({required this.batchSequence, required _CounterPayload payload}) : _payload = payload;

  factory ListeningCounterBatch.fromJson(Map<String, dynamic> json) =>
      ListeningCounterBatch._(batchSequence: json['batch_sequence'] as int, payload: _CounterPayload(json));

  Map<String, dynamic> toJson() => _payload.toJson();
}

/// One paged counter snapshot. Storage owns validation and atomic staging of its
/// contributions; the application uses these fields to advance the request.
class ListeningCounterPage {
  final int historyGeneration;
  final int year;
  final int month;
  final int revision;
  final bool hasMore;
  final String nextKey;
  final _CounterPayload _payload;

  ListeningCounterPage._({
    required this.historyGeneration,
    required this.year,
    required this.month,
    required this.revision,
    required this.hasMore,
    required this.nextKey,
    required _CounterPayload payload,
  }) : _payload = payload;

  factory ListeningCounterPage.fromJson(Map<String, dynamic> json) => ListeningCounterPage._(
    historyGeneration: json['history_generation'] as int,
    year: json['year'] as int,
    month: json['month'] as int,
    revision: json['revision'] as int,
    hasMore: json['has_more'] == true,
    nextKey: json['next_key'] as String,
    payload: _CounterPayload(json),
  );

  Map<String, dynamic> toJson() => _payload.toJson();
}

/// Account identity, preference barrier and month revisions observed together.
class ListeningCounterState {
  final String serverId;
  final String userId;
  final int? historyGeneration;
  final bool collectionEnabled;
  final bool deviceEnabled;
  final int preferenceRevision;
  final ListeningCounterCheckpoint checkpoint;
  final List<ListeningCounterMonth> months;

  ListeningCounterState._({
    required this.serverId,
    required this.userId,
    required this.historyGeneration,
    required this.collectionEnabled,
    required this.deviceEnabled,
    required this.preferenceRevision,
    required this.checkpoint,
    required this.months,
  });

  factory ListeningCounterState.fromJson(Map<String, dynamic> json) => ListeningCounterState._(
    serverId: json['server_id']?.toString() ?? '',
    userId: json['user_id']?.toString() ?? '',
    historyGeneration: (json['history_generation'] as num?)?.toInt(),
    collectionEnabled: json['collection_enabled'] == true,
    deviceEnabled: json['device_enabled'] != false,
    preferenceRevision: (json['preference_revision'] as num?)?.toInt() ?? 0,
    checkpoint: ListeningCounterCheckpoint.fromJson(Map<String, dynamic>.from(json['checkpoint'] as Map)),
    months: List<ListeningCounterMonth>.unmodifiable([
      for (final month in json['months'] as List? ?? const [])
        ListeningCounterMonth.fromJson(Map<String, dynamic>.from(month as Map)),
    ]),
  );
}

/// Keeps JSON-shaped protocol content private without changing its wire schema.
class _CounterPayload {
  final Map<String, dynamic> _json;

  _CounterPayload(Map<String, dynamic> json) : _json = _copyCounterJson(json) as Map<String, dynamic>;

  Map<String, dynamic> toJson() => _copyCounterJson(_json) as Map<String, dynamic>;
}

Object? _copyCounterJson(Object? value) {
  if (value is Map) {
    return <String, dynamic>{for (final entry in value.entries) entry.key as String: _copyCounterJson(entry.value)};
  }

  if (value is List) {
    return <Object?>[for (final item in value) _copyCounterJson(item)];
  }

  return value;
}
