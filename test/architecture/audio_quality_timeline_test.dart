import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/data/models/audio/audio_stream_quality.dart';
import 'package:phonolite_app/data/structures/audio/audio_quality_timeline.dart';

void main() {
  test('buffered future qualities cannot overtake confirmed playback', () {
    final timeline = AudioQualityTimeline();
    timeline.append(100, AudioStreamQuality.medium);
    timeline.append(100, AudioStreamQuality.low);
    timeline.append(100, AudioStreamQuality.high);
    expect(timeline.qualityAt(0), AudioStreamQuality.medium);
    expect(timeline.qualityAt(99), AudioStreamQuality.medium);
    expect(timeline.qualityAt(100), AudioStreamQuality.low);
    expect(timeline.qualityAt(150), AudioStreamQuality.low);
    expect(timeline.qualityAt(150), AudioStreamQuality.low, reason: 'Paused playback retains its audible quality.');
    expect(timeline.qualityAt(200), AudioStreamQuality.high);
    expect(timeline.qualityAt(300), AudioStreamQuality.high);
  });

  test('a seek resets sample placement and unknown quality cannot retain an old grade', () {
    final timeline = AudioQualityTimeline()..append(100, AudioStreamQuality.high);
    timeline.reset();
    expect(timeline.qualityAt(0), isNull);
    timeline.append(20, null);
    timeline.append(100, AudioStreamQuality.low);
    expect(timeline.qualityAt(0), isNull);
    expect(timeline.qualityAt(19), isNull);
    expect(timeline.qualityAt(20), AudioStreamQuality.low);
  });
}
