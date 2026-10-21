import CarPlay
import UIKit

struct CarPlayRootPage {
  let sourceGrid: CarPlaySourceGrid

  func makeLoadingTemplate() -> CPListTemplate {
    return CarPlayListFrame.makeMessageTemplate(text: "Loading...")
  }

  func makeContent(state: CarPlaySourceState, contentStyle: UIUserInterfaceStyle) -> CarPlayRootContent? {
    if !state.hasAnySource {
      let template = CarPlayListFrame.makeMessageTemplate(
        text: "Nothing available in CarPlay",
        detail: "Connect to a server or download tracks in Phonolite"
      )

      return CarPlayRootContent(template: template, localTemplate: nil, serverTemplate: nil)
    }

    let local = state.localAvailable ? sourceGrid.makeTemplate(scope: .local, contentStyle: contentStyle) : nil
    let server = state.serverAvailable ? sourceGrid.makeTemplate(scope: .server, contentStyle: contentStyle) : nil
    let templates: [CPTemplate] = [local, server].compactMap { $0 }
    let template: CPTemplate

    if templates.count > 1 {
      template = CPTabBarTemplate(templates: templates)
    } else if let first = templates.first {
      template = first
    } else {
      return nil
    }

    return CarPlayRootContent(template: template, localTemplate: local, serverTemplate: server)
  }
}
