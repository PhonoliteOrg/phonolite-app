import Foundation

/// Engine-bound system media integration. All state and Flutter calls use the main thread.
final class NowPlayingService {
  private let sendCommand: (String, [String: Any]) -> Void
  private let publisher = NowPlayingInfoPublisher()
  private let artwork = NowPlayingArtwork()
  private var state = NowPlayingState()
  private lazy var commands = RemoteCommandService(
    sendCommand: { [weak self] command in self?.send(command) },
    onSeek: { [weak self] position in self?.sendCommand("seek", ["position": position]) })

  init(sendCommand: @escaping (String, [String: Any]) -> Void) {
    self.sendCommand = sendCommand
    artwork.onChanged = { [weak self] in self?.publish() }
  }

  func attach() {
    commands.configure()
    commands.setEnabled(state.trackID != nil, canSeek: (state.duration ?? 0) > 0)
  }

  func detach() {
    commands.stop()
    clear()
  }

  func update(_ update: NowPlayingUpdate) {
    if let trackID = update.trackID, trackID != state.trackID { artwork.clear() }

    state.apply(update)
    artwork.update(update.artworkSource, data: update.artworkData)
    commands.setEnabled(state.trackID != nil, canSeek: (state.duration ?? 0) > 0)
    publish()
  }

  func clear() {
    state = NowPlayingState()
    artwork.clear()
    commands.setEnabled(false)
    publisher.clear()
  }

  private func send(_ command: NativeRemoteCommand) {
    let action = command == .toggle ? (state.isPlaying ? NativeRemoteCommand.pause : .play) : command

    sendCommand(action.rawValue, [:])
  }

  private func publish() { publisher.publish(state: state, artwork: artwork.current) }
}
