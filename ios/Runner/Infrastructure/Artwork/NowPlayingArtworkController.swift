import Foundation
import UIKit

/// Owns artwork replacement, bounded reuse and stale-completion rejection.
/// Mutate on the platform main thread; background decoding installs there too.
final class NowPlayingArtworkController {
  private let loader: NativeArtworkLoader
  private let decodeQueue: DispatchQueue
  private let cache = NativeArtworkCache()

  var onArtworkChanged: (() -> Void)?

  private var source = ArtworkSource()
  private var cacheKey: ArtworkCacheKey?
  private var generation = 0
  private var isLoading = false
  private(set) var current: CachedNowPlayingArtwork?

  init(artworkSession: URLSession? = nil) {
    let queue = DispatchQueue(label: "phonolite.now-playing-artwork", qos: .userInitiated)

    decodeQueue = queue
    loader = NativeArtworkLoader(artworkSession: artworkSession, localReadQueue: queue)
  }

  func clear() {
    cancelRequest()
    loader.clear()
    cache.clear()

    cacheKey = nil
    source = ArtworkSource()
    current = nil
  }

  func update(_ source: ArtworkSource, inlineData: Data?) {
    if source != self.source {
      cancelRequest()
      self.source = source

      let key = ArtworkCacheKey(source: source)

      cacheKey = key
      current = cache.artwork(for: key)
    }

    if let inlineData, inlineData != current?.data, let image = UIImage(data: inlineData) {
      cancelRequest()
      install(image, data: inlineData)
    }
  }

  /// Publication precedes loading, preserving synchronous metadata acceptance.
  func loadIfNeeded() {
    guard current == nil && !isLoading, source.path != nil || source.url != nil else {
      return
    }

    isLoading = true

    let requestGeneration = generation
    let artworkKey = source.key
    let queue = decodeQueue

    let started = loader.load(source) { [weak self] data in
      queue.async {
        let image = data.flatMap { NativeArtworkDecoder.decode($0) }

        DispatchQueue.main.async {
          self?.finishLoading(image, requestGeneration: requestGeneration, artworkKey: artworkKey)
        }
      }
    }

    if !started {
      isLoading = false
    }
  }

  private func cancelRequest() {
    generation += 1
    loader.cancel()
    isLoading = false
  }

  private func finishLoading(_ image: UIImage?, requestGeneration: Int, artworkKey: String?) {
    guard generation == requestGeneration, source.key == artworkKey else {
      return
    }

    isLoading = false
    loader.finishRequest()

    // A failed request may retry on the next metadata update.
    guard let image else {
      return
    }

    install(image)
    onArtworkChanged?()
  }

  private func install(_ image: UIImage, data: Data? = nil) {
    let artwork = CachedNowPlayingArtwork(image: image, data: data)

    current = artwork

    if let cacheKey {
      cache.insert(artwork, for: cacheKey)
    }
  }
}
