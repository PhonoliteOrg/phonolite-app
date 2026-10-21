import Foundation

import Flutter

final class PermissionsChannelAdapter: FlutterChannelEndpoint {
  private let readStatus: () -> LocalNetworkPermissionStatus
  private let requestPermission: () -> Void
  private let openSettings: () -> Bool

  private let channel = FlutterChannelAdapter(
    pluginName: "phonolite_permissions",
    name: "phonolite/permissions",
    releasedOwnerMessage: "Permission manager released"
  )

  init(
    readStatus: @escaping () -> LocalNetworkPermissionStatus,
    requestPermission: @escaping () -> Void,
    openSettings: @escaping () -> Bool
  ) {
    self.readStatus = readStatus
    self.requestPermission = requestPermission
    self.openSettings = openSettings
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

  func publish(_ status: LocalNetworkPermissionStatus) {
    DispatchQueue.main.async { [weak self] in
      self?.channel.send("localNetworkPermission", arguments: ["status": status.rawValue])
    }
  }

  private func handle(_ call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "getLocalNetworkPermission":
      result(readStatus().rawValue)
    case "refreshLocalNetworkPermission":
      requestPermission()
      result(true)
    case "openAppSettings":
      result(openSettings())
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
