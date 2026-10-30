part of '../app_controller.dart';

/// Reserves at most two future occurrences without changing the audible queue,
/// listening account or durable resume cursor. A second decoder is prepared only
/// when the first successor is under one second. The worker commits by occurrence
/// ID only after the corresponding output-frame marker has been consumed.
class _GaplessCoordinator {
  final AppController _host;
  int _revision = 0;
  int _nextId = 0;
  int? _preparing;
  int? _failedRevision;
  _GaplessCandidate? _candidate;
  _GaplessCandidate? _lookahead;
  int? _preparingLookahead;
  int? _failedLookaheadParent;
  int? _lastTransitionedId;
  bool waitingForSuccessor = false;

  _GaplessCoordinator(this._host);

  int? get preparedId => _candidate?.id;

  void buffering(bool waiting) {
    if (_host._disposed) return;
    waitingForSuccessor = waiting;
    _host._updatePlayback(
      isLoading: waiting && _host._wantsPlayback && !_host._audioSessionSuspended,
      nowPlaying: false,
    );
  }

  void invalidate({bool prepareAgain = false}) {
    if (waitingForSuccessor) buffering(false);
    final previous = _candidate;
    final lookahead = _lookahead;
    _candidate = null;
    _lookahead = null;
    _preparing = null;
    _preparingLookahead = null;
    _failedLookaheadParent = null;
    _lastTransitionedId = null;
    _failedRevision = null;
    _revision++;
    if (previous != null) _host._audio?.cancelPreparedNext(preparationId: previous.id);
    if (previous == null && lookahead != null) _host._audio?.cancelPreparedNext(preparationId: lookahead.id);
    _releaseReservation(lookahead);
    _releaseReservation(previous);
    if (prepareAgain) scheduleMicrotask(prepare);
  }

  void prepare() {
    if (_host._disposed ||
        _host._shutdown != null ||
        !_host._wantsPlayback ||
        _host._audioSessionSuspended ||
        _host._playbackState.track == null ||
        _host._isScrubbing ||
        _host._seeking ||
        _host._audio == null ||
        _preparing != null ||
        _failedRevision == _revision) {
      return;
    }
    final head = _candidate;
    if (head != null) {
      _prepareLookahead(head);
      return;
    }
    if (_preparingLookahead != null) return;
    final revision = _revision;
    _preparing = revision;
    unawaited(_prepare(revision));
  }

  void listeningChanged() {
    final enabled =
        _host.statsCollectionEnabled &&
        !_host._statsCoordinator._suspendedListeningForReset &&
        _host._listeningStats.storageError == null;
    for (final candidate in [_candidate, _lookahead]) {
      if (candidate == null) continue;
      final context = candidate.listeningContext;
      if ((context != null) != enabled ||
          (context != null &&
              (context['account_scope'] != _host._listeningStats.accountScope ||
                  context['history_generation'] != _host._listeningStats.historyGeneration ||
                  context['collection_revision'] != _host._listeningStats.preferenceRevision))) {
        invalidate(prepareAgain: true);
        return;
      }
    }
  }

  Future<void> _prepare(int revision) async {
    _GaplessCandidate? candidate;
    try {
      // Restoring membership/cursor is separate from advancing it. A restored
      // queue can invalidate this request; reserve again against its revision.
      if (_host._resumeCoordinator.hasDeferredNavigation) {
        if (!await _host._resumeCoordinator.prepareNavigation(1)) return;
        if (revision != _revision) {
          prepare();
          return;
        }
        if (_host._resumeCoordinator.hasDeferredNavigation) return;
      }
      candidate = await _reserve(revision);
      if (candidate == null) return;
      if (!_isCurrent(candidate)) {
        _releaseReservation(candidate);
        return;
      }
      _candidate = candidate;
      _host._audioEngine.setGaplessResampling(_host.gaplessResampling);
      await _sendCandidate(candidate);
      if (identical(_candidate, candidate)) _prepareLookahead(candidate);
    } catch (error) {
      if (_revision == revision) {
        _failedRevision = revision;
        if (identical(_candidate, candidate)) _candidate = null;
        _releaseReservation(candidate);
        _host._pushMessage('Next-track preparation deferred: $error', level: LogLevel.debug);
      } else {
        _releaseReservation(candidate);
      }
    } finally {
      if (_preparing == revision) _preparing = null;
    }
  }

