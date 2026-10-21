import Foundation
import Security

/// Native artwork uses the authenticated SPKI even while Dart is suspended.
/// Sessions have no CA fallback or automatic redirects.
final class PinnedArtworkSession: NSObject {
  private let host: String
  private let port: Int
  private let pin: String

  private init(host: String, port: Int, pin: String) {
    self.host = host.lowercased()
    self.port = port
    self.pin = pin
  }

  static func make(url: URL, pin: String) -> URLSession? {
    guard url.scheme == "https", let host = url.host, url.user == nil, url.password == nil,
          pin.count == 64, pin.allSatisfy({ "0123456789abcdef".contains($0) }) else {
      return nil
    }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.tlsMinimumSupportedProtocolVersion = .TLSv13
    configuration.timeoutIntervalForRequest = 15
    configuration.timeoutIntervalForResource = 15

    return URLSession(
      configuration: configuration,
      delegate: PinnedArtworkSession(host: host, port: url.port ?? 443, pin: pin),
      delegateQueue: nil
    )
  }
}

extension PinnedArtworkSession: URLSessionTaskDelegate {
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    let space = challenge.protectionSpace

    guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
          space.host.lowercased() == host, space.port == port,
          let trust = space.serverTrust,
          let certificate = SecTrustGetCertificateAtIndex(trust, 0) else {
      completionHandler(.cancelAuthenticationChallenge, nil)

      return
    }

    let der = SecCertificateCopyData(certificate) as Data

    // The Rust helper checks certificate validity and hashes the complete SPKI.
    let actual: String? = der.withUnsafeBytes { bytes in
      guard let value = phonolite_security_spki(
        bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count
      ) else {
        return nil
      }

      defer { phonolite_quic_free_string(value) }

      return String(cString: value)
    }

    guard actual == pin else {
      completionHandler(.cancelAuthenticationChallenge, nil)

      return
    }

    completionHandler(.useCredential, URLCredential(trust: trust))
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}
