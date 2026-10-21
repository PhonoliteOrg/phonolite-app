import Foundation

/// Metadata fields are patches; artwork identity is replaced by every update.
struct NowPlayingUpdate {
  let trackID: String?
  let epoch: Int?
  let title: String?
  let artist: String?
  let album: String?
  let isPlaying: Bool?
  let liked: Bool?
  let duration: Double?
  let position: Double?
  let artworkSource: ArtworkSource
  let artworkData: Data?

  init(
    trackID: String? = nil,
    epoch: Int? = nil,
    title: String? = nil,
    artist: String? = nil,
    album: String? = nil,
    isPlaying: Bool? = nil,
    liked: Bool? = nil,
    duration: Double? = nil,
    position: Double? = nil,
    artworkSource: ArtworkSource = ArtworkSource(),
    artworkData: Data? = nil
  ) {
    self.trackID = trackID
    self.epoch = epoch
    self.title = title
    self.artist = artist
    self.album = album
    self.isPlaying = isPlaying
    self.liked = liked
    self.duration = duration
    self.position = position
    self.artworkSource = artworkSource
    self.artworkData = artworkData
  }
}
