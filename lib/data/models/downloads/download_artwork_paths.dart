class DownloadArtworkPaths {
  final String? albumArtPath;
  final String? artistArtPath;
  final String? artistBannerPath;

  const DownloadArtworkPaths({this.albumArtPath, this.artistArtPath, this.artistBannerPath});

  bool get isEmpty => albumArtPath == null && artistArtPath == null && artistBannerPath == null;
}
