import Foundation
import UIKit

/// Owns current and upcoming artwork, bounded reuse and stale-completion rejection.
/// Mutate on the platform main thread; background decoding installs there too.
final class NowPlayingArtworkController {
  private let loader: NativeArtworkLoader
  private let decodeQueue: DispatchQueue
  private let cache = NativeArtworkCache()

  var onArtworkChanged: (() -> Void)?

  private var source = ArtworkSource()
  private var cacheKey: ArtworkCacheKey?
  private var generation = 0
  private var loadingSource: ArtworkSource?
  private var preloadSources: [ArtworkSource] = []
  private var failedPreloads: Set<ArtworkCacheKey> = []
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
    preloadSources = []
    failedPreloads = []
  }

  func update(_ source: ArtworkSource, inlineData: Data?) {
    if source != self.source {
      self.source = source

      let key = ArtworkCacheKey(source: source)

      cacheKey = key
      current = cache.artwork(for: key)

      if let loadingSource, loadingSource != source, !preloadSources.contains(loadingSource) {
        cancelRequest()
      }
    }

    if let inlineData, inlineData != current?.data, let image = UIImage(data: inlineData) {
      if loadingSource == source {
        cancelRequest()
      }

      install(image, data: inlineData)
    }
  }

  /// Publication precedes loading, preserving synchronous metadata acceptance.
  func loadIfNeeded() {
    guard current == nil, source.path != nil || source.url != nil else {
      loadNextPreload()

      return
    }

    if loadingSource != source {
      // Promote an in-flight preload when it becomes current; otherwise the
      // current cover takes priority over speculative work.
      cancelRequest()
      load(source)
    }
  }

  func preload(_ sources: [ArtworkSource]) {
    var seen: Set<ArtworkCacheKey> = []

    preloadSources = sources.filter { source in
      guard source.path != nil || source.url != nil, seen.count < 3 else {
        return false
      }

      return seen.insert(ArtworkCacheKey(source: source)).inserted
    }
    failedPreloads.formIntersection(seen)

    if let loadingSource, loadingSource != source, !preloadSources.contains(loadingSource) {
      cancelRequest()
    }

    loadNextPreload()
  }

  private func loadNextPreload() {
    guard loadingSource == nil else {
      return
    }

    for candidate in preloadSources {
      let key = ArtworkCacheKey(source: candidate)

      if cache.artwork(for: key) == nil, !failedPreloads.contains(key) {
        load(candidate)

        return
      }
    }
  }

  private func load(_ requestSource: ArtworkSource) {
    loadingSource = requestSource

    let requestGeneration = generation
    let queue = decodeQueue

    let started = loader.load(requestSource) { [weak self] data in
      queue.async {
        let image = data.flatMap { NativeArtworkDecoder.decode($0) }

        DispatchQueue.main.async {
          self?.finishLoading(image, requestGeneration: requestGeneration, requestSource: requestSource)
        }
      }
    }

    if !started {
      finishLoading(nil, requestGeneration: requestGeneration, requestSource: requestSource)
    }
  }

  private func cancelRequest() {
    generation += 1
    loader.cancel()
    loadingSource = nil
  }

  private func finishLoading(_ image: UIImage?, requestGeneration: Int, requestSource: ArtworkSource) {
    guard generation == requestGeneration, loadingSource == requestSource else {
      return
    }

    loadingSource = nil
    loader.finishRequest()
    let key = ArtworkCacheKey(source: requestSource)

    if let image {
      let artwork = CachedNowPlayingArtwork(image: image, data: nil)

      cache.insert(artwork, for: key)
      failedPreloads.remove(key)

      if source == requestSource {
        current = artwork
        onArtworkChanged?()
      }
    } else if preloadSources.contains(requestSource) {
      // Speculative failures wait until they leave the window. A current
      // cover can still retry on the next ordinary metadata update.
      failedPreloads.insert(key)
    }

    loadNextPreload()
  }

  private func install(_ image: UIImage, data: Data? = nil) {
    let artwork = CachedNowPlayingArtwork(image: image, data: data)

    current = artwork

    if let cacheKey {
      cache.insert(artwork, for: cacheKey)
    }
  }
}
