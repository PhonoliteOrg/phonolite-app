import CarPlay
import Foundation
import UIKit

struct CarPlayRootContent {
  let template: CPTemplate
  let localTemplate: CPGridTemplate?
  let serverTemplate: CPGridTemplate?
}

/// Main-thread owner of the scene's active native template resources and navigation presentation.
final class CarPlayShell {
  private let nowPlaying: CarPlayNowPlayingPresenter
  private let refreshNowPlaying: () -> Void

  private weak var interfaceController: CPInterfaceController?
  // Retain the scene's root independently of CarPlay's installation callback.
  private var rootTemplate: CPTemplate?
  private var localTemplate: CPGridTemplate?
  private var serverTemplate: CPGridTemplate?

  init(nowPlaying: CarPlayNowPlayingPresenter, refreshNowPlaying: @escaping () -> Void) {
    self.nowPlaying = nowPlaying
    self.refreshNowPlaying = refreshNowPlaying
  }

  var isConnected: Bool {
    return interfaceController != nil
  }

  func connect(using interfaceController: CPInterfaceController) {
    self.interfaceController = interfaceController
    interfaceController.prefersDarkUserInterfaceStyle = false
    nowPlaying.configureMiniPlayer()
  }

  func disconnect(_ controller: CPInterfaceController) {
    if interfaceController === controller {
      interfaceController = nil
    }

    rootTemplate = nil
    resetSourceTemplates()
  }

  func resetSourceTemplates() {
    localTemplate = nil
    serverTemplate = nil
  }

  func installRoot(_ template: CPTemplate) {
    guard let interfaceController else {
      return
    }

    rootTemplate = template

    interfaceController.setRootTemplate(template, animated: false) { [weak self] success, _ in
      if success {
        self?.refreshNowPlaying()
      }
    }
  }

  func installRoot(_ content: CarPlayRootContent) {
    localTemplate = content.localTemplate
    serverTemplate = content.serverTemplate

    installRoot(content.template)
  }

  func updateSourceButtons(using grid: CarPlaySourceGrid, contentStyle: UIUserInterfaceStyle) {
    localTemplate?.updateGridButtons(grid.makeButtons(scope: .local, contentStyle: contentStyle))
    serverTemplate?.updateGridButtons(grid.makeButtons(scope: .server, contentStyle: contentStyle))
  }

  func push(_ template: CPTemplate) {
    guard let interfaceController else {
      return
    }

    interfaceController.pushTemplate(template, animated: true, completion: { _, _ in })
  }

  func showNowPlaying() {
    guard let interfaceController, interfaceController.topTemplate !== nowPlaying.template else {
      return
    }

    push(nowPlaying.template)

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
      self?.refreshNowPlaying()
    }
  }

  func updateNowPlayingButtons(liked: Bool, available: Bool) {
    nowPlaying.updateButtons(liked: liked, available: available)
  }
}
