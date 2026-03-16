import CarPlay
import Flutter
import UIKit

@available(iOS 13.0, *)
class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
  private weak var interfaceController: CPInterfaceController?
  private var rootTemplate: CPTemplate?
  private var homeTemplate: CPListTemplate?
  private var libraryTemplate: CPListTemplate?
  private var loggedOutTemplate: CPListTemplate?
  private var tabBarTemplate: CPTabBarTemplate?
  private var nowPlayingItem: CPListItem?
  private let nowPlayingTemplate = CPNowPlayingTemplate.shared
  private var nowPlayingButtonVisible = false
  private var isAuthorized = false

  private func refreshNowPlayingUI(force: Bool) {
    if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
      appDelegate.refreshNowPlayingForCarPlay(force: force)
    }
  }

  private func configureRootTemplate(using interfaceController: CPInterfaceController) {
    self.interfaceController = interfaceController
    DispatchQueue.main.async {
      if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
        appDelegate.carPlaySceneDelegate = self
        appDelegate.refreshNowPlayingForCarPlay(force: true)
        appDelegate.configureCarPlayChannel()
      }

      self.nowPlayingItem = nil
      self.updateAuthState(authorized: false, force: true)
      self.requestAuthState()
    }
  }

  private func buildHomeTemplate() -> CPListTemplate {
    let template = CPListTemplate(
      title: "Home",
      sections: [CPListSection(items: [disabledItem(text: "Loading...")])]
    )
    setNowPlayingButtonVisible(template, visible: nowPlayingButtonVisible)
    configureTab(template, title: "Home", systemImageName: "house", fallback: .featured)
    requestCarPlayList(method: "getHomeActions") { [weak self] entries, error in
      guard let self else {
        return
      }
      let items = self.buildListItems(
        entries: entries,
        emptyText: "No actions available",
        errorText: "Connect to a server",
        error: error
      ) { entry in
        self.handleHomeAction(entry.id)
      }
      items.forEach { item in
        switch item.text {
        case "Start Library Shuffle":
          item.setImage(UIImage(systemName: "shuffle"))
        case "Start Liked Shuffle":
          item.setImage(UIImage(systemName: "heart.fill"))
        case "Start Custom Shuffle":
          item.setImage(UIImage(systemName: "line.3.horizontal.decrease.circle"))
        default:
          break
        }
      }
      self.updateListTemplate(template, items: items)
    }
    return template
  }

  private func buildLibraryTemplate() -> CPListTemplate {
    let template = CPListTemplate(
      title: "Library",
      sections: [CPListSection(items: buildLibraryItems(likedEnabled: false, likedSubtitle: "Loading..."))]
    )
    setNowPlayingButtonVisible(template, visible: nowPlayingButtonVisible)
    configureTab(
      template,
      title: "Library",
      systemImageName: "music.note.list",
      fallback: .bookmarks
    )
    requestCarPlayStatus { [weak self] status in
      guard let self else {
        return
      }
      let enabled = status.likedAvailable
      let subtitle: String
      if let error = status.error, !error.isEmpty {
        subtitle = "Connect to a server"
      } else if enabled {
        subtitle = "Play from the top"
      } else {
        subtitle = "No liked songs yet"
      }
      let items = self.buildLibraryItems(likedEnabled: enabled, likedSubtitle: subtitle)
      self.updateListTemplate(template, items: items)
    }
    return template
  }

  private func buildLoggedOutTemplate() -> CPListTemplate {
    let item = disabledItem(
      text: "Not logged into server",
      detail: "Open Phonolite to log in"
    )
    let template = CPListTemplate(
      title: "Phonolite",
      sections: [CPListSection(items: [item])]
    )
    setNowPlayingButtonVisible(template, visible: false)
    return template
  }

  private func buildLibraryItems(
    likedEnabled: Bool,
    likedSubtitle: String
  ) -> [CPListItem] {
    let artistsItem = CPListItem(text: "Artists", detailText: "Browse artists")
    artistsItem.setImage(UIImage(systemName: "music.mic"))
    artistsItem.handler = { [weak self] _, completion in
      self?.showArtistsList()
      completion()
    }

    let playlistsItem = CPListItem(text: "Playlists", detailText: "Pick a playlist")
    playlistsItem.setImage(UIImage(systemName: "music.note.list"))
    playlistsItem.handler = { [weak self] _, completion in
      self?.showPlaylistsList()
      completion()
    }

    let likedItem = CPListItem(text: "Liked Songs", detailText: likedSubtitle)
    likedItem.setImage(UIImage(systemName: "heart.fill"))
    likedItem.isEnabled = likedEnabled
    if likedEnabled {
      likedItem.handler = { [weak self] _, completion in
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
          appDelegate.invokeCarPlayMethod("playLiked")
        }
        self?.showNowPlaying(animated: true)
        completion()
      }
    }
    return [artistsItem, playlistsItem, likedItem]
  }

  private func handleHomeAction(_ actionId: String) {
    guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
      return
    }
    switch actionId {
    case "startLibraryShuffle":
      appDelegate.invokeCarPlayMethod("startLibraryShuffle")
    case "startLikedShuffle":
      appDelegate.invokeCarPlayMethod("startLikedShuffle")
    case "startCustomShuffle":
      appDelegate.invokeCarPlayMethod("startCustomShuffle")
    default:
      return
    }
    showNowPlaying(animated: true)
  }

  private func showArtistsList() {
    guard interfaceController != nil else {
      return
    }
    let template = CPListTemplate(
      title: "Artists",
      sections: [CPListSection(items: [disabledItem(text: "Loading artists...")])]
    )
    setNowPlayingButtonVisible(template, visible: nowPlayingButtonVisible)
    pushTemplate(template, animated: true)

    requestCarPlayList(method: "getArtists") { [weak self] entries, error in
      guard let self else {
        return
      }
      let items = self.buildListItems(
        entries: entries,
        emptyText: "No artists found",
        errorText: "Connect to a server",
        error: error
      ) { entry in
        self.showAlbumsList(artistId: entry.id, title: entry.title)
      }
      self.updateListTemplate(template, items: items)
    }
  }

  private func showAlbumsList(artistId: String, title: String) {
    guard interfaceController != nil else {
      return
    }
    let template = CPListTemplate(
      title: title,
      sections: [CPListSection(items: [disabledItem(text: "Loading albums...")])]
    )
    setNowPlayingButtonVisible(template, visible: nowPlayingButtonVisible)
    pushTemplate(template, animated: true)

    requestCarPlayList(method: "getAlbums", arguments: ["artistId": artistId]) { [weak self] entries, error in
      guard let self else {
        return
      }
      let items = self.buildListItems(
        entries: entries,
        emptyText: "No albums found",
        errorText: "Connect to a server",
        error: error
      ) { entry in
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
          appDelegate.invokeCarPlayMethod("playAlbum", arguments: ["albumId": entry.id])
        }
        self.showNowPlaying(animated: true)
      }
      self.updateListTemplate(template, items: items)
    }
  }

  private func showPlaylistsList() {
    guard interfaceController != nil else {
      return
    }
    let template = CPListTemplate(
      title: "Playlists",
      sections: [CPListSection(items: [disabledItem(text: "Loading playlists...")])]
    )
    setNowPlayingButtonVisible(template, visible: nowPlayingButtonVisible)
    pushTemplate(template, animated: true)

    requestCarPlayList(method: "getPlaylists") { [weak self] entries, error in
      guard let self else {
        return
      }
      let items = self.buildListItems(
        entries: entries,
        emptyText: "No playlists found",
        errorText: "Connect to a server",
        error: error
      ) { entry in
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
          appDelegate.invokeCarPlayMethod("playPlaylist", arguments: ["playlistId": entry.id])
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

  private func requestCarPlayStatus(
    completion: @escaping ((likedAvailable: Bool, error: String?)) -> Void
  ) {
    guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
      completion((likedAvailable: false, error: "unavailable"))
      return
    }
    appDelegate.invokeCarPlayMethod("getLibraryStatus") { result in
      var likedAvailable = false
      var error: String?
      if let payload = result as? [String: Any] {
        likedAvailable = payload["likedAvailable"] as? Bool ?? false
        error = payload["error"] as? String
      } else if let flutterError = result as? FlutterError {
        error = flutterError.message
      }
      DispatchQueue.main.async {
        completion((likedAvailable: likedAvailable, error: error))
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
      guard let image = UIImage(systemName: imageName) else {
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

  func updateAuthState(authorized: Bool, force: Bool = false) {
    DispatchQueue.main.async { [weak self] in
      guard let self else {
        return
      }
      if !force && self.isAuthorized == authorized {
        return
      }
      self.isAuthorized = authorized
      if authorized {
        self.showAuthorizedRoot()
      } else {
        self.showLoggedOutRoot()
      }
    }
  }

  private func requestAuthState() {
    guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
      return
    }
    appDelegate.invokeCarPlayMethod("getAuthState") { [weak self] result in
      guard let self else {
        return
      }
      var authorized = false
      if let payload = result as? [String: Any] {
        authorized = payload["authorized"] as? Bool ?? false
      }
      self.updateAuthState(authorized: authorized)
    }
  }

  private func showAuthorizedRoot() {
    guard let interfaceController else {
      return
    }
    let homeTemplate = buildHomeTemplate()
    let libraryTemplate = buildLibraryTemplate()
    self.homeTemplate = homeTemplate
    self.libraryTemplate = libraryTemplate
    self.loggedOutTemplate = nil
    applyNowPlayingButtonVisibility()
    if #available(iOS 14.0, *) {
      let tabBar = CPTabBarTemplate(templates: [homeTemplate, libraryTemplate])
      tabBarTemplate = tabBar
      rootTemplate = tabBar
      interfaceController.setRootTemplate(tabBar, animated: false, completion: nil)
      refreshTabBarTemplates()
    } else {
      rootTemplate = homeTemplate
      interfaceController.setRootTemplate(homeTemplate, animated: false)
    }
  }

  private func showLoggedOutRoot() {
    guard let interfaceController else {
      return
    }
    nowPlayingButtonVisible = false
    applyNowPlayingButtonVisibility()
    let template = loggedOutTemplate ?? buildLoggedOutTemplate()
    loggedOutTemplate = template
    homeTemplate = nil
    libraryTemplate = nil
    tabBarTemplate = nil
    rootTemplate = template
    if #available(iOS 14.0, *) {
      interfaceController.setRootTemplate(template, animated: false, completion: nil)
    } else {
      interfaceController.setRootTemplate(template, animated: false)
    }
  }

  func updateNowPlayingVisibility(hasTrack: Bool) {
    DispatchQueue.main.async { [weak self] in
      guard let self else {
        return
      }
      self.nowPlayingButtonVisible = self.isAuthorized && hasTrack
      self.applyNowPlayingButtonVisibility()
    }
  }

  private func applyNowPlayingButtonVisibility() {
    setNowPlayingButtonVisible(homeTemplate, visible: nowPlayingButtonVisible)
    setNowPlayingButtonVisible(libraryTemplate, visible: nowPlayingButtonVisible)
    setNowPlayingButtonVisible(loggedOutTemplate, visible: nowPlayingButtonVisible)
    if let topTemplate = interfaceController?.topTemplate {
      setNowPlayingButtonVisible(topTemplate, visible: nowPlayingButtonVisible)
    }
  }

  private func setNowPlayingButtonVisible(_ template: CPTemplate?, visible: Bool) {
    guard let template else {
      return
    }
    let selector = Selector(("setShowsNowPlayingButton:"))
    if template.responds(to: selector) {
      template.setValue(visible, forKey: "showsNowPlayingButton")
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
      if let image = UIImage(systemName: systemImageName) {
        template.tabImage = image
      } else {
        template.tabSystemItem = fallback
      }
    }
  }

  private func refreshTabBarTemplates() {
    guard #available(iOS 14.0, *),
          let tabBarTemplate,
          let homeTemplate,
          let libraryTemplate else {
      return
    }
    configureTab(homeTemplate, title: "Home", systemImageName: "house", fallback: .featured)
    configureTab(
      libraryTemplate,
      title: "Library",
      systemImageName: "music.note.list",
      fallback: .bookmarks
    )
    DispatchQueue.main.async { [weak tabBarTemplate] in
      tabBarTemplate?.updateTemplates([homeTemplate, libraryTemplate])
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
    if self.interfaceController === interfaceController {
      self.interfaceController = nil
    }
    rootTemplate = nil
    homeTemplate = nil
    libraryTemplate = nil
    loggedOutTemplate = nil
    tabBarTemplate = nil
    nowPlayingItem = nil
    if let appDelegate = UIApplication.shared.delegate as? AppDelegate,
       appDelegate.carPlaySceneDelegate === self {
      appDelegate.carPlaySceneDelegate = nil
    }
  }

  @available(iOS 14.0, *)
  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnect interfaceController: CPInterfaceController
  ) {
    if self.interfaceController === interfaceController {
      self.interfaceController = nil
    }
    rootTemplate = nil
    homeTemplate = nil
    libraryTemplate = nil
    loggedOutTemplate = nil
    tabBarTemplate = nil
    nowPlayingItem = nil
    if let appDelegate = UIApplication.shared.delegate as? AppDelegate,
       appDelegate.carPlaySceneDelegate === self {
      appDelegate.carPlaySceneDelegate = nil
    }
  }
}
