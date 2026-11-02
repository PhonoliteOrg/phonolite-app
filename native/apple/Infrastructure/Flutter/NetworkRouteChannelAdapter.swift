import Foundation

#if os(macOS)
  import FlutterMacOS
#else
  import Flutter
#endif

/// Event transport owns observation only while Dart has a subscriber.
final class NetworkRouteChannelAdapter: FlutterChannelEndpoint {
  let pluginName = "NetworkRouteChannel"

  private let monitor = NetworkRouteMonitor()
  private var channel: FlutterEventChannel?
  private var handler: StreamHandler?

  var isAttached: Bool { channel != nil }

  deinit { detach() }

  func attach(to messenger: FlutterBinaryMessenger) {
    guard channel == nil else { return }

    let channel = FlutterEventChannel(
      name: "com.phonoliteorg.phonolite_app/network_routes", binaryMessenger: messenger)
    let handler = StreamHandler(owner: self)
    channel.setStreamHandler(handler)
    self.channel = channel
    self.handler = handler
  }

  func detach() {
    monitor.stop()
    channel?.setStreamHandler(nil)
    channel = nil
    handler = nil
  }

  private final class StreamHandler: NSObject, FlutterStreamHandler {
    private weak var owner: NetworkRouteChannelAdapter?

    init(owner: NetworkRouteChannelAdapter) { self.owner = owner }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
      guard let owner else {
        return FlutterError(code: "released", message: "Network monitor owner released", details: nil)
      }

      owner.monitor.start { revision in events(revision) }

      return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
      owner?.monitor.stop()

      return nil
    }
  }
}
