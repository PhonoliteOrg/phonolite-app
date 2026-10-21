/// Borrows the engine-bound CarPlay channel without exposing its wire representation.
protocol CarPlayClient: AnyObject {
  func requestState(completion: @escaping (CarPlaySourceState) -> Void)

  func requestList(_ request: CarPlayListRequest, completion: @escaping (CarPlayListResult) -> Void)

  func send(_ command: CarPlayCommand)
}
