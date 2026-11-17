import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import 'package:phonolite_app/data/models/server/server_errors.dart';
import 'package:phonolite_app/infrastructure/server/transport/api_transport.dart';

/// Shared authenticated SSE framing and response-body ownership.
///
/// Each returned stream has one listener, performs I/O on listen, and releases
/// its body on cancellation, including a response arriving after cancellation.
class SseTransport {
  final ApiTransport _transport;

  SseTransport(this._transport);

  /// With [idleTimeout], a body that delivers nothing (not even a keep-alive comment) for that
  /// long fails the stream with a [TimeoutException], so callers notice a half-open connection.
  Stream<T> openJson<T>({
    required String path,
    required T? Function(Map<String, dynamic>) decode,
    Duration? idleTimeout,
  }) => _SseRequest<T>(transport: _transport, path: path, decode: decode, idleTimeout: idleTimeout).stream;
}

class _SseRequest<T> {
  static const _maximumFrameCharacters = 1024 * 1024;
  static const _maximumErrorCharacters = 8192;

  final ApiTransport _transport;
  final String _path;
  final T? Function(Map<String, dynamic>) _decode;
  final Duration? _idleTimeout;
  late final StreamController<T> _controller;
  StreamSubscription<String>? _bodySubscription;
  Timer? _idleTimer;
  bool _cancelled = false;
  String _buffer = '';

  _SseRequest({required this._transport, required this._path, required this._decode, required this._idleTimeout}) {
    _controller = StreamController<T>(onListen: _start, onPause: _pause, onResume: _resume, onCancel: _cancel);
  }

  Stream<T> get stream => _controller.stream;

  void _start() => unawaited(_open());

  void _pause() {
    _idleTimer?.cancel();
    _bodySubscription?.pause();
  }

  void _resume() {
    _bodySubscription?.resume();
    _watchIdle();
  }

  Future<void> _cancel() async {
    _cancelled = true;
    _idleTimer?.cancel();
    final subscription = _bodySubscription;
    _bodySubscription = null;

    await subscription?.cancel();
  }

  void _close() {
    _idleTimer?.cancel();

    if (!_controller.isClosed) {
      unawaited(_controller.close());
    }
  }

  void _watchIdle() {
    final timeout = _idleTimeout;

    _idleTimer?.cancel();

    if (timeout == null || _bodySubscription == null || _controller.isPaused) {
      return;
    }

    _idleTimer = Timer(timeout, () {
      final subscription = _bodySubscription;
      _bodySubscription = null;

      unawaited(subscription?.cancel());
      _fail(TimeoutException('SSE stream idle', timeout), StackTrace.current);
    });
  }

  void _fail(Object error, StackTrace stackTrace) {
    if (!_cancelled && !_controller.isClosed) {
      _controller.addError(error, stackTrace);
      _close();
    }
  }

  void _decodeFrame(String frame) {
    final data = <String>[];

    for (final rawLine in frame.split('\n')) {
      final line = rawLine.endsWith('\r') ? rawLine.substring(0, rawLine.length - 1) : rawLine;

      if (line.startsWith('data:')) {
        data.add(line.substring(5).trimLeft());
      }
    }

    if (data.isEmpty) {
      return;
    }

    try {
      final decoded = jsonDecode(data.join('\n'));

      if (decoded is Map<String, dynamic>) {
        final event = _decode(decoded);

        if (event != null) {
          _controller.add(event);
        }
      }
    } on Object catch (error, stackTrace) {
      developer.log('Ignoring malformed SSE event', name: 'ServerConnection', error: error, stackTrace: stackTrace);
    }
  }

  void _receive(String chunk) {
    if (_cancelled || _controller.isClosed) {
      return;
    }

    _buffer = (_buffer + chunk).replaceAll('\r\n', '\n');
    var separator = _buffer.indexOf('\n\n');

    while (separator >= 0) {
      if (separator > _maximumFrameCharacters) {
        _fail(const FormatException('SSE frame exceeds its size limit'), StackTrace.current);

        return;
      }

      _decodeFrame(_buffer.substring(0, separator));
      _buffer = _buffer.substring(separator + 2);
      separator = _buffer.indexOf('\n\n');
    }

    if (_buffer.length > _maximumFrameCharacters) {
      _fail(const FormatException('SSE frame exceeds its size limit'), StackTrace.current);
    }
  }

  Future<void> _open() async {
    try {
      final request = http.Request('GET', Uri.parse('${_transport.baseUrl}$_path'));
      request.headers.addAll(_transport.buildHeaders());
      request.headers['Accept'] = 'text/event-stream';
      final response = await _transport.client.send(request);

      if (_cancelled) {
        await response.stream.listen(null, onError: (Object _, StackTrace _) {}).cancel();

        return;
      }

      final successful = response.statusCode >= 200 && response.statusCode < 300;
      final errorBody = StringBuffer();

      void receive(String chunk) {
        // Any bytes, including keep-alive comments, prove the connection is alive.
        _watchIdle();

        if (successful) {
          _receive(chunk);
        } else if (errorBody.length < _maximumErrorCharacters) {
          errorBody.write(chunk.substring(0, chunk.length.clamp(0, _maximumErrorCharacters - errorBody.length)));
        }
      }

      void complete() {
        _bodySubscription = null;

        if (_cancelled || _controller.isClosed) {
          return;
        }

        if (!successful) {
          _controller.addError(ApiException(response.statusCode, errorBody.toString()));
        } else if (_buffer.trim().isNotEmpty) {
          _decodeFrame(_buffer.trim());
        }

        _close();
      }

      _bodySubscription = response.stream.transform(utf8.decoder).listen(receive, onError: _fail, onDone: complete);

      if (_controller.isPaused) {
        _bodySubscription?.pause();
      }

      _watchIdle();
    } on Object catch (error, stackTrace) {
      _fail(error, stackTrace);
    }
  }
}
