part of '../audio_engine.dart';

class _OpusDecodePipeline {
  final _PlaybackSession _host;
  final EncodedAudioCache _encodedCache = EncodedAudioCache();
  final RawOpusStreamReader _rawReader = RawOpusStreamReader();
  EncodedAudioCursor? _decodeCursor;
  EncodedAudioSegment? _incomingSegment;
  int? _decodedThroughSample;

  _OpusDecodePipeline(this._host);

  Future<void> _decodeRemoteAudio() async {
    EncodedAudioCursor? configured;
    int configuredGeneration = -1;
    Future<void>? pump;

    try {
      while (_host._isActive) {
        final cachedSeek = _host._cachedSeek;

        if (cachedSeek != null) {
          _host._cachedSeek = null;
          _decodeCursor = cachedSeek;
        }

        final cursor = _decodeCursor;

        if (cursor == null) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          continue;
        }

        final generation = _host._seekRequestGeneration;

        if (!identical(cursor, configured) || generation != configuredGeneration) {
          _host._decoder?.dispose();
          _host._decoder = null;

          await _host._configureRemoteOutput(cursor.segment.header, generation: generation, cursor: cursor);

          if (!_host._isActive || generation != _host._seekRequestGeneration || !identical(cursor, _decodeCursor)) {
            continue;
          }

          if (generation != configuredGeneration) {
            // Use the server's accepted position (including endpoint clamping).
            _host._baseOffsetMs = cursor.positionMs;
            _decodedThroughSample = cursor.positionMs * _host._sampleRate ~/ 1000;
          }

          _host._decoder =
              _host._decoderFactory?.call(_host._sampleRate, _host._channels) ??
              OpusDecoder(sampleRate: _host._sampleRate, channels: _host._channels);
          configured = cursor;
          configuredGeneration = generation;

          if (!_host._pumpRunning) {
            pump = _host._runPump();
          }
        }

        if (_host._player != null && _host._buffer != null && !_host._pumpRunning) {
          pump = _host._runPump();
        }

        final segment = cursor.segment;

        if (cursor.packetIndex >= segment.packets.length) {
          final atEnd = segment.hasAllFrames;

          if (atEnd && segment.endOfTrack) {
            _host._streamEnded = true;

            if (_host._autoPaused && !_host._userPaused) {
              _host._resumeFromAutoPause();
            }

            if (!_host._paused && (_host._buffer?.length ?? 0) == 0) {
              final player = _host._player!;
              final epoch = _host._outputEpoch;
              final idle = await player.isIdle();

              if (!_host._isActive ||
                  generation != _host._seekRequestGeneration ||
                  epoch != _host._outputEpoch ||
                  !identical(cursor, _decodeCursor) ||
                  !identical(player, _host._player)) {
                continue;
              }

              if (idle && !_host._paused && (_host._buffer?.length ?? 0) == 0) {
                _host._remotePlaybackComplete = true;
                break;
              }
            }

            await Future<void>.delayed(const Duration(milliseconds: 5));
            continue;
          }

          if (segment.complete && !atEnd) {
            throw Exception('Encoded audio range ended before its advertised boundary.');
          }

          final nextMs = atEnd ? segment.rangeEndMs : segment.availableEndMs;
          final next = _encodedCache.seek(nextMs);

          if (next != null && !identical(next.segment, segment)) {
            // Range requests use milliseconds, but an incomplete packet cache
            // can finish between milliseconds. Drop any overlap already queued.
            final overlap = math.max(0, (_decodedThroughSample ?? 0) - nextMs * _host._sampleRate ~/ 1000);

            next.skipSamplesPerChannel += overlap;
            _decodeCursor = next;
            continue;
          }

          final incoming = _incomingSegment;
          // A retained partial range may have been abandoned by an earlier seek.
          // Wait only for its live producer or a replacement covering the gap;
          // a replacement header can arrive before its first audio packet.
          final receivingMissingAudio =
              incoming != null &&
              !incoming.complete &&
              (identical(incoming, segment) || (incoming.startMs <= nextMs && nextMs < incoming.rangeEndMs));

          if (!_host._waitingForHeader && !receivingMissingAudio) {
            _host._requestRemoteRange(nextMs, continuation: true);
          }

          await Future<void>.delayed(const Duration(milliseconds: 5));
          continue;
        }

        final packet = segment.packets[cursor.packetIndex];
        var samples = _host._decoder!.decode(
          packet,
          frameSize: segment.header.sampleRate * segment.header.frameMs ~/ 1000,
        );

        cursor.packetIndex++;

        final skip = math.min(samples.length, cursor.skipSamplesPerChannel * _host._channels);

        cursor.skipSamplesPerChannel -= skip ~/ _host._channels;

        if (skip > 0) {
          samples = samples.sublist(skip);
        }

        final endSamples = segment.playableFrames;
        final packetEndSamples = cursor.packetIndex * segment.frameSamples - segment.header.preSkip;
        final excessSamples = math.max(0, packetEndSamples - endSamples) * _host._channels;

        if (excessSamples > 0) {
          samples = samples.sublist(0, math.max(0, samples.length - excessSamples));
        }

        cursor.positionMs = math.min(
          segment.rangeEndMs,
          segment.startMs + math.max(0, packetEndSamples) * 1000 ~/ _host._sampleRate,
        );

        if (samples.isNotEmpty) {
          await _host._writeToBuffer(samples);
        }

        if (generation != _host._seekRequestGeneration) {
          continue;
        }

        _decodedThroughSample = math.max(
          _decodedThroughSample ?? 0,
          segment.startMs * _host._sampleRate ~/ 1000 + math.min(math.max(0, packetEndSamples), endSamples),
        );
      }

      if (pump != null) {
        await pump;
      }
    } catch (_) {
      _host.requestStop(outcome: 'decode_error');

      rethrow;
    }
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _OpusDecodePipelineFacade {
  _OpusDecodePipeline get _ownerDecoder;

  EncodedAudioCache get _encodedCache => _ownerDecoder._encodedCache;

  RawOpusStreamReader get _rawReader => _ownerDecoder._rawReader;

  EncodedAudioCursor? get _decodeCursor => _ownerDecoder._decodeCursor;

  set _decodeCursor(EncodedAudioCursor? value) => _ownerDecoder._decodeCursor = value;

  EncodedAudioSegment? get _incomingSegment => _ownerDecoder._incomingSegment;

  set _incomingSegment(EncodedAudioSegment? value) => _ownerDecoder._incomingSegment = value;

  set _decodedThroughSample(int? value) => _ownerDecoder._decodedThroughSample = value;

  Future<void> _decodeRemoteAudio() => _ownerDecoder._decodeRemoteAudio();
}
