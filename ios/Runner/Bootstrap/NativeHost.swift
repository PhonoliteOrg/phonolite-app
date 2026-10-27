import Foundation

/// Assembles process services, one engine binding and the current scene session.
final class NativeHost {
  private let nowPlaying = NowPlayingCoordinator(artworkSession: nil)
  private let permissions = LocalNetworkPermissionService()
  private let settings = ApplicationSettingsService()

  private var engineBinding: FlutterEngineBinding?
  private weak var carPlaySession: CarPlayNavigationCoordinator?

  private lazy var audioSession = AudioSessionService(
    isPlaying: { [weak self] in self?.nowPlaying.isPlaying ?? false },
    sendRemoteCommand: { [weak self] command in self?.sendRemoteCommand(command) }
  )

  private lazy var remoteCommands = RemoteCommandService { [weak self] command in
    self?.sendRemoteCommand(command)
  }

  private lazy var nowPlayingChannel = NowPlayingChannelAdapter(
    onUpdate: { [weak self] update in self?.nowPlaying.update(update) },
    onPreloadArtwork: { [weak self] sources in self?.nowPlaying.preloadArtwork(sources) },
    onClear: { [weak self] in self?.nowPlaying.clear() },
    onAttached: { [weak self] in self?.remoteCommands.configure() }
  )

  private lazy var carPlayChannel = CarPlayChannelAdapter(
    prepareToInvoke: { [weak self] in self?.configureCarPlayChannel() },
    onSourceState: { [weak self] state in self?.carPlaySession?.updateSourceState(state, force: false) },
    onAuthorizationChanged: { [weak self] in self?.carPlaySession?.requestSourceState(force: false) }
  )

  private lazy var permissionsChannel = PermissionsChannelAdapter(
    readStatus: { [weak self] in self?.permissions.status ?? .unknown },
    requestPermission: { [weak self] in self?.permissions.requestPermission() },
    openSettings: { [weak self] in self?.settings.open() ?? false }
  )

  init() {
    nowPlaying.onPresentationChanged = { [weak self] state in
      self?.carPlaySession?.updateNowPlayingButtons(liked: state.liked, available: state.trackID != nil)
    }

    permissions.setStatusHandler { [weak self] status in
      self?.permissionsChannel.publish(status)
    }
  }

  func bindEngine(_ binding: FlutterEngineBinding) {
    engineBinding = binding
  }

  func configureInitialAudioSession() {
    audioSession.configureInitialSession()
  }

  func configureAudioSessionObservers() {
    audioSession.configureObservers()
  }

  func configureNowPlayingChannel() {
    engineBinding?.attach(nowPlayingChannel)
  }

  func configureCarPlayChannel() {
    engineBinding?.attach(carPlayChannel)
  }

  func configurePermissionsChannel() {
    engineBinding?.attach(permissionsChannel)
  }

  func requestLocalNetworkPermission() {
    permissions.requestPermission()
  }

  func refreshOfflineStorageBackupExclusions() {
    OfflineBackupExclusions.refresh()
  }

  private func connectCarPlaySession(_ session: CarPlayNavigationCoordinator) {
    carPlaySession = session
    nowPlaying.refreshPresentation()
    configureCarPlayChannel()
  }

  private func disconnectCarPlaySession(_ session: CarPlayNavigationCoordinator) {
    if carPlaySession === session {
      carPlaySession = nil
    }
  }

  private func sendRemoteCommand(_ command: NativeRemoteCommand) {
    // MediaPlayer and audio-session callbacks may arrive outside Flutter's
    // platform thread. Preserve the shared main-queue delivery boundary.
    guard Thread.isMainThread else {
      DispatchQueue.main.async { [weak self] in
        self?.sendRemoteCommand(command)
      }

      return
    }

    configureNowPlayingChannel()

    let resolved: NativeRemoteCommand

    if command == .toggle {
      resolved = nowPlaying.isPlaying ? .pause : .play
    } else {
      resolved = command
    }

    nowPlayingChannel.send(resolved)
  }

  private func makeArtworkLoader() -> CarPlayListFrame.ArtworkLoader {
    let artworkLoader = CarPlayArtworkLoader()

    return { [artworkLoader] entry, completion in
      guard let artworkURL = entry.artworkURL else {
        completion(nil)

        return
      }

      artworkLoader.loadImage(
        urlString: artworkURL,
        token: entry.token,
        serverPin: entry.serverPin,
        completion: completion
      )
    }
  }

  func makeCarPlaySession() -> CarPlayNavigationCoordinator {
    return CarPlayNavigationCoordinator(
      client: carPlayChannel,
      loadArtwork: makeArtworkLoader(),
      refreshNowPlaying: { [weak self] in self?.nowPlaying.refreshPresentation() },
      sendRemoteCommand: { [weak self] command in self?.sendRemoteCommand(command) },
      onConnected: { [weak self] session in self?.connectCarPlaySession(session) },
      onDisconnected: { [weak self] session in self?.disconnectCarPlaySession(session) }
    )
  }
}
