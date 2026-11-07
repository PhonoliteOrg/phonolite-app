import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:phonolite_local_audio/phonolite_local_audio.dart';
import 'package:phonolite_quic/phonolite_quic.dart';

import 'package:phonolite_app/data/models/audio/audio_file_format.dart';
import 'package:phonolite_app/data/models/audio/audio_source_rejected.dart';
import 'package:phonolite_app/data/rules/audio/audio_recovery_policy.dart';
import 'package:phonolite_app/data/structures/audio/pcm_stream_converter.dart';

typedef AudioFileDecoderWorkerSpawner = Future<Isolate> Function(
  Map<String, dynamic> configuration,
  SendPort errors,
  SendPort exit,
);

class AudioFileTransportFailure extends StateError {
  AudioFileTransportFailure(super.message);
}

/// Owns a native file decoder on a separate isolate, including its bounded
/// network reads. Playback controls and device release never wait on synchronous
/// transport work in the audio engine's isolate.
class AudioFileDecoder {
  final String? _filePath;
  final String? _url;
  final String? _quicHost;
  final int? _quicPort;
  final String? _quicTrackId;
  final String _token;
  final String _serverPin;
  final Duration _startOffset;
  final AudioFileDecoderWorkerSpawner? _workerSpawner;
  final Map<int, Completer<Map<String, dynamic>>> _requests = {};
  final Completer<void> _ready = Completer<void>();
  final Completer<void> _exited = Completer<void>();
  ReceivePort? _messages;
  ReceivePort? _errors;
  ReceivePort? _exit;
  Isolate? _isolate;
  SendPort? _commands;
  AudioFileFormat? _format;
  Future<void>? _initialization;
  Future<void>? _shutdown;
  Timer? _heartbeat;
  QuicOwnerLease? _quicOwner;
  int _nextRequest = 0;
  int _routeGeneration = 0;
  int? _startFrame;
  Map<String, dynamic>? _expectedSourceMetadata;
  Duration? _recoveryRemaining;
  int _recoveryAttemptsRemaining = 3;
  Stopwatch? _recoveryTransferClock;

  AudioFileDecoder.local({required String filePath, Duration startOffset = Duration.zero})
    : _filePath = filePath,
      _url = null,
      _quicHost = null,
      _quicPort = null,
      _quicTrackId = null,
      _token = '',
      _serverPin = '',
      _workerSpawner = null,
      _startOffset = startOffset;

  AudioFileDecoder.remote({
    required Uri url,
    required String token,
    required String serverPin,
    Duration startOffset = Duration.zero,
  }) : _filePath = null,
       _url = url.toString(),
       _quicHost = null,
       _quicPort = null,
       _quicTrackId = null,
       _token = token,
       _serverPin = serverPin,
       _workerSpawner = null,
       _startOffset = startOffset;

  AudioFileDecoder.quic({
    required String host,
    required int port,
    required String trackId,
    required String token,
    required String serverPin,
    Duration startOffset = Duration.zero,
    AudioFileDecoderWorkerSpawner? workerSpawner,
    Map<String, dynamic>? expectedSourceMetadata,
  }) : _filePath = null,
       _url = null,
       _quicHost = host,
       _quicPort = port,
       _quicTrackId = trackId,
       _token = token,
       _serverPin = serverPin,
       _workerSpawner = workerSpawner,
       _startOffset = startOffset,
       _expectedSourceMetadata = expectedSourceMetadata == null ? null : Map.unmodifiable(expectedSourceMetadata);

  AudioFileFormat get format => _format ?? (throw StateError('Audio decoder is not initialized.'));

  Map<String, dynamic>? get sourceMetadata => _quicOwner?.sourceMetadata ?? _expectedSourceMetadata;

  Duration get recoveryRemaining => _quicOwner?.recoveryRemaining ?? Duration.zero;

  int get recoveryAttempts => _quicOwner?.recoveryAttempts ?? 0;

