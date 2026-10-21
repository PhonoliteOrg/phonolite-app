import MediaPlayer
import UIKit

final class RemoteCommandService {
  private let sendCommand: (NativeRemoteCommand) -> Void

  private var isConfigured = false
  private var registrations: [(command: MPRemoteCommand, token: Any)] = []

  init(sendCommand: @escaping (NativeRemoteCommand) -> Void) {
    self.sendCommand = sendCommand
  }

  deinit {
    for registration in registrations {
      registration.command.removeTarget(registration.token)
    }
  }

  func configure() {
    guard !isConfigured else {
      return
    }

    UIApplication.shared.beginReceivingRemoteControlEvents()

    let commandCenter = MPRemoteCommandCenter.shared()
    commandCenter.playCommand.isEnabled = true
    commandCenter.pauseCommand.isEnabled = true
    commandCenter.togglePlayPauseCommand.isEnabled = true
    commandCenter.nextTrackCommand.isEnabled = true
    commandCenter.previousTrackCommand.isEnabled = true
    commandCenter.changePlaybackPositionCommand.isEnabled = false
    commandCenter.changePlaybackPositionCommand.removeTarget(nil)

    register(commandCenter.playCommand, action: .play)
    register(commandCenter.pauseCommand, action: .pause)
    register(commandCenter.togglePlayPauseCommand, action: .toggle)
    register(commandCenter.nextTrackCommand, action: .next)
    register(commandCenter.previousTrackCommand, action: .previous)

    let positionCommand = commandCenter.changePlaybackPositionCommand
    let positionToken = positionCommand.addTarget { _ in
      return .commandFailed
    }

    registrations.append((command: positionCommand, token: positionToken))
    isConfigured = true
  }

  private func register(_ command: MPRemoteCommand, action: NativeRemoteCommand) {
    let token = command.addTarget { [weak self] _ in
      self?.sendCommand(action)

      return .success
    }

    registrations.append((command: command, token: token))
  }
}
