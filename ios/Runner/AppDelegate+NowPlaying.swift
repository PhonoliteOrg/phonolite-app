import Flutter
import MediaPlayer
import UIKit

extension AppDelegate {
  func updateNowPlayingInfo(args: [String: Any]) {
    nowPlayingCoordinator.update(
      args: args,
      carPlaySceneDelegate: carPlaySceneDelegate
    )
  }

  func clearNowPlaying() {
    nowPlayingCoordinator.clear(carPlaySceneDelegate: carPlaySceneDelegate)
  }

  func configureRemoteCommands(channel _: FlutterMethodChannel) {
    UIApplication.shared.beginReceivingRemoteControlEvents()
    let commandCenter = MPRemoteCommandCenter.shared()
    commandCenter.playCommand.isEnabled = true
    commandCenter.pauseCommand.isEnabled = true
    commandCenter.togglePlayPauseCommand.isEnabled = true
    commandCenter.nextTrackCommand.isEnabled = true
    commandCenter.previousTrackCommand.isEnabled = true
    commandCenter.changePlaybackPositionCommand.isEnabled = false
    commandCenter.changePlaybackPositionCommand.removeTarget(nil)

    commandCenter.playCommand.addTarget { [weak self] _ in
      self?.sendRemoteCommandToFlutter("play")
      return .success
    }
    commandCenter.pauseCommand.addTarget { [weak self] _ in
      self?.sendRemoteCommandToFlutter("pause")
      return .success
    }
    commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
      self?.sendRemoteCommandToFlutter("toggle")
      return .success
    }
    commandCenter.nextTrackCommand.addTarget { [weak self] _ in
      self?.sendRemoteCommandToFlutter("next")
      return .success
    }
    commandCenter.previousTrackCommand.addTarget { [weak self] _ in
      self?.sendRemoteCommandToFlutter("prev")
      return .success
    }
    commandCenter.changePlaybackPositionCommand.addTarget { _ in
      return .commandFailed
    }
  }

  func refreshNowPlayingForCarPlay(force: Bool) {
    nowPlayingCoordinator.refreshForCarPlay(
      force: force,
      carPlaySceneDelegate: carPlaySceneDelegate
    )
  }
}
