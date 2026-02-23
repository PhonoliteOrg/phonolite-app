import AVFoundation
import CarPlay
import Flutter
import MediaPlayer
import Network
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var nowPlayingChannel: FlutterMethodChannel?
  private var carPlayChannel: FlutterMethodChannel?
  private var currentArtworkUrl: String?
  private var currentArtworkToken: String?
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
  private var remoteCommandsConfigured = false
  weak var carPlaySceneDelegate: CarPlaySceneDelegate?
  private let localNetworkPermissions = LocalNetworkPermissionManager()

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


  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetoothA2DP])
      try session.setActive(true)
    } catch {
      NSLog("Failed to activate audio session: %@", "\(error)")
    }

    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    configureNowPlayingChannel()
    configureCarPlayChannel()
    configurePermissionsChannel()
    localNetworkPermissions.requestPermission()
    return result
  }

  override func application(
    _ application: UIApplication,
    configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    if #available(iOS 13.0, *) {
      if connectingSceneSession.role == UISceneSession.Role.carTemplateApplication {
        let config = UISceneConfiguration(
          name: "CarPlay Configuration",
          sessionRole: connectingSceneSession.role
        )
        config.sceneClass = CPTemplateApplicationScene.self
        config.delegateClass = CarPlaySceneDelegate.self
        return config
      }
      let config = UISceneConfiguration(
        name: "Default Configuration",
        sessionRole: connectingSceneSession.role
      )
      config.delegateClass = SceneDelegate.self
      config.storyboard = UIStoryboard(name: "Main", bundle: nil)
      return config
    }
    return super.application(
      application,
      configurationForConnecting: connectingSceneSession,
      options: options
    )
  }

  func configureNowPlayingChannel() {
    if nowPlayingChannel != nil {
      return
    }
    guard let messenger = resolveMessenger(plugin: "phonolite_now_playing") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "phonolite/now_playing",
      binaryMessenger: messenger
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
    if !remoteCommandsConfigured {
      configureRemoteCommands(channel: channel)
      remoteCommandsConfigured = true
    }
  }

  func sendRemoteCommandToFlutter(_ type: String, arguments: [String: Any] = [:]) {
    configureNowPlayingChannel()
    guard let channel = nowPlayingChannel else {
      return
    }
    var payload = arguments
    payload["type"] = type
    channel.invokeMethod("remoteCommand", arguments: payload)
  }

  func configureCarPlayChannel() {
    if carPlayChannel != nil {
      return
    }
    guard let messenger = resolveMessenger(plugin: "phonolite_carplay") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "phonolite/carplay",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "no_self", message: "AppDelegate released", details: nil))
        return
      }
      switch call.method {
      case "authState":
        let args = call.arguments as? [String: Any]
        let authorized = args?["authorized"] as? Bool ?? false
        self.carPlaySceneDelegate?.updateAuthState(authorized: authorized)
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    carPlayChannel = channel
  }

  func invokeCarPlayMethod(
    _ method: String,
    arguments: Any? = nil,
    completion: ((Any?) -> Void)? = nil
  ) {
    configureCarPlayChannel()
    guard let channel = carPlayChannel else {
      completion?(nil)
      return
    }
    channel.invokeMethod(method, arguments: arguments) { result in
      completion?(result)
    }
  }

  func configurePermissionsChannel() {
    guard let messenger = resolveMessenger(plugin: "phonolite_permissions") else {
      return
    }
    localNetworkPermissions.configureChannel(messenger: messenger)
  }

  private func updateNowPlayingInfo(args: [String: Any]) {
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

  private func clearNowPlaying() {
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

  private func configureRemoteCommands(channel: FlutterMethodChannel) {
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

  private func rootFlutterViewController() -> FlutterViewController? {
    if let controller = window?.rootViewController as? FlutterViewController {
      return controller
    }
    if #available(iOS 13.0, *) {
      for scene in UIApplication.shared.connectedScenes {
        guard let windowScene = scene as? UIWindowScene else {
          continue
        }
        for candidate in windowScene.windows {
          if let controller = candidate.rootViewController as? FlutterViewController {
            return controller
          }
        }
      }
    }
    return nil
  }

  private func resolveMessenger(plugin: String) -> FlutterBinaryMessenger? {
    if let controller = rootFlutterViewController() {
      return controller.binaryMessenger
    }
    if let registrar = registrar(forPlugin: plugin) {
      return registrar.messenger()
    }
    return nil
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
}

final class LocalNetworkPermissionManager {
  private var listener: NWListener?
  private let queue = DispatchQueue(label: "phonolite.localnetwork")
  private var channel: FlutterMethodChannel?
  private var status: String?
  private let statusKey = "localNetworkStatus"

  init() {
    status = UserDefaults.standard.string(forKey: statusKey)
  }

  func configureChannel(messenger: FlutterBinaryMessenger) {
    if channel != nil {
      return
    }
    let channel = FlutterMethodChannel(
      name: "phonolite/permissions",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "no_self", message: "Permission manager released", details: nil))
        return
      }
      switch call.method {
      case "getLocalNetworkPermission":
        result(self.status ?? "unknown")
      case "refreshLocalNetworkPermission":
        self.requestPermission()
        result(true)
      case "openAppSettings":
        self.openAppSettings(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  func requestPermission() {
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
            self?.notify(status: "granted")
            self?.stopListener()
          case .failed(let error):
            if self?.isDenied(error) == true {
              self?.notify(status: "denied")
            }
            self?.stopListener()
          default:
            break
          }
        }
        self.listener = listener
        listener.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 2.0) { [weak self] in
          self?.stopListener()
        }
      } catch let error as NWError {
        if isDenied(error) {
          notify(status: "denied")
        }
      } catch {
        // Leave as unknown on unexpected errors.
      }
    }
  }

  private func openAppSettings(result: FlutterResult) {
    let open = {
      if let url = URL(string: UIApplication.openSettingsURLString),
         UIApplication.shared.canOpenURL(url) {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        return true
      }
      return false
    }
    if Thread.isMainThread {
      result(open())
      return
    }
    var success = false
    DispatchQueue.main.sync {
      success = open()
    }
    result(success)
  }

  private func stopListener() {
    listener?.cancel()
    listener = nil
  }

  private func notify(status: String) {
    if self.status == status {
      return
    }
    self.status = status
    if status != "unknown" {
      UserDefaults.standard.set(status, forKey: statusKey)
    }
    DispatchQueue.main.async { [weak self] in
      self?.channel?.invokeMethod(
        "localNetworkPermission",
        arguments: ["status": status]
      )
    }
  }

  private func isDenied(_ error: NWError) -> Bool {
    switch error {
    case .posix(let code):
      return code == .EACCES || code == .EPERM
    case .dns(let code):
      return code == -65570
    default:
      return false
    }
  }
}

