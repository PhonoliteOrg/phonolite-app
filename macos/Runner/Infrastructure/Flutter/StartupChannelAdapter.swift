import FlutterMacOS

/// Engine-bound transport around an injected login-item capability.
final class StartupChannelAdapter {
  private let channel: FlutterMethodChannel
  private let isEnabled: () -> Bool
  private let setEnabled: (Bool) throws -> Void

  init(messenger: FlutterBinaryMessenger, isEnabled: @escaping () -> Bool, setEnabled: @escaping (Bool) throws -> Void) {
    channel = FlutterMethodChannel(name: "launch_at_startup", binaryMessenger: messenger)
    self.isEnabled = isEnabled
    self.setEnabled = setEnabled
  }

  func attach() {
    let isEnabled = self.isEnabled
    let setEnabled = self.setEnabled

    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "launchAtStartupIsEnabled":
        result(isEnabled())
      case "launchAtStartupSetEnabled":
        guard let arguments = call.arguments as? [String: Any],
              let enabled = arguments["setEnabledValue"] as? Bool else {
          result(FlutterError(code: "invalid_setting", message: "A startup setting is required.", details: nil))

          return
        }

        do {
          try setEnabled(enabled)

          result(nil)
        } catch {
          result(FlutterError(code: "startup_failed", message: error.localizedDescription, details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func detach() {
    channel.setMethodCallHandler(nil)
  }
}
