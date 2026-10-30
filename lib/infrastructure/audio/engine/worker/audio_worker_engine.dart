part of '../audio_engine.dart';

class _GaplessOccurrence {
  final _PlaybackSession session;
  final _GaplessSourceOutput output;
  final int? preparationId;
  final int listeningRevision;
  final Map<String, dynamic>? context;
  bool ended = false, completeReported = false;
  bool acknowledged = false;
  _GaplessOccurrence? predecessor;
  _GaplessOccurrence(this.session, this.output, this.preparationId, this.listeningRevision, this.context);
}

class _AudioWorkerEngine {
  final void Function(Map<String, dynamic>) _send;
  final AudioPcmOutput Function(int, int, int, int, int)? outputFactory;
  final AudioFileDecoder Function(String, Uri, Duration)? fileDecoderFactory;
  final OpusDecoder Function(int, int)? decoderFactory;
  final QuicClient Function(String)? transportFactory;
  final Duration outputProgressTimeout;
  final Duration transportProgressTimeout;
  final Set<_GaplessOccurrence> _occurrences = {};
  final Set<Future<void>> _runs = {};
  final Map<int, Future<void>> _cancellations = {};
  _GaplessOccurrence? _current, _prepared, _following;
  _GaplessOccurrence? _seekingOccurrence;
  int _seekGeneration = 0;
  final Map<int, _GaplessOccurrence> _unacknowledged = {};
  _GaplessOutputTimeline? _timeline;
  int _playbackId = 0, _startGeneration = 0, _preparationGeneration = 0, _listeningRevision = 0;
  int _tailGeneration = 0;
  int _requestedPlaybackId = 0;
  final List<Map> _pendingPreparations = [];
  bool _stopping = false;
  int _audibleSuppression = 0;
  int _pauseRevision = 0;
  Future<void>? _retiringOutput;
  double _volume = 1;
  int _outputDeviceId = kDefaultOutputDeviceId;
  bool _paused = false;
  bool gaplessResampling = false;
  bool _buffering = false;
  Map<String, dynamic>? _latestListeningContext;
  Future<void>? _stopInFlight;

  _AudioWorkerEngine({
    required void Function(Map<String, dynamic>) send,
    this.outputFactory,
    this.fileDecoderFactory,
    this.decoderFactory,
    this.transportFactory,
    this.outputProgressTimeout = const Duration(seconds: 5),
    this.transportProgressTimeout = const Duration(seconds: 15),
  }) : _send = send;

  Future<void> stop({bool notify = true}) {
    if (notify) _startGeneration++;
    return _stopInFlight ??= _stopSession(notify).whenComplete(() => _stopInFlight = null);
  }

  Future<void> dispose() => stop();
  void acknowledge(int id) {
    final entry = _unacknowledged.remove(id);
    if (entry != null) {
      entry.acknowledged = true;
      entry.predecessor = null;
    }
  }

  void configureListening(Map<String, dynamic>? context, {bool discardPending = true}) {
    _listeningRevision++;
    _latestListeningContext = context;
    for (final entry in _occurrences.toList()) {
      unawaited(
        entry.session.configureListening(identical(entry, _current) ? context : null, discardPending: discardPending),
      );
    }
  }

  Future<void> pause({int? playbackId}) async {
    if (playbackId != null && playbackId != (_requestedPlaybackId > 0 ? _requestedPlaybackId : _playbackId)) return;
    final revision = ++_pauseRevision;
    final startGeneration = _startGeneration;
    _paused = true;
    _timeline?.pause();
    for (final entry in _occurrences.toList()) {
      if (revision != _pauseRevision || startGeneration != _startGeneration || !_paused) return;
      await entry.session.pause();
    }
  }

  void resume({int? playbackId}) {
    if (playbackId != null && playbackId != (_requestedPlaybackId > 0 ? _requestedPlaybackId : _playbackId)) return;
    _pauseRevision++;
    _paused = false;
    _timeline?.resume();
    for (final entry in _occurrences.toList()) {
      entry.session.resume();
    }
    if (_buffering) _send({'type': 'gapless_buffering', 'waiting': true, 'playback_id': _playbackId});
  }

