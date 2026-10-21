import AppKit

import FlutterMacOS

final class MainFlutterWindow: NSWindow {
  private var engineBinding: FlutterEngineBinding?

  deinit {
    engineBinding?.detach()
  }

  override func awakeFromNib() {
    engineBinding?.detach()

    let flutterViewController = FlutterViewController()
    let windowFrame = frame
    contentViewController = flutterViewController
    setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let binding = FlutterEngineBinding(messenger: flutterViewController.engine.binaryMessenger)
    binding.attach()
    engineBinding = binding

    super.awakeFromNib()
  }
}
