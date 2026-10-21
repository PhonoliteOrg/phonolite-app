import Foundation

final class LocalNetworkPermissionStore {
  private static let statusKey = "localNetworkStatus"

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func read() -> LocalNetworkPermissionStatus? {
    guard let value = defaults.string(forKey: Self.statusKey) else {
      return nil
    }

    return LocalNetworkPermissionStatus(rawValue: value)
  }

  func write(_ status: LocalNetworkPermissionStatus) {
    defaults.set(status.rawValue, forKey: Self.statusKey)
  }
}