@available(iOS 13.0, *)
class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
      appDelegate.configureNowPlayingChannel()
      appDelegate.configurePermissionsChannel()
    }
  }

  override func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
    // Disable scene restoration to avoid NSUserActivity with an empty activityType.
    return nil
  }
}

@available(iOS 13.0, *)
class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
  private weak var interfaceController: CPInterfaceController?
  private var rootTemplate: CPTemplate?
  private var homeTemplate: CPListTemplate?
  private var libraryTemplate: CPListTemplate?
  private var loggedOutTemplate: CPListTemplate?
  private var nowPlayingItem: CPListItem?
  private let nowPlayingTemplate = CPNowPlayingTemplate.shared
  private var nowPlayingButtonVisible = false
  private var isAuthorized = false

  private func refreshNowPlayingUI(force: Bool) {
    if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
      appDelegate.refreshNowPlayingForCarPlay(force: force)
    }
  }

  private func configureRootTemplate(using interfaceController: CPInterfaceController) {
    self.interfaceController = interfaceController
    DispatchQueue.main.async {
      if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
        appDelegate.carPlaySceneDelegate = self
        appDelegate.refreshNowPlayingForCarPlay(force: true)
        appDelegate.configureCarPlayChannel()
      }

      self.nowPlayingItem = nil
      self.updateAuthState(authorized: false, force: true)
      self.requestAuthState()
    }
  }

  private func buildHomeTemplate() -> CPListTemplate {
    let template = CPListTemplate(
      title: "Home",
      sections: [CPListSection(items: [disabledItem(text: "Loading…")])]
    )
    setNowPlayingButtonVisible(template, visible: nowPlayingButtonVisible)
    if #available(iOS 14.0, *) {
      template.tabTitle = "Home"
      template.tabImage = UIImage(systemName: "house")
    }
    requestCarPlayList(method: "getHomeActions") { [weak self] entries, error in
      guard let self else {
        return
      }
      let items = self.buildListItems(
        entries: entries,
        emptyText: "No actions available",
        errorText: "Connect to a server",
        error: error
      ) { entry in
        self.handleHomeAction(entry.id)
      }
      items.forEach { item in
        switch item.text {
        case "Start Library Shuffle":
          item.setImage(UIImage(systemName: "shuffle"))
        case "Start Liked Shuffle":
          item.setImage(UIImage(systemName: "heart.fill"))
        case "Start Custom Shuffle":
          item.setImage(UIImage(systemName: "line.3.horizontal.decrease.circle"))
        default:
          break
        }
      }
      self.updateListTemplate(template, items: items)
    }
    return template
  }

  private func buildLibraryTemplate() -> CPListTemplate {
    let template = CPListTemplate(
      title: "Library",
      sections: [CPListSection(items: buildLibraryItems(likedEnabled: false, likedSubtitle: "Loading…"))]
    )
    setNowPlayingButtonVisible(template, visible: nowPlayingButtonVisible)
    if #available(iOS 14.0, *) {
      template.tabTitle = "Library"
      template.tabImage = UIImage(systemName: "music.note.list")
    }
    requestCarPlayStatus { [weak self] status in
      guard let self else {
        return
      }
      let enabled = status.likedAvailable
      let subtitle: String
      if let error = status.error, !error.isEmpty {
        subtitle = "Connect to a server"
      } else if enabled {
        subtitle = "Play from the top"
      } else {
        subtitle = "No liked songs yet"
      }
      let items = self.buildLibraryItems(likedEnabled: enabled, likedSubtitle: subtitle)
      self.updateListTemplate(template, items: items)
    }
    return template
  }

  private func buildLoggedOutTemplate() -> CPListTemplate {
    let item = disabledItem(
      text: "Not logged into server",
      detail: "Open Phonolite to log in"
    )
    let template = CPListTemplate(
      title: "Phonolite",
      sections: [CPListSection(items: [item])]
    )
    setNowPlayingButtonVisible(template, visible: false)
    return template
  }

  private func buildLibraryItems(
    likedEnabled: Bool,
    likedSubtitle: String
  ) -> [CPListItem] {
    let artistsItem = CPListItem(text: "Artists", detailText: "Browse artists")
    artistsItem.setImage(UIImage(systemName: "music.mic"))
    artistsItem.handler = { [weak self] _, completion in
      self?.showArtistsList()
      completion()
    }

    let playlistsItem = CPListItem(text: "Playlists", detailText: "Pick a playlist")
    playlistsItem.setImage(UIImage(systemName: "music.note.list"))
    playlistsItem.handler = { [weak self] _, completion in
      self?.showPlaylistsList()
      completion()
    }

    let likedItem = CPListItem(text: "Liked Songs", detailText: likedSubtitle)
    likedItem.setImage(UIImage(systemName: "heart.fill"))
    likedItem.isEnabled = likedEnabled
    if likedEnabled {
      likedItem.handler = { [weak self] _, completion in
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
          appDelegate.invokeCarPlayMethod("playLiked")
        }
        self?.showNowPlaying(animated: true)
        completion()
      }
    }
    return [artistsItem, playlistsItem, likedItem]
  }

  private func handleHomeAction(_ actionId: String) {
    guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
      return
    }
    switch actionId {
    case "startLibraryShuffle":
      appDelegate.invokeCarPlayMethod("startLibraryShuffle")
    case "startLikedShuffle":
      appDelegate.invokeCarPlayMethod("startLikedShuffle")
    case "startCustomShuffle":
      appDelegate.invokeCarPlayMethod("startCustomShuffle")
    default:
      return
    }
    showNowPlaying(animated: true)
  }

  private func showArtistsList() {
    guard interfaceController != nil else {
      return
    }
    let template = CPListTemplate(
      title: "Artists",
      sections: [CPListSection(items: [disabledItem(text: "Loading artists…")])]
    )
    setNowPlayingButtonVisible(template, visible: nowPlayingButtonVisible)
    pushTemplate(template, animated: true)

    requestCarPlayList(method: "getArtists") { [weak self] entries, error in
      guard let self else {
        return
      }
      let items = self.buildListItems(
        entries: entries,
        emptyText: "No artists found",
        errorText: "Connect to a server",
        error: error
      ) { entry in
        self.showAlbumsList(artistId: entry.id, title: entry.title)
      }
      self.updateListTemplate(template, items: items)
    }
  }

  private func showAlbumsList(artistId: String, title: String) {
    guard interfaceController != nil else {
      return
    }
    let template = CPListTemplate(
      title: title,
      sections: [CPListSection(items: [disabledItem(text: "Loading albums…")])]
    )
    setNowPlayingButtonVisible(template, visible: nowPlayingButtonVisible)
    pushTemplate(template, animated: true)

    requestCarPlayList(method: "getAlbums", arguments: ["artistId": artistId]) { [weak self] entries, error in
      guard let self else {
        return
      }
      let items = self.buildListItems(
        entries: entries,
        emptyText: "No albums found",
        errorText: "Connect to a server",
        error: error
      ) { entry in
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
          appDelegate.invokeCarPlayMethod("playAlbum", arguments: ["albumId": entry.id])
        }
        self.showNowPlaying(animated: true)
      }
      self.updateListTemplate(template, items: items)
    }
  }

  private func showPlaylistsList() {
    guard interfaceController != nil else {
      return
    }
    let template = CPListTemplate(
      title: "Playlists",
      sections: [CPListSection(items: [disabledItem(text: "Loading playlists…")])]
    )
    setNowPlayingButtonVisible(template, visible: nowPlayingButtonVisible)
    pushTemplate(template, animated: true)

    requestCarPlayList(method: "getPlaylists") { [weak self] entries, error in
      guard let self else {
        return
      }
      let items = self.buildListItems(
        entries: entries,
        emptyText: "No playlists found",
        errorText: "Connect to a server",
        error: error
      ) { entry in
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
          appDelegate.invokeCarPlayMethod("playPlaylist", arguments: ["playlistId": entry.id])
        }
        self.showNowPlaying(animated: true)
      }
      self.updateListTemplate(template, items: items)
    }
  }

  private func requestCarPlayList(
    method: String,
    arguments: [String: Any]? = nil,
    completion: @escaping (
      [(id: String, title: String, subtitle: String?, enabled: Bool, artworkUrl: String?, token: String?)],
      String?
    ) -> Void
  ) {
    guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
      completion([], "unavailable")
      return
    }
    appDelegate.invokeCarPlayMethod(method, arguments: arguments) { result in
      let parsed = self.parseCarPlayList(result)
      DispatchQueue.main.async {
        completion(parsed.items, parsed.error)
      }
    }
  }

  private func requestCarPlayStatus(
    completion: @escaping ((likedAvailable: Bool, error: String?)) -> Void
  ) {
    guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
      completion((likedAvailable: false, error: "unavailable"))
      return
    }
    appDelegate.invokeCarPlayMethod("getLibraryStatus") { result in
      var likedAvailable = false
      var error: String?
      if let payload = result as? [String: Any] {
        likedAvailable = payload["likedAvailable"] as? Bool ?? false
        error = payload["error"] as? String
      } else if let flutterError = result as? FlutterError {
        error = flutterError.message
      }
      DispatchQueue.main.async {
        completion((likedAvailable: likedAvailable, error: error))
      }
    }
  }

  private func parseCarPlayList(
    _ result: Any?
  ) -> (
    items: [
      (id: String, title: String, subtitle: String?, enabled: Bool, artworkUrl: String?, token: String?)
    ],
    error: String?
  ) {
    if let error = result as? FlutterError {
      return ([], error.message ?? "error")
    }
    guard let payload = result as? [String: Any] else {
      return ([], "bad_response")
    }
    let error = payload["error"] as? String
    let rawItems = payload["items"] as? [[String: Any]] ?? []
    let items: [
      (id: String, title: String, subtitle: String?, enabled: Bool, artworkUrl: String?, token: String?)
    ] = rawItems.compactMap { item in
      let id = item["id"] as? String ?? ""
      let title = item["title"] as? String ?? ""
      let subtitle = item["subtitle"] as? String
      let enabled = item["enabled"] as? Bool ?? true
      let artworkUrl = item["artworkUrl"] as? String
      let token = item["token"] as? String
      if id.isEmpty || title.isEmpty {
        return nil
      }
      return (
        id: id,
        title: title,
        subtitle: subtitle,
        enabled: enabled,
        artworkUrl: artworkUrl,
        token: token
      )
    }
    return (items, error)
  }

  private func buildListItems(
    entries: [
      (id: String, title: String, subtitle: String?, enabled: Bool, artworkUrl: String?, token: String?)
    ],
    emptyText: String,
    errorText: String,
    error: String?,
    onSelect: @escaping (
      (id: String, title: String, subtitle: String?, enabled: Bool, artworkUrl: String?, token: String?)
    ) -> Void
  ) -> [CPListItem] {
    if let error, !error.isEmpty {
      return [disabledItem(text: errorText)]
    }
    if entries.isEmpty {
      return [disabledItem(text: emptyText)]
    }
    return entries.map { entry in
      let item = CPListItem(text: entry.title, detailText: entry.subtitle)
      if let artworkUrl = entry.artworkUrl, !artworkUrl.isEmpty {
        fetchCarPlayImage(urlString: artworkUrl, token: entry.token) { image in
          if let image {
            item.setImage(image)
          }
        }
      }
      item.isEnabled = entry.enabled
      if entry.enabled {
        item.handler = { _, completion in
          onSelect(entry)
          completion()
        }
      }
      return item
    }
  }

  private func disabledItem(text: String, detail: String? = nil) -> CPListItem {
    let item = CPListItem(text: text, detailText: detail)
    item.isEnabled = false
    return item
  }

  private func updateListTemplate(_ template: CPListTemplate, items: [CPListItem]) {
    let section = CPListSection(items: items)
    if #available(iOS 14.0, *) {
      template.updateSections([section])
    }
  }

  private func fetchCarPlayImage(
    urlString: String,
    token: String?,
    completion: @escaping (UIImage?) -> Void
  ) {
    guard let url = URL(string: urlString) else {
      completion(nil)
      return
    }
    var request = URLRequest(url: url)
    if let token, !token.isEmpty {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    URLSession.shared.dataTask(with: request) { data, _, _ in
      if let data, let image = UIImage(data: data) {
        DispatchQueue.main.async {
          completion(image)
        }
      } else {
        DispatchQueue.main.async {
          completion(nil)
        }
      }
    }.resume()
  }

  private func pushTemplate(_ template: CPTemplate, animated: Bool) {
    guard let interfaceController else {
      return
    }
    if #available(iOS 14.0, *) {
      interfaceController.pushTemplate(template, animated: animated, completion: { _, _ in })
    } else {
      interfaceController.pushTemplate(template, animated: animated)
    }
  }

  private func showNowPlaying(animated: Bool) {
    guard let interfaceController else {
      return
    }
    if interfaceController.topTemplate === nowPlayingTemplate {
      return
    }
    if #available(iOS 14.0, *) {
      interfaceController.pushTemplate(nowPlayingTemplate, animated: animated, completion: { _, _ in })
    } else {
      interfaceController.pushTemplate(nowPlayingTemplate, animated: animated)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
      self?.refreshNowPlayingUI(force: true)
    }
  }

  func updateNowPlayingListItem(
    title: String?,
    artist: String?,
    album: String?,
    artwork: UIImage?
  ) {
    guard #available(iOS 14.0, *) else {
      return
    }
    guard let item = nowPlayingItem else {
      return
    }
    let cleanTitle = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanArtist = (artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanAlbum = (album ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let displayTitle = cleanTitle.isEmpty ? "Now Playing" : cleanTitle
    var detail = ""
    if !cleanArtist.isEmpty && !cleanAlbum.isEmpty {
      detail = "\(cleanArtist) • \(cleanAlbum)"
    } else if !cleanArtist.isEmpty {
      detail = cleanArtist
    } else if !cleanAlbum.isEmpty {
      detail = cleanAlbum
    } else {
      detail = "Tap to open"
    }
    DispatchQueue.main.async {
      item.setText(displayTitle)
      item.setDetailText(detail)
      if let artwork {
        item.setImage(artwork)
      } else {
        item.setImage(nil)
      }
    }
  }

  func clearNowPlayingListItem() {
    guard #available(iOS 14.0, *) else {
      return
    }
    guard let item = nowPlayingItem else {
      return
    }
    DispatchQueue.main.async {
      item.setText("Now Playing")
      item.setDetailText("Tap to open")
      item.setImage(nil)
    }
  }

  func updateNowPlayingButtons(liked: Bool, available: Bool) {
    guard #available(iOS 14.0, *) else {
      return
    }
    DispatchQueue.main.async { [weak self] in
      guard let self else {
        return
      }
      if !available {
        self.nowPlayingTemplate.updateNowPlayingButtons([])
        return
      }
      let imageName = liked ? "heart.fill" : "heart"
      guard let image = UIImage(systemName: imageName) else {
        self.nowPlayingTemplate.updateNowPlayingButtons([])
        return
      }
      let button = CPNowPlayingImageButton(image: image) { _ in
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
          appDelegate.sendRemoteCommandToFlutter("toggleLike")
        }
      }
      self.nowPlayingTemplate.updateNowPlayingButtons([button])
    }
  }

  func updateAuthState(authorized: Bool, force: Bool = false) {
    DispatchQueue.main.async { [weak self] in
      guard let self else {
        return
      }
      if !force && self.isAuthorized == authorized {
        return
      }
      self.isAuthorized = authorized
      if authorized {
        self.showAuthorizedRoot()
      } else {
        self.showLoggedOutRoot()
      }
    }
  }

  private func requestAuthState() {
    guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
      return
    }
    appDelegate.invokeCarPlayMethod("getAuthState") { [weak self] result in
      guard let self else {
        return
      }
      var authorized = false
      if let payload = result as? [String: Any] {
        authorized = payload["authorized"] as? Bool ?? false
      }
      self.updateAuthState(authorized: authorized)
    }
  }

  private func showAuthorizedRoot() {
    guard let interfaceController else {
      return
    }
    let homeTemplate = buildHomeTemplate()
    let libraryTemplate = buildLibraryTemplate()
    self.homeTemplate = homeTemplate
    self.libraryTemplate = libraryTemplate
    self.loggedOutTemplate = nil
    applyNowPlayingButtonVisibility()
    if #available(iOS 14.0, *) {
      let tabBar = CPTabBarTemplate(templates: [homeTemplate, libraryTemplate])
      rootTemplate = tabBar
      interfaceController.setRootTemplate(tabBar, animated: false, completion: nil)
    } else {
      rootTemplate = homeTemplate
      interfaceController.setRootTemplate(homeTemplate, animated: false)
    }
  }

  private func showLoggedOutRoot() {
    guard let interfaceController else {
      return
    }
    nowPlayingButtonVisible = false
    applyNowPlayingButtonVisibility()
    let template = loggedOutTemplate ?? buildLoggedOutTemplate()
    loggedOutTemplate = template
    homeTemplate = nil
    libraryTemplate = nil
    rootTemplate = template
    if #available(iOS 14.0, *) {
      interfaceController.setRootTemplate(template, animated: false, completion: nil)
    } else {
      interfaceController.setRootTemplate(template, animated: false)
    }
  }

  func updateNowPlayingVisibility(hasTrack: Bool) {
    DispatchQueue.main.async { [weak self] in
      guard let self else {
        return
      }
      self.nowPlayingButtonVisible = self.isAuthorized && hasTrack
      self.applyNowPlayingButtonVisibility()
    }
  }

  private func applyNowPlayingButtonVisibility() {
    setNowPlayingButtonVisible(homeTemplate, visible: nowPlayingButtonVisible)
    setNowPlayingButtonVisible(libraryTemplate, visible: nowPlayingButtonVisible)
    setNowPlayingButtonVisible(loggedOutTemplate, visible: nowPlayingButtonVisible)
    if let topTemplate = interfaceController?.topTemplate {
      setNowPlayingButtonVisible(topTemplate, visible: nowPlayingButtonVisible)
    }
  }

  private func setNowPlayingButtonVisible(_ template: CPTemplate?, visible: Bool) {
    guard let template else {
      return
    }
    let selector = Selector(("setShowsNowPlayingButton:"))
    if template.responds(to: selector) {
      template.setValue(visible, forKey: "showsNowPlayingButton")
    }
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController,
    to window: CPWindow
  ) {
    configureRootTemplate(using: interfaceController)
  }

  @available(iOS 14.0, *)
  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController
  ) {
    configureRootTemplate(using: interfaceController)
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnect interfaceController: CPInterfaceController,
    from window: CPWindow
  ) {
    if self.interfaceController === interfaceController {
      self.interfaceController = nil
    }
    rootTemplate = nil
    homeTemplate = nil
    libraryTemplate = nil
    loggedOutTemplate = nil
    nowPlayingItem = nil
    if let appDelegate = UIApplication.shared.delegate as? AppDelegate,
       appDelegate.carPlaySceneDelegate === self {
      appDelegate.carPlaySceneDelegate = nil
    }
  }

  @available(iOS 14.0, *)
  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnect interfaceController: CPInterfaceController
  ) {
    if self.interfaceController === interfaceController {
      self.interfaceController = nil
    }
    rootTemplate = nil
    homeTemplate = nil
    libraryTemplate = nil
    loggedOutTemplate = nil
    nowPlayingItem = nil
    if let appDelegate = UIApplication.shared.delegate as? AppDelegate,
       appDelegate.carPlaySceneDelegate === self {
      appDelegate.carPlaySceneDelegate = nil
    }
  }
}
