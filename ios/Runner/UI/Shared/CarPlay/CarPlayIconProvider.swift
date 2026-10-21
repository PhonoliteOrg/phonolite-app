import UIKit

struct CarPlayIconProvider {
  func templateIcon(named imageName: String) -> UIImage? {
    return UIImage(named: imageName)?.withRenderingMode(.alwaysTemplate)
  }

  func gridIcon(named imageName: String, contentStyle: UIUserInterfaceStyle) -> UIImage {
    let traits = contentStyle == .unspecified
      ? nil : UITraitCollection(userInterfaceStyle: contentStyle)

    // Grid assets contain original colored pixels and appearance variants, not template masks.
    return UIImage(named: "\(imageName)Grid", in: .main, compatibleWith: traits)
      ?? UIImage(named: "LucideEllipsisGrid", in: .main, compatibleWith: traits)
      ?? UIImage()
  }
}
