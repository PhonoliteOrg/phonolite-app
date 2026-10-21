import Foundation
import UIKit

/// Loads list artwork with a separate session per request.
/// File/network replies arrive on the main queue; rejected sources complete synchronously.
final class CarPlayArtworkLoader {
  func loadImage(
    urlString: String,
    token: String?,
    serverPin: String?,
    completion: @escaping (UIImage?) -> Void
  ) {
    guard let url = URL(string: urlString) else {
      completion(nil)

      return
    }

    if url.isFileURL {
      loadFileImage(url: url, completion: completion)

      return
    }

    loadRemoteImage(url: url, token: token, serverPin: serverPin, completion: completion)
  }

  private func loadFileImage(url: URL, completion: @escaping (UIImage?) -> Void) {
    DispatchQueue.global(qos: .utility).async {
      let image = (try? Data(contentsOf: url)).flatMap { UIImage(data: $0) }

      DispatchQueue.main.async {
        completion(image)
      }
    }
  }

  private func loadRemoteImage(
    url: URL,
    token: String?,
    serverPin: String?,
    completion: @escaping (UIImage?) -> Void
  ) {
    guard let serverPin, let session = PinnedArtworkSession.make(url: url, pin: serverPin) else {
      completion(nil)

      return
    }

    var request = URLRequest(url: url)

    if let token, !token.isEmpty {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    session.dataTask(with: request) { data, response, error in
      session.finishTasksAndInvalidate()

      let image: UIImage?

      if error == nil, let response = response as? HTTPURLResponse,
         (200..<300).contains(response.statusCode), let data {
        image = UIImage(data: data)
      } else {
        image = nil
      }

      DispatchQueue.main.async {
        completion(image)
      }
    }.resume()
  }
}