  Future<void> _sendCandidate(_GaplessCandidate candidate) => _host._audioEngine.prepareNext(
    preparationId: candidate.id,
    afterPreparationId: candidate.afterId,
    track: candidate.track,
    connection: _host.connection,
    settings: _host._playbackCoordinator._streamSettings(_host._playbackState.streamMode),
    filePath: candidate.filePath,
    quicPort: _host._quicPort,
    listeningContext: candidate.listeningContext,
  );

  void _prepareLookahead(_GaplessCandidate parent) {
    if (!identical(_candidate, parent) ||
        parent.track.durationMs >= 1000 ||
        _lookahead != null ||
        _preparingLookahead != null ||
        _failedLookaheadParent == parent.id ||
        _host._disposed ||
        !_host._wantsPlayback) {
      return;
    }
    _preparingLookahead = parent.id;
    unawaited(_prepareTail(parent));
  }

  Future<void> _prepareTail(_GaplessCandidate parent) async {
    _GaplessCandidate? candidate;
    bool isCurrent() =>
        !_host._disposed &&
        _preparingLookahead == parent.id &&
        parent.sourceSession == _host.connection.sessionRevision &&
        (identical(_candidate, parent) || (_lastTransitionedId == parent.id && _candidate == null));
    try {
      candidate = await _reserve(_revision, after: parent);
      if (candidate == null) {
        if (isCurrent()) _failedLookaheadParent = parent.id;
        return;
      }
      if (!isCurrent()) {
        _releaseReservation(candidate);
        return;
      }
      candidate.revision = _revision;
      if (identical(_candidate, parent)) {
        _lookahead = candidate;
      } else {
        _candidate = candidate;
      }
      await _sendCandidate(candidate);
    } catch (error) {
      if (candidate != null && (identical(_candidate, candidate) || identical(_lookahead, candidate))) {
        preparationFailed(candidate.id);
      } else {
        _releaseReservation(candidate);
      }
      if (isCurrent()) _failedLookaheadParent = parent.id;
      _host._pushMessage('Short-track lookahead deferred: $error', level: LogLevel.debug);
    } finally {
      if (_preparingLookahead == parent.id) _preparingLookahead = null;
      final head = _candidate;
      if (head != null && !identical(head, parent)) _prepareLookahead(head);
    }
  }

  Future<_GaplessCandidate?> _reserve(int revision, {_GaplessCandidate? after}) async {
    final state = _host._playbackState;
    final current = after?.track ?? state.track!;
    final sourceSession = _host.connection.sessionRevision;
    final shuffle = _host._shuffleCoordinator;
    Track? track;
    var index = after?.index ?? _host._playIndex;
    ServerShuffleReservation? reservation;
    ServerShuffleDeck? replacementDeck;
    List<Track>? replacementQueue;
    final deck = after?.replacementDeck ?? after?.deck ?? shuffle._serverDeck;
    final queue = after?.replacementQueue ?? _host._playQueue;

    if (state.repeatMode == PlaybackRepeatMode.one) {
      track = current;
    } else if (state.shuffleMode != ShuffleMode.off && state.shuffleScope == ActionScope.server) {
      if (deck == null) return null;
      if (!shuffle._serverDeckExpired || !identical(deck, shuffle._serverDeck)) {
        reservation = await deck.reserveNext(after: after?.reservation);
      }
      if (after == null && revision != _revision) {
        if (reservation != null) deck.cancelReservation(reservation);
        return null;
      }
      if (reservation != null) {
        track = reservation.track;
      } else {
        replacementDeck = await _reserveServerPass();
        if (replacementDeck == null) return null;
        track = replacementDeck.tracks[replacementDeck.queueIndex];
      }
    } else if (queue.isNotEmpty) {
      if (state.shuffleMode != ShuffleMode.off &&
          state.shuffleScope == ActionScope.local &&
          index >= queue.length - 1) {
        final tracks = _localShuffleTracks();
        if (tracks.isEmpty) return null;
        replacementQueue = shuffle._shuffleTracks(tracks, avoidTrackId: current.id);
        index = 0;
        track = replacementQueue.first;
      } else {
        index = (index + 1) % queue.length;
        track = queue[index];
      }
    }
    if (track == null) return null;
    if (state.queueSource != PlaybackQueueSource.offline) track = _host.connection.projectServerTrack(track);
    final download = _host.availableOfflineDownloadForTrack(track.id);
    final local = state.queueSource == PlaybackQueueSource.offline || !_host._canAttemptRemotePlayback;
    final filePath = local ? download?.filePath : null;
    final candidate = _GaplessCandidate(
      id: ++_nextId,
      afterId: after?.id,
      revision: revision,
      sourceSession: sourceSession,
      fromTrackId: current.id,
      track: track,
      index: index,
      filePath: filePath,
      listeningContext: _host._statsCoordinator._newListeningContext(track),
      deck: deck,
      reservation: reservation,
      replacementDeck: replacementDeck,
      replacementQueue: replacementQueue,
    );
    if (local && (filePath == null || !File(filePath).existsSync())) {
      _releaseReservation(candidate);
      return null;
    }
    return candidate;
  }

