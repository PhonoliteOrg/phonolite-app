import Flutter
import ImageIO
import MediaPlayer
import Security
import UIKit

final class NowPlayingCoordinator {
  private let injectedArtworkSession: URLSession?
  private var artworkSession: URLSession?
  private var artworkSessionKey: NSArray?
  private var artworkTask: URLSessionDataTask?
  private let artworkDecodeQueue = DispatchQueue(label: "phonolite.now-playing-artwork", qos: .userInitiated)
  private let artworkCache = NSCache<NSArray, CachedNowPlayingArtwork>()
  private var currentArtworkCacheKey: NSArray?
  private var artworkGeneration = 0
  private var artworkLoading = false
  private var currentArtworkData: Data?
  private var currentMediaArtwork: MPMediaItemArtwork?
  private var currentArtworkPath: String?
  private var currentArtworkUrl: String?
  private var currentArtworkToken: String?
  private var currentArtworkPin: String?
  private var currentArtworkKey: String?
  private var currentDuration: Double?
  private var currentIsPlaying: Bool = false
  private var currentLiked: Bool = false
  private var currentTitle: String?
  private var currentArtist: String?
  private var currentAlbum: String?
  private var currentArtwork: UIImage?
  private var currentTrackId: String?
  private var currentEpoch: Int = 0
  private var lastReportedPosition: Double = -1
  private let seekBackwardTolerance: Double = 0.75

  init(artworkSession: URLSession? = nil) {
    self.injectedArtworkSession = artworkSession
    artworkCache.countLimit = 8
    artworkCache.totalCostLimit = 20 * 1024 * 1024
  }

  deinit {
    artworkTask?.cancel()
    if injectedArtworkSession == nil { artworkSession?.invalidateAndCancel() }
  }

  var isPlaying: Bool {
    currentIsPlaying
  }

  func update(args: [String: Any], carPlaySceneDelegate: CarPlaySceneDelegate?) {
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

    let normalizedArtworkKey = nonEmptyString(args["artworkKey"])
    let artworkUrl = nonEmptyString(args["artworkUrl"])
    let artworkPath = nonEmptyString(args["artworkPath"])
    let token = nonEmptyString(args["token"])
    let serverPin = nonEmptyString(args["serverPin"])
    if normalizedArtworkKey != currentArtworkKey ||
        artworkUrl != currentArtworkUrl || artworkPath != currentArtworkPath ||
        token != currentArtworkToken || serverPin != currentArtworkPin {
      cancelArtworkRequest()
      currentArtworkKey = normalizedArtworkKey
      currentArtworkUrl = artworkUrl
      currentArtworkPath = artworkPath
      currentArtworkToken = token
      currentArtworkPin = serverPin
      currentArtwork = nil
      currentArtworkData = nil
      currentMediaArtwork = nil
      let cacheKey = [normalizedArtworkKey ?? "", artworkUrl ?? "", artworkPath ?? "",
                      token ?? "", serverPin ?? ""] as NSArray
      currentArtworkCacheKey = cacheKey
      if let cached = artworkCache.object(forKey: cacheKey) {
        useArtwork(cached)
      }
    }

    if let typedData = args["artworkBytes"] as? FlutterStandardTypedData,
       typedData.data != currentArtworkData,
       let image = UIImage(data: typedData.data) {
      cancelArtworkRequest()
      installArtwork(image, data: typedData.data)
    }

    applyNowPlayingInfo()
    updateCarPlayPresentation(
      carPlaySceneDelegate: carPlaySceneDelegate,
      artwork: currentArtwork
    )
    if currentArtwork == nil && !artworkLoading {
      fetchArtwork(
        urlString: artworkUrl,
        localPath: artworkPath,
        token: token,
        serverPin: serverPin,
        artworkKey: normalizedArtworkKey,
        carPlaySceneDelegate: carPlaySceneDelegate
      )
    }
  }

