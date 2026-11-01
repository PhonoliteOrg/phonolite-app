import CarPlay
import Foundation
import UIKit

struct CarPlayRootContent {
  let template: CPTemplate
  let localTemplate: CPGridTemplate?
  let serverTemplate: CPGridTemplate?
  let preferredScope: CarPlayScope
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
  private lazy var rootSelection = CarPlayRootSelectionController { [weak self] scope in
    self?.applySourceSelection(scope)
  }

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
    rootSelection.invalidate()
    localTemplate = nil
    serverTemplate = nil
  }

  func installRoot(_ template: CPTemplate) {
    installRoot(template, preferredScope: nil)
  }

  func installRoot(_ content: CarPlayRootContent) {
    localTemplate = content.localTemplate
    serverTemplate = content.serverTemplate

    installRoot(content.template, preferredScope: content.preferredScope)
  }

  func updateSourceButtons(using grid: CarPlaySourceGrid, contentStyle: UIUserInterfaceStyle) {
    localTemplate?.updateGridButtons(grid.makeButtons(scope: .local, contentStyle: contentStyle))
    serverTemplate?.updateGridButtons(grid.makeButtons(scope: .server, contentStyle: contentStyle))
  }

  /// Updates a restored source without replacing the scene's root template.
  func selectSource(_ scope: CarPlayScope) -> Bool {
    let selected = scope == .local ? localTemplate : serverTemplate

    guard let selected else {
      return false
    }

    if rootTemplate === selected {
      rootSelection.select(scope)

      return true
    }

    if #available(iOS 17.0, *), rootTemplate is CPTabBarTemplate {
      rootSelection.select(scope)

      return true
    }

    return false
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

  private func installRoot(_ template: CPTemplate, preferredScope: CarPlayScope?) {
    guard let interfaceController else {
      return
    }

    let generation = rootSelection.beginInstallation(preferredScope: preferredScope)
    rootTemplate = template

    interfaceController.setRootTemplate(template, animated: false) { [weak self] success, error in
      guard let self,
        self.rootSelection.completeInstallation(generation: generation, succeeded: success)
      else {
        if let error {
          NSLog("Phonolite CarPlay root installation failed: %@", error.localizedDescription)
        }

        return
      }

      self.refreshNowPlaying()
    }
  }

  private func applySourceSelection(_ scope: CarPlayScope) {
    guard #available(iOS 17.0, *), let tabs = rootTemplate as? CPTabBarTemplate else {
      return
    }

    // Select only after installation. A pre-install selection can be replaced
    // by CarPlay's initial Local tab, even when selectedTemplate looks current.
    tabs.selectTemplate(at: scope == .local ? 0 : 1)
    NSLog("Phonolite CarPlay source selection requested after root installation: %@", scope.rawValue)
  }
}