  List<Track> _localShuffleTracks() {
    final shuffle = _host._shuffleCoordinator;
    return switch (_host._playbackState.shuffleMode) {
      ShuffleMode.currentPlaylist => _host.localPlaylistTracks,
      ShuffleMode.liked => _host.localLiked,
      ShuffleMode.artist => shuffle._localLibrary.artist(shuffle._queueShuffleArtistId ?? '')?.tracksForArtist ?? [],
      ShuffleMode.album => shuffle._localLibrary.album(shuffle._queueShuffleAlbumId ?? '')?.tracks ?? [],
      ShuffleMode.custom =>
        _host.offlineTracks
            .where(
              (track) => shuffle._localLibrary.matchesCustomShuffle(
                track,
                artistIds: _host._customShuffleSettings.localArtistIds.toSet(),
                genres: _host._customShuffleSettings.localGenres.map((genre) => genre.toLowerCase()).toSet(),
              ),
            )
            .toList(),
      _ => _host.offlineTracks,
    };
  }

  Future<ServerShuffleDeck?> _reserveServerPass() async {
    final shuffle = _host._shuffleCoordinator;
    final scope = shuffle._queueShuffleScope ?? 'library';
    final mode = _host._playbackState.shuffleMode;
    final session = _host.connection.sessionRevision;
    final first = await _host.connection.createShuffleSession(
      mode: scope == 'playlist' || scope == 'liked' ? scope : shuffle._shuffleQueryMode(mode),
      clientId: shuffle._serverClientId,
      requestId: _newShuffleIdentifier(),
      artistId: shuffle._queueShuffleArtistId,
      albumId: shuffle._queueShuffleAlbumId,
      artistIds: mode == ShuffleMode.custom ? _host._customShuffleSettings.artistIds : const [],
      genres: mode == ShuffleMode.custom ? _host._customShuffleSettings.genres : const [],
      playlistId: shuffle._queueShufflePlaylistId,
    );
    final next = ServerShuffleDeck(
      first,
      load: (offset) =>
          _host.connection.fetchShuffleSessionPage(first.sessionId, clientId: shuffle._serverClientId, offset: offset),
    );
    try {
      if (session != _host.connection.sessionRevision || !await next.initialize(play: true)) {
        next.close();
        shuffle._releaseServerShuffleSession(first.sessionId, session);
        return null;
      }
      return next;
    } catch (_) {
      next.close();
      shuffle._releaseServerShuffleSession(first.sessionId, session);
      rethrow;
    }
  }

  bool _isCurrent(_GaplessCandidate candidate) =>
      !_host._disposed &&
      candidate.revision == _revision &&
      candidate.sourceSession == _host.connection.sessionRevision &&
      candidate.fromTrackId == _host._playbackState.track?.id &&
      (candidate.deck == null || identical(candidate.deck, _host._shuffleCoordinator._serverDeck));

  void preparationFailed(int id) {
    final tail = _lookahead;
    if (tail != null && tail.id == id) {
      _lookahead = null;
      _failedLookaheadParent = tail.afterId;
      _releaseReservation(tail);
      return;
    }
    final candidate = _candidate;
    if (candidate == null || candidate.id != id) return;
    _candidate = null;
    _lookahead = null;
    _preparingLookahead = null;
    _failedRevision = _revision;
    if (tail != null) {
      _host._audio?.cancelPreparedNext(preparationId: tail.id);
      _releaseReservation(tail);
    }
    _releaseReservation(candidate);
  }

