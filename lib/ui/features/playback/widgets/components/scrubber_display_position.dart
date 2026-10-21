import 'dart:math' as math;

const int playbackScrubberAuthoritativeDiscontinuityMs = 1500;

const int playbackScrubberMaxInterpolationLeadMs = 1500;

Duration playbackBoundedScrubberDisplayPosition({
  required Duration displayPosition,
  required Duration authoritativePosition,
  required Duration duration,
}) {
  final durationMs = duration.inMilliseconds;
  final authoritativeMs = math.max(0, authoritativePosition.inMilliseconds);
  var nextMs = math.max(0, displayPosition.inMilliseconds);

  if (nextMs < authoritativeMs) {
    nextMs = authoritativeMs;
  }

  final leadCeilingMs = authoritativeMs + playbackScrubberMaxInterpolationLeadMs;

  if (nextMs > leadCeilingMs) {
    nextMs = leadCeilingMs;
  }

  if (durationMs > 0 && nextMs > durationMs) {
    nextMs = durationMs;
  }

  return Duration(milliseconds: nextMs);
}
