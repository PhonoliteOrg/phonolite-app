import 'dart:math' as math;
import 'dart:typed_data';

/// Streaming conversion into one persistent output format.
///
/// Positions use integer frame ratios, so chunk boundaries never change phase
/// or duration. A Blackman-windowed sinc filter retains bounded history and
/// lookahead; EOF emits exactly the rounded input duration, without extra tail
/// frames. Equal rates bypass filtering, preserving integer PCM exactly.
class PcmStreamConverter {
  final int inputRate;
  final int inputChannels;
  final int outputRate;
  final int outputChannels;
  final int inputBits;
  final int outputBits;

  static const int _phases = 1024;
  late final int _radius;
  late final List<Float64List> _kernels;
  final List<double> _buffer = <double>[];
  int _bufferedFrom = 0;
  int _inputFrames = 0;
  int _nextOutputFrame = 0;
  bool _finished = false;

  PcmStreamConverter({
    required this.inputRate,
    required this.inputChannels,
    required this.outputRate,
    required this.outputChannels,
    this.inputBits = 32,
    this.outputBits = 32,
  }) {
    if (inputRate <= 0 || outputRate <= 0 || inputRate > 768000 || outputRate > 768000) {
      throw ArgumentError('PCM rates must be positive and at most 768000 Hz.');
    }
    if ((inputChannels != 1 && inputChannels != 2) || (outputChannels != 1 && outputChannels != 2)) {
      throw ArgumentError('PCM conversion supports mono and stereo.');
    }
    if ((inputBits != 16 && inputBits != 32) || (outputBits != 16 && outputBits != 32)) {
      throw ArgumentError('PCM containers must have 16 or 32 bits.');
    }
    final ratio = math.min(1.0, outputRate / inputRate);
    _radius = (32 / ratio).ceil().clamp(32, 256);
    _kernels = inputRate == outputRate ? const <Float64List>[] : _buildKernels(ratio * 0.94);
  }

  /// Returns interleaved signed PCM, typed for the selected output container.
  /// Each supplied chunk must contain complete input frames. EOF is terminal.
  List<int> process(List<int> interleaved, {bool endOfInput = false}) {
    if (_finished) {
      throw StateError('PCM input has already ended.');
    }
    if (interleaved.length % inputChannels != 0) {
      throw ArgumentError('PCM chunk ends inside an interleaved frame.');
    }
    _finished = endOfInput;
    if (inputRate == outputRate) {
      return _convertUnity(interleaved);
    }

    final scale = math.pow(2, outputBits - inputBits).toDouble();
    for (var offset = 0; offset < interleaved.length; offset += inputChannels) {
      if (inputChannels == outputChannels) {
        for (var channel = 0; channel < outputChannels; channel++) {
          _buffer.add(interleaved[offset + channel] * scale);
        }
      } else if (inputChannels == 1) {
        final value = interleaved[offset] * scale;
        _buffer.add(value);
        _buffer.add(value);
      } else {
        _buffer.add((interleaved[offset] + interleaved[offset + 1]) * scale * 0.5);
      }
    }
    _inputFrames += interleaved.length ~/ inputChannels;
    if (_buffer.isEmpty) {
      return _typed(const <int>[]);
    }

    final output = <int>[];
    final outputEnd = (_inputFrames * outputRate + inputRate ~/ 2) ~/ inputRate;
    while (_nextOutputFrame < outputEnd) {
      final numerator = _nextOutputFrame * inputRate;
      final center = numerator ~/ outputRate;
      if (!endOfInput && center + _radius >= _inputFrames) {
        break;
      }
      final phaseScaled = (numerator % outputRate) * _phases;
      final phase = phaseScaled ~/ outputRate;
      final blend = (phaseScaled % outputRate) / outputRate;
      final firstKernel = _kernels[phase];
      final nextKernel = _kernels[phase + 1];
      for (var channel = 0; channel < outputChannels; channel++) {
        var sample = 0.0;
        for (var tap = 0; tap < _radius * 2; tap++) {
          final inputFrame = (center + tap - _radius + 1).clamp(0, _inputFrames - 1);
          final index = (inputFrame - _bufferedFrom) * outputChannels + channel;
          final weight = firstKernel[tap] + blend * (nextKernel[tap] - firstKernel[tap]);
          sample += _buffer[index] * weight;
        }
        output.add(_quantize(sample));
      }
      _nextOutputFrame++;
    }

    final nextCenter = _nextOutputFrame * inputRate ~/ outputRate;
    final discardUntil = (nextCenter - _radius).clamp(_bufferedFrom, _inputFrames);
    final discardSamples = (discardUntil - _bufferedFrom) * outputChannels;
    if (discardSamples > 0) {
      _buffer.removeRange(0, discardSamples);
      _bufferedFrom = discardUntil;
    }
    if (endOfInput) {
      _buffer.clear();
    }
    return _typed(output);
  }

  List<int> _convertUnity(List<int> input) {
    if (inputChannels == outputChannels && inputBits == outputBits) {
      return _typed(input);
    }
    final output = <int>[];
    final scale = math.pow(2, outputBits - inputBits).toDouble();
    for (var offset = 0; offset < input.length; offset += inputChannels) {
      if (inputChannels == outputChannels) {
        for (var channel = 0; channel < outputChannels; channel++) {
          output.add(_quantize(input[offset + channel] * scale));
        }
      } else if (inputChannels == 1) {
        final value = _quantize(input[offset] * scale);
        output.add(value);
        output.add(value);
      } else {
        output.add(_quantize((input[offset] + input[offset + 1]) * scale * 0.5));
      }
    }
    return _typed(output);
  }

  int _quantize(double sample) {
    final minimum = outputBits == 16 ? -32768 : -2147483648;
    final maximum = outputBits == 16 ? 32767 : 2147483647;
    return sample.round().clamp(minimum, maximum);
  }

  List<int> _typed(List<int> samples) => outputBits == 16 ? Int16List.fromList(samples) : Int32List.fromList(samples);

  List<Float64List> _buildKernels(double cutoff) {
    return List<Float64List>.generate(_phases + 1, (phase) {
      final fraction = phase / _phases;
      final weights = Float64List(_radius * 2);
      var sum = 0.0;
      for (var tap = 0; tap < weights.length; tap++) {
        final distance = tap - _radius + 1 - fraction;
        final argument = math.pi * cutoff * distance;
        final sinc = argument.abs() < 1e-12 ? 1.0 : math.sin(argument) / argument;
        final window =
            0.42 + 0.5 * math.cos(math.pi * distance / _radius) + 0.08 * math.cos(2 * math.pi * distance / _radius);
        weights[tap] = cutoff * sinc * window;
        sum += weights[tap];
      }
      for (var tap = 0; tap < weights.length; tap++) {
        weights[tap] /= sum;
      }
      return weights;
    });
  }
}