  void transitioned(int id) {
    final candidate = _candidate;
    if (candidate == null || candidate.id != id) return;
    if (!_isCurrent(candidate)) {
      invalidate();
      return;
    }
    final shuffle = _host._shuffleCoordinator;
    final reservation = candidate.reservation;
    if (reservation != null && !candidate.deck!.commitReservation(reservation)) {
      invalidate();
      return;
    }
    _candidate = _lookahead;
    _lookahead = null;
    waitingForSuccessor = false;
    _revision++;
    _candidate?.revision = _revision;
    _lastTransitionedId = id;
    _failedRevision = null;
    _failedLookaheadParent = null;
    _preparing = null;
    final replacement = candidate.replacementDeck;
    if (replacement != null) {
      final previous = shuffle._serverDeck;
      shuffle._serverDeck = replacement;
      shuffle._serverDeckSessionRevision = candidate.sourceSession;
      shuffle._serverDeckExpired = false;
      shuffle._serverDeckReady = true;
      previous?.close();
      if (previous != null) shuffle._releaseServerShuffleSession(previous.sessionId, candidate.sourceSession);
    }
    if (candidate.deck != null || replacement != null) {
      shuffle._applyServerShuffleWindow(replacement ?? candidate.deck!);
    } else {
      if (candidate.replacementQueue != null) _host._playQueue = candidate.replacementQueue!;
      _host._playIndex = candidate.index;
    }
    final indexed = _host._playIndex >= 0 && _host._playIndex < _host._playQueue.length
        ? _host._playQueue[_host._playIndex]
        : null;
    final track = indexed?.id == candidate.track.id ? indexed! : candidate.track;
    final wantsPlayback = _host._wantsPlayback;
    _host._accountServices.prepareTrackStart();
    _host._bumpNowPlayingEpoch();
    _host._resetTrackTransitionState();
    _host._wantsPlayback = wantsPlayback;
    _host._audioOutputStarted = true;
    _host._autoAdvanceInFlight = false;
    _host._queueCoordinator._ignoreCompleteUntil = null;
    final context = candidate.listeningContext;
    _host._listeningSessionContext = context == null
        ? null
        : {...context, 'session_started_at_ms': _host._playbackClock().toUtc().millisecondsSinceEpoch};
    _host._updatePlayback(
      track: track,
      isPlaying: wantsPlayback && !_host._audioSessionSuspended,
      isLoading: false,
      position: Duration.zero,
      duration: Duration(milliseconds: track.durationMs),
      bufferRatio: 0,
      isLocalPlayback: candidate.filePath != null,
      streamConnected: candidate.filePath == null,
    );
    _host._accountServices.reportStartedTrack();
    _host._resumeCoordinator.changed();
    _host._resumeCoordinator.progress(force: true);
    unawaited(_host._pushNowPlayingUpdate(force: true));
    _host._audioEngine.acknowledgeGaplessTransition(id);
    shuffle._prefetchServerShuffle();
    prepare();
  }

  void _releaseReservation(_GaplessCandidate? candidate) {
    final reservation = candidate?.reservation;
    if (reservation != null) candidate!.deck?.cancelReservation(reservation);
    final next = candidate?.replacementDeck;
    if (next == null || identical(next, _host._shuffleCoordinator._serverDeck)) return;
    next.close();
    _host._shuffleCoordinator._releaseServerShuffleSession(next.sessionId, candidate!.sourceSession);
  }
}

class _GaplessCandidate {
  final int id;
  final int? afterId;
  int revision;
  final int sourceSession;
  final String fromTrackId;
  final Track track;
  final int index;
  final String? filePath;
  final Map<String, dynamic>? listeningContext;
  final ServerShuffleDeck? deck;
  final ServerShuffleReservation? reservation;
  final ServerShuffleDeck? replacementDeck;
  final List<Track>? replacementQueue;

  _GaplessCandidate({
    required this.id,
    required this.revision,
    required this.sourceSession,
    required this.fromTrackId,
    required this.track,
    required this.index,
    required this.filePath,
    required this.listeningContext,
    this.afterId,
    this.deck,
    this.reservation,
    this.replacementDeck,
    this.replacementQueue,
  });
}
