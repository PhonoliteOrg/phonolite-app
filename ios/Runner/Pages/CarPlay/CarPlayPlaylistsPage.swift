import CarPlay

struct CarPlayPlaylistsPage {
  let scope: CarPlayScope
  let controller: CarPlayBrowseController
  let loadArtwork: CarPlayListFrame.ArtworkLoader
  let onSelect: (CarPlayItem) -> Void

  func show(present: (CPListTemplate) -> Void) {
    let frame = CarPlayListFrame(
      loadingMessage: "Loading playlists...",
      emptyMessage: scope == .local ? "No local playlists" : "No playlists found",
      errorMessage: scope == .local ? "No local playlists" : "Connect to a server",
      loadArtwork: loadArtwork
    )
    let page = CarPlayBrowsePage(
      controller: controller,
      request: .playlists(scope: scope),
      frame: frame,
      onSelect: onSelect
    )

    page.show(present: present)
  }
}