  func clear(carPlaySceneDelegate: CarPlaySceneDelegate?) {
    cancelArtworkRequest()
    if injectedArtworkSession == nil { artworkSession?.invalidateAndCancel() }
    artworkSession = nil
    artworkSessionKey = nil
    artworkCache.removeAllObjects()
    currentArtworkCacheKey = nil
    currentArtworkPath = nil
    currentArtworkData = nil
    currentMediaArtwork = nil
    currentArtworkUrl = nil
    currentArtworkToken = nil
    currentArtworkPin = nil
    currentArtworkKey = nil
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

  func refreshForCarPlay(force _: Bool, carPlaySceneDelegate: CarPlaySceneDelegate?) {
    // Republish without briefly telling the system that playback has stopped.
    applyNowPlayingInfo()
    updateCarPlayPresentation(
      carPlaySceneDelegate: carPlaySceneDelegate,
      artwork: currentArtwork
    )
  }

  private func updateCarPlayPresentation(
    carPlaySceneDelegate: CarPlaySceneDelegate?,
    artwork: UIImage?
  ) {
    carPlaySceneDelegate?.updateNowPlayingListItem(
      title: currentTitle,
      artist: currentArtist,
      album: currentAlbum,
      artwork: artwork
    )
    carPlaySceneDelegate?.updateNowPlayingButtons(
      liked: currentLiked,
      available: currentTrackId != nil
    )
    carPlaySceneDelegate?.updateNowPlayingVisibility(hasTrack: currentTrackId != nil)
  }

  func buildNowPlayingInfo() -> [String: Any] {
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
    if let artwork = currentMediaArtwork {
      info[MPMediaItemPropertyArtwork] = artwork
    }
    return info
  }

  private func applyNowPlayingInfo() {
    guard currentTrackId != nil else { return }
    let info = buildNowPlayingInfo()
    let playbackState: MPNowPlayingPlaybackState = currentIsPlaying ? .playing : .paused
    let apply = {
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

  private func nonEmptyString(_ value: Any?) -> String? {
    guard let value = value as? String else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private func cancelArtworkRequest() {
    artworkGeneration += 1
    artworkTask?.cancel()
    artworkTask = nil
    artworkLoading = false
  }

  private func useArtwork(_ artwork: CachedNowPlayingArtwork) {
    currentArtwork = artwork.image
    currentArtworkData = artwork.data
    currentMediaArtwork = artwork.mediaArtwork
  }

  private func installArtwork(_ image: UIImage, data: Data? = nil) {
    let artwork = CachedNowPlayingArtwork(image: image, data: data)
    useArtwork(artwork)
    if let key = currentArtworkCacheKey {
      artworkCache.setObject(artwork, forKey: key, cost: artwork.cost)
    }
  }

  private static func decodeArtwork(_ data: Data) -> UIImage? {
    guard let source = CGImageSourceCreateWithData(
      data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary
    ), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: 1024,
      kCGImageSourceShouldCacheImmediately: true,
    ] as CFDictionary) else { return nil }
    return UIImage(cgImage: image)
  }

  private func fetchArtwork(
    urlString: String?,
    localPath: String?,
    token: String?,
    serverPin: String?,
    artworkKey: String?,
    carPlaySceneDelegate: CarPlaySceneDelegate?
  ) {
    guard localPath != nil || urlString != nil else { return }
    artworkLoading = true
    let generation = artworkGeneration
    let decodeQueue = artworkDecodeQueue
    let complete: (Data?) -> Void = { [weak self, weak carPlaySceneDelegate] data in
      decodeQueue.async {
        let image = data.flatMap { Self.decodeArtwork($0) }
        DispatchQueue.main.async {
          guard let self, self.artworkGeneration == generation,
                self.currentArtworkKey == artworkKey else { return }
          self.artworkLoading = false
          self.artworkTask = nil
          // A failed request may retry on the next metadata update.
          guard let image else { return }
          self.installArtwork(image)
          self.applyNowPlayingInfo()
          self.updateCarPlayPresentation(
            carPlaySceneDelegate: carPlaySceneDelegate,
            artwork: image
          )
        }
      }
    }
    if let localPath {
      decodeQueue.async {
        complete(try? Data(contentsOf: URL(fileURLWithPath: localPath)))
      }
      return
    }
    guard let urlString, let url = URL(string: urlString), url.scheme == "https",
          let serverPin else {
      artworkLoading = false
      return
    }
    let session: URLSession
    if let injectedArtworkSession {
      session = injectedArtworkSession
    } else {
      let sessionKey = [url.host?.lowercased() ?? "", String(url.port ?? 443),
                        serverPin, token ?? ""] as NSArray
      if artworkSessionKey != sessionKey {
        artworkSession?.invalidateAndCancel()
        artworkSession = PinnedArtworkSession.make(url: url, pin: serverPin)
        artworkSessionKey = sessionKey
      }
      guard let artworkSession else {
        artworkLoading = false
        return
      }
      session = artworkSession
    }
    var request = URLRequest(url: url)
    request.timeoutInterval = 15
    if let token {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    let task = session.dataTask(with: request) { data, response, error in
      guard error == nil, let response = response as? HTTPURLResponse,
            (200..<300).contains(response.statusCode) else {
        complete(nil)
        return
      }
      complete(data)
    }
    artworkTask = task
    task.resume()
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

/// Keep decoded covers and MediaPlayer's artwork objects reusable across albums.
private final class CachedNowPlayingArtwork {
  let image: UIImage
  let data: Data?
  let mediaArtwork: MPMediaItemArtwork
  let cost: Int

  init(image: UIImage, data: Data?) {
    self.image = image
    self.data = data
    self.cost = (image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0) + (data?.count ?? 0)
    let resizedImages = NSCache<NSString, UIImage>()
    resizedImages.countLimit = 4
    resizedImages.totalCostLimit = 2 * 1024 * 1024
    mediaArtwork = MPMediaItemArtwork(boundsSize: image.size) { size in
      guard size.width > 0, size.height > 0 else { return image }
      let key = "\(size.width)x\(size.height)" as NSString
      if let cached = resizedImages.object(forKey: key) { return cached }
      let format = UIGraphicsImageRendererFormat()
      format.scale = 1
      let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
        image.draw(in: CGRect(origin: .zero, size: size))
      }
      let cost = resized.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
      resizedImages.setObject(resized, forKey: key, cost: cost)
      return resized
    }
  }
}

// Native artwork can load while Dart is suspended. Use the same authenticated
// SPKI as Dart and QUIC, with no CA fallback or automatic redirects.
final class PinnedArtworkSession: NSObject, URLSessionTaskDelegate {
  private let host: String
  private let port: Int
  private let pin: String

  private init(host: String, port: Int, pin: String) {
    self.host = host.lowercased()
    self.port = port
    self.pin = pin
  }

  static func make(url: URL, pin: String) -> URLSession? {
    guard url.scheme == "https", let host = url.host, url.user == nil, url.password == nil,
          pin.count == 64, pin.allSatisfy({ "0123456789abcdef".contains($0) }) else { return nil }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.tlsMinimumSupportedProtocolVersion = .TLSv13
    configuration.timeoutIntervalForRequest = 15
    configuration.timeoutIntervalForResource = 15
    return URLSession(
      configuration: configuration,
      delegate: PinnedArtworkSession(host: host, port: url.port ?? 443, pin: pin),
      delegateQueue: nil
    )
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    let space = challenge.protectionSpace
    guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
          space.host.lowercased() == host, space.port == port,
          let trust = space.serverTrust,
          let certificate = SecTrustGetCertificateAtIndex(trust, 0) else {
      completionHandler(.cancelAuthenticationChallenge, nil)
      return
    }
    let der = SecCertificateCopyData(certificate) as Data
    // The Rust helper checks certificate validity and hashes the complete SPKI.
    let actual: String? = der.withUnsafeBytes { bytes in
      guard let value = phonolite_security_spki(
        bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count
      ) else { return nil }
      defer { phonolite_quic_free_string(value) }
      return String(cString: value)
    }
    guard actual == pin else {
      completionHandler(.cancelAuthenticationChallenge, nil)
      return
    }
    completionHandler(.useCredential, URLCredential(trust: trust))
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}
