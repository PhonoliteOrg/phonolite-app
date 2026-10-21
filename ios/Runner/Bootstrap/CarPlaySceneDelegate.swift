import CarPlay
import UIKit

final class CarPlaySceneDelegate: UIResponder {
  private var session: CarPlayNavigationCoordinator?

  private func connect(using interfaceController: CPInterfaceController, scene: CPTemplateApplicationScene) {
    guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
      return
    }

    let session = appDelegate.nativeHost.makeCarPlaySession()
    self.session = session
    session.connect(using: interfaceController, scene: scene)
  }

  private func disconnect(_ interfaceController: CPInterfaceController) {
    session?.disconnect(interfaceController)
    session = nil
  }
}

extension CarPlaySceneDelegate: CPTemplateApplicationSceneDelegate {
  func contentStyleDidChange(_ contentStyle: UIUserInterfaceStyle) {
    session?.contentStyleDidChange(contentStyle)
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController,
    to window: CPWindow
  ) {
    connect(using: interfaceController, scene: templateApplicationScene)
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController
  ) {
    connect(using: interfaceController, scene: templateApplicationScene)
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnect interfaceController: CPInterfaceController,
    from window: CPWindow
  ) {
    disconnect(interfaceController)
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnect interfaceController: CPInterfaceController
  ) {
    disconnect(interfaceController)
  }
}
