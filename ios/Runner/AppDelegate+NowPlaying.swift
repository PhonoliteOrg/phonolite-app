import Flutter
import MediaPlayer
import UIKit

extension AppDelegate {
  func updateNowPlayingInfo(args: [String: Any]) {
    if let trackId = args["trackId"] as? String {
      if currentTrackId != trackId {
        currentTrackId = trackId
        lastReportedPosition = -1
      }
    }
    if let epoch = args["epoch"] as? Int {
      if epoch != currentEpoch {
        currentEpoch = epoch
        lastReportedPosition = -1
      }
    }
    if let title = args["title"] as? String {
      currentTitle = title
    }
    if let artist = args["artist"] as? String {
      currentArtist = artist
    }
    if let album = args["album"] as? String {
      currentAlbum = album
    }

    if let isPlaying = parseBool(args["isPlaying"]) {
      currentIsPlaying = isPlaying
    }
    if let liked = parseBool(args["liked"]) {
      currentLiked = liked
    }

    if let duration = parseDouble(args["duration"]) {
      currentDuration = duration
    }

    if let position = parseDouble(args["position"]) {
      _ = applyPosition(position)
    }
    var artworkImage: UIImage?
    if let artworkTypedData = args["artworkBytes"] as? FlutterStandardTypedData {
      let data = artworkTypedData.data
      if !data.isEmpty, let image = UIImage(data: data) {
        currentArtworkUrl = nil
        currentArtworkToken = nil
        currentArtwork = image
        artworkImage = image
      }
    }

    applyNowPlayingInfo()
    let listArtwork = artworkImage ?? currentArtwork
    carPlaySceneDelegate?.updateNowPlayingListItem(
      title: currentTitle,
      artist: currentArtist,
      album: currentAlbum,
      artwork: listArtwork
    )
    carPlaySceneDelegate?.updateNowPlayingButtons(
      liked: currentLiked,
      available: currentTrackId != nil
    )
    carPlaySceneDelegate?.updateNowPlayingVisibility(hasTrack: currentTrackId != nil)

    let artworkUrl = args["artworkUrl"] as? String
    let token = args["token"] as? String
    if let artworkUrl, !artworkUrl.isEmpty {
      if artworkUrl != currentArtworkUrl || token != currentArtworkToken {
        currentArtworkUrl = artworkUrl
        currentArtworkToken = token
        fetchArtwork(urlString: artworkUrl, token: token)
      }
    }
  }

  func clearNowPlaying() {
    currentArtworkUrl = nil
    currentArtworkToken = nil
    currentTrackId = nil
    currentTitle = nil
    currentArtist = nil
    currentAlbum = nil
    currentArtwork = nil
    currentDuration = nil
    currentIsPlaying = false
    currentLiked = false
    currentEpoch = 0
    lastReportedPosition = -1
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    MPNowPlayingInfoCenter.default().playbackState = .stopped
    carPlaySceneDelegate?.clearNowPlayingListItem()
    carPlaySceneDelegate?.updateNowPlayingButtons(liked: false, available: false)
    carPlaySceneDelegate?.updateNowPlayingVisibility(hasTrack: false)
  }