  void setVolume(double value) {
    _volume = value.clamp(0.0, 1.0);
    _timeline?.setVolume(_volume);
    for (final entry in _occurrences) {
      entry.session._volume = _volume;
    }
  }

  void setOutputDevice(int deviceId) {
    _outputDeviceId = deviceId;
    for (final entry in _occurrences) {
      entry.session.setOutputDevice(deviceId);
    }
  }

  Future<void> seekTo(Duration position, {int? playbackId, int requestId = 0}) async {
    final current = _current;
    final sessionId = _playbackId;
    final startGeneration = _startGeneration;
    if ((playbackId != null && playbackId != sessionId) || current == null || _stopping) {
      _send({'type': 'seek_failed', 'request_id': requestId, 'playback_id': playbackId});
      return;
    }
    final seekGeneration = ++_seekGeneration;
    _seekingOccurrence = current;
    bool isCurrent() =>
        !_stopping &&
        sessionId == _playbackId &&
        startGeneration == _startGeneration &&
        seekGeneration == _seekGeneration &&
        identical(current, _current) &&
        !current.output._cancelled;
    try {
      // Cancellation flushes a submitted successor, but the requested seek
      // replaces its ordinary rewind of the current track.
      await cancelPreparedNext();
      if (!isCurrent()) {
        _send({'type': 'seek_failed', 'request_id': requestId, 'playback_id': sessionId});
        return;
      }
      await current.session.seekTo(position, requestId: requestId);
    } catch (error) {
      if (isCurrent()) {
        _send({'type': 'message', 'text': 'Unable to prepare audio seek: $error', 'playback_id': sessionId});
      }
      _send({'type': 'seek_failed', 'request_id': requestId, 'playback_id': sessionId});
    } finally {
      if (seekGeneration == _seekGeneration) _seekingOccurrence = null;
    }
  }

  Future<void> playTrack({
    required int playbackId,
    required String trackId,
    required String trackTitle,
    required String baseUrl,
    required String token,
    String serverPin = '',
    required StreamSettings settings,
    Duration startOffset = Duration.zero,
    List<String> queueTrackIds = const [],
    int? quicPort,
    bool quickStart = true,
    bool initialPaused = false,
    Map<String, dynamic>? listeningContext,
  }) async {
    final generation = ++_startGeneration;
    _requestedPlaybackId = playbackId;
    _pendingPreparations.clear();
    final listeningRevision = _listeningRevision;
    final pauseRevision = _pauseRevision;
    await stop(notify: false);
    if (generation != _startGeneration) return;
    _begin(playbackId, pauseRevision == _pauseRevision ? initialPaused : _paused);
    _current = _create(
      trackId: trackId,
      trackTitle: trackTitle,
      baseUrl: baseUrl,
      token: token,
      serverPin: serverPin,
      settings: settings,
      startOffset: startOffset,
      queueTrackIds: queueTrackIds,
      quicPort: quicPort,
      quickStart: quickStart,
      context: listeningRevision == _listeningRevision ? listeningContext : _latestListeningContext,
    );
    _launch(_current!);
    unawaited(_drainPreparations(playbackId));
  }

  Future<void> playLocalFile({
    required int playbackId,
    required String trackId,
    required String trackTitle,
    required String filePath,
    Duration startOffset = Duration.zero,
    bool initialPaused = false,
    Map<String, dynamic>? listeningContext,
  }) async {
    final generation = ++_startGeneration;
    _requestedPlaybackId = playbackId;
    _pendingPreparations.clear();
    final listeningRevision = _listeningRevision;
    final pauseRevision = _pauseRevision;
    await stop(notify: false);
    if (generation != _startGeneration) return;
    _begin(playbackId, pauseRevision == _pauseRevision ? initialPaused : _paused);
    _current = _create(
      trackId: trackId,
      trackTitle: trackTitle,
      filePath: filePath,
      settings: const StreamSettings(mode: 'local', quality: 'source'),
      startOffset: startOffset,
      context: listeningRevision == _listeningRevision ? listeningContext : _latestListeningContext,
    );
    _launch(_current!);
    unawaited(_drainPreparations(playbackId));
  }

