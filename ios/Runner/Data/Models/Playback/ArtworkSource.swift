/// An artwork identity includes its location, credentials and authenticated pin.
struct ArtworkSource: Equatable {
  let key: String?
  let url: String?
  let path: String?
  let token: String?
  let serverPin: String?

  init(key: String? = nil, url: String? = nil, path: String? = nil, token: String? = nil, serverPin: String? = nil) {
    self.key = key
    self.url = url
    self.path = path
    self.token = token
    self.serverPin = serverPin
  }
}
