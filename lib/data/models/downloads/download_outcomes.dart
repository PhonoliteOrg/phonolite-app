class DownloadArtworkPaths {
  final String? albumArtPath;
  final String? artistArtPath;
  final String? artistBannerPath;

  const DownloadArtworkPaths({this.albumArtPath, this.artistArtPath, this.artistBannerPath});

  bool get isEmpty => albumArtPath == null && artistArtPath == null && artistBannerPath == null;
}

class DownloadPaused implements Exception {
  final String message;

  const DownloadPaused(this.message);

  @override
  String toString() => message;
}

class DownloadCanceled implements Exception {
  const DownloadCanceled();
}

class DownloadRenditionExpired implements Exception {
  const DownloadRenditionExpired();
}

class DownloadCorrupt implements Exception {
  final String message;

  const DownloadCorrupt(this.message);

  @override
  String toString() => message;
}
