import Foundation
import MediaPlayer

#if os(iOS)
  import UIKit
#endif

final class RemoteCommandService {
  private let sendCommand: (NativeRemoteCommand) -> Void
  private let onSeek: ((Double) -> Void)?

  private var isConfigured = false
  private var isEnabled = false
  private var registrations: [(command: MPRemoteCommand, token: Any)] = []

  init(sendCommand: @escaping (NativeRemoteCommand) -> Void, onSeek: ((Double) -> Void)? = nil) {
    self.sendCommand = sendCommand
    self.onSeek = onSeek
  }

  deinit { stop() }

  func configure() {
    guard !isConfigured else { return }

    #if os(iOS)
      UIApplication.shared.beginReceivingRemoteControlEvents()
    #endif

    let commandCenter = MPRemoteCommandCenter.shared()
    register(commandCenter.playCommand, action: .play)
    register(commandCenter.pauseCommand, action: .pause)
    register(commandCenter.togglePlayPauseCommand, action: .toggle)
    register(commandCenter.nextTrackCommand, action: .next)
    register(commandCenter.previousTrackCommand, action: .previous)

    let positionCommand = commandCenter.changePlaybackPositionCommand
    let positionToken = positionCommand.addTarget { [weak self] event in
      guard let self, self.onSeek != nil, let event = event as? MPChangePlaybackPositionCommandEvent,
        event.positionTime.isFinite, event.positionTime >= 0, event.positionTime <= 1.0e9
      else { return .commandFailed }

      self.dispatch { self.onSeek?(event.positionTime) }

      return .success
    }

    registrations.append((command: positionCommand, token: positionToken))
    isConfigured = true
    setEnabled(true)
  }

  func stop() {
    guard isConfigured else { return }

    setEnabled(false)
    isConfigured = false

    for registration in registrations { registration.command.removeTarget(registration.token) }

    registrations.removeAll()
  }

  func setEnabled(_ enabled: Bool, canSeek: Bool = true) {
    isEnabled = enabled

    let center = MPRemoteCommandCenter.shared()
    center.playCommand.isEnabled = enabled
    center.pauseCommand.isEnabled = enabled
    center.togglePlayPauseCommand.isEnabled = enabled
    center.nextTrackCommand.isEnabled = enabled
    center.previousTrackCommand.isEnabled = enabled
    center.changePlaybackPositionCommand.isEnabled = enabled && canSeek && onSeek != nil
  }

  private func register(_ command: MPRemoteCommand, action: NativeRemoteCommand) {
    let token = command.addTarget { [weak self] _ in
      guard let self else { return .commandFailed }

      self.dispatch { self.sendCommand(action) }

      return .success
    }

    registrations.append((command: command, token: token))
  }

  private func dispatch(_ action: @escaping () -> Void) {
    func perform() {
      guard isConfigured, isEnabled else { return }

      action()
    }

    if Thread.isMainThread { perform() } else { DispatchQueue.main.async { perform() } }
  }
}
