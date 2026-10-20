import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/frame_metrics.dart';

void main() {
  Map<String, int> frame(int build, int raster) => {
    'build_us': build,
    'raster_us': raster,
  };

  test('parallel build and raster durations are not added', () {
    final report = summarizeFrames([
      frame(12000, 12000),
      frame(18000, 2000),
      frame(1000, 19000),
    ], targetFps: 60);
    expect(report['janky_frames'], 2);
    expect(report['jank_percent'], closeTo(200 / 3, .001));
    expect(report['worst_build_us'], 18000);
    expect(report['raster_p95_us'], 19000);
  });

  test('120 Hz uses its own smaller frame budget', () {
    final report = summarizeFrames([frame(9000, 1000)], targetFps: 120);
    expect(report['janky_frames'], 1);
    expect(report['budget_us'], closeTo(8333.333, .001));
  });

  test('no frames does not fabricate healthy performance', () {
    final report = summarizeFrames([], targetFps: 60);
    expect(report['sample_quality'], 'insufficient');
    expect(report['jank_percent'], isNull);
    expect(report['build_p95_us'], isNull);
    expect(() => summarizeFrames([], targetFps: 0), throwsArgumentError);
  });
}
