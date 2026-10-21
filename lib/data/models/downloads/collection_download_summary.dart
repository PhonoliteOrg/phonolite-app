class CollectionDownloadSummary {
  final int total;
  final int downloaded;
  final int active;
  final int failed;

  const CollectionDownloadSummary({
    required this.total,
    required this.downloaded,
    required this.active,
    required this.failed,
  });

  bool get isComplete => total > 0 && downloaded >= total;

  bool get canStart => total > 0 && active == 0 && !isComplete;

  String get label {
    if (active > 0) {
      return 'Downloading';
    }

    if (isComplete) {
      return 'Downloaded';
    }

    if (failed > 0) {
      return 'Retry Downloads';
    }

    if (downloaded > 0) {
      return 'Download Missing';
    }

    return 'Download Album';
  }
}
