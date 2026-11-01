import AppKit
import ImageIO
import MediaPlayer

/// Dart supplies authenticated artwork bytes; decoding never opens a network connection.
/// Accept updates on the main thread and reject completions from an older cover.
final class NowPlayingArtwork {
  var onChanged: (() -> Void)?

  private let queue = DispatchQueue(label: "phonolite.macos.artwork", qos: .userInitiated)
  private var source = ArtworkSource()
  private var data: Data?
  private var generation = 0
  private(set) var current: MPMediaItemArtwork?

  func clear() {
    generation += 1
    source = ArtworkSource()
    data = nil
    current = nil
  }

  func update(_ source: ArtworkSource, data: Data?) {
    if source != self.source {
      clear()
      self.source = source
    }

    guard let data, data != self.data else { return }

    generation += 1
    self.data = data
    current = nil

    let requestGeneration = generation

    queue.async { [weak self] in
      let image = Self.decode(data)

      DispatchQueue.main.async {
        guard let self, self.generation == requestGeneration else { return }

        if let image {
          self.current = MPMediaItemArtwork(boundsSize: CGSize(width: image.width, height: image.height)) { size in
            NSImage(cgImage: image, size: size)
          }
        }

        self.onChanged?()
      }
    }
  }

  private static func decode(_ data: Data) -> CGImage? {
    guard data.count <= 20 * 1024 * 1024,
      let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
    else { return nil }

    let options =
      [
        kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: 1024, kCGImageSourceShouldCacheImmediately: true,
      ] as CFDictionary

    return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
  }
}
