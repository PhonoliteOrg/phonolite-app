import Flutter
import UIKit

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
