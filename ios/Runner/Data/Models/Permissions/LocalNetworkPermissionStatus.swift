/// Preserves saved status values while naming the statuses produced by the probe.
struct LocalNetworkPermissionStatus: Equatable {
  static let unknown = LocalNetworkPermissionStatus(rawValue: "unknown")
  static let granted = LocalNetworkPermissionStatus(rawValue: "granted")
  static let denied = LocalNetworkPermissionStatus(rawValue: "denied")

  let rawValue: String
}
