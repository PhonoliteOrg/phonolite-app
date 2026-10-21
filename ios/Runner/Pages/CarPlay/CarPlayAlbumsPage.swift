import CarPlay

struct CarPlayAlbumsPage {
  let scope: CarPlayScope
  let artistID: String
  let controller: CarPlayBrowseController
  let loadArtwork: CarPlayListFrame.ArtworkLoader
  let onSelect: (CarPlayItem) -> Void

  func show(present: (CPListTemplate) -> Void) {
    let frame = CarPlayListFrame(
      loadingMessage: "Loading albums...",
      emptyMessage: "No albums found",
      errorMessage: scope == .local ? "No downloaded albums" : "Connect to a server",
      loadArtwork: loadArtwork
    )
    let page = CarPlayBrowsePage(
      controller: controller,
      request: .albums(scope: scope, artistID: artistID),
      frame: frame,
      onSelect: onSelect
    )

    page.show(present: present)
  }
}
