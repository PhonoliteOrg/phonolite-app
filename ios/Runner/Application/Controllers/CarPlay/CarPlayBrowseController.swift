import Foundation

/// Main-thread owner of independent page requests; active replies are delivered on the main queue.
final class CarPlayBrowseController {
  private let client: CarPlayClient
  private var pendingRequests: Set<UUID> = []
  private(set) var sourceState = CarPlaySourceState.empty

  init(client: CarPlayClient) {
    self.client = client
  }

  var isLoading: Bool {
    return !pendingRequests.isEmpty
  }

  /// Invalidates presentation callbacks; an already-sent Flutter request still completes.
  func disconnect() {
    pendingRequests.removeAll()
    sourceState = .empty
  }

  func updateSourceState(_ state: CarPlaySourceState, force: Bool) -> Bool {
    if !force && sourceState == state {
      return false
    }

    sourceState = state

    return true
  }

  func requestState(completion: @escaping (CarPlaySourceState) -> Void) {
    request(using: client.requestState, completion: completion)
  }

  func load(_ request: CarPlayListRequest, completion: @escaping (CarPlayListResult) -> Void) {
    self.request(using: { reply in client.requestList(request, completion: reply) }, completion: completion)
  }

  func perform(_ command: CarPlayCommand) {
    client.send(command)
  }

  private func request<Value>(
    using operation: (@escaping (Value) -> Void) -> Void,
    completion: @escaping (Value) -> Void
  ) {
    let requestID = UUID()
    pendingRequests.insert(requestID)

    operation { [weak self] result in
      DispatchQueue.main.async { [weak self] in
        guard let self, self.pendingRequests.remove(requestID) != nil else {
          return
        }

        completion(result)
      }
    }
  }
}
