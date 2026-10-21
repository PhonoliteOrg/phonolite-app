import Foundation

/// A bounded decoded-cover cache; each consumer owns its own instance.
final class NativeArtworkCache {
  private let entries = NSCache<CacheKey, CachedNowPlayingArtwork>()

  init() {
    entries.countLimit = 8
    entries.totalCostLimit = 20 * 1024 * 1024
  }

  func artwork(for key: ArtworkCacheKey) -> CachedNowPlayingArtwork? {
    return entries.object(forKey: CacheKey(key))
  }

  func insert(_ artwork: CachedNowPlayingArtwork, for key: ArtworkCacheKey) {
    entries.setObject(artwork, forKey: CacheKey(key), cost: artwork.cost)
  }

  func clear() {
    entries.removeAllObjects()
  }
}

private final class CacheKey: NSObject {
  private let value: ArtworkCacheKey

  init(_ value: ArtworkCacheKey) {
    self.value = value
  }

  override var hash: Int {
    value.hashValue
  }

  override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? CacheKey else {
      return false
    }

    return value == other.value
  }
}
