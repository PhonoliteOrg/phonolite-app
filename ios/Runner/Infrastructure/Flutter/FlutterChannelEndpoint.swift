import Flutter

/// Identifies an engine-bound channel and its idempotent attachment operation.
protocol FlutterChannelEndpoint: AnyObject {
  var pluginName: String { get }

  var isAttached: Bool { get }

  func attach(to messenger: FlutterBinaryMessenger)
}