  void _begin(int id, bool paused) {
    _stopping = false;
    _playbackId = id;
    _paused = paused;
    _seekGeneration++;
    _seekingOccurrence = null;
    _cancellations.clear();
    _timeline = _GaplessOutputTimeline(
      factory: outputFactory,
      normalize: gaplessResampling,
      progressTimeout: outputProgressTimeout,
    )..setVolume(_volume);
    if (_paused) _timeline!.pause();
  }

  Future<void> prepareNext(Map message) async {
    if (message['playback_id'] == _requestedPlaybackId && (_stopping || _current == null || _timeline == null)) {
      if (message['after_preparation_id'] == null) {
        _pendingPreparations.clear();
        _pendingPreparations.add(Map.from(message));
      } else if (_pendingPreparations.length == 1 &&
          _pendingPreparations.first['preparation_id'] == message['after_preparation_id']) {
        _pendingPreparations.add(Map.from(message));
      }
      return;
    }
    if (message['playback_id'] != _playbackId || _current == null || _timeline == null) return;
    final after = (message['after_preparation_id'] as num?)?.toInt();
    final generation = after == null ? ++_preparationGeneration : ++_tailGeneration;
    if (after == null) {
      await cancelPreparedNext(invalidate: false);
    } else if (_following != null) {
      await cancelPreparedNext(invalidate: false, preparationId: _following!.preparationId);
    }
    if (generation != (after == null ? _preparationGeneration : _tailGeneration) ||
        _current == null ||
        _timeline == null) {
      return;
    }
    if (after != null &&
        after != _prepared?.preparationId &&
        !(after == _current?.preparationId && _prepared == null)) {
      _send({
        'type': 'gapless_preparation_failed',
        'preparation_id': message['preparation_id'],
        'playback_id': _playbackId,
      });
      return;
    }
    final rawContext = message['listening_context'];
    final id = (message['preparation_id'] as num?)?.toInt();
    if (id == null || id <= 0) return;
    const defaultSettings = StreamSettings.original();
    final entry = _create(
      preparationId: id,
      trackId: message['track_id']?.toString() ?? '',
      trackTitle: message['track_title']?.toString() ?? '',
      baseUrl: message['base_url']?.toString() ?? '',
      token: message['token']?.toString() ?? '',
      serverPin: message['server_pin']?.toString() ?? '',
      filePath: message['file_path'] as String?,
      quicPort: (message['quic_port'] as num?)?.toInt(),
      settings: StreamSettings(
        mode: message['mode']?.toString() ?? defaultSettings.mode,
        quality: message['quality']?.toString() ?? defaultSettings.quality,
        frameMs: (message['frame_ms'] as num?)?.toInt() ?? defaultSettings.frameMs,
      ),
      context: rawContext is Map ? Map<String, dynamic>.from(rawContext) : null,
    );
    if (after != null && after == _prepared?.preparationId) {
      _following = entry;
    } else {
      _prepared = entry;
    }
    _launch(entry);
  }

  Future<void> _drainPreparations(int id) async {
    final pending = _pendingPreparations.toList();
    _pendingPreparations.clear();
    for (final message in pending) {
      if (_requestedPlaybackId != id || _playbackId != id) return;
      await prepareNext(message);
    }
  }

