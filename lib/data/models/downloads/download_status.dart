enum OfflineDownloadStatus {
  queued,
  preparing,
  downloading,
  paused,
  validating,
  downloaded,
  removing,
  failed,
  corrupt,
  canceled;

  static final Map<String, OfflineDownloadStatus> _byName = values.asNameMap();

  /// Parses a stored status name; unknown or missing values fall back to [queued].
  static OfflineDownloadStatus fromName(Object? name) => _byName[name] ?? queued;
}
