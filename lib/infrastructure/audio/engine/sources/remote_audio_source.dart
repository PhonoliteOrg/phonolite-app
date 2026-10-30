part of '../audio_engine.dart';

class _RemoteAudioSource {
  final _PlaybackSession _host;
  bool _remoteContinuation = false;
  bool _waitingForHeader = false;
  int _incomingStartMs = 0;
  int? _incomingRangeEndMs;
  bool _incomingEndOfTrack = true;
  String _sourceVersion = '';
  int? _transportRequestId;
  Future<void>? _outputReset;

  _RemoteAudioSource(this._host);

  void _requestRemoteRange(int ms, {required bool continuation}) {
    final quic = _host._quic;

    if (quic == null || !_host._isActive) {
      return;
    }

    _host._rawReader.reset();
    _host._incomingSegment = null;
    _incomingStartMs = ms;
    _incomingRangeEndMs = null;
    _incomingEndOfTrack = true;
    _remoteContinuation = continuation;
    _host._pendingSeekMs = ms;
    _host._pendingSeekId = _host._allocateSeekId();
    _waitingForHeader = true;

    try {
      _transportRequestId = quic.seek(trackId: _host.trackId, positionMs: ms, seekId: _host._pendingSeekId!);
      _host._reportBuffer(force: true);
    } catch (error) {
      _waitingForHeader = false;
      _host._failSeek('error');

      throw Exception('Unable to request audio range: $error');
    }
  }

  void _pollTransportEvents(QuicClient quic) {
    Map<String, Object?>? event;

    while ((event = quic.pollEvent()) != null) {
      final requestId = (event!['request_id'] as num?)?.toInt();

      if (requestId != null && requestId != _transportRequestId) {
        continue;
      }

      if (event['type'] == 'error') {
        final message = 'Audio range request failed: ${event['message']}';

        if (event['origin'] == 'server' && event['retryable'] != true && !_retryableServerFailure(event['message'])) {
          throw AudioSourceRejected(message);
        }

        _host._failSeek('server_error');

        throw Exception(message);
      }

      if (event['type'] != 'stream') {
        continue;
      }

      final version = event['source_version']?.toString() ?? '';

      if (_sourceVersion.isNotEmpty && version.isNotEmpty && _sourceVersion != version) {
        throw Exception('The audio source changed during playback.');
      }

      _sourceVersion = version;
      _incomingStartMs = (event['position_ms'] as num?)?.toInt() ?? _incomingStartMs;
      _incomingRangeEndMs = (event['range_end_ms'] as num?)?.toInt();
      _incomingEndOfTrack = event['end_of_track'] != false;
    }
  }

  bool _retryableServerFailure(Object? message) {
    // Older servers expose only a message. Keep their explicit admission and
    // shutdown failures recoverable; unknown source/auth failures stay rejected.
    final text = message?.toString().toLowerCase() ?? '';
    return text.contains('capacity exhausted') ||
        text.contains('stream capacity unavailable') ||
        text.contains('streamlimit') ||
        text.contains('server shutting down') ||
        text.contains('worker stopped');
  }

