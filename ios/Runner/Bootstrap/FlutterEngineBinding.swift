import Flutter

/// Resolves the host's messenger without exposing UIKit discovery to adapters.
final class FlutterEngineBinding {
  private let resolveMessenger: (String) -> FlutterBinaryMessenger?

  init(resolveMessenger: @escaping (String) -> FlutterBinaryMessenger?) {
    self.resolveMessenger = resolveMessenger
  }

  func attach(_ endpoint: FlutterChannelEndpoint) {
    guard !endpoint.isAttached else {
      return
    }

    guard let messenger = resolveMessenger(endpoint.pluginName) else {
      return
    }

    endpoint.attach(to: messenger)
  }
}
