import UIKit

/// Reuses the native launch screen for iOS's background/next-launch snapshot.
/// Flutter keeps its own copy visible during cold start until its first frame.
final class LaunchSnapshotCover {
  private var cover: UIView?

  func show(in window: UIWindow?) {
    guard cover == nil, let window,
      let view = UIStoryboard(name: "LaunchScreen", bundle: nil).instantiateInitialViewController()?.view
    else { return }

    view.frame = window.bounds
    view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    window.addSubview(view)
    window.layoutIfNeeded()

    cover = view
  }

  func remove() {
    cover?.removeFromSuperview()
    cover = nil
  }
}
