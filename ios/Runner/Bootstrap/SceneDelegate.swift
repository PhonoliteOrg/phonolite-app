import Flutter
import UIKit

final class SceneDelegate: FlutterSceneDelegate {
  private let launchSnapshotCover = LaunchSnapshotCover()

  override func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)

    if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
      appDelegate.nativeHost.configureNowPlayingChannel()
      appDelegate.nativeHost.configurePermissionsChannel()
    }
  }

  override func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
    // Disable scene restoration to avoid NSUserActivity with an empty activityType.
    return nil
  }

  override func sceneDidEnterBackground(_ scene: UIScene) {
    // UIKit captures the scene after this callback returns. Save the splash
    // instead of an old Flutter page that would appear during the next launch.
    launchSnapshotCover.show(in: window)

    super.sceneDidEnterBackground(scene)

    if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
      appDelegate.nativeHost.refreshOfflineStorageBackupExclusions()
    }
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)

    // On a warm resume the UI is already present. During cold startup Flutter's
    // native splash remains responsible for waiting for the first frame.
    launchSnapshotCover.remove()
  }

  override func sceneDidDisconnect(_ scene: UIScene) {
    launchSnapshotCover.remove()

    super.sceneDidDisconnect(scene)
  }
}
