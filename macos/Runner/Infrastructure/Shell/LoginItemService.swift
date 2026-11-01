import ServiceManagement

/// Uses the system-managed main-app login item without a bundled helper.
final class LoginItemService {
  func isEnabled() -> Bool { return SMAppService.mainApp.status == .enabled }

  func setEnabled(_ enabled: Bool) throws {
    if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
  }
}
