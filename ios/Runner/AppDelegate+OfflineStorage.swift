import Foundation

extension AppDelegate {
  func refreshOfflineStorageBackupExclusions() {
    OfflineStorageBackupManager.refresh()
  }
}

private enum OfflineStorageBackupManager {
  static func refresh() {
    guard let root = offlineRootURL() else {
      return
    }

    excludeFromBackupIfPresent(root.appendingPathComponent("art", isDirectory: true))

    guard
      let children = try? FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return
    }

    for child in children where child.lastPathComponent.hasPrefix("server_") {
      guard isDirectory(child) else {
        continue
      }
      excludeFromBackup(child)
    }
  }

  private static func offlineRootURL() -> URL? {
    guard
      let supportDirectory = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first
    else {
      return nil
    }
    return supportDirectory
      .appendingPathComponent("Phonolite", isDirectory: true)
      .appendingPathComponent("offline", isDirectory: true)
  }

  private static func isDirectory(_ url: URL) -> Bool {
    var isDirectoryValue: ObjCBool = false
    let exists = FileManager.default.fileExists(
      atPath: url.path,
      isDirectory: &isDirectoryValue
    )
    return exists && isDirectoryValue.boolValue
  }

  private static func excludeFromBackupIfPresent(_ url: URL) {
    guard isDirectory(url) else {
      return
    }
    excludeFromBackup(url)
  }

  private static func excludeFromBackup(_ url: URL) {
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    var mutableURL = url
    do {
      try mutableURL.setResourceValues(values)
    } catch {
      NSLog("Failed to exclude offline storage path from backup: %@", error.localizedDescription)
    }
  }
}