  int? get transportRttMilliseconds => _quicOwner?.rttMilliseconds;

  int get transportReceivedBytes => _quicOwner?.receivedBytes ?? 0;

  Future<void> initialize() => _initialization ??= _initialize();

  /// Waits for the native decoder to close before retiring its isolate.
  Future<void> close() => _shutdown ??= _close();

  /// Interrupts the borrowed source operation without freeing its handle.
  /// A following seek resets parser state on the same owned connection.
  void interruptRead() => _quicOwner?.interrupt();

  void notifyNetworkChange(int routeGeneration) {
    if (routeGeneration <= _routeGeneration) {
      return;
    }
    _routeGeneration = routeGeneration;
    _quicOwner?.notifyNetworkChange(routeGeneration);
  }

  void beginRecovery({Duration remaining = AudioRecoveryPolicy.budget, int attemptsRemaining = 3}) {
    _quicOwner?.beginRecovery(remaining: remaining, attemptsRemaining: attemptsRemaining);
  }

  void finishRecovery() => _quicOwner?.finishRecovery();

  void reportPlayableMilliseconds(int milliseconds) => _quicOwner?.reportPlayableMilliseconds(milliseconds);

  /// Retires a failed parser and initializes a fresh, representation-pinned one.
  /// The caller retains accepted PCM/output and supplies its next missing frame.
  Future<AudioFileDecoder> replacementAtFrame(
    int presentationFrame, {
    required Duration remaining,
    required int attemptsRemaining,
    void Function(AudioFileDecoder replacement)? onCreated,
  }) async {
    final metadata = sourceMetadata;
    if (_quicHost == null || metadata == null) {
      throw StateError('This source has no pinned Original restart descriptor.');
    }
    final replacement =
        AudioFileDecoder.quic(
            host: _quicHost,
            port: _quicPort!,
            trackId: _quicTrackId!,
            token: _token,
            serverPin: _serverPin,
            workerSpawner: _workerSpawner,
          )
          .._startFrame = presentationFrame
          .._expectedSourceMetadata = metadata
          .._recoveryRemaining = remaining
          .._recoveryAttemptsRemaining = attemptsRemaining
          .._recoveryTransferClock = (Stopwatch()..start())
          .._routeGeneration = _routeGeneration;
    _expectedSourceMetadata = metadata;
    onCreated?.call(replacement);
    try {
      await close();
      await replacement.initialize();
      return replacement;
    } catch (_) {
      await replacement.close();
      rethrow;
    }
  }

  Future<Int32List> read32(int maxSamples) async {
    final response = await _request('read', {'max_samples': maxSamples});
    final transferred = response['samples'] as TransferableTypedData;

    return transferred.materialize().asInt32List();
  }

  /// Converts bounded source blocks on the decoder isolate. A seek resets the
  /// converter; raw and normalized reads must not be interleaved between seeks.
  Future<Int32List> readNormalized32({required int outputRate, required int outputChannels}) async {
    final response = await _request('read_normalized', {'output_rate': outputRate, 'output_channels': outputChannels});
    final transferred = response['samples'] as TransferableTypedData;

    return transferred.materialize().asInt32List();
  }

  Future<Duration> seek(Duration position) async {
    final response = await _request('seek', {'position_ms': position.inMilliseconds});

    return Duration(milliseconds: response['position_ms'] as int);
  }

