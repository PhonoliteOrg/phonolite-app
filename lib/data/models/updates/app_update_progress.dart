enum AppUpdatePhase {
  idle,
  downloading,
  verifying,
  authorizing,
  preparing,
  installing,
  failed,
  recoveryRequired,
  restartRequired,
}

class AppUpdateProgress {
  final AppUpdatePhase phase;
  final double? fraction;
  final String? message;

  const AppUpdateProgress({this.phase = AppUpdatePhase.idle, this.fraction, this.message});

  bool get cancellable => phase == AppUpdatePhase.downloading || phase == AppUpdatePhase.verifying;
}
