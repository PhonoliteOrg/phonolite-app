import Foundation

/// Main-thread ownership of user-selected directories, retained until the engine closes.
final class SecurityScopedDirectories {
  private let store: DirectoryBookmarkStore
  private let resolve: (Data) throws -> (url: URL, stale: Bool)
  private let bookmark: (URL) throws -> Data
  private let startAccess: (URL) -> Bool
  private let stopAccess: (URL) -> Void
  private var active: [String: URL] = [:]
  private var accessed: Set<URL> = []

  init(
    store: DirectoryBookmarkStore = DirectoryBookmarkStore(),
    resolve: @escaping (Data) throws -> (url: URL, stale: Bool) = { data in
      var stale = false
      let url = try URL(
        resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], bookmarkDataIsStale: &stale)

      return (url, stale)
    },
    bookmark: @escaping (URL) throws -> Data = {
      try $0.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }, startAccess: @escaping (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
    stopAccess: @escaping (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }
  ) {
    self.store = store
    self.resolve = resolve
    self.bookmark = bookmark
    self.startAccess = startAccess
    self.stopAccess = stopAccess
  }

  deinit { close() }

  func restore() -> (paths: [String: String], unavailable: [String]) {
    var bookmarks = store.read()
    var paths: [String: String] = [:]
    var unavailable: [String] = []

    for (path, data) in bookmarks {
      if let url = active[path] {
        paths[path] = url.path

        continue
      }

      do {
        let restored = try resolve(data)
        let alreadyAccessed = accessed.contains(restored.url)
        guard alreadyAccessed || startAccess(restored.url) else {
          unavailable.append(path)

          continue
        }

        do { bookmarks[path] = restored.stale ? try bookmark(restored.url) : data } catch {
          if !alreadyAccessed { stopAccess(restored.url) }

          throw error
        }

        active[path] = restored.url
        active[restored.url.path] = restored.url
        accessed.insert(restored.url)
        // Keep the last resolved spelling too: saved settings use this path
        // after a move, including when the volume is unavailable next launch.
        bookmarks[restored.url.path] = bookmarks[path]
        paths[path] = restored.url.path
      } catch {
        // Keep unavailable grants so removable volumes can be restored later.
        unavailable.append(path)
      }
    }

    store.write(bookmarks)

    return (paths, unavailable)
  }

  func retainAccess(to url: URL) throws -> String {
    let path = url.path
    let data = try bookmark(url)

    if active[path] != url {
      guard accessed.contains(url) || startAccess(url) else { throw CocoaError(.fileReadNoPermission) }

      active[path] = url
      accessed.insert(url)
    }

    var bookmarks = store.read()
    bookmarks[path] = data
    store.write(bookmarks)

    return path
  }

  func close() {
    for url in accessed { stopAccess(url) }

    active.removeAll()
    accessed.removeAll()
  }
}
