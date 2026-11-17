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

  // Launch only declares the category. Activating a non-mixable playback session here would
  // interrupt other apps' audio before the user plays anything; activateForPlayback does that.
  func configureInitialSession() {
    do {
      try configureCategory()
    } catch {
      NSLog("Failed to configure audio session: %@", "\(error)")
    }
  }

  func activateForPlayback() -> Bool {
    do {
      try configureCategory()
      try AVAudioSession.sharedInstance().setActive(true)

      return true
    } catch {
      NSLog("Failed to activate audio session: %@", "\(error)")

      return false
    }
  }

  private func configureCategory() throws {
    // Playback already supports AirPlay and Bluetooth A2DP. Explicit
    // allowAirPlay is only valid for the playAndRecord category.
    let session = AVAudioSession.sharedInstance()

    try session.setCategory(.playback, mode: .default, options: [])
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

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleMediaServicesReset(_:)),
      name: AVAudioSession.mediaServicesWereResetNotification,
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
      sendRemoteCommand(.audioInterruptionBegan)
    case .ended:
      let optionsValue = (information[AVAudioSessionInterruptionOptionKey] as? NSNumber)?.uintValue ?? 0
      let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
      sendRemoteCommand(options.contains(.shouldResume) ? .audioInterruptionEnded : .audioInterruptionEndedPaused)
    @unknown default:
      break
    }
  }

  @objc private func handleMediaServicesReset(_ notification: Notification) {
    // Dart retires orphaned outputs and retains the track paused. Explicit
    // user playback then creates fresh queues and reactivates the session.
    sendRemoteCommand(.audioServicesReset)
  }

  @objc private func handleRouteChange(_ notification: Notification) {
    guard let information = notification.userInfo else {
      return
    }

    let reasonValue = (information[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue ?? 0

    // Route changes are posted on a background thread; playback state and the channel
    // are main-thread only.
    DispatchQueue.main.async { [weak self] in
      self?.applyRouteChange(reasonValue: reasonValue)
    }
  }

  private func applyRouteChange(reasonValue: UInt) {

    guard let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
      return
    }

    NSLog("Phonolite audio route changed: reason=%lu playing=%d", reasonValue, isPlaying() ? 1 : 0)

    switch reason {
    case .oldDeviceUnavailable:
      // Bluetooth can disappear as wired CarPlay takes over. Preserve playback
      // for that handoff; disconnecting to the speaker still pauses normally.
      let connectedToCar = AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .carAudio }

      if !connectedToCar {
        sendRemoteCommand(.pause)
      }

      sendRemoteCommand(.audioRouteChanged)
    case .newDeviceAvailable, .routeConfigurationChange:
      sendRemoteCommand(.audioRouteChanged)
    default:
      break
    }
  }
}
