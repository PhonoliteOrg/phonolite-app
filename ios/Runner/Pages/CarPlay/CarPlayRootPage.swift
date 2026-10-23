import CarPlay
import UIKit

struct CarPlayRootPage {
  let sourceGrid: CarPlaySourceGrid

  func makeLoadingTemplate() -> CPListTemplate {
    return CarPlayListFrame.makeMessageTemplate(text: "Loading...")
  }

  func makeContent(state: CarPlaySourceState, contentStyle: UIUserInterfaceStyle) -> CarPlayRootContent {
    let local = sourceGrid.makeTemplate(scope: .local, contentStyle: contentStyle)

    guard state.serverAvailable else {
      return CarPlayRootContent(template: local, localTemplate: local, serverTemplate: nil)
    }

    // A connected server adds the selector and keeps the tabbed navigation
    // needed for Now Playing even when there are no downloaded tracks.
    let server = sourceGrid.makeTemplate(scope: .server, contentStyle: contentStyle)
    let template = CPTabBarTemplate(templates: [local, server])

    if #available(iOS 17.0, *) {
      template.select(local)
    }

    return CarPlayRootContent(template: template, localTemplate: local, serverTemplate: server)
  }
}
