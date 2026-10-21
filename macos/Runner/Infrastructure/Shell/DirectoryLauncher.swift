import AppKit
import Foundation

/// Main-thread access to the system file manager; acceptance does not imply presentation has finished.
final class DirectoryLauncher {
  private let openURL: (URL) -> Bool

  init(openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
    self.openURL = openURL
  }

  func openDirectory(at directory: URL) -> Bool {
    return openURL(directory)
  }
}
