struct CarPlaySourceState: Equatable {
  static let empty = CarPlaySourceState(serverAvailable: false, localAvailable: false)

  let serverAvailable: Bool
  let localAvailable: Bool
  let hasAnySource: Bool
  let playbackScope: CarPlayScope?

  init(
    serverAvailable: Bool,
    localAvailable: Bool,
    hasAnySource: Bool = false,
    playbackScope: CarPlayScope? = nil
  ) {
    self.serverAvailable = serverAvailable
    self.localAvailable = localAvailable
    self.hasAnySource = hasAnySource || serverAvailable || localAvailable
    self.playbackScope = playbackScope
  }

  var preferredScope: CarPlayScope {
    if let playbackScope, playbackScope == .local ? localAvailable : serverAvailable {
      return playbackScope
    }

    return serverAvailable && !localAvailable ? .server : .local
  }
}
