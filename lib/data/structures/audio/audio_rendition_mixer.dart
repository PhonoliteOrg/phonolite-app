import 'dart:typed_data';

/// Blends sample-aligned sources into a stable PCM32 output without adding,
/// dropping or repeating presentation frames. Opus remains the ready fallback.
class AudioRenditionMixer {
  final int channels;
  final int transitionFrames;
  bool _original = false;
  bool _fromOriginal = false;
  int _transition = 0;
  late final List<int> _last = List.filled(channels, 0);

  AudioRenditionMixer({required this.channels, required this.transitionFrames})
    : assert(channels > 0),
      assert(transitionFrames > 0);

  Int32List continueOriginal(Int32List samples) {
    if (!_original || samples.length % channels != 0) {
      throw StateError('Original is not the active rendition.');
    }
    if (samples.isNotEmpty) {
      for (var channel = 0; channel < channels; channel++) {
        _last[channel] = samples[samples.length - channels + channel];
      }
    }
    _transition = 0;

    return samples;
  }

  Int32List mix(Int16List opus, Int32List? original, {required bool useOriginal}) {
    if (opus.length % channels != 0 || (original != null && original.length != opus.length)) {
      throw StateError('Renditions must cover the same complete channel frames.');
    }
    if (useOriginal && original == null) {
      throw StateError('Original PCM is unavailable.');
    }
    if (useOriginal != _original) {
      _fromOriginal = _original;
      _original = useOriginal;
      _transition = transitionFrames;
    }

    final result = Int32List(opus.length);
    for (var frame = 0; frame < opus.length ~/ channels; frame++) {
      final blend = _transition == 0 ? 1.0 : (transitionFrames - _transition + 1) / transitionFrames;
      for (var channel = 0; channel < channels; channel++) {
        final index = frame * channels + channel;
        final compressed = opus[index] << 16;
        final precise = original?[index] ?? _last[channel];
        final next = _original ? precise : compressed;
        final previous = _fromOriginal ? precise : compressed;
        result[index] = (previous + (next - previous) * blend).round().clamp(-2147483648, 2147483647);
        _last[channel] = result[index];
      }
      if (_transition > 0) {
        _transition--;
      }
    }

    return result;
  }
}
