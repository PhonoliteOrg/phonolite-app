import Flutter

/// Shared registration and invocation mechanics for one Flutter channel binding.
final class FlutterChannelAdapter {
  let pluginName: String

  private let name: String
  private let releasedOwnerMessage: String
  private var channel: FlutterMethodChannel?

  init(pluginName: String, name: String, releasedOwnerMessage: String = "AppDelegate released") {
    self.pluginName = pluginName
    self.name = name
    self.releasedOwnerMessage = releasedOwnerMessage
  }

  var isAttached: Bool {
    return channel != nil
  }

  @discardableResult
  func attach<Owner: AnyObject>(
    to messenger: FlutterBinaryMessenger,
    owner: Owner,
    handler: @escaping (Owner, FlutterMethodCall, FlutterResult) -> Void
  ) -> Bool {
    guard channel == nil else {
      return false
    }

    let channel = FlutterMethodChannel(name: name, binaryMessenger: messenger)
    let releasedOwnerMessage = self.releasedOwnerMessage

    channel.setMethodCallHandler { [weak owner] call, result in
      guard let owner else {
        result(FlutterError(code: "no_self", message: releasedOwnerMessage, details: nil))

        return
      }

      handler(owner, call, result)
    }

    self.channel = channel

    return true
  }

  func send(_ method: String, arguments: Any?) {
    channel?.invokeMethod(method, arguments: arguments)
  }

  func invoke(_ method: String, arguments: Any? = nil, completion: @escaping (Any?) -> Void) {
    guard let channel else {
      completion(nil)

      return
    }

    channel.invokeMethod(method, arguments: arguments, result: completion)
  }
}
