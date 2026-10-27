import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:phonolite_local_audio/phonolite_local_audio.dart';

import 'package:phonolite_app/data/models/audio/audio_file_format.dart';
import 'package:phonolite_app/data/models/audio/audio_source_rejected.dart';

/// Owns a native file decoder on a separate isolate, including its bounded
/// network reads. Playback controls and device release never wait on synchronous
/// HTTP work in the audio engine's isolate.
class AudioFileDecoder {
  final String? _filePath;
  final String? _url;
  final String _token;
  final String _serverPin;
  final Duration _startOffset;
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
  int _nextRequest = 0;

  AudioFileDecoder.local({required String filePath, Duration startOffset = Duration.zero})
    : _filePath = filePath,
      _url = null,
      _token = '',
      _serverPin = '',
      _startOffset = startOffset;

  AudioFileDecoder.remote({
    required Uri url,
    required String token,
    required String serverPin,
    Duration startOffset = Duration.zero,
  }) : _filePath = null,
       _url = url.toString(),
       _token = token,
       _serverPin = serverPin,
       _startOffset = startOffset;

  AudioFileFormat get format => _format ?? (throw StateError('Audio decoder is not initialized.'));

  Future<void> initialize() => _initialization ??= _initialize();

  /// Waits for the native decoder to close before retiring its isolate.
  Future<void> close() => _shutdown ??= _close();

  Future<Int32List> read32(int maxSamples) async {
    final response = await _request('read', {'max_samples': maxSamples});
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
      _isolate = await Isolate.spawn(
        _decodeFileWorker,
        <String, dynamic>{
          'reply': _messages!.sendPort,
          'file_path': _filePath,
          'url': _url,
          'token': _token,
          'server_pin': _serverPin,
          'start_ms': _startOffset.inMilliseconds,
        },
        debugName: 'phonolite_file_decoder',
        onError: _errors!.sendPort,
        onExit: _exit!.sendPort,
        errorsAreFatal: true,
      );
    } catch (error, stack) {
      _fail(error, stack);
      _exited.complete();
    }

    await _ready.future;
  }

  Future<void> _close() async {
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
    port.send({'id': requestId, 'command': command, ...payload});

    return result.future;
  }

  void _handleMessage(dynamic raw) {
    final message = Map<String, dynamic>.from(raw as Map);

    if (message['type'] == 'commands') {
      final commands = message['port'] as SendPort;

      _commands = commands;
      // The child closes even if the audio engine must forcibly retire this
      // worker. A heartbeat lease also covers a race while registering exit.
      Isolate.current.addOnExitListener(commands, response: 'owner_exit');
      _heartbeat = Timer.periodic(const Duration(seconds: 1), (_) => commands.send('heartbeat'));
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
    if (!_exited.isCompleted) {
      _exited.complete();
    }

    if (_shutdown == null) {
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

Future<void> _decodeFileWorker(Map<String, dynamic> configuration) async {
  final reply = configuration['reply'] as SendPort;
  final commands = ReceivePort();
  // Exceed the native 15-second initialization budget so queued heartbeats can
  // be processed after a slow but successful open before the lease expires.
  final incoming = StreamIterator<dynamic>(commands.timeout(const Duration(seconds: 30)));
  LocalAudioDecoder? decoder;

  try {
    // Do not acquire a native handle until the owner acknowledges the command
    // port. Its exit listener and lease now cover initialization as well.
    reply.send({'type': 'commands', 'port': commands.sendPort});

    if (!await incoming.moveNext() || incoming.current is! Map || incoming.current['command'] != 'open') {
      return;
    }

    final filePath = configuration['file_path'] as String?;
    final startOffset = Duration(milliseconds: configuration['start_ms'] as int);

    decoder = filePath != null
        ? LocalAudioDecoder.open(filePath, startOffset: startOffset)
        : LocalAudioDecoder.openRemote(
            configuration['url'] as String,
            token: configuration['token'] as String,
            serverPin: configuration['server_pin'] as String,
            startOffset: startOffset,
          );

    reply.send({
      'type': 'ready',
      'format': AudioFileFormat(
        sampleRate: decoder.sampleRate,
        channels: decoder.channels,
        bitDepth: decoder.bitDepth,
        duration: decoder.duration,
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

        switch (message['command']) {
          case 'read':
            final samples = activeDecoder.read32(message['max_samples'] as int);

            reply.send({
              'id': requestId,
              'samples': TransferableTypedData.fromList([samples]),
            });
          case 'seek':
            final position = activeDecoder.seek(Duration(milliseconds: message['position_ms'] as int));

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
        });
      }
    }
  } catch (error) {
    reply.send({'error': error.toString(), 'source_rejected': error is LocalAudioException && error.isSourceRejected});
  } finally {
    decoder?.close();
    await incoming.cancel();
    commands.close();
  }
}