  Future<void> _initialize() async {
    if (_shutdown != null) {
      throw StateError('Audio decoder is closed.');
    }

    _messages = ReceivePort()..listen(_handleMessage);
    _errors = ReceivePort()..listen(_handleError);
    _exit = ReceivePort()..listen(_handleExit);
    _ready.future.ignore();

    try {
      if (_quicHost != null) {
        _quicOwner ??= QuicOwnerLease();
        _quicOwner!.setMigrationEnabled(const bool.fromEnvironment('PHONOLITE_QUIC_MIGRATION'));
        final metadata = _expectedSourceMetadata;
        if (metadata != null &&
            !_quicOwner!.expectSource(metadata['source_version'] as String, metadata['total_length'] as int)) {
          throw AudioSourceRejected('The expected Original source identity is unavailable.');
        }
        final remaining = _recoveryRemaining;
        if (remaining != null) {
          final budget = remaining - (_recoveryTransferClock?.elapsed ?? Duration.zero);
          _quicOwner!.beginRecovery(
            remaining: budget.isNegative ? Duration.zero : budget,
            attemptsRemaining: _recoveryAttemptsRemaining,
          );
        }
        if (_routeGeneration > 0) {
          _quicOwner!.notifyNetworkChange(_routeGeneration);
        }
      }
      final configuration = <String, dynamic>{
        'reply': _messages!.sendPort,
        'file_path': _filePath,
        'url': _url,
        'quic_host': _quicHost,
        'quic_port': _quicPort,
        'quic_track_id': _quicTrackId,
        'quic_owner_id': _quicOwner?.id,
        'token': _token,
        'server_pin': _serverPin,
        'start_ms': _startOffset.inMilliseconds,
        'start_frame': _startFrame,
      };
      _isolate = await (_workerSpawner ?? _spawnWorker)(configuration, _errors!.sendPort, _exit!.sendPort);
    } catch (error, stack) {
      _fail(error, stack);
      _exited.complete();
    }

    await _ready.future;
  }

  Future<void> _close() async {
    // This parent-owned token is independent of the decoder's borrowed source
    // pointer. Cancellation can interrupt FFI before a queued close is handled.
    _quicOwner?.cancel();
    try {
      final initialization = _initialization;

      if (initialization == null) {
        return;
      }

      try {
        await initialization;
      } catch (_) {
        if (_isolate != null) {
          await _exited.future;
        }

        return;
      }

      if (!_exited.isCompleted) {
        await Future.any<void>([_request('close').then((_) {}), _exited.future]);
        await _exited.future;
      }
    } finally {
      _messages?.close();
      _errors?.close();
      _exit?.close();
      _heartbeat?.cancel();
      _quicOwner?.close();
      _quicOwner = null;

      final commands = _commands;

      if (commands != null) {
        Isolate.current.removeOnExitListener(commands);
      }

      _commands = null;
      _isolate = null;
      _fail(StateError('Audio decoder is closed.'));
    }
  }

  Future<Map<String, dynamic>> _request(String command, [Map<String, dynamic> payload = const {}]) {
    final port = _commands;

    if (port == null || _exited.isCompleted || (_shutdown != null && command != 'close')) {
      return Future.error(StateError('Audio decoder is closed.'));
    }

    final requestId = ++_nextRequest;
    final result = Completer<Map<String, dynamic>>();

    _requests[requestId] = result;
    port.send({'id': requestId, 'command': command, 'operation_epoch': _quicOwner?.operationEpoch, ...payload});

    if (_quicHost == null || command == 'close') {
      return result.future;
    }

    return result.future.timeout(
      // Native reads/seeks can use fifteen seconds. Leave time for isolate IPC
      // after that deadline; this watchdog only retires an unresponsive worker.
      const Duration(seconds: 20),
      onTimeout: () {
        _requests.remove(requestId);
        _quicOwner?.cancel();
        throw TimeoutException('Original decoder $command did not finish.');
      },
    );
  }

