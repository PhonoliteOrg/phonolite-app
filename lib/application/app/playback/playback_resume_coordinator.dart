part of '../app_controller.dart';

/// Owns durable playback checkpoints separately from audio transport and account events.
class _PlaybackResumeCoordinator {
  final AppController _host;
  late final _PlaybackResumeRestorer _restorer = _PlaybackResumeRestorer(_host, this);
  final String _sessionId = _newShuffleIdentifier();
  final _closing = Completer<void>();
  final _accountReads = RequestGeneration();
  PlaybackSourceContext _source = PlaybackSourceContext(kind: 'standalone');
  PlaybackSourceContext _shuffleContext = PlaybackSourceContext(kind: 'library');
  AccountPlaybackSnapshot _account = const AccountPlaybackSnapshot(revision: 0);
  Future<void> _writes = Future<void>.value();
  Future<void> _localWrites = Future<void>.value();
  Future<void>? _accountReady;
  String? _scope;
  String? _activeScope;
  int _accountSession = -1;
  int _selection = 0;
  int _lastStartedSelection = -1;
  int _sequence = 0;
  int _accountMutation = 0;
  int _localGeneration = 0;
  bool _restoring = false;
  bool _closed = false;
  bool _supportsResume = false;
  bool _ownsAccountGeneration = false;
  bool _localAuthority = false;
  PlaybackResumeCheckpoint? _retainedLocalCheckpoint;
  PlaybackResumeCheckpoint? _deferredAccountDeck;
  String? _activeDurableDeckId;
  DateTime? _lastProgressSave;

  _PlaybackResumeCoordinator(this._host);

  bool get canRestore => !_closed && !_host._disposed && _host._playbackState.track == null && _host._playQueue.isEmpty;

  bool get hasDeferredNavigation => _supportsResume && !_localAuthority && _deferredAccountDeck != null;

  Future<void> initialize() async {
    if (!_host._resumeDeviceStorageEnabled) {
      return;
    }

    final selection = _selection;
    try {
      _activeScope = await _host._playbackResumeStorage.readActiveScope();
      final snapshot = await _host._playbackResumeStorage.readLocal();
      if (snapshot != null && selection == _selection && canRestore) {
        _restorer._restoreModes(snapshot);
      }

      if (snapshot != null && _activeScope == 'local' && selection == _selection && canRestore) {
        await _restorer.restoreLocal(snapshot, isCurrent: () => selection == _selection && canRestore);
      }
    } catch (error) {
      AppLogger.debug('Local playback restore deferred: $error');
    }
  }

  void start(ServerCapabilities capabilities) {
    if (!capabilities.playbackResume || _closed) {
      return;
    }

    final session = _host.connection.sessionRevision;
    _supportsResume = true;
    _accountSession = session;
    _accountReady = _loadAccount(session).catchError((Object error) {
      AppLogger.debug('Account playback initialization deferred: $error');
    });
    unawaited(_accountReady);
  }

  void detachAccount() {
    _accountReads.advance();
    _accountMutation++;
    _accountSession = -1;
    _scope = null;
    _supportsResume = false;
    _ownsAccountGeneration = false;
    _account = const AccountPlaybackSnapshot(revision: 0);
    _deferredAccountDeck = null;
    _activeDurableDeckId = null;
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }

