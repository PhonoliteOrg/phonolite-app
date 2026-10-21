import CarPlay
import Foundation

/// Main-thread presentation owner; button updates are queued onto the main thread.
final class CarPlayNowPlayingPresenter {
  private let sendRemoteCommand: (NativeRemoteCommand) -> Void
  private let icons = CarPlayIconProvider()

  let template = CPNowPlayingTemplate.shared

  init(sendRemoteCommand: @escaping (NativeRemoteCommand) -> Void) {
    self.sendRemoteCommand = sendRemoteCommand
  }

  func configureMiniPlayer() {
    // Keep builds on older SDKs while using CarPlay's public MiniPlayer setter when available.
    if #available(iOS 27.0, *), template.responds(to: NSSelectorFromString("setAllowsMiniPlayer:")) {
      template.setValue(true, forKey: "allowsMiniPlayer")
    }
  }

  func updateButtons(liked: Bool, available: Bool) {
    DispatchQueue.main.async { [weak self] in
      self?.applyButtons(liked: liked, available: available)
    }
  }

  private func applyButtons(liked: Bool, available: Bool) {
    guard available else {
      template.updateNowPlayingButtons([])

      return
    }

    let imageName = liked ? "LucideHeartFilled" : "LucideHeart"

    guard let image = icons.templateIcon(named: imageName) else {
      template.updateNowPlayingButtons([])

      return
    }

    let button = CPNowPlayingImageButton(image: image) { [sendRemoteCommand = self.sendRemoteCommand] _ in
      sendRemoteCommand(.toggleLike)
    }

    template.updateNowPlayingButtons([button])
  }
}