  void _handleMessage(dynamic raw) {
    final message = Map<String, dynamic>.from(raw as Map);

    if (message['type'] == 'commands') {
      final commands = message['port'] as SendPort;

      _commands = commands;
      // The child closes even if the audio engine must forcibly retire this
      // worker. A heartbeat lease also covers a race while registering exit.
      Isolate.current.addOnExitListener(commands, response: 'owner_exit');
      _heartbeat = Timer.periodic(const Duration(seconds: 1), (_) {
        _quicOwner?.heartbeat();
        commands.send('heartbeat');
      });
      commands.send({'command': 'open'});

      return;
    }

    if (message['type'] == 'ready') {
      _format = message['format'] as AudioFileFormat;
      _ready.complete();

      return;
    }

    final error = message['error'];
    final failure = message['source_rejected'] == true
        ? AudioSourceRejected(error?.toString() ?? 'Original source is unavailable.')
        : message['transport_failure'] == true
        ? AudioFileTransportFailure(error?.toString() ?? 'Original transport failed.')
        : StateError(error?.toString() ?? 'Audio decoder failed.');
    final requestId = message['id'] as int?;

    if (requestId == null) {
      _fail(failure);

      return;
    }

    final result = _requests.remove(requestId);

    if (error != null) {
      result?.completeError(failure);
    } else {
      result?.complete(message);
    }
  }

  void _handleError(dynamic error) => _fail(StateError('Audio decoder failed: $error'));

  void _handleExit(dynamic _) {
    _heartbeat?.cancel();
    _quicOwner?.close();
    _quicOwner = null;
    if (!_exited.isCompleted) {
      _exited.complete();
    }

    if (_shutdown == null || !_ready.isCompleted) {
      _fail(StateError('Audio decoder exited unexpectedly.'));
    }
  }

  void _fail(Object error, [StackTrace? stack]) {
    if (!_ready.isCompleted) {
      _ready.future.ignore();
      _ready.completeError(error, stack);
    }

    for (final request in _requests.values) {
      request.completeError(error, stack);
    }

    _requests.clear();
  }
}

Future<Isolate> _spawnWorker(Map<String, dynamic> configuration, SendPort errors, SendPort exit) => Isolate.spawn(
  _decodeFileWorker,
  configuration,
  debugName: 'phonolite_file_decoder',
  onError: errors,
  onExit: exit,
  errorsAreFatal: true,
);

