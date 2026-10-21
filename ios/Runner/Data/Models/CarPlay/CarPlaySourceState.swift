struct CarPlaySourceState: Equatable {
  static let empty = CarPlaySourceState(serverAvailable: false, localAvailable: false)

  let serverAvailable: Bool
  let localAvailable: Bool
  let hasAnySource: Bool

  init(serverAvailable: Bool, localAvailable: Bool, hasAnySource: Bool = false) {
    self.serverAvailable = serverAvailable
    self.localAvailable = localAvailable
    self.hasAnySource = hasAnySource || serverAvailable || localAvailable
  }
}
