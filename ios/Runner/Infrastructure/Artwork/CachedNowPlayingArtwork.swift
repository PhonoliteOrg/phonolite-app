import Foundation
import MediaPlayer
import UIKit

/// Keep decoded covers and MediaPlayer's artwork objects reusable across albums.
final class CachedNowPlayingArtwork {
  let data: Data?
  let mediaArtwork: MPMediaItemArtwork
  let cost: Int

  init(image: UIImage, data: Data?) {
    self.data = data
    cost = (image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0) + (data?.count ?? 0)

    let resizedImages = NSCache<NSString, UIImage>()
    resizedImages.countLimit = 4
    resizedImages.totalCostLimit = 2 * 1024 * 1024

    mediaArtwork = MPMediaItemArtwork(boundsSize: image.size) { size in
      CachedNowPlayingArtwork.resizedImage(image, size: size, cache: resizedImages)
    }
  }

  private static func resizedImage(_ image: UIImage, size: CGSize, cache: NSCache<NSString, UIImage>) -> UIImage {
    guard size.width > 0, size.height > 0 else {
      return image
    }

    let key = "\(size.width)x\(size.height)" as NSString

    if let cached = cache.object(forKey: key) {
      return cached
    }

    let format = UIGraphicsImageRendererFormat()
    format.scale = 1

    let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: size))
    }
    let cost = resized.cgImage.map { $0.bytesPerRow * $0.height } ?? 0

    cache.setObject(resized, forKey: key, cost: cost)

    return resized
  }
}
