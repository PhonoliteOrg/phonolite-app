import FlutterMacOS

/// Main-thread channel ownership for the engine hosted by one window.
final class FlutterEngineBinding {
  private let directories: DirectoriesChannelAdapter

  init(messenger: FlutterBinaryMessenger, directoryLauncher: DirectoryLauncher = DirectoryLauncher()) {
    directories = DirectoriesChannelAdapter(messenger: messenger, openDirectory: directoryLauncher.openDirectory(at:))
  }

  func attach() {
    directories.attach()
  }

  func detach() {
    directories.detach()
  }
}
