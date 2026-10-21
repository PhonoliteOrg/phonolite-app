import Flutter

enum CarPlayCodec {
  static let stateMethod = "getCarPlayState"

  static func decodeSourceState(_ result: Any?) -> CarPlaySourceState {
    let payload = result as? [String: Any]

    return CarPlaySourceState(
      serverAvailable: payload?["serverAvailable"] as? Bool ?? false,
      localAvailable: payload?["localAvailable"] as? Bool ?? false,
      hasAnySource: payload?["hasAnySource"] as? Bool ?? false
    )
  }

  static func decodeList(_ result: Any?) -> CarPlayListResult {
    if let error = result as? FlutterError {
      return CarPlayListResult(items: [], error: error.message ?? "error")
    }

    guard let payload = result as? [String: Any] else {
      return CarPlayListResult(items: [], error: "bad_response")
    }

    let rawItems = payload["items"] as? [[String: Any]] ?? []
    let items = rawItems.compactMap(decodeItem)

    return CarPlayListResult(items: items, error: payload["error"] as? String)
  }

  static func method(for request: CarPlayListRequest) -> String {
    switch request {
    case .artists:
      return "getArtists"
    case .albums:
      return "getAlbums"
    case .playlists:
      return "getPlaylists"
    }
  }

  static func arguments(for request: CarPlayListRequest) -> [String: Any] {
    switch request {
    case .artists(let scope), .playlists(let scope):
      return ["scope": scope.rawValue]
    case .albums(let scope, let artistID):
      return ["scope": scope.rawValue, "artistId": artistID]
    }
  }

  static func method(for command: CarPlayCommand) -> String {
    switch command {
    case .playLiked:
      return "playLiked"
    case .startLibraryShuffle:
      return "startShuffle"
    case .playAlbum:
      return "playAlbum"
    case .playPlaylist:
      return "playPlaylist"
    }
  }

  static func arguments(for command: CarPlayCommand) -> [String: Any] {
    switch command {
    case .playLiked(let scope):
      return ["scope": scope.rawValue]
    case .startLibraryShuffle(let scope):
      return ["scope": scope.rawValue, "kind": "library"]
    case .playAlbum(let scope, let albumID):
      return ["scope": scope.rawValue, "albumId": albumID]
    case .playPlaylist(let scope, let playlistID):
      return ["scope": scope.rawValue, "playlistId": playlistID]
    }
  }

  private static func decodeItem(_ payload: [String: Any]) -> CarPlayItem? {
    let id = payload["id"] as? String ?? ""
    let title = payload["title"] as? String ?? ""

    guard !id.isEmpty, !title.isEmpty else {
      return nil
    }

    return CarPlayItem(
      id: id,
      title: title,
      subtitle: payload["subtitle"] as? String,
      enabled: payload["enabled"] as? Bool ?? true,
      artworkURL: payload["artworkUrl"] as? String,
      token: payload["token"] as? String,
      serverPin: payload["serverPin"] as? String
    )
  }
}
