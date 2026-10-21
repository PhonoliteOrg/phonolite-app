import AVFoundation
import Foundation

final class AudioSessionService: NSObject {
  private let isPlaying: () -> Bool
  private let sendRemoteCommand: (NativeRemoteCommand) -> Void

  private var hasConfiguredObservers = false

  init(isPlaying: @escaping () -> Bool, sendRemoteCommand: @escaping (NativeRemoteCommand) -> Void) {
    self.isPlaying = isPlaying
    self.sendRemoteCommand = sendRemoteCommand

    super.init()
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  func configureInitialSession() {
    do {
      let session = AVAudioSession.sharedInstance()

      // Playback already supports AirPlay and Bluetooth A2DP. Explicit
      // allowAirPlay is only valid for the playAndRecord category.
      try session.setCategory(.playback, mode: .default, options: [])
      try session.setActive(true)
    } catch {
      NSLog("Failed to activate audio session: %@", "\(error)")
    }
  }

  func configureObservers() {
    guard !hasConfiguredObservers else {
      return
    }

    hasConfiguredObservers = true

    let session = AVAudioSession.sharedInstance()

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleInterruption(_:)),
      name: AVAudioSession.interruptionNotification,
      object: session
    )

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleRouteChange(_:)),
      name: AVAudioSession.routeChangeNotification,
      object: session
    )
  }

  @objc private func handleInterruption(_ notification: Notification) {
    guard let information = notification.userInfo else {
      return
    }

    let typeValue = (information[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue ?? 0

    guard let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
      return
    }

    switch type {
    case .began:
      if isPlaying() {
        sendRemoteCommand(.pause)
      }
    case .ended:
      break
    @unknown default:
      break
    }
  }

  @objc private func handleRouteChange(_ notification: Notification) {
    guard let information = notification.userInfo else {
      return
    }

    let reasonValue = (information[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue ?? 0

    guard let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
      return
    }

    switch reason {
    case .oldDeviceUnavailable:
      if isPlaying() {
        sendRemoteCommand(.pause)
      }
    default:
      break
    }
  }
}
