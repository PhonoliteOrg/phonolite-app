String listeningDurationLabel(int milliseconds) {
  if (milliseconds <= 0) {
    return '0m';
  }

  if (milliseconds < 1000) {
    return '<1s';
  }

  final seconds = milliseconds ~/ 1000;

  if (seconds < 60) {
    return '${seconds}s';
  }

  if (seconds >= 3600) {
    return '${seconds ~/ 3600}h ${(seconds ~/ 60) % 60}m ${seconds % 60}s';
  }

  return '${seconds ~/ 60}m ${seconds % 60}s';
}
