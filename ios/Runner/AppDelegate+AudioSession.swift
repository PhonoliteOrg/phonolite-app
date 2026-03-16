import AVFoundation
import UIKit

extension AppDelegate {
  func configureInitialAudioSession() {
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(
        .playback,
        mode: .default,
        options: [.allowAirPlay, .allowBluetoothA2DP]
      )
      try session.setActive(true)
    } catch {
      NSLog("Failed to activate audio session: %@", "\(error)")
    }
  }

  func configureAudioSessionObservers() {
    if audioSessionObserversConfigured {
      return
    }
    audioSessionObserversConfigured = true
    let session = AVAudioSession.sharedInstance()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAudioSessionInterruption(_:)),
      name: AVAudioSession.interruptionNotification,
      object: session
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAudioSessionRouteChange(_:)),
      name: AVAudioSession.routeChangeNotification,
      object: session
    )
  }

  @objc func handleAudioSessionInterruption(_ notification: Notification) {
    guard let info = notification.userInfo else {
      return
    }
    let typeValue =
      (info[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue ?? 0
    guard let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
      return
    }
    switch type {
    case .began:
      if currentIsPlaying {
        sendRemoteCommandToFlutter("pause")
      }
    case .ended:
      break
    @unknown default:
      break
    }
  }

  @objc func handleAudioSessionRouteChange(_ notification: Notification) {
    guard let info = notification.userInfo else {
      return
    }
    let reasonValue =
      (info[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue ?? 0
    guard let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
      return
    }
    switch reason {
    case .oldDeviceUnavailable:
      if currentIsPlaying {
        sendRemoteCommandToFlutter("pause")
      }
    default:
      break
    }
  }
}
