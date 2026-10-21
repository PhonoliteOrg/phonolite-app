part of 'package:phonolite_app/infrastructure/audio/engine/audio_engine.dart';

class _AudioListeningSession {
  final _PlaybackSession _host;
  int _listeningContextRevision = 0;

  _AudioListeningSession(this._host);

  Future<void> configureListening(Map<String, dynamic>? context, {bool discardPending = true}) async {
    final revision = ++_listeningContextRevision;

    if (context == null && discardPending) {
      _host._listening.setContext(null);

      return;
    }

    final player = _host._player;

    if (player != null) {
      try {
        // Account changes/re-enabling do not claim audio consumed before the
        // new context. Keep queue accounting and the previous recorder aligned.
        final epoch = _host._outputEpoch;
        final done = await _collectListeningSamples(player);

        if (epoch == _host._outputEpoch && identical(player, _host._player)) {
          _host._playedSamples += done;
        }
      } catch (_) {}
    }

    if (revision != _listeningContextRevision || _host._stopRequested) {
      return;
    }

    if (context == null) {
      _host._listening.flush(endReason: 'interrupted');
    }

    _host._listening.setContext(context);
  }

  Future<int> _collectListeningSamples(AudioPcmOutput player) async {
    // A replacement header can change the decoder format during the native
    // call. Convert this output's samples using its captured format.
    final sampleRate = _host._playerSampleRate ?? _host._sampleRate;
    final channels = _host._playerChannels ?? _host._channels;

    final done = await player.collectDoneSamples();

    _host._listening.addSamples(done, sampleRate: sampleRate, channels: channels);

    return done;
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _AudioListeningSessionFacade {
  _AudioListeningSession get _ownerListening;

  Future<void> configureListening(Map<String, dynamic>? context, {bool discardPending = true}) =>
      _ownerListening.configureListening(context, discardPending: discardPending);

  Future<int> _collectListeningSamples(AudioPcmOutput player) => _ownerListening._collectListeningSamples(player);
}
