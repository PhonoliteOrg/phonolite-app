/// Playback metadata and the position-acceptance rule, independent of native UI.
struct NowPlayingState {
  private static let seekBackwardTolerance = 0.75

  private(set) var trackID: String?
  private(set) var epoch = 0
  private(set) var title: String?
  private(set) var artist: String?
  private(set) var album: String?
  private(set) var isPlaying = false
  private(set) var liked = false
  private(set) var duration: Double?
  private(set) var position = -1.0

  mutating func apply(_ update: NowPlayingUpdate) {
    if let trackID = update.trackID, self.trackID != trackID {
      self.trackID = trackID
      position = -1
    }

    if let epoch = update.epoch, self.epoch != epoch {
      self.epoch = epoch
      position = -1
    }

    if let title = update.title {
      self.title = title
    }

    if let artist = update.artist {
      self.artist = artist
    }

    if let album = update.album {
      self.album = album
    }

    if let isPlaying = update.isPlaying {
      self.isPlaying = isPlaying
    }

    if let liked = update.liked {
      self.liked = liked
    }

    if let duration = update.duration {
      self.duration = duration
    }

    if let position = update.position {
      applyPosition(position)
    }
  }

  private mutating func applyPosition(_ incoming: Double) {
    let clamped = incoming.isNaN || incoming.isInfinite ? 0.0 : max(0.0, incoming)

    if position >= 0 && clamped + Self.seekBackwardTolerance < position {
      return
    }

    position = clamped
  }
}
