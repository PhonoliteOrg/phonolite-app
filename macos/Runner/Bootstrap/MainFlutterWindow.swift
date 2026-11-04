import AppKit
import FlutterMacOS

final class MainFlutterWindow: NSWindow {
  private var engineBinding: FlutterEngineBinding?

  deinit { engineBinding?.detach() }

  private func configureTitlebar() {
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    titlebarSeparatorStyle = .none
    appearance = NSAppearance(named: .darkAqua)

    // The translucent Flutter background composites over an opaque black canvas.
    backgroundColor = .black
  }

  override func awakeFromNib() {
    engineBinding?.detach()
    configureTitlebar()

    let flutterViewController = FlutterViewController()
    flutterViewController.backgroundColor = backgroundColor
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
