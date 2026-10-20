import 'dart:math' as math;

/// Independent UI/raster budgets; their sum is not a dropped-frame detector.
Map<String, Object?> summarizeFrames(
  List<Map<String, int>> frames, {
  required double targetFps,
}) {
  if (!targetFps.isFinite || targetFps <= 0) {
    throw ArgumentError.value(targetFps, 'targetFps');
  }
  final budget = 1000000 / targetFps;
  final build = frames.map((f) => f['build_us']!).toList()..sort();
  final raster = frames.map((f) => f['raster_us']!).toList()..sort();
  final slow = frames
      .where((f) => f['build_us']! > budget || f['raster_us']! > budget)
      .toList();
  slow.sort(
    (a, b) => math
        .max(b['build_us']!, b['raster_us']!)
        .compareTo(math.max(a['build_us']!, a['raster_us']!)),
  );
  int? percentile(List<int> values, double p) =>
      values.isEmpty ? null : values[(values.length * p).ceil() - 1];
  return {
    'target_fps': targetFps,
    'budget_us': budget,
    'frame_count': frames.length,
    'sample_quality': frames.length < 30 ? 'insufficient' : 'sampled',
    'janky_frames': slow.length,
    'jank_percent': frames.isEmpty ? null : 100 * slow.length / frames.length,
    'build_p95_us': percentile(build, .95),
    'raster_p95_us': percentile(raster, .95),
    'worst_build_us': build.isEmpty ? null : build.last,
    'worst_raster_us': raster.isEmpty ? null : raster.last,
    'worst_frames': slow.take(20).toList(),
  };
}
