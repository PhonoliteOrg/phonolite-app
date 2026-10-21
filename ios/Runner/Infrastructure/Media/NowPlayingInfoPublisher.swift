import Foundation
import MediaPlayer

/// Converts typed media state to the system contract and owns publication.
final class NowPlayingInfoPublisher {
  func buildInfo(state: NowPlayingState, artwork: MPMediaItemArtwork?) -> [String: Any] {
    var info: [String: Any] = [:]
    let title = (state.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let artist = (state.artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let album = (state.album ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let hasMetadata =
      !title.isEmpty || !artist.isEmpty || !album.isEmpty || state.duration != nil || state.position >= 0

    if hasMetadata {
      info[MPMediaItemPropertyTitle] = title.isEmpty ? "Now Playing" : title
    }

    if !artist.isEmpty {
      info[MPMediaItemPropertyArtist] = artist
    }

    if !album.isEmpty {
      info[MPMediaItemPropertyAlbumTitle] = album
    }

    info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
    info[MPNowPlayingInfoPropertyIsLiveStream] = false
    info[MPMediaItemPropertyPlaybackDuration] = state.duration ?? 0.0
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = state.position >= 0 ? state.position : 0.0
    info[MPNowPlayingInfoPropertyPlaybackRate] = state.isPlaying ? 1.0 : 0.0
    info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0

    if let artwork {
      info[MPMediaItemPropertyArtwork] = artwork
    }

    return info
  }

  func publish(state: NowPlayingState, artwork: MPMediaItemArtwork?) {
    guard state.trackID != nil else {
      return
    }

    let info = buildInfo(state: state, artwork: artwork)
    let playbackState: MPNowPlayingPlaybackState = state.isPlaying ? .playing : .paused

    func apply() {
      MPNowPlayingInfoCenter.default().nowPlayingInfo = info
      MPNowPlayingInfoCenter.default().playbackState = playbackState
    }

    if Thread.isMainThread {
      apply()
    } else {
      DispatchQueue.main.async {
        apply()
      }
    }
  }

  func clear() {
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    MPNowPlayingInfoCenter.default().playbackState = .stopped
  }
}
