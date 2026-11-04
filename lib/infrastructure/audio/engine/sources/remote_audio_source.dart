part of '../audio_engine.dart';

class _RemoteTransportFailure implements Exception {
  final String message;
  const _RemoteTransportFailure(this.message);
  @override
  String toString() => message;
}

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
  final Stopwatch _clock = Stopwatch()..start();
  late final AudioRecoveryEpisode _recovery = AudioRecoveryEpisode(now: () => _clock.elapsed);
  static const _policy = AudioRecoveryPolicy();
  int _routeGeneration = 0;
  int _transportGeneration = 0;
  bool _repairRequested = false;
  bool _repairing = false;
  bool _acceptedAudio = false;
  int _acceptedThroughMs = 0;
  int? _explicitTargetMs;

  _RemoteAudioSource(this._host);

  void onSeek(int positionMs) {
    _recovery.reset();
    _explicitTargetMs = null;
    _acceptedThroughMs = positionMs;
    _repairRequested = false;
  }

  int get _playableMs {
    final pcm = _host._bufferedAudioMs();
    // PCM and compressed ranges overlap. Only extend beyond the PCM interval.
    return pcm + _host._encodedCache.bufferedAheadMs(_host._positionMs + pcm);
  }

  int get _missingPositionMs {
    final explicit = _explicitTargetMs;
    return explicit ?? (_host._positionMs + _playableMs);
  }

  bool get _hasCompleteReserve {
    return !_waitingForHeader &&
        _host._encodedCache.hasCompleteTrackAhead(_host._positionMs + _host._bufferedAudioMs());
  }

  bool _terminalFailure(QuicClient quic, Object error) {
    if (error is AudioSourceRejected || error is ServerIdentityChangedException) return true;
    final explicit = error is QuicException ? error.kind : QuicFailureKind.none;
    final native = quic.lastFailureKind;
    return explicit == QuicFailureKind.identity ||
        explicit == QuicFailureKind.sourceRejected ||
        explicit == QuicFailureKind.cancelled ||
        native == QuicFailureKind.identity ||
        native == QuicFailureKind.sourceRejected ||
        native == QuicFailureKind.cancelled;
  }

  void notifyNetworkChange(int generation) {
    if (generation <= _routeGeneration || !_host._isActive || _host._remotePlaybackComplete) return;
    _routeGeneration = generation;
    if (_hasCompleteReserve) return;
    _recovery.interrupted();
    try {
      if (_host._quic?.notifyNetworkChange(generation) == true) return;
    } catch (_) {
      // Unsupported native adapters use the same-session reconnect fallback.
    }
    _repairRequested = true;
  }

  QuicClient connect() {
    final factory = _host._connectionFactory;
    if (factory != null) return factory();
    final uri = Uri.parse(_host.baseUrl);
    final host = uri.host.isEmpty ? '127.0.0.1' : uri.host;
    final httpPort = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
    final client = QuicClient.connect(
      host: host == 'localhost' ? '127.0.0.1' : host,
      port: (_host.quicPort ?? 0) > 0 ? _host.quicPort! : httpPort + 1,
      token: _host.token,
      serverPin: _host.serverPin,
    );
    client.setMigrationEnabled(const bool.fromEnvironment('PHONOLITE_QUIC_MIGRATION'));
    return client;
  }

  Never _connectionFailed(QuicClient quic, Object error) {
    if (_terminalFailure(quic, error)) {
      throw AudioSourceRejected(error.toString());
    }
    throw _RemoteTransportFailure(error.toString());
  }

  Future<void> _repairTransport() async {
    if (_repairing || !_host._isActive) return;
    if (_hasCompleteReserve) {
      _repairRequested = false;
      return;
    }
    _repairing = true;
    final seekGeneration = _host._seekRequestGeneration;
    _recovery.begin(_missingPositionMs);
    _recovery.interrupted();
    try {
      final delay = _policy.retryDelay(_recovery.attempts);
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay < _recovery.remaining ? delay : _recovery.remaining);
      }
      if (!_host._isActive) return;
      if (seekGeneration != _host._seekRequestGeneration) return;
      if (!_recovery.reserveAttempt()) {
        throw TimeoutException('Audio connection recovery exhausted.', AudioRecoveryPolicy.budget);
      }
      if (_host._encodedCache.bytes > 0 && _sourceVersion.isEmpty) {
        throw AudioSourceRejected('The server did not identify the retained audio source.');
      }
      final previous = _host._quic;
      _transportGeneration++;
      previous?.close();
      final position = _missingPositionMs;
      _host._rawReader.reset();
      _host._incomingSegment = null;
      _incomingStartMs = position;
      _incomingRangeEndMs = null;
      _incomingEndOfTrack = true;
      _remoteContinuation = _host._decodeCursor != null;
      _waitingForHeader = true;
      _host._streamEnded = false;
      _host._remotePlaybackComplete = false;
      _host._pendingSeekId = null;
      final replacement = connect();
      if (!_host._isActive) {
        replacement.close();
        return;
      }
      _host._quic = replacement;
      _transportRequestId = replacement.openTrack(
        trackId: _host.trackId,
        mode: _host.settings.mode,
        quality: _host.settings.quality,
        frameMs: _host.settings.frameMs,
        queue: _host.queueTrackIds,
        startMs: position,
      );
      _repairRequested = false;
      _host._reportBuffer(force: true);
      _host._log('Audio delivery reconnecting at ${position}ms (attempt ${_recovery.attempts}).');
    } on AudioSourceRejected {
      rethrow;
    } on ServerIdentityChangedException catch (error) {
      throw AudioSourceRejected(error.toString());
    } on TimeoutException {
      rethrow;
    } on QuicException catch (error) {
      if (error.kind != QuicFailureKind.transport && error.kind != QuicFailureKind.none) {
        throw AudioSourceRejected(error.toString());
      }
      _repairRequested = true;
    } catch (error) {
      _repairRequested = true;
      _host._log('Audio delivery retry deferred (${error.runtimeType}).');
    } finally {
      _repairing = false;
    }
  }

  void _requestRemoteRange(int ms, {required bool continuation}) {
    final quic = _host._quic;

    if (!_host._isActive) {
      return;
    }

    if (!continuation) {
      _explicitTargetMs = ms;
      _recovery.reset();
    }
    if (quic == null || _repairing || _repairRequested) {
      _waitingForHeader = true;
      _remoteContinuation = continuation;
      _repairRequested = true;
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
      if (_terminalFailure(quic, error)) throw AudioSourceRejected(error.toString());
      _repairRequested = true;
    }
  }

  void _pollTransportEvents(QuicClient quic) {
    Map<String, Object?>? event;

    while ((event = quic.pollEvent()) != null) {
      if (!identical(quic, _host._quic)) return;
      if (event!['type'] == 'transport_recovery') {
        _repairRequested = true;
        continue;
      }
      final requestId = (event['request_id'] as num?)?.toInt();

      if (requestId != null && requestId != _transportRequestId) {
        continue;
      }

      if (event['type'] == 'error') {
        final message = 'Audio range request failed: ${event['message']}';

        if (event['origin'] == 'server' && event['retryable'] != true && !_retryableServerFailure(event['message'])) {
          throw AudioSourceRejected(message);
        }

        _connectionFailed(quic, message);
      }

      if (event['type'] != 'stream') {
        continue;
      }

      final version = event['source_version']?.toString() ?? '';

      if (_sourceVersion.isNotEmpty && _sourceVersion != version) {
        throw AudioSourceRejected('The audio source changed during playback.');
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
    var transportGeneration = _transportGeneration;
    var lastProgress = _clock.elapsed;

    while (_host._isActive && !_host._remotePlaybackComplete) {
      try {
        if (_repairRequested) {
          await _repairTransport();
          if (!_host._isActive) return;
          if (_repairRequested) continue;
        }
        quic = _host._quic ?? quic;
        if (transportGeneration != _transportGeneration) {
          transportGeneration = _transportGeneration;
          progressRequestId = _transportRequestId;
          progress.reset();
          lastProgress = _clock.elapsed;
        }
        _pollTransportEvents(quic);
        if (_repairRequested) continue;
        if (_hasCompleteReserve) {
          progress.reset();
          _recovery.reset();
          await Future<void>.delayed(const Duration(milliseconds: 5));
          continue;
        }
        final coverage = _playableMs;
        if (_host._userPaused ||
            coverage >= _host._encodedReadAheadTargetMs ||
            _clock.elapsed - lastProgress < _policy.stallTimeout(playableMilliseconds: coverage)) {
          _recovery.observe(
            acceptedThrough: _acceptedThroughMs,
            playableMilliseconds: coverage,
            endOfTrack: _host._incomingSegment?.hasAllFrames == true && _host._incomingSegment?.endOfTrack == true,
          );
        }
        if (_recovery.active && _recovery.remaining == Duration.zero) {
          throw TimeoutException('Audio connection recovery exhausted.', AudioRecoveryPolicy.budget);
        }

        if (progressRequestId != _transportRequestId) {
          progressRequestId = _transportRequestId;
          progress.reset();
          lastProgress = _clock.elapsed;
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
          lastProgress = _clock.elapsed;
          _host._reportBuffer();
          await Future<void>.delayed(const Duration(milliseconds: 10));
          continue;
        }

        final int read;
        try {
          read = quic.read(data);
        } catch (error) {
          _connectionFailed(quic, error);
        }

        _pollTransportEvents(quic);

        if (progressRequestId != _transportRequestId) {
          progressRequestId = _transportRequestId;
          progress.reset();
          lastProgress = _clock.elapsed;
        }

        if (read == -5) {
          final waiting = !_host._userPaused && (_waitingForHeader || ahead < horizon);
          if (!waiting) lastProgress = _clock.elapsed;
          if (waiting &&
              _acceptedAudio &&
              _clock.elapsed - lastProgress >= _policy.stallTimeout(playableMilliseconds: _playableMs)) {
            _repairRequested = true;
            continue;
          }
          progress.check(waiting: waiting, operation: 'QUIC audio delivery');
          await Future<void>.delayed(const Duration(milliseconds: 10));
          continue;
        }

        if (read <= 0) {
          _connectionFailed(quic, 'QUIC audio connection failed: ${quic.lastError() ?? read}');
        }

        _host._bytesReceived += read;
        progress.reset();
        lastProgress = _clock.elapsed;

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
              throw AudioSourceRejected('Audio range belongs to a different track.');
            }

            final header = event.header;
            final oldHeader = _host._decodeCursor?.segment.header;
            if (oldHeader != null &&
                (oldHeader.sampleRate != header.sampleRate ||
                    oldHeader.channels != header.channels ||
                    oldHeader.bitrateBps != header.bitrateBps ||
                    oldHeader.frameMs != header.frameMs)) {
              throw AudioSourceRejected('The audio rendition changed during recovery.');
            }
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
            _explicitTargetMs = null;
            _host._reportBuffer(force: true);

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
            if (incoming.availableEndMs > incoming.startMs) {
              _acceptedAudio = true;
              _acceptedThroughMs = math.max(_acceptedThroughMs, incoming.availableEndMs);
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
        _recovery.observe(
          acceptedThrough: _acceptedThroughMs,
          playableMilliseconds: _playableMs,
          endOfTrack: _host._incomingSegment?.hasAllFrames == true && _host._incomingSegment?.endOfTrack == true,
        );
      } on _RemoteTransportFailure {
        _repairRequested = true;
        _recovery.interrupted();
      } on TimeoutException {
        if (_recovery.active) rethrow;
        _repairRequested = true;
      }
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
