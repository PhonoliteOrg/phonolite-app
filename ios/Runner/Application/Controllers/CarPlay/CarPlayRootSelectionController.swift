/// Defers source selection until the current root has finished installing.
final class CarPlayRootSelectionController {
  private let applySelection: (CarPlayScope) -> Void

  private var generation = 0
  private var isInstalled = false
  private var requestedScope: CarPlayScope?

  init(applySelection: @escaping (CarPlayScope) -> Void) {
    self.applySelection = applySelection
  }

  func beginInstallation(preferredScope: CarPlayScope? = nil) -> Int {
    invalidate()
    requestedScope = preferredScope

    return generation
  }

  /// A stale completion cannot select a tab in a replacement root or scene.
  func completeInstallation(generation: Int, succeeded: Bool) -> Bool {
    guard generation == self.generation else {
      return false
    }

    isInstalled = succeeded
    applyRequestedSelection()

    return succeeded
  }

  func invalidate() {
    generation += 1
    isInstalled = false
    requestedScope = nil
  }

  func select(_ scope: CarPlayScope) {
    requestedScope = scope
    applyRequestedSelection()
  }

  private func applyRequestedSelection() {
    guard isInstalled, let requestedScope else {
      return
    }

    applySelection(requestedScope)
  }
}
