import AVFoundation
import Flutter
import MediaPlayer
import Network
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var nowPlayingChannel: FlutterMethodChannel?
  private var nowPlayingInfo: [String: Any] = [:]
  private var currentArtworkUrl: String?
  private var currentArtworkToken: String?
  private var currentDuration: Double?
  private var currentIsPlaying: Bool = false
  private var lastSeekPosition: Double?
  private var lastSeekAt: Date?
  private var currentTrackId: String?
  private var currentEpoch: Int = 0
  private var lastReportedPosition: Double = -1
  private let seekBackwardTolerance: Double = 0.75
  private let seekForwardTolerance: Double = 1.5
  private var localNetworkBrowser: NWBrowser?
  private var localNetworkListener: NWListener?
  private let localNetworkQueue = DispatchQueue(label: "phonolite.localnetwork")
  private var permissionsChannel: FlutterMethodChannel?
  private var localNetworkStatus: String?
  private let localNetworkStatusKey = "localNetworkStatus"
  

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    localNetworkStatus = UserDefaults.standard.string(forKey: localNetworkStatusKey)
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    configureNowPlayingChannel()
    configurePermissionsChannel()
    requestLocalNetworkPermission()
    return result
  }

  private func requestLocalNetworkPermission() {
    if #available(iOS 14.0, *) {
      let parameters = NWParameters.tcp
      parameters.includePeerToPeer = true
      do {
        let listener = try NWListener(using: parameters, on: 0)
        listener.service = NWListener.Service(name: "Phonolite", type: "_phonolite._tcp")
        listener.newConnectionHandler = { connection in
          connection.cancel()
        }
        listener.stateUpdateHandler = { [weak self] state in
          switch state {
          case .ready:
            self?.notifyLocalNetworkPermission(status: "granted")
            self?.stopLocalNetworkBrowser()
          case .failed(let error):
            if self?.isLocalNetworkDenied(error) == true {
              self?.notifyLocalNetworkPermission(status: "denied")
            }
            self?.stopLocalNetworkBrowser()
          default:
            break
          }
        }
        localNetworkListener = listener
        listener.start(queue: localNetworkQueue)
        localNetworkQueue.asyncAfter(deadline: .now() + 2.0) { [weak self] in
          self?.stopLocalNetworkBrowser()
        }
      } catch let error as NWError {
        if isLocalNetworkDenied(error) {
          notifyLocalNetworkPermission(status: "denied")
        }
      } catch {
        // Leave as unknown on unexpected errors.
      }
    }
  }

  private func stopLocalNetworkBrowser() {
    localNetworkBrowser?.cancel()
    localNetworkBrowser = nil
    localNetworkListener?.cancel()
    localNetworkListener = nil
  }

  private func notifyLocalNetworkPermission(status: String) {
    if localNetworkStatus == status {
      return
    }
    localNetworkStatus = status
    if status != "unknown" {
      UserDefaults.standard.set(status, forKey: localNetworkStatusKey)
    }
    DispatchQueue.main.async { [weak self] in
      self?.permissionsChannel?.invokeMethod(
        "localNetworkPermission",
        arguments: ["status": status]
      )
    }
  }

  private func isLocalNetworkDenied(_ error: NWError) -> Bool {
    switch error {
    case .posix(let code):
      return code == .EACCES || code == .EPERM
    case .dns(let code):
      return code == -65570
    default:
      return false
    }
  }

  func configureNowPlayingChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "phonolite/now_playing",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "no_self", message: "AppDelegate released", details: nil))
        return
      }
      switch call.method {
      case "setNowPlaying":
        guard let args = call.arguments as? [String: Any] else {
          result(FlutterError(code: "bad_args", message: "Missing args", details: nil))
          return
        }
        self.updateNowPlayingInfo(args: args)
        result(true)
      case "clearNowPlaying":
        self.clearNowPlaying()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    nowPlayingChannel = channel
    configureRemoteCommands(channel: channel)
  }

  func configurePermissionsChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }
    permissionsChannel = FlutterMethodChannel(
      name: "phonolite/permissions",
      binaryMessenger: controller.binaryMessenger
    )
    permissionsChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "no_self", message: "AppDelegate released", details: nil))
        return
      }
      switch call.method {
      case "getLocalNetworkPermission":
        result(self.localNetworkStatus ?? "unknown")
      case "refreshLocalNetworkPermission":
        self.requestLocalNetworkPermission()
        result(true)
      case "openAppSettings":
        DispatchQueue.main.async {
          if let url = URL(string: UIApplication.openSettingsURLString),
             UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            result(true)
          } else {
            result(false)
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func updateNowPlayingInfo(args: [String: Any]) {
    var info = nowPlayingInfo
    if let trackId = args["trackId"] as? String {
      if currentTrackId != trackId {
        currentTrackId = trackId
        lastSeekAt = nil
        lastSeekPosition = nil
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
      info[MPMediaItemPropertyTitle] = title
    }
    if let artist = args["artist"] as? String {
      info[MPMediaItemPropertyArtist] = artist
    }
    if let album = args["album"] as? String {
      info[MPMediaItemPropertyAlbumTitle] = album
    }
    if let isPlaying = args["isPlaying"] as? Bool {
      currentIsPlaying = isPlaying
      info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
      info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
      MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }
    if let duration = args["duration"] as? Double {
      info[MPMediaItemPropertyPlaybackDuration] = duration
      currentDuration = duration
    } else if let durationNum = args["duration"] as? NSNumber {
      info[MPMediaItemPropertyPlaybackDuration] = durationNum.doubleValue
      currentDuration = durationNum.doubleValue
    }
    if let position = args["position"] as? Double {
      info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = applyPosition(position)
    } else if let positionNum = args["position"] as? NSNumber {
      info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = applyPosition(positionNum.doubleValue)
    }

    nowPlayingInfo = info
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info

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
      let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
      self.nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
      DispatchQueue.main.async {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = self.nowPlayingInfo
      }
    }.resume()
  }

  private func clearNowPlaying() {
    nowPlayingInfo = [:]
    currentArtworkUrl = nil
    currentArtworkToken = nil
    currentTrackId = nil
    lastSeekAt = nil
    lastSeekPosition = nil
    currentEpoch = 0
    lastReportedPosition = -1
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    MPNowPlayingInfoCenter.default().playbackState = .stopped
  }

  private func configureRemoteCommands(channel: FlutterMethodChannel) {
    UIApplication.shared.beginReceivingRemoteControlEvents()
    let commandCenter = MPRemoteCommandCenter.shared()
    commandCenter.playCommand.isEnabled = true
    commandCenter.pauseCommand.isEnabled = true
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
    commandCenter.nextTrackCommand.addTarget { _ in
      channel.invokeMethod("remoteCommand", arguments: ["type": "next"])
      return .success
    }
    commandCenter.previousTrackCommand.addTarget { _ in
      channel.invokeMethod("remoteCommand", arguments: ["type": "prev"])
      return .success
    }
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
