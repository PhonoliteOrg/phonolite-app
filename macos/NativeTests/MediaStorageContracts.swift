import Foundation
import MediaPlayer

@main enum MediaStorageContracts {
  static func main() throws {
    verifyPlaybackState()
    try verifyDirectoryLifetimes()
    verifyFailedRestoration()

    print("macOS metadata, seek-epoch and sandbox bookmark contracts passed.")
  }

  private static func verifyPlaybackState() {
    var state = NowPlayingState()
    state.apply(NowPlayingUpdate(trackID: "a", epoch: 1, title: "First", isPlaying: true, duration: 120, position: 30))
    state.apply(NowPlayingUpdate(position: 10))
    precondition(state.position == 30, "Late progress must not undo a newer position")
    state.apply(NowPlayingUpdate(epoch: 2, isPlaying: false, position: 10))
    precondition(
      state.position == 10 && state.title == "First", "A seek epoch accepts a new position and keeps metadata")

    let publisher = NowPlayingInfoPublisher()
    let info = publisher.buildInfo(state: state, artwork: nil)
    precondition(info[MPMediaItemPropertyTitle] as? String == "First")
    precondition(info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double == 10)
    precondition(info[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 0)
    precondition(info[MPMediaItemPropertyPlaybackDuration] as? Double == 120)

    state.apply(NowPlayingUpdate(trackID: "b", title: "Second", isPlaying: true, position: 0))
    precondition(state.position == 0, "Changing tracks resets the position acceptance window")
    state.apply(NowPlayingUpdate(epoch: 3, position: .nan))
    precondition(state.position == 0, "Invalid elapsed time must never reach MediaPlayer")
  }

  private static func verifyDirectoryLifetimes() throws {
    var saved: [String: Data] = [:]
    var started: [URL] = []
    var stopped: [URL] = []
    let store = DirectoryBookmarkStore(load: { saved }, save: { saved = $0 })
    let original = URL(fileURLWithPath: "/original é", isDirectory: true)
    let moved = URL(fileURLWithPath: "/moved é", isDirectory: true)
    let access = SecurityScopedDirectories(
      store: store, resolve: { _ in (moved, true) }, bookmark: { Data($0.path.utf8) },
      startAccess: {
        started.append($0)
        return true
      }, stopAccess: { stopped.append($0) })

    let selected = try access.retainAccess(to: original)
    precondition(selected == original.path)
    _ = try access.retainAccess(to: original)
    precondition(started.count == 1, "Repeated selection must not leak another access claim")
    access.close()
    precondition(stopped == [original])

    let restored = access.restore()
    precondition(restored.paths[original.path] == moved.path)
    precondition(restored.unavailable.isEmpty)
    precondition(saved[original.path] == Data(moved.path.utf8), "Stale bookmarks must be refreshed")
    precondition(saved[moved.path] != nil, "Keep the resolved path for next-launch permission failures")
    _ = access.restore()
    precondition(started.count == 2, "Restoration is idempotent for an active grant")
    access.close()
    access.close()
    precondition(stopped == [original, moved], "Every acquired scope is stopped exactly once")
  }

  private static func verifyFailedRestoration() {
    let url = URL(fileURLWithPath: "/disconnected", isDirectory: true)
    var saved = [url.path: Data([1])]
    var stopped = 0
    let store = DirectoryBookmarkStore(load: { saved }, save: { saved = $0 })
    let access = SecurityScopedDirectories(
      store: store, resolve: { _ in (url, true) }, bookmark: { _ in throw CocoaError(.fileWriteNoPermission) },
      startAccess: { _ in true }, stopAccess: { _ in stopped += 1 })

    let restored = access.restore()
    precondition(restored.paths.isEmpty && restored.unavailable == [url.path])
    precondition(stopped == 1, "Failed refresh must release its temporary access claim")
    precondition(saved[url.path] != nil, "Keep unavailable bookmarks for reconnecting a volume")
    access.close()
    precondition(stopped == 1)
  }
}
