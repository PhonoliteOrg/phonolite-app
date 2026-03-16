import AVFoundation
import CarPlay
import Flutter
import MediaPlayer
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  var nowPlayingChannel: FlutterMethodChannel?
  var carPlayChannel: FlutterMethodChannel?
  var currentArtworkUrl: String?
  var currentArtworkToken: String?
  var currentDuration: Double?
  var currentIsPlaying: Bool = false
  var currentLiked: Bool = false
  var currentTitle: String?
  var currentArtist: String?
  var currentAlbum: String?
  var currentArtwork: UIImage?
  var currentTrackId: String?
  var currentEpoch: Int = 0
  var lastReportedPosition: Double = -1
  let seekBackwardTolerance: Double = 0.75
  var remoteCommandsConfigured = false
  var audioSessionObserversConfigured = false
  weak var carPlaySceneDelegate: CarPlaySceneDelegate?
  let localNetworkPermissions = LocalNetworkPermissionManager()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    configureInitialAudioSession()
    configureAudioSessionObservers()

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
}
