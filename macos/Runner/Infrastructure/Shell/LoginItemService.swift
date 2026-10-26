import ServiceManagement

import LaunchAtLogin

/// Uses the system-managed main-app login item on modern macOS and the
/// embedded helper on macOS 10.15–12.
final class LoginItemService {
  func isEnabled() -> Bool {
    if #available(macOS 13.0, *) {
      return SMAppService.mainApp.status == .enabled
    }

    return LaunchAtLogin.isEnabled
  }

  func setEnabled(_ enabled: Bool) throws {
    if #available(macOS 13.0, *) {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } else {
      LaunchAtLogin.isEnabled = enabled
    }
  }
}
