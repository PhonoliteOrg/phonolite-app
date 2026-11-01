import FlutterMacOS
import Foundation

final class StorageAccessChannelAdapter {
  private let channel = FlutterChannelAdapter(pluginName: "phonolite_storage_access", name: "phonolite/storage_access")
  private let messenger: FlutterBinaryMessenger
  private let directories: SecurityScopedDirectories
  private let picker: DirectoryPicking
  private var pendingResult: FlutterResult?

  init(
    messenger: FlutterBinaryMessenger, directories: SecurityScopedDirectories = SecurityScopedDirectories(),
    picker: DirectoryPicking = DirectoryPicker()
  ) {
    self.messenger = messenger
    self.directories = directories
    self.picker = picker
  }

  deinit { detach() }

  func attach() {
    channel.attach(to: messenger, owner: self) { owner, call, result in
      switch call.method {
      case "restoreDirectories":
        let restored = owner.directories.restore()
        result(["paths": restored.paths, "unavailable": restored.unavailable])
      case "selectDirectory": owner.selectDirectory(initialPath: call.arguments as? String, result: result)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  func detach() {
    channel.detach()

    let reply = pendingResult
    pendingResult = nil
    if let reply {
      reply(nil)
      picker.cancel()
    }

    directories.close()
  }

  private func selectDirectory(initialPath: String?, result: @escaping FlutterResult) {
    guard pendingResult == nil else {
      result(FlutterError(code: "busy", message: "A folder chooser is already open.", details: nil))

      return
    }

    var initialDirectory: URL?

    if let initialPath, !initialPath.isEmpty { initialDirectory = URL(fileURLWithPath: initialPath, isDirectory: true) }

    pendingResult = result
    let accepted = picker.select(initialDirectory: initialDirectory) { [weak self] url in
      guard let self, let reply = self.pendingResult else { return }

      self.pendingResult = nil
      guard let url else {
        reply(nil)

        return
      }

      do { reply(try self.directories.retainAccess(to: url)) } catch {
        reply(FlutterError(code: "access_failed", message: error.localizedDescription, details: nil))
      }
    }

    if !accepted {
      pendingResult = nil
      result(FlutterError(code: "busy", message: "A folder chooser is already open.", details: nil))
    }
  }
}
