import Foundation

/// Reuse a pinned session only for the same server, credentials and pin.
struct ArtworkSessionIdentity: Equatable {
  let host: String
  let port: Int
  let serverPin: String
  let token: String

  init(url: URL, serverPin: String, token: String?) {
    host = url.host?.lowercased() ?? ""
    port = url.port ?? 443
    self.serverPin = serverPin
    self.token = token ?? ""
  }
}
