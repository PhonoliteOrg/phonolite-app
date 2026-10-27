part of '../audio_engine.dart';

/// The output-device protocol shared by local and remote playback sources.
/// Source-specific decoder/header and buffer policy stays with each source.
class _AudioOutputConfiguration {
  final _PlaybackSession _host;
  int? _playerSampleRate;
  int? _playerChannels;
  int? _playerDeviceId;

  _AudioOutputConfiguration(this._host);

  Future<void> _configurePcmOutput() async {
    if (_host._player == null ||
        _playerSampleRate != _host._sampleRate ||
        _playerChannels != _host._channels ||
        _playerDeviceId != _host._outputDeviceId) {
      final epoch = ++_host._outputEpoch;
      final previous = _host._player;

      if (previous != null) {
        await _host._disposeReplacedOutput(previous);
      }

      if (identical(_host._player, previous)) {
        _host._player = null;
      }

      if (!_host._isActive || epoch != _host._outputEpoch) {
        return;
      }

      final outputFactory = _host._outputFactory;
      final sampleRate = _host._sampleRate;
      final channels = _host._channels;
      final deviceId = _host._outputDeviceId;
      final player = outputFactory != null
          ? outputFactory(sampleRate, channels, deviceId)
          : createAudioPcmOutput(
              sampleRate: sampleRate,
              channels: channels,
              deviceId: deviceId,
              bitsPerSample: _host._pcmBitsPerSample,
              validBitsPerSample: _host._sourceBitDepth,
            );

      // Startup is owned immediately: stop must be able to await a device whose
      // native open is still pending, before the worker acknowledges release.
      _host._player = player;

      try {
        await player.initialize();
      } catch (_) {
        if (identical(_host._player, player)) {
          _host._player = null;
        }

        await player.dispose();

        rethrow;
      }

      if (!_host._isActive || epoch != _host._outputEpoch) {
        await player.dispose();

        return;
      }

      _playerSampleRate = sampleRate;
      _playerChannels = channels;
      _playerDeviceId = deviceId;
    }

    _host._player!.setVolume(_host._volume);

    if (_host._paused) {
      _host._player!.pause();
    }

    _host._sendPlaybackMessage({'type': 'state', 'active': true, 'paused': _host._paused});
  }
}

mixin _AudioOutputConfigurationFacade {
  _AudioOutputConfiguration get _ownerOutput;

  int? get _playerSampleRate => _ownerOutput._playerSampleRate;

  set _playerSampleRate(int? value) => _ownerOutput._playerSampleRate = value;

  int? get _playerChannels => _ownerOutput._playerChannels;

  set _playerChannels(int? value) => _ownerOutput._playerChannels = value;

  set _playerDeviceId(int? value) => _ownerOutput._playerDeviceId = value;

  Future<void> _configurePcmOutput() => _ownerOutput._configurePcmOutput();
}
