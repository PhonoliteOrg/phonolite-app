import Foundation

import FlutterMacOS

/// Main-thread transport for one engine. The binding detaches before releasing its messenger.
final class DirectoriesChannelAdapter {
  private static let channelName = "phonolite/directories"

  private let openDirectory: (URL) -> Bool
  private let setMethodCallHandler: (FlutterMethodCallHandler?) -> Void

  private(set) var isAttached = false

  init(openDirectory: @escaping (URL) -> Bool, setMethodCallHandler: @escaping (FlutterMethodCallHandler?) -> Void) {
    self.openDirectory = openDirectory
    self.setMethodCallHandler = setMethodCallHandler
  }

  convenience init(messenger: FlutterBinaryMessenger, openDirectory: @escaping (URL) -> Bool) {
    let channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)

    self.init(openDirectory: openDirectory, setMethodCallHandler: { channel.setMethodCallHandler($0) })
  }

  func attach() {
    guard !isAttached else {
      return
    }

    // Capturing the capability keeps accepted calls completable without retaining this adapter.
    let openDirectory = self.openDirectory
    setMethodCallHandler { call, result in
      Self.handle(call, result: result, openDirectory: openDirectory)
    }
    isAttached = true
  }

  func detach() {
    guard isAttached else {
      return
    }

    setMethodCallHandler(nil)
    isAttached = false
  }

  private static func handle(_ call: FlutterMethodCall, result: FlutterResult, openDirectory: (URL) -> Bool) {
    guard call.method == "openDirectory" else {
      result(FlutterMethodNotImplemented)

      return
    }

    guard let path = call.arguments as? String, !path.isEmpty else {
      result(FlutterError(code: "invalid_path", message: "A folder path is required.", details: nil))

      return
    }

    let directory = URL(fileURLWithPath: path, isDirectory: true)

    if openDirectory(directory) {
      result(nil)
    } else {
      result(FlutterError(code: "open_failed", message: "Could not open the folder.", details: nil))
    }
  }
}
