import Foundation
import Network

/// Owns the Network listener and retains its existing queue and timeout behavior.
final class LocalNetworkPermissionProbe {
  private let onStatus: (LocalNetworkPermissionStatus) -> Void

  private let queue = DispatchQueue(label: "phonolite.localnetwork")
  private var listener: NWListener?

  init(onStatus: @escaping (LocalNetworkPermissionStatus) -> Void) {
    self.onStatus = onStatus
  }

  deinit {
    listener?.cancel()
  }

  func requestPermission() {
    let parameters = NWParameters.tcp
    parameters.includePeerToPeer = true

    do {
      let listener = try NWListener(using: parameters, on: 0)
      listener.service = NWListener.Service(name: "Phonolite", type: "_phonolite._tcp")
      listener.newConnectionHandler = { connection in
        connection.cancel()
      }
      listener.stateUpdateHandler = { [weak self] state in
        self?.handleListenerState(state)
      }

      self.listener = listener
      listener.start(queue: queue)

      queue.asyncAfter(deadline: .now() + 2.0) { [weak self] in
        self?.stopListener()
      }
    } catch let error as NWError {
      if isDenied(error) {
        onStatus(.denied)
      }
    } catch {
      // Leave as unknown on unexpected errors.
    }
  }

  private func handleListenerState(_ state: NWListener.State) {
    switch state {
    case .ready:
      onStatus(.granted)
      stopListener()
    case .failed(let error):
      if isDenied(error) {
        onStatus(.denied)
      }

      stopListener()
    default:
      break
    }
  }

  private func stopListener() {
    listener?.cancel()
    listener = nil
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
