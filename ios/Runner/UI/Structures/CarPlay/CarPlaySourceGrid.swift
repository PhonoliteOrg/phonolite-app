import CarPlay
import UIKit

/// Supplies the common source destinations and action design for both source scopes.
struct CarPlaySourceGrid {
  private let onLibrary: (CarPlayScope) -> Void
  private let onPlaylists: (CarPlayScope) -> Void
  private let onLiked: (CarPlayScope) -> Void
  private let onShuffle: (CarPlayScope) -> Void

  private let icons = CarPlayIconProvider()

  init(
    onLibrary: @escaping (CarPlayScope) -> Void,
    onPlaylists: @escaping (CarPlayScope) -> Void,
    onLiked: @escaping (CarPlayScope) -> Void,
    onShuffle: @escaping (CarPlayScope) -> Void
  ) {
    self.onLibrary = onLibrary
    self.onPlaylists = onPlaylists
    self.onLiked = onLiked
    self.onShuffle = onShuffle
  }

  func makeButtons(scope: CarPlayScope, contentStyle: UIUserInterfaceStyle) -> [CPGridButton] {
    let libraryItem = CPGridButton(
      titleVariants: ["Library"],
      image: icons.gridIcon(named: "LucideDisc3", contentStyle: contentStyle)
    ) { _ in
      onLibrary(scope)
    }

    let playlistsItem = CPGridButton(
      titleVariants: ["Playlists"],
      image: icons.gridIcon(named: "LucideListMusic", contentStyle: contentStyle)
    ) { _ in
      onPlaylists(scope)
    }

    let likedItem = CPGridButton(
      titleVariants: ["Liked Songs", "Liked"],
      image: icons.gridIcon(named: "LucideHeartFilled", contentStyle: contentStyle)
    ) { _ in
      onLiked(scope)
    }

    let shuffleItem = CPGridButton(
      titleVariants: ["Shuffle"],
      image: icons.gridIcon(named: "LucideShuffle", contentStyle: contentStyle)
    ) { _ in
      onShuffle(scope)
    }

    return [libraryItem, playlistsItem, likedItem, shuffleItem]
  }

  private func configureTab(_ template: CPTemplate, scope: CarPlayScope) {
    let title = scope == .local ? "Local" : "Server"
    let imageName = scope == .local ? "LucideDownload" : "LucideAntenna"
    let fallback = scope == .local ? "LucideBookmark" : "LucideEllipsis"

    template.tabTitle = title
    template.tabImage = icons.templateIcon(named: imageName) ?? icons.templateIcon(named: fallback)
  }

  func makeTemplate(scope: CarPlayScope, contentStyle: UIUserInterfaceStyle) -> CPGridTemplate {
    let template = CPGridTemplate(title: "", gridButtons: makeButtons(scope: scope, contentStyle: contentStyle))
    configureTab(template, scope: scope)

    return template
  }
}
