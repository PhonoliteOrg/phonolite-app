import Flutter

final class NowPlayingChannelAdapter: FlutterChannelEndpoint {
  private let onUpdate: (NowPlayingUpdate) -> Void
  private let onClear: () -> Void
  private let onAttached: () -> Void

  private let channel = FlutterChannelAdapter(pluginName: "phonolite_now_playing", name: "phonolite/now_playing")

  init(
    onUpdate: @escaping (NowPlayingUpdate) -> Void,
    onClear: @escaping () -> Void,
    onAttached: @escaping () -> Void
  ) {
    self.onUpdate = onUpdate
    self.onClear = onClear
    self.onAttached = onAttached
  }

  var pluginName: String {
    return channel.pluginName
  }

  var isAttached: Bool {
    return channel.isAttached
  }

  func attach(to messenger: FlutterBinaryMessenger) {
    let attached = channel.attach(to: messenger, owner: self) { owner, call, result in
      owner.handle(call, result: result)
    }

    if attached {
      onAttached()
    }
  }

  func send(_ command: NativeRemoteCommand) {
    channel.send("remoteCommand", arguments: ["type": command.rawValue])
  }

  private func handle(_ call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "setNowPlaying":
      guard let arguments = call.arguments as? [String: Any] else {
        result(FlutterError(code: "bad_args", message: "Missing args", details: nil))

        return
      }

      onUpdate(NowPlayingCodec.decode(arguments))
      result(true)
    case "clearNowPlaying":
      onClear()
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