  _GaplessOccurrence _create({
    required String trackId,
    required String trackTitle,
    required StreamSettings settings,
    String baseUrl = '',
    String token = '',
    String serverPin = '',
    String? filePath,
    int? preparationId,
    int? quicPort,
    Duration startOffset = Duration.zero,
    List<String> queueTrackIds = const [],
    bool quickStart = true,
    Map<String, dynamic>? context,
  }) {
    late _GaplessOccurrence entry;
    final playbackId = _playbackId;
    final output = _timeline!.addSource(
      onAudible: () => _becameAudible(entry),
      onAbort: (begin) => _audibleSuppression += begin ? 1 : -1,
    ).._isPrepared = preparationId != null;
    void send(Map<String, dynamic> message) => _handle(entry, message);
    AudioFileDecoder makeDecoder(Uri uri, Duration offset) => fileDecoderFactory!(trackId, uri, offset);
    final session = filePath != null
        ? _PlaybackSession.local(
            send: send,
            playbackId: playbackId,
            getPlaybackId: () => _playbackId,
            trackId: trackId,
            trackTitle: trackTitle,
            filePath: filePath,
            startOffset: startOffset,
            initialPaused: _paused,
            volume: _volume,
            outputDeviceId: _outputDeviceId,
            listeningContext: preparationId == null ? context : null,
            gaplessSource: output,
            fileDecoderFactory: fileDecoderFactory == null ? null : makeDecoder,
          )
        : _PlaybackSession.remote(
            send: send,
            releaseConnection: (connection) => connection.close(),
            playbackId: playbackId,
            getPlaybackId: () => _playbackId,
            trackId: trackId,
            trackTitle: trackTitle,
            baseUrl: baseUrl,
            token: token,
            serverPin: serverPin,
            quicPort: quicPort,
            settings: settings,
            startOffset: startOffset,
            queueTrackIds: queueTrackIds,
            quickStart: quickStart,
            transportProgressTimeout: transportProgressTimeout,
            initialPaused: _paused,
            volume: _volume,
            outputDeviceId: _outputDeviceId,
            listeningContext: preparationId == null ? context : null,
            gaplessSource: output,
            decoderFactory: decoderFactory,
            fileDecoderFactory: fileDecoderFactory == null ? null : makeDecoder,
            reusableConnection: settings.isOriginal ? null : transportFactory?.call(trackId),
          );
    entry = _GaplessOccurrence(session, output, preparationId, _listeningRevision, context);
    _occurrences.add(entry);
    return entry;
  }

  void _launch(_GaplessOccurrence entry) {
    late Future<void> run;
    run = entry.session.run().whenComplete(() {
      _runs.remove(run);
      _occurrences.remove(entry);
    });
    _runs.add(run);
    unawaited(run);
  }

  void _becameAudible(_GaplessOccurrence entry) {
    if (entry.output._cancelled || entry.session._playbackId != _playbackId) return;
    if (entry.preparationId == null || identical(entry, _current)) return;
    final context = entry.listeningRevision == _listeningRevision ? entry.context : null;
    entry.session._listening.setContext(
      context == null ? null : {...context, 'session_started_at_ms': DateTime.now().toUtc().millisecondsSinceEpoch},
    );
    if (_stopping || _audibleSuppression > 0) return;
    entry.predecessor = _current;
    _unacknowledged[entry.preparationId!] = entry;
    _current = entry;
    if (identical(_prepared, entry)) {
      _prepared = _following;
      _following = null;
    }
    _setBuffering(false);
    _send({'type': 'gapless_transition', 'preparation_id': entry.preparationId, 'playback_id': _playbackId});
    _send({'type': 'started', 'playback_id': _playbackId});
  }

  void _handle(_GaplessOccurrence entry, Map<String, dynamic> message) {
    final type = message['type'];
    if (type == 'listening_segment') {
      _send(message);
      return;
    }
    if (entry.session._playbackId != _playbackId) return;
    if (_stopping) return;
    if (type == 'state' && message['active'] == false && identical(entry, _current)) {
      _stopping = true;
      unawaited(stop(notify: false).then((_) => _send(message)));
      return;
    }
    if (type == 'complete') {
      entry.ended = true;
      if ((identical(_prepared, entry) || identical(_following, entry)) && entry.output._deviceWritten == 0) {
        _preparationFailed(entry);
      } else {
        _maybeComplete(entry);
      }
      return;
    }
    if (type == 'state' &&
        message['active'] == false &&
        (identical(_prepared, entry) || identical(_following, entry))) {
      _preparationFailed(entry);
      return;
    }
    if (identical(entry, _current)) _send(message);
  }

  void _preparationFailed(_GaplessOccurrence entry) {
    unawaited(
      cancelPreparedNext(preparationId: entry.preparationId).then((_) {
        _send({
          'type': 'gapless_preparation_failed',
          'preparation_id': entry.preparationId,
          'playback_id': entry.session._playbackId,
        });
        final current = _current;
        if (current != null) _maybeComplete(current);
      }),
    );
  }

