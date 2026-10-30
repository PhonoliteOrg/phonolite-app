part of '../offline_download_client.dart';

class _OfflineActorClient {
  final OfflineDownloadClient _host;
  ReceivePort? _receivePort;
  Isolate? _isolate;
  SendPort? _actorPort;
  Future<void>? _actorStartFuture;
  final RootIsolateToken? _rootIsolateToken = RootIsolateToken.instance;
  final Map<int, Completer<Object?>> _pending = <int, Completer<Object?>>{};

  _OfflineActorClient(this._host);

  Future<void> _commandOrInline(
    String name,
    Object? payload,
    Future<void> Function(_OfflineDownloadActorCore core) inline,
  ) {
    final core = _host._inlineCore;
    if (core != null) {
      return _host._withQueueQuality(() => inline(core));
    }

    return _host._send<void>(name, payload);
  }

  Future<void> _ensureActor() {
    if (_actorPort != null) {
      return Future<void>.value();
    }

    final existing = _actorStartFuture;
    if (existing != null) {
      return existing;
    }

    final ready = Completer<void>();

    _receivePort = ReceivePort();
    _receivePort!.listen(_handleActorMessage);
    _actorStartFuture = ready.future.whenComplete(() {
      _actorStartFuture = null;
    });

    void failStartup(Object err, StackTrace stack) {
      if (!ready.isCompleted) {
        ready.completeError(err, stack);
      }
    }

    void retainActor(Isolate isolate) {
      if (_host._disposed) {
        isolate.kill(priority: Isolate.immediate);
      } else {
        _isolate = isolate;
      }
    }

    Isolate.spawn(
      _offlineDownloadActorMain,
      OfflineActorInit(
        replyPort: _receivePort!.sendPort,
        baseUrl: _host.connection.baseUrl,
        token: _host.connection.token,
        trust: _host.connection.trust,
        storageConfig: _host._storageConfig,
        rootIsolateToken: _rootIsolateToken,
      ),
      debugName: 'OfflineDownloadActor',
    ).then(retainActor).catchError(failStartup);

    void completeStartup(Object? _) {
      if (!ready.isCompleted) {
        ready.complete();
      }
    }

    final handshake = Completer<Object?>();

    handshake.future.then(completeStartup).catchError(failStartup);
    _pending[0] = handshake;

    return _actorStartFuture!;
  }

  void _handleActorMessage(Object? message) {
    if (message is OfflineActorReady) {
      _actorPort = message.commandPort;

      final ready = _pending.remove(0);

      if (ready != null && !ready.isCompleted) {
        ready.complete(null);
      }

      return;
    }

    if (message is OfflineActorDownloadState) {
      _host._applyDownloadState(message);

      return;
    }

    if (message is OfflineActorLibraryState) {
      _host._applyLibraryState(message);

      return;
    }

    if (message is OfflineActorResult) {
      final completer = _pending.remove(message.id);

      if (completer == null || completer.isCompleted) {
        return;
      }

      if (message.error != null) {
        completer.completeError(StateError(message.error!));
      } else {
        completer.complete(message.result);
      }
    }
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _OfflineActorClientFacade {
  _OfflineActorClient get _ownerActor;

  ReceivePort? get _receivePort => _ownerActor._receivePort;

  Isolate? get _isolate => _ownerActor._isolate;

  SendPort? get _actorPort => _ownerActor._actorPort;

  Map<int, Completer<Object?>> get _pending => _ownerActor._pending;

  Future<void> _commandOrInline(
    String name,
    Object? payload,
    Future<void> Function(_OfflineDownloadActorCore core) inline,
  ) => _ownerActor._commandOrInline(name, payload, inline);

  Future<void> _ensureActor() => _ownerActor._ensureActor();
}
