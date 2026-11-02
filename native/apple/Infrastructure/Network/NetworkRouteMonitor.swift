import Darwin
import Foundation
import Network

/// One subscriber-owned path monitor; state and publication stay on the main queue.
final class NetworkRouteMonitor {
  private let queue = DispatchQueue(label: "phonolite.network_routes")
  private var monitor: NWPathMonitor?
  private var publish: ((Int64) -> Void)?
  private var signature: [String]?
  private var generation = 0
  private var revision: Int64 = 0

  deinit { monitor?.cancel() }

  func start(onRevision: @escaping (Int64) -> Void) {
    stop()

    let observation = generation
    let monitor = NWPathMonitor()
    self.monitor = monitor
    publish = onRevision
    monitor.pathUpdateHandler = { [weak self] path in
      let signature = Self.signature(for: path)

      DispatchQueue.main.async { [weak self] in
        guard let self, self.generation == observation, self.monitor != nil else { return }
        guard self.signature != signature else { return }

        self.signature = signature
        self.revision += 1
        self.publish?(self.revision)
      }
    }
    monitor.start(queue: queue)
  }

  func stop() {
    generation += 1
    monitor?.cancel()
    monitor = nil
    publish = nil
    signature = nil
  }

  private static func signature(for path: NWPath) -> [String] {
    let interfaces = path.availableInterfaces.filter { path.usesInterfaceType($0.type) }
    let names = Set(interfaces.map(\.name))

    return [
      String(describing: path.status),
      "\(path.supportsIPv4):\(path.supportsIPv6):\(path.supportsDNS)",
      "\(path.isExpensive):\(path.isConstrained)",
    ] + interfaces.map { "\($0.name):\($0.index)" }.sorted()
      + path.gateways.map { String(describing: $0) }.sorted()
      + addresses(on: names)
  }

  private static func addresses(on interfaces: Set<String>) -> [String] {
    var list: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&list) == 0 else { return [] }
    defer { freeifaddrs(list) }

    var result: [String] = []
    var cursor = list

    while let current = cursor {
      defer { cursor = current.pointee.ifa_next }

      let name = String(cString: current.pointee.ifa_name)
      guard interfaces.contains(name), let address = current.pointee.ifa_addr else { continue }
      guard address.pointee.sa_family == UInt8(AF_INET) || address.pointee.sa_family == UInt8(AF_INET6) else {
        continue
      }

      var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      let capacity = socklen_t(host.count)
      let status = getnameinfo(
        address, socklen_t(address.pointee.sa_len), &host, capacity, nil, 0, NI_NUMERICHOST
      )

      if status == 0 { result.append("\(name):\(String(cString: host))") }
    }

    return result.sorted()
  }
}
