import CarPlay

/// Binds a typed browse request to its shared frame without rebuilding the active template.
struct CarPlayBrowsePage {
  let controller: CarPlayBrowseController
  let request: CarPlayListRequest
  let frame: CarPlayListFrame
  let onSelect: (CarPlayItem) -> Void

  func show(present: (CPListTemplate) -> Void) {
    let template = frame.makeLoadingTemplate()

    present(template)

    controller.load(request) { [frame, onSelect] result in
      frame.update(template, result: result, onSelect: onSelect)
    }
  }
}
