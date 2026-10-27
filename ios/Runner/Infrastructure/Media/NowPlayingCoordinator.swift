import Foundation

/// Coordinates typed media state, native artwork and system publication.
/// State operations run on the platform main thread.
final class NowPlayingCoordinator {
  private let artwork: NowPlayingArtworkController
  private let publisher = NowPlayingInfoPublisher()
  var onPresentationChanged: ((NowPlayingState) -> Void)?

  private var state = NowPlayingState()

  init(artworkSession: URLSession? = nil) {
    artwork = NowPlayingArtworkController(artworkSession: artworkSession)
    artwork.onArtworkChanged = { [weak self] in
      self?.refreshPresentation()
    }
  }

  var isPlaying: Bool {
    state.isPlaying
  }

  func clear() {
    artwork.clear()
    state = NowPlayingState()

    publisher.clear()
    onPresentationChanged?(state)
  }

  func update(_ update: NowPlayingUpdate) {
    state.apply(update)
    artwork.update(update.artworkSource, inlineData: update.artworkData)

    refreshPresentation()
    artwork.loadIfNeeded()
  }

  /// CarPlay's Now Playing template shares this publisher and decoded cache.
  func preloadArtwork(_ sources: [ArtworkSource]) {
    artwork.preload(sources)
  }

  /// Republish without briefly telling the system that playback has stopped.
  func refreshPresentation() {
    publisher.publish(state: state, artwork: artwork.current?.mediaArtwork)
    onPresentationChanged?(state)
  }

  func buildNowPlayingInfo() -> [String: Any] {
    return publisher.buildInfo(state: state, artwork: artwork.current?.mediaArtwork)
  }
}
