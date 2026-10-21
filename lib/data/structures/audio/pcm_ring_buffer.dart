import 'dart:math' as math;
import 'dart:typed_data';

/// An ordered PCM queue that can grow without invalidating producer references.
class PcmRingBuffer {
  Int16List _buffer;
  int _readIndex = 0;
  int _writeIndex = 0;
  int _length = 0;

  PcmRingBuffer(int capacitySamples) : _buffer = Int16List(capacitySamples);

  int get _capacity => _buffer.length;

  int get length => _length;

  int get capacity => _capacity;

  int get free => _capacity - _length;

  void ensureCapacity(int minimumSamples) {
    if (minimumSamples <= _capacity) {
      return;
    }

    // Grow this object in place: producer and pump can retain references across
    // awaits, and replacing the object would strand pending writes or samples.
    final grown = Int16List(minimumSamples);
    final firstPart = math.min(_length, _capacity - _readIndex);

    grown.setRange(0, firstPart, _buffer, _readIndex);

    final remaining = _length - firstPart;
    if (remaining > 0) {
      grown.setRange(firstPart, _length, _buffer);
    }

    _buffer = grown;
    _readIndex = 0;
    _writeIndex = _length;
  }

  int write(Int16List data, int offset) {
    if (offset >= data.length || _length >= _capacity) {
      return 0;
    }

    final available = _capacity - _length;

    final remaining = data.length - offset;
    final toWrite = remaining < available ? remaining : available;

    final firstPart = toWrite < (_capacity - _writeIndex) ? toWrite : (_capacity - _writeIndex);

    _buffer.setRange(_writeIndex, _writeIndex + firstPart, data, offset);

    final leftover = toWrite - firstPart;
    if (leftover > 0) {
      _buffer.setRange(0, leftover, data, offset + firstPart);
    }

    _writeIndex = (_writeIndex + toWrite) % _capacity;
    _length += toWrite;

    return toWrite;
  }

  Int16List? read(int count) {
    if (_length == 0 || count <= 0) {
      return null;
    }

    final toRead = count < _length ? count : _length;
    final out = Int16List(toRead);
    final firstPart = toRead < (_capacity - _readIndex) ? toRead : (_capacity - _readIndex);

    out.setRange(0, firstPart, _buffer, _readIndex);

    final leftover = toRead - firstPart;
    if (leftover > 0) {
      out.setRange(firstPart, toRead, _buffer, 0);
    }

    _readIndex = (_readIndex + toRead) % _capacity;
    _length -= toRead;

    return out;
  }
}
