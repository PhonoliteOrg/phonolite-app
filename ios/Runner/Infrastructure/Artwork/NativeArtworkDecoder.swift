import Foundation
import ImageIO
import UIKit

enum NativeArtworkDecoder {
  static func decode(_ data: Data) -> UIImage? {
    guard let source = CGImageSourceCreateWithData(
      data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary
    ) else {
      return nil
    }

    let options = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: 1024,
      kCGImageSourceShouldCacheImmediately: true,
    ] as CFDictionary

    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
      return nil
    }

    return UIImage(cgImage: image)
  }
}
