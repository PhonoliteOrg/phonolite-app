/// Immediate listening-history state, independent of its database owner.
class ListeningStatsSnapshot {
  final bool enabled;
  final int preferenceRevision;
  final int collectionIntentRevision;
  final String deviceId;
  final String accountScope;
  final int historyGeneration;
  final int cursor;
  final int pendingCount;
  final bool canImportLocalHistory;
  final DateTime? lastSyncedAt;
  final String? storageError;

  const ListeningStatsSnapshot({
    required this.enabled,
    required this.preferenceRevision,
    required this.collectionIntentRevision,
    required this.deviceId,
    required this.accountScope,
    required this.historyGeneration,
    required this.cursor,
    required this.pendingCount,
    required this.canImportLocalHistory,
    required this.lastSyncedAt,
    required this.storageError,
  });

  @override
  bool operator ==(Object other) =>
      other is ListeningStatsSnapshot &&
      runtimeType == other.runtimeType &&
      enabled == other.enabled &&
      preferenceRevision == other.preferenceRevision &&
      collectionIntentRevision == other.collectionIntentRevision &&
      deviceId == other.deviceId &&
      accountScope == other.accountScope &&
      historyGeneration == other.historyGeneration &&
      cursor == other.cursor &&
      pendingCount == other.pendingCount &&
      canImportLocalHistory == other.canImportLocalHistory &&
      lastSyncedAt == other.lastSyncedAt &&
      storageError == other.storageError;

  @override
  int get hashCode => Object.hash(
    runtimeType,
    enabled,
    preferenceRevision,
    collectionIntentRevision,
    deviceId,
    accountScope,
    historyGeneration,
    cursor,
    pendingCount,
    canImportLocalHistory,
    lastSyncedAt,
    storageError,
  );
}
