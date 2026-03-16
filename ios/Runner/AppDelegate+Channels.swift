import Flutter
import UIKit

extension AppDelegate {
  func configureNowPlayingChannel() {
    if nowPlayingChannel != nil {
      return
    }
    guard let messenger = resolveMessenger(plugin: "phonolite_now_playing") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "phonolite/now_playing",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "no_self", message: "AppDelegate released", details: nil))
        return
      }
      switch call.method {
      case "setNowPlaying":
        guard let args = call.arguments as? [String: Any] else {
          result(FlutterError(code: "bad_args", message: "Missing args", details: nil))
          return
        }
        self.updateNowPlayingInfo(args: args)
        result(true)
      case "clearNowPlaying":
        self.clearNowPlaying()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    nowPlayingChannel = channel
    if !remoteCommandsConfigured {
      configureRemoteCommands(channel: channel)
      remoteCommandsConfigured = true
    }
  }

  func sendRemoteCommandToFlutter(_ type: String, arguments: [String: Any] = [:]) {
    configureNowPlayingChannel()
    guard let channel = nowPlayingChannel else {
      return
    }
    var payload = arguments
    payload["type"] = type
    channel.invokeMethod("remoteCommand", arguments: payload)
  }

  func configureCarPlayChannel() {
    if carPlayChannel != nil {
      return
    }
    guard let messenger = resolveMessenger(plugin: "phonolite_carplay") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "phonolite/carplay",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "no_self", message: "AppDelegate released", details: nil))
        return
      }
      switch call.method {
      case "authState":
        let args = call.arguments as? [String: Any]
        let authorized = args?["authorized"] as? Bool ?? false
        self.carPlaySceneDelegate?.updateAuthState(authorized: authorized)
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    carPlayChannel = channel
  }

  func invokeCarPlayMethod(
    _ method: String,
    arguments: Any? = nil,
    completion: ((Any?) -> Void)? = nil
  ) {
    configureCarPlayChannel()
    guard let channel = carPlayChannel else {
      completion?(nil)
      return
    }
    channel.invokeMethod(method, arguments: arguments) { result in
      completion?(result)
    }
  }

  func configurePermissionsChannel() {
    guard let messenger = resolveMessenger(plugin: "phonolite_permissions") else {
      return
    }
    localNetworkPermissions.configureChannel(messenger: messenger)
  }

  private func rootFlutterViewController() -> FlutterViewController? {
    if let controller = window?.rootViewController as? FlutterViewController {
      return controller
    }
    if #available(iOS 13.0, *) {
      for scene in UIApplication.shared.connectedScenes {
        guard let windowScene = scene as? UIWindowScene else {
          continue
        }
        for candidate in windowScene.windows {
          if let controller = candidate.rootViewController as? FlutterViewController {
            return controller
          }
        }
      }
    }
    return nil
  }

  private func resolveMessenger(plugin: String) -> FlutterBinaryMessenger? {
    if let controller = rootFlutterViewController() {
      return controller.binaryMessenger
    }
    if let registrar = registrar(forPlugin: plugin) {
      return registrar.messenger()
    }
    return nil
  }
}