  void _maybeComplete(_GaplessOccurrence entry) {
    if (!entry.ended || entry.completeReported || !identical(entry, _current)) return;
    if (_prepared != null || _following != null) {
      _setBuffering(true);
      return;
    }
    _setBuffering(false);
    entry.completeReported = true;
    if (entry.output._deviceWritten == 0 && entry.session._baseOffsetMs == 0) {
      _send({'type': 'message', 'text': 'The source contains no playable audio.', 'playback_id': _playbackId});
      _send({'type': 'state', 'active': false, 'paused': false, 'source_rejected': true, 'playback_id': _playbackId});
    } else {
      _send({'type': 'complete', 'playback_id': _playbackId});
    }
    final timeline = _timeline;
    _timeline = null;
    if (timeline != null) {
      final closing = timeline.close();
      _retiringOutput = closing;
      unawaited(
        closing.whenComplete(() {
          if (identical(_retiringOutput, closing)) _retiringOutput = null;
        }),
      );
    }
  }

  void _setBuffering(bool waiting) {
    if (_buffering == waiting) return;
    _buffering = waiting;
    _send({'type': 'gapless_buffering', 'waiting': waiting, 'playback_id': _playbackId});
  }

  Future<void> cancelPreparedNext({bool invalidate = true, int? preparationId}) {
    if (preparationId == null) {
      _pendingPreparations.clear();
    } else {
      final index = _pendingPreparations.indexWhere((item) => item['preparation_id'] == preparationId);
      if (index >= 0) _pendingPreparations.removeRange(index, _pendingPreparations.length);
    }
    if (preparationId == null && _cancellations.isNotEmpty) {
      return _joinPreparedCancellations(invalidate: invalidate);
    }
    final key = preparationId ?? _prepared?.preparationId ?? 0;
    final pending = _cancellations[key];
    if (pending != null) return pending;
    final keys = <int>{key};
    if (preparationId == null ||
        preparationId == _prepared?.preparationId ||
        (preparationId == _following?.preparationId && (_following?.output._deviceWritten ?? 0) > 0)) {
      for (final entry in [_prepared, _following]) {
        if (entry?.preparationId != null) keys.add(entry!.preparationId!);
      }
    }
    if (_unacknowledged.containsKey(preparationId)) {
      for (final entry in [_prepared, _following, ..._unacknowledged.values]) {
        if (entry?.preparationId != null) keys.add(entry!.preparationId!);
      }
    }
    final timeline = _timeline;
    final playbackId = _playbackId;
    final startGeneration = _startGeneration;
    final future = _cancelPreparedNext(invalidate: invalidate, preparationId: preparationId).catchError((Object error) {
      if (!_stopping &&
          playbackId == _playbackId &&
          startGeneration == _startGeneration &&
          identical(timeline, _timeline)) {
        throw error;
      }
      // A release failure from an already retired timeline cannot fail the
      // replacement worker command or revive its old playback occurrence.
    });
    for (final id in keys) {
      _cancellations[id] = future;
    }
    return future.whenComplete(() {
      for (final id in keys) {
        if (identical(_cancellations[id], future)) _cancellations.remove(id);
      }
    });
  }

  Future<void> _joinPreparedCancellations({required bool invalidate}) async {
    final timeline = _timeline;
    final playbackId = _playbackId;
    final startGeneration = _startGeneration;
    bool isCurrent() =>
        !_stopping &&
        playbackId == _playbackId &&
        startGeneration == _startGeneration &&
        identical(timeline, _timeline);
    while (isCurrent() && _cancellations.isNotEmpty) {
      final pending = _cancellations.values.toSet();
      await Future.wait(pending);
    }
    if (isCurrent()) {
      // A targeted tail cancellation can leave the head in place. Re-evaluate
      // after release rather than treating a targeted future as cancel-all.
      await cancelPreparedNext(invalidate: invalidate);
    }
  }

