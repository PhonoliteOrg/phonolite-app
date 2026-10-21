/// Coordinates the native probe's cached status without owning a Flutter channel.
final class LocalNetworkPermissionService {
  private let store: LocalNetworkPermissionStore

  private var savedStatus: LocalNetworkPermissionStatus?
  private var statusHandler: ((LocalNetworkPermissionStatus) -> Void)?

  private lazy var probe = LocalNetworkPermissionProbe { [weak self] status in
    self?.receive(status)
  }

  init(store: LocalNetworkPermissionStore = LocalNetworkPermissionStore()) {
    self.store = store
    savedStatus = store.read()
  }

  var status: LocalNetworkPermissionStatus {
    return savedStatus ?? .unknown
  }

  func setStatusHandler(_ handler: @escaping (LocalNetworkPermissionStatus) -> Void) {
    statusHandler = handler
  }

  func requestPermission() {
    probe.requestPermission()
  }

  private func receive(_ status: LocalNetworkPermissionStatus) {
    guard savedStatus != status else {
      return
    }

    savedStatus = status

    if status != .unknown {
      store.write(status)
    }

    statusHandler?(status)
  }
}
