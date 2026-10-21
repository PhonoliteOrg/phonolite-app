class ArtistDownloadSummary {
  final int total;
  final int downloaded;
  final int active;
  final int failed;
  final bool hasActiveArtistJob;
  final bool hasDownloadScope;

  const ArtistDownloadSummary({
    required this.total,
    required this.downloaded,
    required this.active,
    required this.failed,
    required this.hasActiveArtistJob,
    required this.hasDownloadScope,
  });

  bool get isComplete => total > 0 && downloaded >= total;

  bool get canStart =>
      hasDownloadScope &&
      !hasActiveArtistJob &&
      !isComplete &&
      (total == 0 || downloaded + active < total || failed > 0);

  String get label {
    if (hasActiveArtistJob || (active > 0 && !canStart)) {
      return 'Downloading';
    }

    if (isComplete) {
      return 'Downloaded';
    }

    if (failed > 0) {
      return 'Retry Downloads';
    }

    if (downloaded > 0 || active > 0) {
      return 'Download Missing';
    }

    return 'Download Artist';
  }
}
