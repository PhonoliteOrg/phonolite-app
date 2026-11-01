import FlutterMacOS

/// Main-thread channel ownership for the engine hosted by one window.
final class FlutterEngineBinding {
  private let directories: DirectoriesChannelAdapter
  private let startup: StartupChannelAdapter
  private let nowPlaying: NowPlayingChannelAdapter
  private let media: NowPlayingService
  private let storageAccess: StorageAccessChannelAdapter
  private let messenger: FlutterBinaryMessenger

  init(
    messenger: FlutterBinaryMessenger, directoryLauncher: DirectoryLauncher = DirectoryLauncher(),
    loginItems: LoginItemService = LoginItemService()
  ) {
    self.messenger = messenger
    directories = DirectoriesChannelAdapter(messenger: messenger, openDirectory: directoryLauncher.openDirectory(at:))
    startup = StartupChannelAdapter(
      messenger: messenger, isEnabled: loginItems.isEnabled, setEnabled: loginItems.setEnabled)
    storageAccess = StorageAccessChannelAdapter(messenger: messenger)

    weak var outgoing: NowPlayingChannelAdapter?
    let media = NowPlayingService { type, arguments in outgoing?.send(type: type, arguments: arguments) }
    let channel = NowPlayingChannelAdapter(
      onUpdate: media.update, onPreloadArtwork: { _ in }, onClear: media.clear, onAttached: media.attach)

    outgoing = channel
    self.media = media
    nowPlaying = channel
  }

  func attach() {
    directories.attach()
    storageAccess.attach()
    startup.attach()
    nowPlaying.attach(to: messenger)
  }

  func detach() {
    nowPlaying.detach()
    media.detach()
    storageAccess.detach()
    startup.detach()
    directories.detach()
  }
}