  func configureRemoteCommands(channel: FlutterMethodChannel) {
    UIApplication.shared.beginReceivingRemoteControlEvents()
    let commandCenter = MPRemoteCommandCenter.shared()
    commandCenter.playCommand.isEnabled = true
    commandCenter.pauseCommand.isEnabled = true
    commandCenter.togglePlayPauseCommand.isEnabled = true
    commandCenter.nextTrackCommand.isEnabled = true
    commandCenter.previousTrackCommand.isEnabled = true
    commandCenter.changePlaybackPositionCommand.isEnabled = false
    commandCenter.changePlaybackPositionCommand.removeTarget(nil)

    commandCenter.playCommand.addTarget { _ in
      channel.invokeMethod("remoteCommand", arguments: ["type": "play"])
      return .success
    }
    commandCenter.pauseCommand.addTarget { _ in
      channel.invokeMethod("remoteCommand", arguments: ["type": "pause"])
      return .success
    }
    commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
      let isPlaying = self?.currentIsPlaying ?? false
      channel.invokeMethod("remoteCommand", arguments: ["type": isPlaying ? "pause" : "play"])
      return .success
    }
    commandCenter.nextTrackCommand.addTarget { _ in
      channel.invokeMethod("remoteCommand", arguments: ["type": "next"])
      return .success
    }
    commandCenter.previousTrackCommand.addTarget { _ in
      channel.invokeMethod("remoteCommand", arguments: ["type": "prev"])
      return .success
    }
    commandCenter.changePlaybackPositionCommand.addTarget { _ in
      return .commandFailed
    }
  }

  func refreshNowPlayingForCarPlay(force: Bool) {
    applyNowPlayingInfo(forceRefresh: force)
    carPlaySceneDelegate?.updateNowPlayingListItem(
      title: currentTitle,
      artist: currentArtist,
      album: currentAlbum,
      artwork: currentArtwork
    )
    carPlaySceneDelegate?.updateNowPlayingButtons(
      liked: currentLiked,
      available: currentTrackId != nil
    )
    carPlaySceneDelegate?.updateNowPlayingVisibility(hasTrack: currentTrackId != nil)
  }

  private func buildNowPlayingInfo() -> [String: Any] {
    var info: [String: Any] = [:]
    let title = (currentTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let artist = (currentArtist ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let album = (currentAlbum ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let hasMetadata =
      !title.isEmpty ||
      !artist.isEmpty ||
      !album.isEmpty ||
      currentDuration != nil ||
      lastReportedPosition >= 0
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
    let duration = currentDuration ?? 0.0
    info[MPMediaItemPropertyPlaybackDuration] = duration
    let position = lastReportedPosition >= 0 ? lastReportedPosition : 0.0
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
    info[MPNowPlayingInfoPropertyPlaybackRate] = currentIsPlaying ? 1.0 : 0.0
    info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
    if let artworkImage = currentArtwork {
      let artwork = MPMediaItemArtwork(boundsSize: artworkImage.size) { _ in artworkImage }
      info[MPMediaItemPropertyArtwork] = artwork
    }
    return info
  }

  private func applyNowPlayingInfo(forceRefresh: Bool = false) {
    let info = buildNowPlayingInfo()
    if forceRefresh && info.isEmpty {
      return
    }
    let playbackState: MPNowPlayingPlaybackState = currentIsPlaying ? .playing : .paused
    let apply = {
      if forceRefresh {
        MPNowPlayingInfoCenter.default().playbackState = .stopped
      }
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

  private func parseBool(_ value: Any?) -> Bool? {
    if let boolValue = value as? Bool {
      return boolValue
    }
    if let number = value as? NSNumber {
      return number.boolValue
    }
    return nil
  }

  private func parseDouble(_ value: Any?) -> Double? {
    if let doubleValue = value as? Double {
      return doubleValue
    }
    if let number = value as? NSNumber {
      return number.doubleValue
    }
    return nil
  }

  private func fetchArtwork(urlString: String, token: String?) {
    guard let url = URL(string: urlString) else {
      return
    }
    var request = URLRequest(url: url)
    if let token, !token.isEmpty {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
      guard let self, let data, let image = UIImage(data: data) else {
        return
      }
      self.currentArtwork = image
      self.applyNowPlayingInfo()
      self.carPlaySceneDelegate?.updateNowPlayingListItem(
        title: self.currentTitle,
        artist: self.currentArtist,
        album: self.currentAlbum,
        artwork: image
      )
    }.resume()
  }

  private func applyPosition(_ incoming: Double) -> Double {
    let clamped = incoming.isNaN || incoming.isInfinite ? 0.0 : max(0.0, incoming)
    if lastReportedPosition < 0 {
      lastReportedPosition = clamped
      return clamped
    }
    if clamped + seekBackwardTolerance < lastReportedPosition {
      return lastReportedPosition
    }
    lastReportedPosition = clamped
    return clamped
  }
}
