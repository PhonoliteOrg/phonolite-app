import Foundation
import UIKit

final class ApplicationSettingsService {
  /// Reports that opening Settings was requested, retaining the synchronous reply.
  func open() -> Bool {
    if Thread.isMainThread {
      return openOnMainThread()
    }

    return DispatchQueue.main.sync {
      openOnMainThread()
    }
  }

  private func openOnMainThread() -> Bool {
    guard let url = URL(string: UIApplication.openSettingsURLString), UIApplication.shared.canOpenURL(url) else {
      return false
    }

    UIApplication.shared.open(url, options: [:], completionHandler: nil)

    return true
  }
}
