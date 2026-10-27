import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:phonolite_app/infrastructure/audio/output/audio_pcm_output.dart';
import 'package:phonolite_app/infrastructure/platform/audio/windows/wave_out_bindings.dart';

class WaveOutPlayer implements AudioPcmOutput {
  static const int _maxInFlight = 5;

  final int _sampleRate;
  final int _channels;
  final int _deviceId;
  final WaveOutBindings Function() _bindingsFactory;
  late final WaveOutBindings _bindings = _bindingsFactory();
  ffi.Pointer<ffi.Pointer<ffi.Void>>? _handle;
  final List<WaveBuffer> _inFlight = [];
  double _volume = 1.0;
  int _completedSamples = 0;
  int _writeEpoch = 0;
  Future<void>? _initialization;
  Future<void>? _shutdown;

  WaveOutPlayer({
    required int sampleRate,
    required int channels,
    required int deviceId,
    WaveOutBindings Function()? bindingsFactory,
  }) : _sampleRate = sampleRate,
       _channels = channels,
       _deviceId = deviceId,
       _bindingsFactory = bindingsFactory ?? WaveOutBindings.new;

  @override
  Future<void> initialize() => _initialization ??= Future<void>.sync(() {
    if (_shutdown != null) {
      throw StateError('Audio output is closed.');
    }

    _open();
  });

  @override
  Future<void> dispose() => _shutdown ??= Future<void>.sync(_close);

  void _close() {
    _writeEpoch++;

    final handle = _handle;

    _handle = null;

    if (handle == null) {
      return;
    }

    _bindings.waveOutReset(handle.value);
    _collectAll(handle.value);

    _bindings.waveOutClose(handle.value);
    calloc.free(handle);
  }

  @override
  Future<void> write(Int16List samples) async {
    final handle = _handle;
    final epoch = _writeEpoch;

    if (handle == null) {
      return;
    }

    final dataPtr = calloc<ffi.Int16>(samples.length);
    final output = dataPtr.asTypedList(samples.length);
    final volume = _volume;

    // Apply app gain to our own PCM copy so Windows mixer volume stays independent.
    // Buffers already submitted to WinMM remain untouched until playback completes.
    if (volume == 1.0) {
      output.setAll(0, samples);
    } else if (volume != 0.0) {
      for (var i = 0; i < samples.length; i++) {
        output[i] = (samples[i] * volume).round();
      }
    }

    final header = calloc<WAVEHDR>();
    header.ref.lpData = dataPtr.cast<ffi.Uint8>();
    header.ref.dwBufferLength = samples.length * 2;
    header.ref.dwBytesRecorded = 0;
    header.ref.dwUser = 0;
    header.ref.dwFlags = 0;
    header.ref.dwLoops = 0;
    header.ref.lpNext = ffi.nullptr;
    header.ref.reserved = 0;

    var result = _bindings.waveOutPrepareHeader(handle.value, header, ffi.sizeOf<WAVEHDR>());

    if (result != MMSYSERR_NOERROR) {
      calloc.free(header);
      calloc.free(dataPtr);

      throw Exception('waveOutPrepareHeader failed: $result');
    }

    result = _bindings.waveOutWrite(handle.value, header, ffi.sizeOf<WAVEHDR>());

    if (result != MMSYSERR_NOERROR) {
      _bindings.waveOutUnprepareHeader(handle.value, header, ffi.sizeOf<WAVEHDR>());
      calloc.free(header);
      calloc.free(dataPtr);

      throw Exception('waveOutWrite failed: $result');
    }

    _inFlight.add(WaveBuffer(header: header, data: dataPtr, sampleCount: samples.length));
    _collectDone(handle.value);

    while (_inFlight.length >= _maxInFlight) {
      if (!identical(_handle, handle) || epoch != _writeEpoch) {
        return;
      }

      await Future<void>.delayed(const Duration(milliseconds: 2));

      if (!identical(_handle, handle) || epoch != _writeEpoch) {
        return;
      }

      _collectDone(handle.value);
    }
  }

  @override
  Future<void> flush() async {
    _writeEpoch++;

    final handle = _handle;
    if (handle == null) {
      return;
    }

    final result = _bindings.waveOutReset(handle.value);

    if (result != MMSYSERR_NOERROR) {
      throw Exception('waveOutReset failed: $result');
    }

    _collectAll(handle.value);
    _completedSamples = 0;
  }

  @override
  void setVolume(double value) {
    _volume = value.clamp(0.0, 1.0);
  }

  @override
  void pause() {
    final handle = _handle;
    if (handle == null) {
      return;
    }

    final result = _bindings.waveOutPause(handle.value);

    if (result != MMSYSERR_NOERROR) {
      throw Exception('waveOutPause failed: $result');
    }
  }

  @override
  void resume() {
    final handle = _handle;
    if (handle == null) {
      return;
    }

    final result = _bindings.waveOutRestart(handle.value);

    if (result != MMSYSERR_NOERROR) {
      throw Exception('waveOutRestart failed: $result');
    }
  }

  @override
  Future<int> collectDoneSamples() async {
    final handle = _handle;
    if (handle == null) {
      return 0;
    }

    _collectDone(handle.value);

    final out = _completedSamples;

    _completedSamples = 0;

    return out;
  }

  @override
  Future<bool> isIdle() async => _inFlight.isEmpty;

  void _open() {
    final handle = calloc<ffi.Pointer<ffi.Void>>();

    final format = calloc<WAVEFORMATEX>();
    format.ref.wFormatTag = WAVE_FORMAT_PCM;
    format.ref.nChannels = _channels;
    format.ref.nSamplesPerSec = _sampleRate;
    format.ref.wBitsPerSample = 16;
    format.ref.nBlockAlign = (_channels * 2);
    format.ref.nAvgBytesPerSec = format.ref.nSamplesPerSec * format.ref.nBlockAlign;
    format.ref.cbSize = 0;

    final deviceId = _deviceId == kDefaultOutputDeviceId ? WAVE_MAPPER : _deviceId;
    final result = _bindings.waveOutOpen(handle, deviceId, format, ffi.nullptr, ffi.nullptr, CALLBACK_NULL);

    calloc.free(format);

    if (result != MMSYSERR_NOERROR) {
      calloc.free(handle);

      throw Exception('waveOutOpen failed: $result');
    }

    _handle = handle;
  }

  void _collectDone(ffi.Pointer<ffi.Void> handle) {
    var i = 0;

    while (i < _inFlight.length) {
      final buffer = _inFlight[i];

      if (buffer.header.ref.dwFlags & WHDR_DONE != 0) {
        _bindings.waveOutUnprepareHeader(handle, buffer.header, ffi.sizeOf<WAVEHDR>());
        calloc.free(buffer.header);
        calloc.free(buffer.data);

        _completedSamples += buffer.sampleCount;
        _inFlight.removeAt(i);
        continue;
      }

      i++;
    }
  }

  void _collectAll(ffi.Pointer<ffi.Void> handle) {
    for (final buffer in _inFlight) {
      _bindings.waveOutUnprepareHeader(handle, buffer.header, ffi.sizeOf<WAVEHDR>());
      calloc.free(buffer.header);
      calloc.free(buffer.data);
    }

    _inFlight.clear();
  }
}
