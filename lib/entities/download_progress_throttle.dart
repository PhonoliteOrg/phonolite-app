/// Bounds UI updates by elapsed time, independently of transfer size or speed.
class DownloadProgressThrottle {
  DownloadProgressThrottle({required this.interval, int initialBytes = 0})
    : _lastBytes = initialBytes;

  final Duration interval;
  Duration _lastReportedAt = Duration.zero;
  int _lastBytes;

  bool shouldReport({
    required int receivedBytes,
    required Duration elapsed,
    bool force = false,
  }) {
    if (receivedBytes <= _lastBytes ||
        (!force && elapsed - _lastReportedAt < interval)) {
      return false;
    }
    _lastBytes = receivedBytes;
    _lastReportedAt = elapsed;
    return true;
  }
}