Future<void> _decodeFileWorker(Map<String, dynamic> configuration) async {
  final reply = configuration['reply'] as SendPort;
  final commands = ReceivePort();
  // Exceed the native 15-second initialization budget so queued heartbeats can
  // be processed after a slow but successful open before the lease expires.
  final incoming = StreamIterator<dynamic>(commands.timeout(const Duration(seconds: 30)));
  LocalAudioDecoder? decoder;
  PcmStreamConverter? normalizer;
  bool normalizedEnd = false;

  try {
    // Do not acquire a native handle until the owner acknowledges the command
    // port. Its exit listener and lease now cover initialization as well.
    reply.send({'type': 'commands', 'port': commands.sendPort});

    if (!await incoming.moveNext() || incoming.current is! Map || incoming.current['command'] != 'open') {
      return;
    }

    final filePath = configuration['file_path'] as String?;
    final startOffset = Duration(milliseconds: configuration['start_ms'] as int);

    final quicHost = configuration['quic_host'] as String?;

    if (filePath != null) {
      decoder = LocalAudioDecoder.open(filePath, startOffset: startOffset);
    } else if (quicHost != null) {
      final ownerId = configuration['quic_owner_id'] as int?;
      if (ownerId != null && !QuicOwnerLease.beginOperation(ownerId, 0)) {
        throw StateError('Original decoder open was superseded.');
      }
      final source = QuicSourceTransport.connect(
        host: quicHost,
        port: configuration['quic_port'] as int,
        trackId: configuration['quic_track_id'] as String,
        token: configuration['token'] as String,
        serverPin: configuration['server_pin'] as String,
        ownerId: configuration['quic_owner_id'] as int?,
      );

      try {
        decoder = LocalAudioDecoder.openRemoteQuic(
          sourceHandle: source.takeHandle(),
          readRangeAddress: source.readRangeAddress,
          errorCodeAddress: source.errorCodeAddress,
          errorAddress: source.errorAddress,
          closeAddress: source.closeAddress,
          startOffset: startOffset,
        );
      } finally {
        source.close();
      }
    } else {
      decoder = LocalAudioDecoder.openRemote(
        configuration['url'] as String,
        token: configuration['token'] as String,
        serverPin: configuration['server_pin'] as String,
        startOffset: startOffset,
      );
    }

    final startFrame = configuration['start_frame'] as int?;
    if (startFrame != null) {
      final actual = decoder.seekFrame(startFrame);
      if (actual != startFrame) {
        throw LocalAudioException('Original restart checkpoint is outside the source.', code: -101);
      }
    }

    reply.send({
      'type': 'ready',
      'format': AudioFileFormat(
        sampleRate: decoder.sampleRate,
        channels: decoder.channels,
        bitDepth: decoder.bitDepth,
        duration: decoder.duration,
        playableFrames: decoder.playableFrames,
      ),
    });

    while (await incoming.moveNext()) {
      final raw = incoming.current;

      if (raw == 'owner_exit') {
        return;
      }

      if (raw == 'heartbeat') {
        continue;
      }

      final message = Map<String, dynamic>.from(raw as Map);
      final requestId = message['id'] as int;

      try {
        final activeDecoder = decoder;

        if (activeDecoder == null) {
          throw StateError('Audio decoder is closed.');
        }

        final ownerId = configuration['quic_owner_id'] as int?;
        if (ownerId != null &&
            (message['command'] == 'read' || message['command'] == 'read_normalized' || message['command'] == 'seek') &&
            !QuicOwnerLease.beginOperation(ownerId, message['operation_epoch'] as int)) {
          throw StateError('Original decoder operation was superseded.');
        }

        switch (message['command']) {
          case 'read':
            if (normalizer != null) throw StateError('Raw and normalized reads cannot be interleaved.');
            final samples = activeDecoder.read32(message['max_samples'] as int);

            reply.send({
              'id': requestId,
              'samples': TransferableTypedData.fromList([samples]),
            });
          case 'read_normalized':
            final rate = message['output_rate'] as int;
            final channels = message['output_channels'] as int;
            normalizer ??= PcmStreamConverter(
              inputRate: activeDecoder.sampleRate,
              inputChannels: activeDecoder.channels,
              outputRate: rate,
              outputChannels: channels,
            );
            if (normalizer.outputRate != rate || normalizer.outputChannels != channels) {
              throw StateError('Normalized output format cannot change between seeks.');
            }
            var converted = Int32List(0);
            while (!normalizedEnd && converted.isEmpty) {
              final input = activeDecoder.read32(activeDecoder.sampleRate * activeDecoder.channels ~/ 5);
              normalizedEnd = input.isEmpty;
              converted = normalizer.process(input, endOfInput: normalizedEnd) as Int32List;
            }
            reply.send({
              'id': requestId,
              'samples': TransferableTypedData.fromList([converted]),
            });
          case 'seek':
            final position = activeDecoder.seek(Duration(milliseconds: message['position_ms'] as int));
            normalizer = null;
            normalizedEnd = false;

            reply.send({'id': requestId, 'position_ms': position.inMilliseconds});
          case 'close':
            activeDecoder.close();
            decoder = null;
            reply.send({'id': requestId});

            return;
          default:
            throw StateError('Unknown file decoder command.');
        }
      } catch (error) {
        reply.send({
          'id': requestId,
          'error': error.toString(),
          'source_rejected': error is LocalAudioException && error.isSourceRejected,
          'transport_failure': error is LocalAudioException && error.code == -103,
        });
      }
    }
  } catch (error) {
    reply.send({
      'error': error.toString(),
      'source_rejected': error is LocalAudioException && error.isSourceRejected,
      'transport_failure': error is LocalAudioException && error.code == -103,
    });
  } finally {
    decoder?.close();
    await incoming.cancel();
    commands.close();
  }
}
