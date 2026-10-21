import Flutter

final class CarPlayChannelAdapter: FlutterChannelEndpoint, CarPlayClient {
  private let prepareToInvoke: () -> Void
  private let onSourceState: (CarPlaySourceState) -> Void
  private let onAuthorizationChanged: () -> Void

  private let channel = FlutterChannelAdapter(pluginName: "phonolite_carplay", name: "phonolite/carplay")

  init(
    prepareToInvoke: @escaping () -> Void,
    onSourceState: @escaping (CarPlaySourceState) -> Void,
    onAuthorizationChanged: @escaping () -> Void
  ) {
    self.prepareToInvoke = prepareToInvoke
    self.onSourceState = onSourceState
    self.onAuthorizationChanged = onAuthorizationChanged
  }

  var pluginName: String {
    return channel.pluginName
  }

  var isAttached: Bool {
    return channel.isAttached
  }

  func attach(to messenger: FlutterBinaryMessenger) {
    channel.attach(to: messenger, owner: self) { owner, call, result in
      owner.handle(call, result: result)
    }
  }

  func requestState(completion: @escaping (CarPlaySourceState) -> Void) {
    prepareToInvoke()

    channel.invoke(CarPlayCodec.stateMethod) { response in
      completion(CarPlayCodec.decodeSourceState(response))
    }
  }

  func requestList(_ request: CarPlayListRequest, completion: @escaping (CarPlayListResult) -> Void) {
    prepareToInvoke()

    channel.invoke(CarPlayCodec.method(for: request), arguments: CarPlayCodec.arguments(for: request)) { response in
      completion(CarPlayCodec.decodeList(response))
    }
  }

  func send(_ command: CarPlayCommand) {
    prepareToInvoke()

    channel.send(CarPlayCodec.method(for: command), arguments: CarPlayCodec.arguments(for: command))
  }

  private func handle(_ call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "carPlayState":
      onSourceState(CarPlayCodec.decodeSourceState(call.arguments))
      result(true)
    case "authState":
      onAuthorizationChanged()
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