    if (_localAuthority && _host._playbackState.track != null) {
      _saveLocal();
    }
    _closed = true;
    _closing.complete();
    await Future.wait([_writes, _localWrites]);
    await _host._playbackResumeStorage.flush();
  }

  void retireSelection() {
    _deferredAccountDeck = null;
    _selection++;
  }

  void modeChanged() {
    _deferredAccountDeck = null;
    retireSelection();
    changed();
  }

  void progress({bool force = false}) {
    if (_closed || _restoring || !_localAuthority || _host._playbackState.track == null) {
      return;
    }

    final now = _host._playbackClock();
    if (!force && _lastProgressSave != null && now.difference(_lastProgressSave!) < const Duration(seconds: 15)) {
      return;
    }

    _lastProgressSave = now;
    _saveLocal();
  }

  void queueChanged(PlaybackSourceContext? source) {
    _localAuthority = _host._playbackState.queueSource == PlaybackQueueSource.offline;
    _source = source ?? _sourceForQueue();
    if (_localAuthority || _deferredAccountDeck?.source != _source) {
      _deferredAccountDeck = null;
    }
  }

  /// Downloaded audio may continue across sign-out, but private server collection
  /// identity belongs to the account that selected it.
  void detachDownloadedSource() {
    final state = _host._playbackState;
    final track = state.track;

    if (track == null || !state.isLocalPlayback || state.queueSource == PlaybackQueueSource.offline) {
      return;
    }

    final origin = track.serverBaseUrl ?? _host._authState.baseUrl;
    final download = _host.availableOfflineDownloads.where((download) {
      if (track.localId != null && download.localTrackId == track.localId) {
        return true;
      }

      return download.serverBaseUrl == origin &&
          (download.track.serverTrackId ?? download.track.id) == (track.serverTrackId ?? track.id);
    }).firstOrNull;
    final localTrack = track.copyWith(localId: track.localId ?? download?.localTrackId);
    final source = PlaybackSourceContext(kind: 'standalone');
    _host._setQueue(
      [localTrack],
      queueSource: PlaybackQueueSource.offline,
      offlineQueueSource: OfflineQueueSource.tracks,
      sourceContext: source,
    );
    _shuffleContext = source;
    _host._queueShuffleMode = ShuffleMode.off;
    _host._queueShuffleScope = null;
    _host._queueShuffleArtistId = null;
    _host._queueShuffleAlbumId = null;
    _host._queueShufflePlaylistId = null;
    _host._updatePlayback(track: localTrack, shuffleScope: ActionScope.local, shuffleMode: ShuffleMode.off);
    retireSelection();
    changed();
  }

  void rememberShuffle({required String scope, String? playlistId, String? artistId, String? albumId}) {
    final kind = switch (scope) {
      'playlist' || 'localPlaylist' => 'playlist',
      'liked' || 'localLiked' => 'liked',
      'localArtist' => 'artist',
      'localAlbum' => 'album',
      'localCustom' => 'custom',
      _ => switch (_host._playbackState.shuffleMode) {
        ShuffleMode.artist => 'artist',
        ShuffleMode.album => 'album',
        ShuffleMode.custom => 'custom',
        ShuffleMode.liked => 'liked',
        _ => 'library',
      },
    };
    final local = scope.startsWith('local');
    final settings = _host._customShuffleSettings;
    _shuffleContext = PlaybackSourceContext(
      kind: kind,
      id: switch (kind) {
        'playlist' => playlistId,
        'artist' => artistId,
        'album' => albumId,
        _ => null,
      },
      artistIds: kind == 'custom' ? (local ? settings.localArtistIds : settings.artistIds) : const [],
      genres: kind == 'custom' ? (local ? settings.localGenres : settings.genres) : const [],
    );
  }

  void started() {
    if (_closed || _restoring || _lastStartedSelection == _selection) {
      return;
    }

    _lastStartedSelection = _selection;
    _localAuthority = _host._playbackState.queueSource == PlaybackQueueSource.offline;
    if (_localAuthority) {
      changed();
    } else if (_supportsResume) {
      _scheduleAccountWrite(start: true);
    }
  }

  void changed() {
    if (_closed || _restoring) {
      return;
    }

    _saveLocal(profileOnly: true);
    unawaited(_commitChanged());
  }

  void preserveBeforeStop() {
    if (_localAuthority && _host._playbackState.track != null) {
      _saveLocal();
    }
  }

  Future<void> refreshAccount() async {
    final session = _accountSession;
    final scope = _scope;
    if (scope == null || !_isAccountCurrent(session, scope)) {
      return;
    }

    final request = _accountReads.advance();
    final mutation = _accountMutation;

    try {
      final snapshot = await _host.connection.fetchAccountPlayback();
      if (!_isAccountCurrent(session, scope) || !_accountReads.isCurrent(request) || mutation != _accountMutation) {
        return;
      }

      if (snapshot.generation != _account.generation) {
        _ownsAccountGeneration = false;
      }
      _account = snapshot;
      if (_host._resumeDeviceStorageEnabled) {
        await _host._playbackResumeStorage.writeAccount(scope, snapshot, activate: false);
      }
    } catch (error) {
      AppLogger.debug('Account playback refresh deferred: $error');
    }
  }

  Future<void> restoreSavedAccount(AuthCredentials credentials) async {
    final userId = credentials.userId;
    if (!_host._resumeDeviceStorageEnabled || userId == null || userId.isEmpty) {
      return;
    }

    final selection = _selection;
    final origin = ServerTrust.origin(Uri.parse(credentials.baseUrl));
    final identity = '${credentials.trust.spki}/${credentials.trust.opaqueKey}';
    final scope = '$origin/$identity/$userId';
    bool isCurrent() =>
        !_closed &&
        selection == _selection &&
        canRestore &&
        _host._authState.status == SessionStatus.serverUnavailable &&
        _host.connection.token == credentials.token &&
        ServerTrust.origin(Uri.parse(_host.connection.baseUrl)) == origin &&
        _host.connection.trust?.spki == credentials.trust.spki &&
        _host.connection.trust?.opaqueKey == credentials.trust.opaqueKey;

    try {
      if (!isCurrent()) {
        return;
      }

      final active = await _host._playbackResumeStorage.readActiveScope();
      final cached = await _host._playbackResumeStorage.readAccount(scope);
      if (active == 'local' || cached == null || !isCurrent()) {
        return;
      }

      _activeScope = active;
      await _restorer.restoreCachedAccount(cached, isCurrent: isCurrent);
    } catch (error) {
      AppLogger.debug('Saved account playback restore deferred: $error');
    }
  }

  Future<void> clearLocal() async {
    _localGeneration++;
    _selection++;
    _retainedLocalCheckpoint = null;
    if (_host._resumeDeviceStorageEnabled) {
      await _host._playbackResumeStorage.clearLocal();
    }
  }

  void reconcileLocal() {
    if (_localAuthority && !_restoring && !_closed) {
      unawaited(_restorer.reconcileLocal());
    }
  }

  bool hasDurableDeck(String id) => _activeDurableDeckId == id || _account.checkpoint?.deckId == id;

  Future<void> restoreDeferredDeck() async {
    if (_supportsResume && _deferredAccountDeck != null) {
      await _restorer.restoreDeferredDeck();
    }
  }

  Future<bool> prepareNavigation(int direction) async {
    if (!_supportsResume || _localAuthority || _deferredAccountDeck == null) {
      return true;
    }

    return _restorer.restoreDeferredNavigation(direction);
  }

  Future<void> _commitChanged() async {
    final selection = _selection;
    final state = _host._playbackState;
    try {
      if (state.track != null && state.shuffleMode != ShuffleMode.off) {
        if (_localAuthority && state.shuffleScope == ActionScope.local) {
          await _host._shuffleCoordinator._ensureLocalShuffleQueue(play: false);
        } else if (!_localAuthority &&
            state.shuffleScope == ActionScope.server &&
            _supportsResume &&
            _ownsAccountGeneration) {
          await _host._shuffleCoordinator._ensureServerShuffleQueue(play: false);
        }
      }
      if (_closed || _restoring || selection != _selection) {
        return;
      }

      if (!_localAuthority && _supportsResume && _host._playbackState.serverShuffleMode == ShuffleMode.off) {
        final session = _accountSession;
        final ready = await _restorer.normalizeServerQueue(
          isCurrent: () => _isAccountCurrent(session, _scope) && selection == _selection,
        );
        if (!ready || _closed || _restoring || selection != _selection) {
          return;
        }
      }

      _saveLocal();
      if (!_localAuthority && _supportsResume && _host._playbackState.track != null && _ownsAccountGeneration) {
        final deck = _host._shuffleCoordinator._serverDeck;
        if (_host._playbackState.serverShuffleMode != ShuffleMode.off && deck == null) {
          return;
        }
        _scheduleAccountWrite(start: false);
      }
    } catch (error) {
      AppLogger.debug('Playback state commit deferred: $error');
    }
  }

  PlaybackSourceContext _sourceForQueue() {
    final state = _host._playbackState;
    return switch (state.queueSource) {
      PlaybackQueueSource.playlist => PlaybackSourceContext(kind: 'playlist', id: state.queueSourcePlaylistId),
      PlaybackQueueSource.liked => PlaybackSourceContext(kind: 'liked'),
      PlaybackQueueSource.offline => switch (state.localPlaybackSource) {
        LocalPlaybackSource.playlist => PlaybackSourceContext(kind: 'playlist', id: state.queueSourcePlaylistId),
        LocalPlaybackSource.liked => PlaybackSourceContext(kind: 'liked'),
        _ =>
          _host._playbackState.shuffleMode == ShuffleMode.off
              ? PlaybackSourceContext(kind: 'library')
              : _shuffleContext,
      },
      PlaybackQueueSource.none =>
        state.shuffleMode == ShuffleMode.off ? PlaybackSourceContext(kind: 'standalone') : _shuffleContext,
    };
  }

  PlaybackResumeCheckpoint? _checkpoint({required bool local}) {
    final state = _host._playbackState;
    final track = state.track;
    if (track == null) {
      return local ? _retainedLocalCheckpoint : null;
    }

    final deck = _host._shuffleCoordinator._serverDeck;
    final mode = state.shuffleModeFor(local ? ActionScope.local : ActionScope.server);
    return PlaybackResumeCheckpoint(
      trackId: local ? (track.localId ?? track.id) : (track.serverTrackId ?? track.id),
      source: _source,
      shuffleMode: mode,
      shuffleContext: mode == ShuffleMode.off ? _source : _shuffleContext,
      deckId: local || mode == ShuffleMode.off ? null : deck?.sessionId,
      cursor: max(0, local || deck == null ? _host._playIndex : deck.position),
    );
  }

  void _saveLocal({bool profileOnly = false}) {
    if (!_host._resumeDeviceStorageEnabled) {
      return;
    }

    final state = _host._playbackState;
    final checkpoint = _localAuthority && !profileOnly ? _checkpoint(local: true) : null;
    final ids = _localAuthority
        ? _host._playQueue.map((track) => track.localId ?? track.id).toList()
        : const <String>[];
    final generation = _localGeneration;
    final activate = _localAuthority && !profileOnly;
    _enqueueLocal(() async {
      if (generation != _localGeneration) {
        return;
      }

      final previous = activate && checkpoint != null ? null : await _host._playbackResumeStorage.readLocal();
      final snapshot = DevicePlaybackSnapshot(
        checkpoint: activate ? checkpoint ?? previous?.checkpoint : previous?.checkpoint,
        queueTrackIds: activate && state.track != null ? ids : previous?.queueTrackIds ?? const [],
        localShuffleMode: state.localShuffleMode,
        serverShuffleMode: state.serverShuffleMode,
        shuffleScope: state.shuffleScope,
        positionMs: activate && state.track != null ? state.position.inMilliseconds : previous?.positionMs ?? 0,
      );
      await _host._playbackResumeStorage.writeLocal(snapshot, activate: activate);
      if (activate) {
        _activeScope = 'local';
      }
    });
  }

  bool _isAccountCurrent(int session, String? scope) =>
      !_closed &&
      _supportsResume &&
      _accountSession == session &&
      _host._sessionCoordinator._isServerSessionCurrent(session) &&
      (scope == null || scope == _scope);

  Future<void> _loadAccount(int session) async {
    final selection = _selection;
    try {
      final state = await _host.connection.fetchAccountState();
      if (!_isAccountCurrent(session, null)) {
        return;
      }

      _host._sessionCoordinator._rememberAccountIdentity(state.userId);

      final origin = ServerTrust.origin(Uri.parse(_host.connection.baseUrl));
      final trust = _host.connection.trust;
      final identity = trust == null ? origin : '${trust.spki}/${trust.opaqueKey}';
      final scope = '$origin/$identity/${state.userId}';
      _scope = scope;
      final snapshot = await _host.connection.fetchAccountPlayback();
      if (!_isAccountCurrent(session, scope)) {
        return;
      }

      _account = snapshot;
      _ownsAccountGeneration = false;
      if (_host._resumeDeviceStorageEnabled) {
        _activeScope ??= await _host._playbackResumeStorage.readActiveScope();
        if (!_isAccountCurrent(session, scope)) {
          return;
        }

        await _host._playbackResumeStorage.writeAccount(scope, snapshot, activate: false);
      }
      if (_activeScope != 'local' && selection == _selection && canRestore) {
        await _restorer.restoreAccount(
          snapshot,
          isCurrent: () => _isAccountCurrent(session, scope) && selection == _selection && canRestore,
        );
      }
    } catch (error) {
      AppLogger.debug('Account playback restore deferred: $error');
      // Network failures retain the durable account cache; they are not deletions.
      final scope = _scope;
      if (_host._resumeDeviceStorageEnabled &&
          scope != null &&
          _isAccountCurrent(session, scope) &&
          _activeScope != 'local' &&
          selection == _selection &&
          canRestore) {
        final cached = await _host._playbackResumeStorage.readAccount(scope);
        if (cached != null && _isAccountCurrent(session, scope) && selection == _selection && canRestore) {
          await _restorer.restoreCachedAccount(
            cached,
            isCurrent: () => _isAccountCurrent(session, scope) && selection == _selection && canRestore,
          );
        }
      }
    }
  }

  void _scheduleAccountWrite({required bool start}) {
    final checkpoint = _checkpoint(local: false);
    final session = _accountSession;
    final selection = _selection;
    if (checkpoint == null || session < 0) {
      return;
    }

    _enqueue(() async {
      await Future.any([_accountReady ?? Future<void>.value(), _closing.future]);
      final scope = _scope;
      if (scope == null || !_isAccountCurrent(session, scope) || selection != _selection) {
        return;
      }

      if (!start && !_ownsAccountGeneration) {
        return;
      }

      final sequence = ++_sequence;
      try {
        final revision = _account.revision;
        final generation = start ? null : _account.generation;
        Future<AccountPlaybackSnapshot?> send() => Future.any<AccountPlaybackSnapshot?>([
          _host.connection.saveAccountPlayback(
            expectedRevision: revision,
            sessionId: _sessionId,
            sequence: sequence,
            requestId: '$_sessionId-$sequence',
            intent: start ? 'start' : 'update',
            generation: generation,
            clientId: _host._shuffleCoordinator._serverClientId,
            checkpoint: checkpoint,
          ),
          _closing.future.then((_) => null),
        ]);
        AccountPlaybackSnapshot? snapshot;
        try {
          snapshot = await send();
        } catch (error) {
          final transient =
              error is! ApiException || error.statusCode == 408 || error.statusCode == 429 || error.statusCode >= 500;
          if (!transient || !_isAccountCurrent(session, scope) || selection != _selection) {
            rethrow;
          }

          await Future.any([Future<void>.delayed(const Duration(milliseconds: 350)), _closing.future]);
          if (!_isAccountCurrent(session, scope) || selection != _selection) {
            return;
          }

          snapshot = await send();
        }
        if (snapshot == null || !_isAccountCurrent(session, scope)) {
          return;
        }

        _account = snapshot;
        _accountMutation++;
        final activate = selection == _selection && !_localAuthority;
        _ownsAccountGeneration = activate;
        if (activate) {
          _activeDurableDeckId = snapshot.checkpoint?.deckId;
        }
        if (_host._resumeDeviceStorageEnabled) {
          await _host._playbackResumeStorage.writeAccount(scope, snapshot, activate: activate);
          if (activate) {
            _activeScope = scope;
          }
        }
      } on ApiException catch (error) {
        if (!_isAccountCurrent(session, scope)) {
          return;
        }

        if (error.statusCode == 409) {
          _ownsAccountGeneration = false;
          final snapshot = await Future.any<AccountPlaybackSnapshot?>([
            _host.connection.fetchAccountPlayback(),
            _closing.future.then((_) => null),
          ]);
          if (snapshot != null && _isAccountCurrent(session, scope)) {
            _account = snapshot;
          }
        } else {
          AppLogger.debug('Playback checkpoint write deferred: $error');
        }
      } catch (error) {
        AppLogger.debug('Playback checkpoint write deferred: $error');
      }
    });
  }

  void _enqueue(Future<void> Function() operation) {
    _writes = _writes.then((_) => operation()).catchError((Object error) {
      AppLogger.debug('Playback persistence deferred: $error');
    });
  }

  void _enqueueLocal(Future<void> Function() operation) {
    _localWrites = _localWrites.then((_) => operation()).catchError((Object error) {
      AppLogger.debug('Device playback persistence deferred: $error');
    });
  }
}
