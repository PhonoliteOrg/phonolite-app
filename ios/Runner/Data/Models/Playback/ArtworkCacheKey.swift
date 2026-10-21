/// Matches the existing five-part cache identity, including empty placeholders.
struct ArtworkCacheKey: Hashable {
  let key: String
  let url: String
  let path: String
  let token: String
  let serverPin: String

  init(source: ArtworkSource) {
    key = source.key ?? ""
    url = source.url ?? ""
    path = source.path ?? ""
    token = source.token ?? ""
    serverPin = source.serverPin ?? ""
  }
}
