import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var directoryChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    directoryChannel = FlutterMethodChannel(
      name: "phonolite/directories",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    directoryChannel?.setMethodCallHandler { call, result in
      guard call.method == "openDirectory" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let path = call.arguments as? String, !path.isEmpty else {
        result(FlutterError(
          code: "invalid_path", message: "A folder path is required.", details: nil))
        return
      }
      let directory = URL(fileURLWithPath: path, isDirectory: true)
      if NSWorkspace.shared.open(directory) {
        result(nil)
      } else {
        result(FlutterError(
          code: "open_failed", message: "Could not open the folder.", details: nil))
      }
    }

    super.awakeFromNib()
  }
}
