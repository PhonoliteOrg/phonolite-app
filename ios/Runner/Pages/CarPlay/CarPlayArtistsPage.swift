import CarPlay

struct CarPlayArtistsPage {
  let scope: CarPlayScope
  let controller: CarPlayBrowseController
  let loadArtwork: CarPlayListFrame.ArtworkLoader
  let onSelect: (CarPlayItem) -> Void

  func show(present: (CPListTemplate) -> Void) {
    let frame = CarPlayListFrame(
      loadingMessage: "Loading artists...",
      emptyMessage: scope == .local ? "No downloaded artists" : "No artists found",
      errorMessage: scope == .local ? "No downloaded artists" : "Connect to a server",
      loadArtwork: loadArtwork
    )
    let page = CarPlayBrowsePage(
      controller: controller,
      request: .artists(scope: scope),
      frame: frame,
      onSelect: onSelect
    )

    page.show(present: present)
  }
}
