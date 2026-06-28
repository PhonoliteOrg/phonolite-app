import CarPlay
import Flutter
import UIKit

@available(iOS 13.0, *)
class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
  private struct CarPlaySourceState: Equatable {
    var serverAvailable: Bool
    var localAvailable: Bool
    var hasAnySource: Bool

    static let empty = CarPlaySourceState(
      serverAvailable: false,
      localAvailable: false,
      hasAnySource: false
    )
  }

  private weak var interfaceController: CPInterfaceController?
  private var rootTemplate: CPTemplate?
  private var serverTemplate: CPListTemplate?
  private var localTemplate: CPListTemplate?
  private var emptyTemplate: CPListTemplate?
  private var loadingTemplate: CPListTemplate?
  private var tabBarTemplate: CPTabBarTemplate?
  private var nowPlayingItem: CPListItem?
  private let nowPlayingTemplate = CPNowPlayingTemplate.shared
  private var sourceState = CarPlaySourceState.empty

  private func refreshNowPlayingUI(force: Bool) {
    if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
      appDelegate.refreshNowPlayingForCarPlay(force: force)
    }
  }

  private func configureRootTemplate(using interfaceController: CPInterfaceController) {
    self.interfaceController = interfaceController
    nowPlayingItem = nil

    let template = buildLoadingTemplate()
    loadingTemplate = template
    rootTemplate = template
    if #available(iOS 14.0, *) {
      interfaceController.setRootTemplate(template, animated: false, completion: nil)
    } else {
      interfaceController.setRootTemplate(template, animated: false)
    }

    DispatchQueue.main.async {
      if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
        appDelegate.carPlaySceneDelegate = self
        appDelegate.refreshNowPlayingForCarPlay(force: true)
        appDelegate.configureCarPlayChannel()
      }

      self.requestCarPlayState(force: true)
    }
  }

  func updateCarPlayState(
    serverAvailable: Bool,
    localAvailable: Bool,
    hasAnySource: Bool,
    force: Bool = false
  ) {
    DispatchQueue.main.async { [weak self] in
      guard let self else {
        return
      }
      let next = CarPlaySourceState(
        serverAvailable: serverAvailable,
        localAvailable: localAvailable,
        hasAnySource: hasAnySource || serverAvailable || localAvailable
      )
      if !force && self.sourceState == next {
        return
      }
      self.sourceState = next
      self.showRootForCurrentState()
    }
  }

  func requestCarPlayState(force: Bool = false) {
    guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
      updateCarPlayState(
        serverAvailable: false,
        localAvailable: false,
        hasAnySource: false,
        force: force
      )
      return
    }
    appDelegate.invokeCarPlayMethod("getCarPlayState") { [weak self] result in
      guard let self else {
        return
      }
      let payload = result as? [String: Any]
      let serverAvailable = payload?["serverAvailable"] as? Bool ?? false
      let localAvailable = payload?["localAvailable"] as? Bool ?? false
      let hasAnySource = payload?["hasAnySource"] as? Bool ?? false
      self.updateCarPlayState(
        serverAvailable: serverAvailable,
        localAvailable: localAvailable,
        hasAnySource: hasAnySource,
        force: force
      )
    }
  }

  private func buildServerTemplate() -> CPListTemplate {
    return buildSourceTemplate(
      scope: "server",
      title: "Server",
      systemImageName: "antenna.radiowaves.left.and.right",
      fallback: .more
    )
  }

  private func buildLocalTemplate() -> CPListTemplate {
    return buildSourceTemplate(
      scope: "local",
      title: "Local",
      systemImageName: "arrow.down.circle",
      fallback: .bookmarks
    )
  }

  private func buildSourceTemplate(
    scope: String,
    title: String,
    systemImageName: String,
    fallback: UITabBarItem.SystemItem
  ) -> CPListTemplate {
    let template = CPListTemplate(
      title: title,
      sections: [CPListSection(items: buildSourceItems(scope: scope))]
    )
    configureTab(template, title: title, systemImageName: systemImageName, fallback: fallback)
    return template
  }

  private func buildEmptyTemplate() -> CPListTemplate {
    let item = disabledItem(
      text: "Nothing available in CarPlay",
      detail: "Connect to a server or download tracks in Phonolite"
    )
    let template = CPListTemplate(
      title: "Phonolite",
      sections: [CPListSection(items: [item])]
    )
    return template
  }

  private func buildLoadingTemplate() -> CPListTemplate {
    let template = CPListTemplate(
      title: "Phonolite",
      sections: [CPListSection(items: [disabledItem(text: "Loading...")])]
    )
    return template
  }

  private func buildSourceItems(scope: String) -> [CPListItem] {
    let localScope = scope == "local"
    let sourceName = localScope ? "Local" : "Server"
    let libraryItem = CPListItem(
      text: "\(sourceName) Library",
      detailText: localScope ? "Browse downloaded artists" : "Browse server artists"
    )
    libraryItem.setImage(
      carPlaySymbol(named: localScope ? "arrow.down.circle" : "music.mic")
    )
    libraryItem.handler = { [weak self] _, completion in
      self?.showArtistsList(scope: scope)
      completion()
    }

    let playlistsItem = CPListItem(
      text: "\(sourceName) Playlists",
      detailText: localScope ? "Play downloaded playlists" : "Pick a server playlist"
    )
    playlistsItem.setImage(carPlaySymbol(named: "music.note.list"))
    playlistsItem.handler = { [weak self] _, completion in
      self?.showPlaylistsList(scope: scope)
      completion()
    }

    let likedItem = CPListItem(
      text: "\(sourceName) Liked Songs",
      detailText: "Play from the top"
    )
    likedItem.setImage(carPlaySymbol(named: "heart.fill"))
    likedItem.handler = { [weak self] _, completion in
      if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
        appDelegate.invokeCarPlayMethod("playLiked", arguments: ["scope": scope])
      }
      self?.showNowPlaying(animated: true)
      completion()
    }

    let shuffleItem = CPListItem(
      text: "\(sourceName) Shuffle",
      detailText: localScope ? "Shuffle downloaded tracks" : "Shuffle server library"
    )
    shuffleItem.setImage(carPlaySymbol(named: "shuffle"))
    shuffleItem.handler = { [weak self] _, completion in
      if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
        appDelegate.invokeCarPlayMethod(
          "startShuffle",
          arguments: ["scope": scope, "kind": "library"]
        )
      }
      self?.showNowPlaying(animated: true)
      completion()
    }

    return [libraryItem, playlistsItem, likedItem, shuffleItem]
  }

  private func showArtistsList(scope: String) {
    guard interfaceController != nil else {
      return
    }
    let template = CPListTemplate(
      title: scope == "local" ? "Downloaded Artists" : "Artists",
      sections: [CPListSection(items: [disabledItem(text: "Loading artists...")])]
    )
    pushTemplate(template, animated: true)

    requestCarPlayList(method: "getArtists", arguments: ["scope": scope]) { [weak self] entries, error in
      guard let self else {
        return
      }
      let items = self.buildListItems(
        entries: entries,
        emptyText: scope == "local" ? "No downloaded artists" : "No artists found",
        errorText: scope == "local" ? "No downloaded artists" : "Connect to a server",
        error: error
      ) { entry in
        self.showAlbumsList(scope: scope, artistId: entry.id, title: entry.title)
      }
      self.updateListTemplate(template, items: items)
    }
  }

  private func showAlbumsList(scope: String, artistId: String, title: String) {
    guard interfaceController != nil else {
      return
    }
    let template = CPListTemplate(
      title: title,
      sections: [CPListSection(items: [disabledItem(text: "Loading albums...")])]
    )
    pushTemplate(template, animated: true)

    requestCarPlayList(
      method: "getAlbums",
      arguments: ["scope": scope, "artistId": artistId]
    ) { [weak self] entries, error in
      guard let self else {
        return
      }
      let items = self.buildListItems(
        entries: entries,
        emptyText: "No albums found",
        errorText: scope == "local" ? "No downloaded albums" : "Connect to a server",
        error: error
      ) { entry in
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
          appDelegate.invokeCarPlayMethod(
            "playAlbum",
            arguments: ["scope": scope, "albumId": entry.id]
          )
        }
        self.showNowPlaying(animated: true)
      }
      self.updateListTemplate(template, items: items)
    }
  }

  private func showPlaylistsList(scope: String) {
    guard interfaceController != nil else {
      return
    }
    let template = CPListTemplate(
      title: scope == "local" ? "Local Playlists" : "Playlists",
      sections: [CPListSection(items: [disabledItem(text: "Loading playlists...")])]
    )
    pushTemplate(template, animated: true)

    requestCarPlayList(method: "getPlaylists", arguments: ["scope": scope]) { [weak self] entries, error in
      guard let self else {
        return
      }
      let items = self.buildListItems(
        entries: entries,
        emptyText: scope == "local" ? "No local playlists" : "No playlists found",
        errorText: scope == "local" ? "No local playlists" : "Connect to a server",
        error: error
      ) { entry in
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
          appDelegate.invokeCarPlayMethod(
            "playPlaylist",
            arguments: ["scope": scope, "playlistId": entry.id]
          )
        }
        self.showNowPlaying(animated: true)
      }
      self.updateListTemplate(template, items: items)
    }
  }

  private func requestCarPlayList(
    method: String,
    arguments: [String: Any]? = nil,
    completion: @escaping (
      [(id: String, title: String, subtitle: String?, enabled: Bool, artworkUrl: String?, token: String?)],
      String?
    ) -> Void
  ) {
    guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
      completion([], "unavailable")
      return
    }
    appDelegate.invokeCarPlayMethod(method, arguments: arguments) { result in
      let parsed = self.parseCarPlayList(result)
      DispatchQueue.main.async {
        completion(parsed.items, parsed.error)
      }
    }
  }

  private func parseCarPlayList(
    _ result: Any?
  ) -> (
    items: [
      (id: String, title: String, subtitle: String?, enabled: Bool, artworkUrl: String?, token: String?)
    ],
    error: String?
  ) {
    if let error = result as? FlutterError {
      return ([], error.message ?? "error")
    }
    guard let payload = result as? [String: Any] else {
      return ([], "bad_response")
    }
    let error = payload["error"] as? String
    let rawItems = payload["items"] as? [[String: Any]] ?? []
    let items: [
      (id: String, title: String, subtitle: String?, enabled: Bool, artworkUrl: String?, token: String?)
    ] = rawItems.compactMap { item in
      let id = item["id"] as? String ?? ""
      let title = item["title"] as? String ?? ""
      let subtitle = item["subtitle"] as? String
      let enabled = item["enabled"] as? Bool ?? true
      let artworkUrl = item["artworkUrl"] as? String
      let token = item["token"] as? String
      if id.isEmpty || title.isEmpty {
        return nil
      }
      return (
        id: id,
        title: title,
        subtitle: subtitle,
        enabled: enabled,
        artworkUrl: artworkUrl,
        token: token
      )
    }
    return (items, error)
  }

  private func buildListItems(
    entries: [
      (id: String, title: String, subtitle: String?, enabled: Bool, artworkUrl: String?, token: String?)
    ],
    emptyText: String,
    errorText: String,
    error: String?,
    onSelect: @escaping (
      (id: String, title: String, subtitle: String?, enabled: Bool, artworkUrl: String?, token: String?)
    ) -> Void
  ) -> [CPListItem] {
    if let error, !error.isEmpty {
      return [disabledItem(text: errorText)]
    }
    if entries.isEmpty {
      return [disabledItem(text: emptyText)]
    }
    return entries.map { entry in
      let item = CPListItem(text: entry.title, detailText: entry.subtitle)
      if let artworkUrl = entry.artworkUrl, !artworkUrl.isEmpty {
        fetchCarPlayImage(urlString: artworkUrl, token: entry.token) { image in
          if let image {
            item.setImage(image)
          }
        }
      }
      item.isEnabled = entry.enabled
      if entry.enabled {
        item.handler = { _, completion in
          onSelect(entry)
          completion()
        }
      }
      return item
    }
  }

  private func disabledItem(text: String, detail: String? = nil) -> CPListItem {
    let item = CPListItem(text: text, detailText: detail)
    item.isEnabled = false
    return item
  }

  private func updateListTemplate(_ template: CPListTemplate, items: [CPListItem]) {
    let section = CPListSection(items: items)
    if #available(iOS 14.0, *) {
      template.updateSections([section])
    }
  }

  private func fetchCarPlayImage(
    urlString: String,
    token: String?,
    completion: @escaping (UIImage?) -> Void
  ) {
    guard let url = URL(string: urlString) else {
      completion(nil)
      return
    }
    if url.isFileURL {
      DispatchQueue.global(qos: .utility).async {
        let image: UIImage?
        if let data = try? Data(contentsOf: url) {
          image = UIImage(data: data)
        } else {
          image = nil
        }
        DispatchQueue.main.async {
          completion(image)
        }
      }
      return
    }
    var request = URLRequest(url: url)
    if let token, !token.isEmpty {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    URLSession.shared.dataTask(with: request) { data, _, _ in
      if let data, let image = UIImage(data: data) {
        DispatchQueue.main.async {
          completion(image)
        }
      } else {
        DispatchQueue.main.async {
          completion(nil)
        }
      }
    }.resume()
  }

  private func pushTemplate(_ template: CPTemplate, animated: Bool) {
    guard let interfaceController else {
      return
    }
    if #available(iOS 14.0, *) {
      interfaceController.pushTemplate(template, animated: animated, completion: { _, _ in })
    } else {
      interfaceController.pushTemplate(template, animated: animated)
    }
  }

  private func showNowPlaying(animated: Bool) {
    guard let interfaceController else {
      return
    }
    if interfaceController.topTemplate === nowPlayingTemplate {
      return
    }
    if #available(iOS 14.0, *) {
      interfaceController.pushTemplate(nowPlayingTemplate, animated: animated, completion: { _, _ in })
    } else {
      interfaceController.pushTemplate(nowPlayingTemplate, animated: animated)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
      self?.refreshNowPlayingUI(force: true)
    }
  }

  func updateNowPlayingListItem(
    title: String?,
    artist: String?,
    album: String?,
    artwork: UIImage?
  ) {
    guard #available(iOS 14.0, *) else {
      return
    }
    guard let item = nowPlayingItem else {
      return
    }
    let cleanTitle = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanArtist = (artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanAlbum = (album ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let displayTitle = cleanTitle.isEmpty ? "Now Playing" : cleanTitle
    var detail = ""
    if !cleanArtist.isEmpty && !cleanAlbum.isEmpty {
      detail = "\(cleanArtist) - \(cleanAlbum)"
    } else if !cleanArtist.isEmpty {
      detail = cleanArtist
    } else if !cleanAlbum.isEmpty {
      detail = cleanAlbum
    } else {
      detail = "Tap to open"
    }
    DispatchQueue.main.async {
      item.setText(displayTitle)
      item.setDetailText(detail)
      if let artwork {
        item.setImage(artwork)
      } else {
        item.setImage(nil)
      }
    }
  }

  func clearNowPlayingListItem() {
    guard #available(iOS 14.0, *) else {
      return
    }
    guard let item = nowPlayingItem else {
      return
    }
    DispatchQueue.main.async {
      item.setText("Now Playing")
      item.setDetailText("Tap to open")
      item.setImage(nil)
    }
  }

  func updateNowPlayingButtons(liked: Bool, available: Bool) {
    guard #available(iOS 14.0, *) else {
      return
    }
    DispatchQueue.main.async { [weak self] in
      guard let self else {
        return
      }
      if !available {
        self.nowPlayingTemplate.updateNowPlayingButtons([])
        return
      }
      let imageName = liked ? "heart.fill" : "heart"
      guard let image = carPlaySymbol(named: imageName) else {
        self.nowPlayingTemplate.updateNowPlayingButtons([])
        return
      }
      let button = CPNowPlayingImageButton(image: image) { _ in
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
          appDelegate.sendRemoteCommandToFlutter("toggleLike")
        }
      }
      self.nowPlayingTemplate.updateNowPlayingButtons([button])
    }
  }

  func updateNowPlayingVisibility(hasTrack _: Bool) {}

  private func showRootForCurrentState() {
    guard let interfaceController else {
      return
    }
    serverTemplate = nil
    localTemplate = nil
    emptyTemplate = nil
    loadingTemplate = nil
    tabBarTemplate = nil

    if !sourceState.hasAnySource {
      let template = buildEmptyTemplate()
      emptyTemplate = template
      rootTemplate = template
      if #available(iOS 14.0, *) {
        interfaceController.setRootTemplate(template, animated: false, completion: nil)
      } else {
        interfaceController.setRootTemplate(template, animated: false)
      }
      return
    }

    var templates: [CPTemplate] = []
    if sourceState.serverAvailable {
      let server = buildServerTemplate()
      serverTemplate = server
      templates.append(server)
    }
    if sourceState.localAvailable {
      let local = buildLocalTemplate()
      localTemplate = local
      templates.append(local)
    }

    if #available(iOS 14.0, *), templates.count > 1 {
      let tabBar = CPTabBarTemplate(templates: templates)
      tabBarTemplate = tabBar
      rootTemplate = tabBar
      interfaceController.setRootTemplate(tabBar, animated: false, completion: nil)
      refreshTabBarTemplates()
    } else {
      guard let template = templates.first else {
        return
      }
      rootTemplate = template
      if #available(iOS 14.0, *) {
        interfaceController.setRootTemplate(template, animated: false, completion: nil)
      } else {
        interfaceController.setRootTemplate(template, animated: false)
      }
    }
  }

  private func configureTab(
    _ template: CPTemplate,
    title: String,
    systemImageName: String,
    fallback: UITabBarItem.SystemItem
  ) {
    if #available(iOS 14.0, *) {
      template.tabTitle = title
      if let image = carPlaySymbol(named: systemImageName) {
        template.tabImage = image
      } else {
        template.tabSystemItem = fallback
      }
    }
  }

  private func carPlaySymbol(named systemName: String) -> UIImage? {
    return UIImage(systemName: systemName)?.withRenderingMode(.alwaysTemplate)
  }

  private func refreshTabBarTemplates() {
    guard #available(iOS 14.0, *), let tabBarTemplate else {
      return
    }
    var templates: [CPTemplate] = []
    if let serverTemplate {
      configureTab(
        serverTemplate,
        title: "Server",
        systemImageName: "antenna.radiowaves.left.and.right",
        fallback: .more
      )
      templates.append(serverTemplate)
    }
    if let localTemplate {
      configureTab(localTemplate, title: "Local", systemImageName: "arrow.down.circle", fallback: .bookmarks)
      templates.append(localTemplate)
    }
    DispatchQueue.main.async { [weak tabBarTemplate] in
      tabBarTemplate?.updateTemplates(templates)
    }
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController,
    to window: CPWindow
  ) {
    configureRootTemplate(using: interfaceController)
  }

  @available(iOS 14.0, *)
  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController
  ) {
    configureRootTemplate(using: interfaceController)
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnect interfaceController: CPInterfaceController,
    from window: CPWindow
  ) {
    handleDisconnect(interfaceController)
  }

  @available(iOS 14.0, *)
  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnect interfaceController: CPInterfaceController
  ) {
    handleDisconnect(interfaceController)
  }

  private func handleDisconnect(_ interfaceController: CPInterfaceController) {
    if self.interfaceController === interfaceController {
      self.interfaceController = nil
    }
    rootTemplate = nil
    serverTemplate = nil
    localTemplate = nil
    emptyTemplate = nil
    loadingTemplate = nil
    tabBarTemplate = nil
    nowPlayingItem = nil
    sourceState = .empty
    if let appDelegate = UIApplication.shared.delegate as? AppDelegate,
       appDelegate.carPlaySceneDelegate === self {
      appDelegate.carPlaySceneDelegate = nil
    }
  }
}
