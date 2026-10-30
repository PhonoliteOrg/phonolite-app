enum NativeRemoteCommand: String {
  case play
  case pause
  case toggle
  case next
  case previous = "prev"
  case toggleLike
  case audioInterruptionBegan
  case audioInterruptionEnded
  case audioInterruptionEndedPaused
  case audioServicesReset
}