  Future<void> _receiveRemoteAudio(QuicClient quic) async {
    final data = Uint8List(64 * 1024);
    final progress = _AudioProgressDeadline(_host.transportProgressTimeout);
    var progressRequestId = _transportRequestId;

    while (_host._isActive && !_host._remotePlaybackComplete) {
      _pollTransportEvents(quic);

      if (progressRequestId != _transportRequestId) {
        progressRequestId = _transportRequestId;
        progress.reset();
      }

      if (_host._streamEnded && !_waitingForHeader) {
        progress.reset();
        await Future<void>.delayed(const Duration(milliseconds: 5));
        continue;
      }

      final segment = _host._incomingSegment;
      final cursor = _host._decodeCursor;

      if (!_waitingForHeader &&
          segment != null &&
          segment.complete &&
          !segment.endOfTrack &&
          cursor != null &&
          segment.rangeEndMs - _host._positionMs <= (_host._userPaused ? 2000 : 8000)) {
        final next = _host._encodedCache.seek(segment.rangeEndMs);

        if (next == null) {
          _requestRemoteRange(segment.rangeEndMs, continuation: true);
        }
      }

      // Limit encoded read-ahead by playback time, independently of PCM space.
      // Control events are still consumed every iteration, including while paused.
      final ahead = _host._encodedCache.bufferedAheadMs(_host._positionMs);
      final horizon = _host._encodedReadAheadTargetMs;

      if (!_waitingForHeader && ahead >= horizon + 1000) {
        progress.reset();
        _host._reportBuffer();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        continue;
      }

      final read = quic.read(data);

      _pollTransportEvents(quic);

      if (progressRequestId != _transportRequestId) {
        progressRequestId = _transportRequestId;
        progress.reset();
      }

      if (read == -5) {
        progress.check(
          waiting: !_host._userPaused && (_waitingForHeader || ahead < horizon),
          operation: 'QUIC audio delivery',
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        continue;
      }

      if (read <= 0) {
        throw Exception('QUIC audio connection failed: ${quic.lastError() ?? read}');
      }

      _host._bytesReceived += read;
      progress.reset();

      for (final event in _host._rawReader.add(Uint8List.sublistView(data, 0, read))) {
        if (event is RawOpusSeekMarker) {
          if (_host._pendingSeekId != event.seekId) {
            throw Exception('Unexpected audio seek generation.');
          }

          _host._activeSeekId = event.seekId;
          _host._pendingSeekId = null;
        } else if (event is RawOpusStreamHeader) {
          final headerTrack = extractRawHeaderTrackId(event.bytes);

          if (headerTrack != null && headerTrack != _host.trackId) {
            throw Exception('Audio range belongs to a different track.');
          }

          final header = event.header;
          final incoming = EncodedAudioSegment(
            header: header,
            startMs: _incomingStartMs,
            rangeEndMs: _incomingRangeEndMs ?? header.durationMs,
            endOfTrack: _incomingEndOfTrack,
            sourceVersion: _sourceVersion,
          );

          if (!_host._encodedCache.addSegment(incoming, pinned: _host._decodeCursor?.segment)) {
            throw Exception('Encoded audio cache exceeded its memory budget.');
          }

          _host._incomingSegment = incoming;
          _waitingForHeader = false;
          _host._pendingSeekMs = null;

          if (!_remoteContinuation && _host._decodeCursor == null) {
            _host._decodeCursor = incoming.cursorAt(incoming.startMs);
          }
        } else if (event is RawOpusPacket) {
          final incoming = _host._incomingSegment;
          if (incoming == null) {
            throw Exception('Audio packet without a range header.');
          }

          if (!_host._encodedCache.append(incoming, event.bytes, pinned: _host._decodeCursor?.segment)) {
            throw Exception('Encoded audio cache exceeded its memory budget.');
          }
        } else if (event is RawOpusEnd) {
          final incoming = _host._incomingSegment;
          if (incoming == null) {
            throw Exception('Audio range ended before its header.');
          }

          incoming.complete = true;
        }
      }

      _host._reportBuffer();
    }
  }

  Future<void> _configureRemoteOutput(
    RawOpusHeader header, {
    required int generation,
    required EncodedAudioCursor cursor,
  }) async {
    final reset = _outputReset;

    if (reset != null) {
      await reset;

      if (identical(reset, _outputReset)) {
        _outputReset = null;
      }
    }

    if (!_host._isActive || generation != _host._seekRequestGeneration || !identical(cursor, _host._decodeCursor)) {
      return;
    }

    _host._sampleRate = header.sampleRate;
    _host._channels = header.channels;
    _host._frameSamples = _host._sampleRate * header.frameMs ~/ 1000;
    _host._pumpChunkSamples = _host._sampleRate * _host._channels * _PlaybackSession._pumpChunkMs ~/ 1000;
    _host._refreshBufferTargets();

    _host._buffer ??= PcmRingBuffer(math.max(_host._sampleRate * _host._channels, _host._rebufferTargetSamples * 2));
    _host._ensureBufferCapacity();

    await _host._configurePcmOutput();
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _RemoteAudioSourceFacade {
  _RemoteAudioSource get _ownerRemote;

  set _remoteContinuation(bool value) => _ownerRemote._remoteContinuation = value;

  bool get _waitingForHeader => _ownerRemote._waitingForHeader;

  set _waitingForHeader(bool value) => _ownerRemote._waitingForHeader = value;

  set _incomingStartMs(int value) => _ownerRemote._incomingStartMs = value;

  set _transportRequestId(int? value) => _ownerRemote._transportRequestId = value;

  set _outputReset(Future<void>? value) => _ownerRemote._outputReset = value;

  void _requestRemoteRange(int ms, {required bool continuation}) =>
      _ownerRemote._requestRemoteRange(ms, continuation: continuation);

  Future<void> _receiveRemoteAudio(QuicClient quic) => _ownerRemote._receiveRemoteAudio(quic);

  Future<void> _configureRemoteOutput(
    RawOpusHeader header, {
    required int generation,
    required EncodedAudioCursor cursor,
  }) => _ownerRemote._configureRemoteOutput(header, generation: generation, cursor: cursor);
}
