import CarPlay
import UIKit

/// Creates a loading template once and updates that same template with the common list design.
struct CarPlayListFrame {
  /// Supplies an image on the main thread; the caller supplies an entry with a nonempty artwork URL.
  typealias ArtworkLoader = (CarPlayItem, @escaping (UIImage?) -> Void) -> Void

  let loadingMessage: String
  let emptyMessage: String
  let errorMessage: String
  let loadArtwork: ArtworkLoader

  private static func disabledItem(text: String, detail: String? = nil) -> CPListItem {
    let item = CPListItem(text: text, detailText: detail)
    item.isEnabled = false

    return item
  }

  private func listItems(
    result: CarPlayListResult,
    onSelect: @escaping (CarPlayItem) -> Void
  ) -> [CPListItem] {
    if let error = result.error, !error.isEmpty {
      return [Self.disabledItem(text: errorMessage)]
    }

    if result.items.isEmpty {
      return [Self.disabledItem(text: emptyMessage)]
    }

    return result.items.map { makeItem($0, onSelect: onSelect) }
  }

  private func makeItem(_ entry: CarPlayItem, onSelect: @escaping (CarPlayItem) -> Void) -> CPListItem {
    let item = CPListItem(text: entry.title, detailText: nil)

    if let artworkURL = entry.artworkURL, !artworkURL.isEmpty {
      loadArtwork(entry) { image in
        if let image {
          item.setImage(image)
        }
      }
    }

    item.isEnabled = entry.enabled

    if entry.enabled {
      item.handler = { _, completion in
        onSelect(entry)
        completion()
      }
    }

    return item
  }

  static func makeMessageTemplate(text: String, detail: String? = nil) -> CPListTemplate {
    let item = disabledItem(text: text, detail: detail)

    return CPListTemplate(title: "", sections: [CPListSection(items: [item])])
  }

  func makeLoadingTemplate() -> CPListTemplate {
    return Self.makeMessageTemplate(text: loadingMessage)
  }

  func update(
    _ template: CPListTemplate,
    result: CarPlayListResult,
    onSelect: @escaping (CarPlayItem) -> Void
  ) {
    let items = listItems(result: result, onSelect: onSelect)

    template.updateSections([CPListSection(items: items)])
  }
}
