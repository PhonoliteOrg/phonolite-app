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

  func configureRemoteCommands(channel: FlutterMethodChannel) {
    UIApplication.shared.beginReceivingRemoteControlEvents()
    let commandCenter = MPRemoteCommandCenter.shared()
    commandCenter.playCommand.isEnabled = true
    commandCenter.pauseCommand.isEnabled = true
    commandCenter.togglePlayPauseCommand.isEnabled = true
    commandCenter.nextTrackCommand.isEnabled = true
    commandCenter.previousTrackCommand.isEnabled = true
    commandCenter.changePlaybackPositionCommand.isEnabled = false
    commandCenter.changePlaybackPositionCommand.removeTarget(nil)

    commandCenter.playCommand.addTarget { _ in
      channel.invokeMethod("remoteCommand", arguments: ["type": "play"])
      return .success
    }
    commandCenter.pauseCommand.addTarget { _ in
      channel.invokeMethod("remoteCommand", arguments: ["type": "pause"])
      return .success
    }
    commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
      let isPlaying = self?.nowPlayingCoordinator.isPlaying ?? false
      channel.invokeMethod("remoteCommand", arguments: ["type": isPlaying ? "pause" : "play"])
      return .success
    }
    commandCenter.nextTrackCommand.addTarget { _ in
      channel.invokeMethod("remoteCommand", arguments: ["type": "next"])
      return .success
    }
    commandCenter.previousTrackCommand.addTarget { _ in
      channel.invokeMethod("remoteCommand", arguments: ["type": "prev"])
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
