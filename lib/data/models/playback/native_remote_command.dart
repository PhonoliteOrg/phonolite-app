enum NativeRemoteAction {
  play,
  pause,
  next,
  previous,
  toggleLike,
  startLibraryShuffle,
  seek,
  audioInterruptionBegan,
  audioInterruptionEnded,
  audioInterruptionEndedPaused,
  audioServicesReset,
  unknown,
}

class NativeRemoteCommand {
  final NativeRemoteAction action;
  final Duration? position;

  const NativeRemoteCommand({required this.action, this.position});
}
