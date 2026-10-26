import FlutterMacOS

/// Main-thread channel ownership for the engine hosted by one window.
final class FlutterEngineBinding {
  private let directories: DirectoriesChannelAdapter
  private let startup: StartupChannelAdapter

  init(
    messenger: FlutterBinaryMessenger,
    directoryLauncher: DirectoryLauncher = DirectoryLauncher(),
    loginItems: LoginItemService = LoginItemService()
  ) {
    directories = DirectoriesChannelAdapter(messenger: messenger, openDirectory: directoryLauncher.openDirectory(at:))
    startup = StartupChannelAdapter(messenger: messenger, isEnabled: loginItems.isEnabled, setEnabled: loginItems.setEnabled)
  }

  func attach() {
    directories.attach()
    startup.attach()
  }

  func detach() {
    startup.detach()
    directories.detach()
  }
}