  Future<void> _cancelPreparedNext({bool invalidate = true, int? preparationId}) async {
    final timeline = _timeline;
    final playbackId = _playbackId;
    final startGeneration = _startGeneration;
    bool isCurrent() =>
        !_stopping &&
        playbackId == _playbackId &&
        startGeneration == _startGeneration &&
        identical(timeline, _timeline);
    if (!isCurrent()) return;
    final tailOnly = preparationId != null && preparationId == _following?.preparationId;
    if (invalidate) {
      _tailGeneration++;
      if (!tailOnly) _preparationGeneration++;
    }
    final selected = tailOnly ? _following : _prepared;
    if ((_unacknowledged.containsKey(preparationId)) ||
        ((preparationId == null || selected?.preparationId == preparationId) &&
            (selected?.output._deviceWritten ?? 0) > 0)) {
      timeline?.pauseOutput();
      _audibleSuppression++;
      try {
        await timeline?.poll();
      } finally {
        _audibleSuppression--;
      }
    }
    if (!isCurrent()) return;
    // A renderer marker may have crossed while its UI notification was in
    // flight. Targeted invalidation must retract that occurrence as well.
    final audible = _unacknowledged[preparationId];
    if (audible != null && !audible.acknowledged && audible.predecessor != null) {
      final predecessor = audible.predecessor!;
      final cancelled = <_GaplessOccurrence>{
        ..._unacknowledged.values,
        if (_current != null) _current!,
        if (_prepared != null) _prepared!,
        if (_following != null) _following!,
      }..remove(predecessor);
      _prepared = _following = null;
      _current = predecessor;
      for (final entry in cancelled) {
        entry.output.cancel();
        _unacknowledged.remove(entry.preparationId);
      }
      await timeline?.flush();
      await Future.wait(cancelled.map((entry) => entry.session.requestStop(outcome: 'superseded')));
      if (!isCurrent()) return;
      predecessor.ended = true;
      _maybeComplete(predecessor);
      return;
    }
    final entry = tailOnly ? _following : _prepared;
    if (entry == null || (preparationId != null && entry.preparationId != preparationId)) return;
    final committed = entry.output._deviceWritten > 0;
    final cancelled = <_GaplessOccurrence>{entry};
    if (!tailOnly || committed) {
      if (_prepared != null) cancelled.add(_prepared!);
      if (_following != null) cancelled.add(_following!);
      _prepared = _following = null;
    } else {
      _following = null;
    }
    _setBuffering(false);
    for (final item in cancelled) {
      item.output.cancel();
    }
    if (committed) timeline?.pauseOutput();
    await Future.wait(cancelled.map((item) => item.session.requestStop(outcome: 'superseded')));
    if (!isCurrent()) return;
    if (committed) {
      final current = _current;
      await timeline?.poll();
      if (!isCurrent() || !identical(current, _current)) return;
      if (current != null && identical(current, _seekingOccurrence)) {
        await timeline?.flush();
        return;
      }
      if (current != null && !identical(current, entry) && !current.ended) {
        final source = current.output;
        final position =
            current.session._baseOffsetMs + source._played * 1000 ~/ math.max(1, source.rate * source.channels);
        timeline?.pauseOutput();
        await current.session.seekTo(Duration(milliseconds: position));
        await current.session._ownerSeek._seekCompletion?.future.timeout(const Duration(seconds: 6));
      } else {
        await timeline?.flush();
        if (!isCurrent()) return;
        if (current != null) _maybeComplete(current);
      }
    }
  }

  Future<void> _stopSession(bool notify) async {
    _preparationGeneration++;
    _tailGeneration++;
    _stopping = true;
    if (notify) {
      _requestedPlaybackId = 0;
      _pendingPreparations.clear();
    }
    final id = _playbackId;
    await _retiringOutput;
    _timeline?.pause();
    try {
      await _timeline?.poll();
    } catch (_) {
      /* Output failure still releases every source. */
    }
    final entries = _occurrences.toList();
    _current = _prepared = _following = null;
    _unacknowledged.clear();
    _buffering = false;
    final timeline = _timeline;
    _timeline = null;
    for (final entry in entries) {
      entry.output.cancel();
    }
    await timeline?.close();
    await Future.wait(entries.map((entry) => entry.session.requestStop(outcome: notify ? 'cancelled' : 'superseded')));
    if (notify) _send({'type': 'state', 'active': false, 'paused': false, 'playback_id': id});
  }
}
