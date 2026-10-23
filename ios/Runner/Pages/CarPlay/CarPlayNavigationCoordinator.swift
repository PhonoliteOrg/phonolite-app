import CarPlay
import Foundation
import UIKit

/// Main-thread scene owner that assembles concrete pages and delegates navigation presentation to the shell.
final class CarPlayNavigationCoordinator {
  private let browse: CarPlayBrowseController
  private let loadArtwork: CarPlayListFrame.ArtworkLoader
  private let shell: CarPlayShell
  private let onConnected: (CarPlayNavigationCoordinator) -> Void
  private let onDisconnected: (CarPlayNavigationCoordinator) -> Void

  private var contentStyle = UIUserInterfaceStyle.unspecified
  private var sceneGeneration = 0
  private lazy var sourceGrid = CarPlaySourceGrid(
    onLibrary: { [weak self] scope in self?.showArtists(scope: scope) },
    onPlaylists: { [weak self] scope in self?.showPlaylists(scope: scope) },
    onLiked: { [weak self] scope in self?.play(.playLiked(scope: scope)) },
    onShuffle: { [weak self] scope in self?.play(.startLibraryShuffle(scope: scope)) }
  )
  private lazy var rootPage = CarPlayRootPage(sourceGrid: sourceGrid)

  init(
    client: CarPlayClient,
    loadArtwork: @escaping CarPlayListFrame.ArtworkLoader,
    refreshNowPlaying: @escaping () -> Void,
    sendRemoteCommand: @escaping (NativeRemoteCommand) -> Void,
    onConnected: @escaping (CarPlayNavigationCoordinator) -> Void,
    onDisconnected: @escaping (CarPlayNavigationCoordinator) -> Void
  ) {
    self.browse = CarPlayBrowseController(client: client)
    self.loadArtwork = loadArtwork
    self.shell = CarPlayShell(
      nowPlaying: CarPlayNowPlayingPresenter(sendRemoteCommand: sendRemoteCommand),
      refreshNowPlaying: refreshNowPlaying
    )
    self.onConnected = onConnected
    self.onDisconnected = onDisconnected
  }

  /// The enrollment callback refreshes metadata and attaches the channel before the initial state request.
  func connect(using interfaceController: CPInterfaceController, scene: CPTemplateApplicationScene) {
    sceneGeneration += 1
    let generation = sceneGeneration

    shell.connect(using: interfaceController)

    contentStyle = scene.contentStyle

    shell.installRoot(rootPage.makeLoadingTemplate())

    DispatchQueue.main.async { [weak self] in
      guard let self, self.shell.isConnected, self.sceneGeneration == generation else {
        return
      }

      self.onConnected(self)
      self.requestSourceState(force: true)
    }
  }

  func disconnect(_ controller: CPInterfaceController) {
    sceneGeneration += 1
    shell.disconnect(controller)
    browse.disconnect()
    contentStyle = .unspecified

    onDisconnected(self)
  }

  func contentStyleDidChange(_ contentStyle: UIUserInterfaceStyle) {
    DispatchQueue.main.async { [weak self] in
      guard let self, self.contentStyle != contentStyle else {
        return
      }

      self.contentStyle = contentStyle
      self.shell.updateSourceButtons(using: self.sourceGrid, contentStyle: contentStyle)
    }
  }

  func updateSourceState(_ state: CarPlaySourceState, force: Bool = false) {
    DispatchQueue.main.async { [weak self] in
      self?.applySourceState(state, force: force)
    }
  }

  func requestSourceState(force: Bool = false) {
    browse.requestState { [weak self] state in
      self?.applySourceState(state, force: force)
    }
  }

  func updateNowPlayingButtons(liked: Bool, available: Bool) {
    shell.updateNowPlayingButtons(liked: liked, available: available)
  }

  private func applySourceState(_ state: CarPlaySourceState, force: Bool) {
    guard shell.isConnected, browse.updateSourceState(state, force: force) else {
      return
    }

    shell.resetSourceTemplates()

    let content = rootPage.makeContent(state: browse.sourceState, contentStyle: contentStyle)
    shell.installRoot(content)
  }

  private func play(_ command: CarPlayCommand) {
    browse.perform(command)

    shell.showNowPlaying()
  }

  private func showArtists(scope: CarPlayScope) {
    guard shell.isConnected else {
      return
    }

    let page = CarPlayArtistsPage(
      scope: scope,
      controller: browse,
      loadArtwork: loadArtwork,
      onSelect: { [weak self] entry in self?.showAlbums(scope: scope, artistID: entry.id) }
    )

    page.show { [shell] template in shell.push(template) }
  }

  private func showAlbums(scope: CarPlayScope, artistID: String) {
    guard shell.isConnected else {
      return
    }

    let page = CarPlayAlbumsPage(
      scope: scope,
      artistID: artistID,
      controller: browse,
      loadArtwork: loadArtwork
    ) { [weak self] entry in
      self?.play(.playAlbum(scope: scope, albumID: entry.id))
    }

    page.show { [shell] template in shell.push(template) }
  }

  private func showPlaylists(scope: CarPlayScope) {
    guard shell.isConnected else {
      return
    }

    let page = CarPlayPlaylistsPage(
      scope: scope,
      controller: browse,
      loadArtwork: loadArtwork,
      onSelect: { [weak self] entry in self?.play(.playPlaylist(scope: scope, playlistID: entry.id)) }
    )

    page.show { [shell] template in shell.push(template) }
  }
}
