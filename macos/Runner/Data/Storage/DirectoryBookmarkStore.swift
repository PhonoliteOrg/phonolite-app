import Foundation

/// Persistent grants are separate from the active security-scoped URL lifetime.
final class DirectoryBookmarkStore {
  private let load: () -> [String: Data]
  private let save: ([String: Data]) -> Void

  convenience init(defaults: UserDefaults = .standard) {
    let key = "phonolite.storage.directory-bookmarks"

    self.init(
      load: { defaults.dictionary(forKey: key) as? [String: Data] ?? [:] }, save: { defaults.set($0, forKey: key) })
  }

  init(load: @escaping () -> [String: Data], save: @escaping ([String: Data]) -> Void) {
    self.load = load
    self.save = save
  }

  func read() -> [String: Data] { return load() }

  func write(_ bookmarks: [String: Data]) { save(bookmarks) }
}
