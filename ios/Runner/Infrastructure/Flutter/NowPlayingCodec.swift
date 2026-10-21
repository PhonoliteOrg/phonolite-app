import Foundation

import Flutter

/// Preserve the channel's mixed patch/replacement semantics while decoding once.
enum NowPlayingCodec {
  static func decode(_ args: [String: Any]) -> NowPlayingUpdate {
    return NowPlayingUpdate(
      trackID: args["trackId"] as? String,
      epoch: args["epoch"] as? Int,
      title: args["title"] as? String,
      artist: args["artist"] as? String,
      album: args["album"] as? String,
      isPlaying: parseBool(args["isPlaying"]),
      liked: parseBool(args["liked"]),
      duration: parseDouble(args["duration"]),
      position: parseDouble(args["position"]),
      artworkSource: ArtworkSource(
        key: nonEmptyString(args["artworkKey"]),
        url: nonEmptyString(args["artworkUrl"]),
        path: nonEmptyString(args["artworkPath"]),
        token: nonEmptyString(args["token"]),
        serverPin: nonEmptyString(args["serverPin"])
      ),
      artworkData: (args["artworkBytes"] as? FlutterStandardTypedData)?.data
    )
  }

  private static func parseBool(_ value: Any?) -> Bool? {
    if let boolValue = value as? Bool {
      return boolValue
    }

    return (value as? NSNumber)?.boolValue
  }

  private static func parseDouble(_ value: Any?) -> Double? {
    if let doubleValue = value as? Double {
      return doubleValue
    }

    return (value as? NSNumber)?.doubleValue
  }

  private static func nonEmptyString(_ value: Any?) -> String? {
    guard let value = value as? String else {
      return nil
    }

    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

    return trimmed.isEmpty ? nil : trimmed
  }
}
