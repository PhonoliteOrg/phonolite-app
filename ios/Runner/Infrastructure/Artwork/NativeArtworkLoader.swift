import Foundation

/// Owns one request and its sessions; an injected session remains borrowed.
/// Manage requests on the platform main thread; completion runs on a worker queue.
final class NativeArtworkLoader {
  private let injectedSession: URLSession?
  private let localReadQueue: DispatchQueue

  private var session: URLSession?
  private var sessionIdentity: ArtworkSessionIdentity?
  private var task: URLSessionDataTask?

  init(artworkSession: URLSession? = nil, localReadQueue: DispatchQueue) {
    injectedSession = artworkSession
    self.localReadQueue = localReadQueue
  }

  deinit {
    cancel()
    invalidateOwnedSession()
  }

  func cancel() {
    task?.cancel()
    task = nil
  }

  func clear() {
    cancel()
    invalidateOwnedSession()
    session = nil
    sessionIdentity = nil
  }

  func finishRequest() {
    task = nil
  }

  /// Local paths take precedence; a rejected remote source starts no request.
  func load(_ source: ArtworkSource, completion: @escaping (Data?) -> Void) -> Bool {
    if let path = source.path {
      localReadQueue.async {
        completion(try? Data(contentsOf: URL(fileURLWithPath: path)))
      }

      return true
    }

    guard let urlString = source.url, let url = URL(string: urlString), url.scheme == "https",
          let serverPin = source.serverPin else {
      return false
    }

    guard let requestSession = resolveSession(url: url, serverPin: serverPin, token: source.token) else {
      return false
    }

    var request = URLRequest(url: url)
    request.timeoutInterval = 15

    if let token = source.token {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    let task = requestSession.dataTask(with: request) { data, response, error in
      guard error == nil, let response = response as? HTTPURLResponse,
            (200..<300).contains(response.statusCode) else {
        completion(nil)

        return
      }

      completion(data)
    }

    self.task = task
    task.resume()

    return true
  }

  private func resolveSession(url: URL, serverPin: String, token: String?) -> URLSession? {
    if let injectedSession {
      return injectedSession
    }

    let identity = ArtworkSessionIdentity(url: url, serverPin: serverPin, token: token)

    if sessionIdentity != identity {
      session?.invalidateAndCancel()
      session = PinnedArtworkSession.make(url: url, pin: serverPin)
      sessionIdentity = identity
    }

    return session
  }

  private func invalidateOwnedSession() {
    if injectedSession == nil {
      session?.invalidateAndCancel()
    }
  }
}
