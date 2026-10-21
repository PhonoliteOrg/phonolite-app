import CarPlay
import UIKit

import Flutter

@main
@objc final class AppDelegate: FlutterAppDelegate {
  let nativeHost = NativeHost()

  private lazy var engineBinding = FlutterEngineBinding { [weak self] plugin in
    self?.resolveMessenger(plugin: plugin)
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    nativeHost.bindEngine(engineBinding)
    nativeHost.configureInitialAudioSession()
    nativeHost.configureAudioSessionObservers()

    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    nativeHost.configureNowPlayingChannel()
    nativeHost.configureCarPlayChannel()
    nativeHost.configurePermissionsChannel()
    nativeHost.requestLocalNetworkPermission()
    nativeHost.refreshOfflineStorageBackupExclusions()

    return result
  }

  override func applicationDidEnterBackground(_ application: UIApplication) {
    super.applicationDidEnterBackground(application)

    nativeHost.refreshOfflineStorageBackupExclusions()
  }

  override func application(
    _ application: UIApplication,
    configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    if connectingSceneSession.role == UISceneSession.Role.carTemplateApplication {
      let configuration = UISceneConfiguration(
        name: "CarPlay Configuration",
        sessionRole: connectingSceneSession.role
      )
      configuration.sceneClass = CPTemplateApplicationScene.self
      configuration.delegateClass = CarPlaySceneDelegate.self

      return configuration
    }

    let configuration = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    configuration.delegateClass = SceneDelegate.self
    configuration.storyboard = UIStoryboard(name: "Main", bundle: nil)

    return configuration
  }

  private func rootFlutterViewController() -> FlutterViewController? {
    if let controller = window?.rootViewController as? FlutterViewController {
      return controller
    }

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

    return nil
  }

  private func resolveMessenger(plugin: String) -> FlutterBinaryMessenger? {
    if let controller = rootFlutterViewController() {
      return controller.binaryMessenger
    }

    return registrar(forPlugin: plugin)?.messenger()
  }
}
