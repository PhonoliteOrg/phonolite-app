import AppKit

/// A main-thread folder chooser, independent of Flutter and stored access grants.
protocol DirectoryPicking: AnyObject {
  /// False declines the request without invoking its completion.
  @discardableResult func select(initialDirectory: URL?, completion: @escaping (URL?) -> Void) -> Bool
  func cancel()
}

final class DirectoryPicker: DirectoryPicking {
  private var panel: NSOpenPanel?
  private var completion: ((URL?) -> Void)?

  deinit { cancel() }

  @discardableResult func select(initialDirectory: URL?, completion: @escaping (URL?) -> Void) -> Bool {
    guard panel == nil else { return false }

    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = "Choose folder"
    panel.directoryURL = initialDirectory
    self.panel = panel
    self.completion = completion

    panel.begin { [weak self] response in
      guard let self, self.panel === panel else { return }

      let completion = self.completion
      self.completion = nil
      self.panel = nil
      completion?(response == .OK ? panel.url : nil)
    }

    return true
  }

  func cancel() {
    let panel = self.panel
    let completion = self.completion
    self.panel = nil
    self.completion = nil

    panel?.cancel(nil)
    completion?(nil)
  }
}
