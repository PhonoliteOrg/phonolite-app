import Flutter
import Network
import UIKit

final class LocalNetworkPermissionManager {
  private var listener: NWListener?
  private let queue = DispatchQueue(label: "phonolite.localnetwork")
  private var channel: FlutterMethodChannel?
  private var status: String?
  private let statusKey = "localNetworkStatus"

  init() {
    status = UserDefaults.standard.string(forKey: statusKey)
  }

  func configureChannel(messenger: FlutterBinaryMessenger) {
    if channel != nil {
      return
    }
    let channel = FlutterMethodChannel(
      name: "phonolite/permissions",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "no_self", message: "Permission manager released", details: nil))
        return
      }
      switch call.method {
      case "getLocalNetworkPermission":
        result(self.status ?? "unknown")
      case "refreshLocalNetworkPermission":
        self.requestPermission()
        result(true)
      case "openAppSettings":
        self.openAppSettings(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  func requestPermission() {
    if #available(iOS 14.0, *) {
      let parameters = NWParameters.tcp
      parameters.includePeerToPeer = true
      do {
        let listener = try NWListener(using: parameters, on: 0)
        listener.service = NWListener.Service(name: "Phonolite", type: "_phonolite._tcp")
        listener.newConnectionHandler = { connection in
          connection.cancel()
        }
        listener.stateUpdateHandler = { [weak self] state in
          switch state {
          case .ready:
            self?.notify(status: "granted")
            self?.stopListener()
          case .failed(let error):
            if self?.isDenied(error) == true {
              self?.notify(status: "denied")
            }
            self?.stopListener()
          default:
            break
          }
        }
        self.listener = listener
        listener.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 2.0) { [weak self] in
          self?.stopListener()
        }
      } catch let error as NWError {
        if isDenied(error) {
          notify(status: "denied")
        }
      } catch {
        // Leave as unknown on unexpected errors.
      }
    }
  }

  private func openAppSettings(result: FlutterResult) {
    let open = {
      if let url = URL(string: UIApplication.openSettingsURLString),
         UIApplication.shared.canOpenURL(url) {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        return true
      }
      return false
    }
    if Thread.isMainThread {
      result(open())
      return
    }
    var success = false
    DispatchQueue.main.sync {
      success = open()
    }
    result(success)
  }

  private func stopListener() {
    listener?.cancel()
    listener = nil
  }

  private func notify(status: String) {
    if self.status == status {
      return
    }
    self.status = status
    if status != "unknown" {
      UserDefaults.standard.set(status, forKey: statusKey)
    }
    DispatchQueue.main.async { [weak self] in
      self?.channel?.invokeMethod(
        "localNetworkPermission",
        arguments: ["status": status]
      )
    }
  }

  private func isDenied(_ error: NWError) -> Bool {
    switch error {
    case .posix(let code):
      return code == .EACCES || code == .EPERM
    case .dns(let code):
      return code == -65570
    default:
      return false
    }
  }
}
